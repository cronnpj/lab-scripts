<#
bootstrap.ps1 (student-proof, self-healing)

Run this on the Talos CTL VM (inside the isolated lab network).

Behavior:
- If cluster is reachable via kubectl: installs MetalLB + ingress-nginx + sample app.
- If cluster is NOT reachable: automatically wipes (reset) all nodes and rebuilds Talos + Kubernetes, then installs.

Defaults:
  CP  = 192.168.1.3
  W1  = 192.168.1.5
  W2  = 192.168.1.6
  VIP = 192.168.1.200

Usage:
  .\bootstrap.ps1
  .\bootstrap.ps1 -ControlPlaneIP 192.168.1.13 -WorkerIPs 192.168.1.15,192.168.1.16 -VipIP 192.168.1.210
#>

[CmdletBinding()]
param(
  [string]  $ClusterName    = "cita360",
  [string]  $ControlPlaneIP = "192.168.1.3",
  [string[]]$WorkerIPs      = @("192.168.1.5","192.168.1.6"),
  [string]  $VipIP          = "192.168.1.200",

  # Timeouts
  [int]$TimeoutTalosApiSeconds = 300,  # Talos API (50000) after reset/apply
  [int]$TimeoutK8sApiSeconds   = 420,  # K8s API (6443) after bootstrap
  [int]$TimeoutKubectlSeconds  = 420,  # kubectl get nodes after kubeconfig

  # If set, always wipes and rebuilds even if kubectl works
  [switch]$ForceRebuild
)

$ErrorActionPreference = "Stop"

# -------------------------
# Paths
# -------------------------
$RepoRoot     = $PSScriptRoot
$TalosDir     = Join-Path $RepoRoot "01-talos"
$OverridesDir = Join-Path $TalosDir  "student-overrides"
$TalosConfig  = Join-Path $OverridesDir "talosconfig"
$Kubeconfig   = Join-Path $RepoRoot "kubeconfig"

# -------------------------
# Helpers
# -------------------------
function Show-Header {
  param([string]$Title,[string]$Color="Cyan")
  Write-Host ""
  Write-Host $Title -ForegroundColor $Color
  Write-Host ""
}

function Prompt-Default($prompt,$default) {
  $v = Read-Host "$prompt [$default]"
  if ([string]::IsNullOrWhiteSpace($v)) { return $default }
  return $v.Trim()
}

function Prompt-WorkerIPs($defaults) {
  Write-Host ""
  Write-Host "Enter worker IPs one per line. Blank line = done." -ForegroundColor DarkGray
  Write-Host ("Default: {0}" -f ($defaults -join ", ")) -ForegroundColor DarkGray
  $first = Read-Host "Worker IP (blank to accept defaults)"
  if ([string]::IsNullOrWhiteSpace($first)) { return $defaults }

  $ips = @($first.Trim())
  while ($true) {
    $v = Read-Host "Worker IP (blank to finish)"
    if ([string]::IsNullOrWhiteSpace($v)) { break }
    $ips += $v.Trim()
  }
  return $ips
}

function Assert-Command($name) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
    throw "Missing required command '${name}'. Install it first (talosctl / kubectl / git / helm)."
  }
}

function Assert-Reachable($ip,$label) {
  if (-not (Test-Connection -ComputerName $ip -Count 1 -Quiet)) {
    throw "${label} (${ip}) is not reachable by ping. Check IP/subnet/VM power state."
  }
}

function Test-TcpPort {
  param([string]$Ip,[int]$Port,[int]$TimeoutMs=1500)
  try {
    $client = New-Object System.Net.Sockets.TcpClient
    $iar = $client.BeginConnect($Ip, $Port, $null, $null)
    $ok = $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
    if (-not $ok) { $client.Close(); return $false }
    $client.EndConnect($iar) | Out-Null
    $client.Close()
    return $true
  } catch { return $false }
}

function Wait-ForPort {
  param([string]$Ip,[int]$Port,[int]$TimeoutSeconds,[string]$Label)
  $start = Get-Date
  while ($true) {
    if (Test-TcpPort -Ip $Ip -Port $Port) { return $true }
    if (((Get-Date)-$start).TotalSeconds -ge $TimeoutSeconds) {
      Write-Host "${Label} still not reachable: ${Ip}:${Port}" -ForegroundColor Red
      return $false
    }
    Start-Sleep -Seconds 5
  }
}

function Test-KubectlOK {
  param([string]$KubeconfigPath)
  try {
    if (-not $KubeconfigPath -or -not (Test-Path $KubeconfigPath)) { return $false }
    & kubectl --kubeconfig $KubeconfigPath get nodes -o name 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
  } catch { return $false }
}

function Wait-ForKubectl {
  param([string]$KubeconfigPath,[int]$TimeoutSeconds)
  $start = Get-Date
  while ($true) {
    if (Test-KubectlOK -KubeconfigPath $KubeconfigPath) { return $true }
    if (((Get-Date)-$start).TotalSeconds -ge $TimeoutSeconds) { return $false }
    Start-Sleep -Seconds 5
  }
}

function Ensure-OverridesDir {
  New-Item -ItemType Directory -Force -Path $OverridesDir | Out-Null
}

function Clear-GeneratedFiles {
  # Delete kubeconfig + generated talos files so we don't reuse stale state
  Remove-Item -Force -ErrorAction SilentlyContinue $Kubeconfig
  Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $OverridesDir "controlplane.yaml")
  Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $OverridesDir "worker.yaml")
  Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $OverridesDir "talosconfig")
}

function Set-TalosContext {
  param([string]$cp)
  if (-not (Test-Path $TalosConfig)) { throw "talosconfig not found at: $TalosConfig" }
  if ((Get-Item $TalosConfig).Length -lt 50) { throw "talosconfig appears empty/corrupt at: $TalosConfig" }

  $env:TALOSCONFIG = $TalosConfig
  talosctl config endpoint $cp | Out-Null
  talosctl config node $cp | Out-Null
}

function Apply-NodeConfig {
  param([string]$ip,[string]$role,[string]$cp)

  $file = if ($role -eq "controlplane") { Join-Path $OverridesDir "controlplane.yaml" } else { Join-Path $OverridesDir "worker.yaml" }
  if (-not (Test-Path $file)) { throw "Missing ${role} config file: $file" }

  Write-Host "Applying ${role} config to ${ip} ..." -ForegroundColor Gray

  # Try insecure first (common for fresh/reset nodes)
  $out = talosctl apply-config --insecure --nodes $ip --endpoints $cp --file $file 2>&1 | Out-String
  if ($LASTEXITCODE -eq 0) { return }

  # If Talos now requires TLS, retry secure
  if ($out -match "certificate required") {
    Write-Host "TLS required; retrying apply-config securely..." -ForegroundColor Yellow
    talosctl apply-config --nodes $ip --endpoints $cp --file $file 2>&1 | Out-String | Out-Null
    if ($LASTEXITCODE -eq 0) { return }
  }

  throw "apply-config failed for ${ip}:`n$out"
}

function Get-EtcdServiceLine {
  try {
    $lines = talosctl service 2>$null
    if (-not $lines) { return $null }
    # keep it simple: find a line that contains 'etcd'
    foreach ($l in $lines) {
      if ($l -match "\betcd\b") { return $l }
    }
    return $null
  } catch { return $null }
}

function Etcd-IsFailed {
  $line = Get-EtcdServiceLine
  if (-not $line) { return $false }
  return ($line -match "\betcd\b" -and $line -match "\bFailed\b")
}

function Reset-Nodes {
  param([string[]]$Ips)

  Show-Header "RESET: Wiping Talos STATE + EPHEMERAL on all nodes (fresh start)" "Yellow"
  Write-Host ("Nodes: {0}" -f ($Ips -join ", ")) -ForegroundColor Yellow
  Write-Host "This is expected in the lab if anything breaks. Continuing..." -ForegroundColor DarkGray

  # Reset all nodes (best effort)
  foreach ($ip in $Ips) {
    try {
      Write-Host "Resetting ${ip} ..." -ForegroundColor Gray
      talosctl reset --nodes $ip --graceful=false --reboot `
        --system-labels-to-wipe STATE --system-labels-to-wipe EPHEMERAL 2>$null | Out-Null
    } catch {
      Write-Host "Reset command failed on ${ip} (continuing). It may already be rebooting." -ForegroundColor DarkGray
    }
  }

  # Wait for Talos API (50000) to come back on control plane at least
  Write-Host ""
  Write-Host "Waiting for Talos API (port 50000) on control plane..." -ForegroundColor Yellow
  $ok = Wait-ForPort -Ip $ControlPlaneIP -Port 50000 -TimeoutSeconds $TimeoutTalosApiSeconds -Label "Talos API"
  if (-not $ok) {
    throw "Talos API did not come back on ${ControlPlaneIP}:50000 in time."
  }
}

function Generate-TalosConfigs {
  Ensure-OverridesDir
  Clear-GeneratedFiles

  Show-Header "[1/6] Generating Talos configs" "Yellow"
  talosctl gen config $ClusterName "https://${ControlPlaneIP}:6443" --output-dir $OverridesDir | Out-Null

  if (-not (Test-Path (Join-Path $OverridesDir "controlplane.yaml"))) { throw "controlplane.yaml was not generated." }
  if (-not (Test-Path (Join-Path $OverridesDir "worker.yaml")))      { throw "worker.yaml was not generated." }
  if (-not (Test-Path $TalosConfig))                                 { throw "talosconfig was not generated." }

  Set-TalosContext -cp $ControlPlaneIP
}

function Bootstrap-TalosAndK8s {
  Show-Header "[2/6] Applying Talos configs" "Yellow"
  Apply-NodeConfig -ip $ControlPlaneIP -role "controlplane" -cp $ControlPlaneIP
  foreach ($w in $WorkerIPs) { Apply-NodeConfig -ip $w -role "worker" -cp $ControlPlaneIP }

  # After apply, ensure context is set (some students open a new shell; script handles it anyway)
  Set-TalosContext -cp $ControlPlaneIP

  Show-Header "[3/6] Bootstrapping Kubernetes control plane" "Yellow"
  talosctl bootstrap --nodes $ControlPlaneIP --endpoints $ControlPlaneIP 2>$null | Out-Null

  # Give etcd/apiserver time to settle
  Start-Sleep -Seconds 10

  # If etcd is failed, we will force rebuild by throwing
  if (Etcd-IsFailed) {
    Write-Host "Detected etcd FAILED after bootstrap. Will rebuild fresh automatically." -ForegroundColor Red
    throw "etcd_failed"
  }

  Show-Header "[4/6] Waiting for Kubernetes API (port 6443)" "Yellow"
  $apiOk = Wait-ForPort -Ip $ControlPlaneIP -Port 6443 -TimeoutSeconds $TimeoutK8sApiSeconds -Label "Kubernetes API"
  if (-not $apiOk) {
    # If API never opened, rebuild
    throw "k8s_api_down"
  }

  Show-Header "[5/6] Fetching kubeconfig + waiting for kubectl" "Yellow"
  talosctl kubeconfig $Kubeconfig --nodes $ControlPlaneIP --endpoints $ControlPlaneIP --force | Out-Null

  if (-not (Test-Path $Kubeconfig)) { throw "kubeconfig was not created at: $Kubeconfig" }

  $kubectlOk = Wait-ForKubectl -KubeconfigPath $Kubeconfig -TimeoutSeconds $TimeoutKubectlSeconds
  if (-not $kubectlOk) {
    throw "kubectl_not_ready"
  }
}

function Kube {
  param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
  & kubectl --kubeconfig $Kubeconfig @Args
}

function Install-MetalLB {
  Show-Header "[6/6] Installing MetalLB" "Yellow"

  $metallbBase    = Join-Path $RepoRoot "02-metallb\base"
  $metallbOverlay = Join-Path $RepoRoot "02-metallb\overlays\example"
  if (-not (Test-Path $metallbBase))    { throw "Missing folder: $metallbBase" }
  if (-not (Test-Path $metallbOverlay)) { throw "Missing folder: $metallbOverlay" }

  Kube apply -f $metallbBase | Out-Null

  # Update VIP in pool YAML automatically
  $poolFile = Join-Path $metallbOverlay "metallb-pool.yaml"
  if (Test-Path $poolFile) {
    $content = Get-Content $poolFile -Raw
    $content = [regex]::Replace(
      $content,
      '(?m)^\s*-\s*\d{1,3}(\.\d{1,3}){3}/32\s*$',
      "    - $VipIP/32"
    )
    Set-Content -Path $poolFile -Value $content -Encoding utf8
  }

  Kube apply -f $metallbOverlay | Out-Null
}

function Install-IngressNginx {
  Show-Header "Installing ingress-nginx (Helm)" "Yellow"

  $env:KUBECONFIG = $Kubeconfig

  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx | Out-Null
  helm repo update | Out-Null

  helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx `
    --namespace ingress-nginx --create-namespace `
    --set controller.service.type=LoadBalancer | Out-Null

  Kube rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=240s | Out-Null
}

function Install-AppAndIngress {
  Show-Header "Deploying sample app + ingress rule" "Yellow"

  $appDir      = Join-Path $RepoRoot "04-app"
  $ingressYaml = Join-Path $RepoRoot "03-ingress\nginx-ingress.yaml"

  if (-not (Test-Path $appDir))      { throw "Missing folder: $appDir" }
  if (-not (Test-Path $ingressYaml)) { throw "Missing file: $ingressYaml" }

  Kube apply -f $appDir | Out-Null
  Kube apply -f $ingressYaml | Out-Null
}

# -------------------------
# Main
# -------------------------
Clear-Host
Show-Header "== CITA 360 Talos + Kubernetes Bootstrap ==" "Cyan"

# Tools
Assert-Command talosctl
Assert-Command kubectl
Assert-Command git
Assert-Command helm

# Prompt for IPs if user didn’t specify any parameters explicitly
if ($PSBoundParameters.Count -eq 0) {
  $ClusterName    = Prompt-Default "Cluster name" $ClusterName
  $ControlPlaneIP = Prompt-Default "Control plane IP" $ControlPlaneIP
  $WorkerIPs      = Prompt-WorkerIPs $WorkerIPs
  $VipIP          = Prompt-Default "VIP (MetalLB) IP" $VipIP
}

Write-Host "ClusterName:    $ClusterName"
Write-Host "ControlPlaneIP: $ControlPlaneIP"
Write-Host "Workers:        $($WorkerIPs -join ', ')"
Write-Host "VIP (MetalLB):  $VipIP"
Write-Host ""

# Ping sanity
Assert-Reachable $ControlPlaneIP "Control Plane"
foreach ($w in $WorkerIPs) { Assert-Reachable $w "Worker" }

# If kubeconfig exists and kubectl works (and not forcing rebuild), skip rebuild
$clusterOk = $false
if (-not $ForceRebuild -and (Test-KubectlOK -KubeconfigPath $Kubeconfig)) {
  $clusterOk = $true
  Write-Host "Cluster appears healthy via kubectl. Skipping rebuild." -ForegroundColor Green
}

# If cluster not OK, rebuild automatically (wipe + rebuild)
if (-not $clusterOk) {
  $allNodes = @($ControlPlaneIP) + $WorkerIPs

  # Make sure we have a Talos context if possible (best effort). If talosconfig missing, we generate configs first.
  Ensure-OverridesDir

  # Always start from clean generated files when rebuilding
  Clear-GeneratedFiles

  # Generate configs (creates talosconfig + yaml)
  Generate-TalosConfigs

  # Use talosctl reset against nodes (fresh start) BEFORE apply/bootstrap (this is what you asked for)
  Set-TalosContext -cp $ControlPlaneIP
  Reset-Nodes -Ips $allNodes

  # After reset, generate configs again (fresh secrets) and apply/bootstrap
  Generate-TalosConfigs
  Bootstrap-TalosAndK8s

  Write-Host ""
  Write-Host "Rebuild complete. kubectl is working." -ForegroundColor Green
}

# From here kubectl must work; install add-ons
if (-not (Test-KubectlOK -KubeconfigPath $Kubeconfig)) {
  throw "kubectl still not working after rebuild attempt. Check talosctl service/logs, but this should be rare."
}

Install-MetalLB
Install-IngressNginx
Install-AppAndIngress

Write-Host ""
Write-Host "Cluster summary:" -ForegroundColor Cyan
Kube get nodes -o wide
Kube get pods -A
Kube get svc -A
Kube get ingress

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "Test URL (inside lab network): http://$VipIP"
