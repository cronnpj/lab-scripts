<#
bootstrap.ps1 (simple + reliable)

Assumptions (lab standard):
- You are running this on the Win11 "CTL" VM.
- Talos nodes are fresh / wiped (no old STATE).
- If you get x509 unknown authority, STOP and wipe the Talos node disks.

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

  [int]$TimeoutTalosApiSeconds = 300,
  [int]$TimeoutK8sApiSeconds   = 420,
  [int]$TimeoutKubectlSeconds  = 420
)

$ErrorActionPreference = "Stop"

# -------------------------
# Paths (repo-relative)
# -------------------------
$RepoRoot     = $PSScriptRoot
$OverridesDir = Join-Path $RepoRoot "01-talos\student-overrides"
$TalosConfig  = Join-Path $OverridesDir "talosconfig"
$Kubeconfig   = Join-Path $RepoRoot "kubeconfig"

function Show-Header([string]$Title,[string]$Color="Cyan") {
  Write-Host ""
  Write-Host $Title -ForegroundColor $Color
  Write-Host ""
}

function Assert-Command([string]$name) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
    throw "Missing required command '${name}'. Install it first (talosctl / kubectl / helm)."
  }
}

function Assert-Reachable([string]$ip,[string]$label) {
  if (-not (Test-Connection -ComputerName $ip -Count 1 -Quiet)) {
    throw "${label} (${ip}) is not reachable by ping."
  }
}

function Test-TcpPort([string]$Ip,[int]$Port,[int]$TimeoutMs=1500) {
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

function Wait-ForPort([string]$Ip,[int]$Port,[int]$TimeoutSeconds,[string]$Label) {
  $start = Get-Date
  while ($true) {
    if (Test-TcpPort $Ip $Port) { return $true }
    if (((Get-Date)-$start).TotalSeconds -ge $TimeoutSeconds) {
      throw "${Label} not reachable in time: ${Ip}:${Port}"
    }
    Start-Sleep -Seconds 5
  }
}

function Test-KubectlOK([string]$KubeconfigPath) {
  try {
    if (-not (Test-Path $KubeconfigPath)) { return $false }
    & kubectl --kubeconfig $KubeconfigPath get nodes -o name 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
  } catch { return $false }
}

function Wait-ForKubectl([string]$KubeconfigPath,[int]$TimeoutSeconds) {
  $start = Get-Date
  while ($true) {
    if (Test-KubectlOK $KubeconfigPath) { return $true }
    if (((Get-Date)-$start).TotalSeconds -ge $TimeoutSeconds) {
      throw "kubectl not ready in time."
    }
    Start-Sleep -Seconds 5
  }
}

function Fail-WithWipeInstructions([string]$Details) {
  Write-Host "" 
  Write-Host "TLS/x509 mismatch detected." -ForegroundColor Red
  Write-Host "This means the Talos node(s) still have old STATE/CA on disk." -ForegroundColor Red
  Write-Host ""
  Write-Host "Lab Fix (guaranteed):" -ForegroundColor Yellow
  Write-Host "1) In Proxmox: delete the Talos node VM(s) AND their disks (do not keep disks)." -ForegroundColor Yellow
  Write-Host "   OR boot each Talos node into maintenance mode and wipe the disk (wipefs -a /dev/sda)." -ForegroundColor Yellow
  Write-Host "2) Recreate nodes, boot them, then rerun .\bootstrap.ps1" -ForegroundColor Yellow
  Write-Host ""
  Write-Host "Details:" -ForegroundColor DarkGray
  Write-Host $Details -ForegroundColor DarkGray
  throw "x509_mismatch"
}

function New-CleanOverridesDir {
  New-Item -ItemType Directory -Force -Path $OverridesDir | Out-Null
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue (Join-Path $OverridesDir "*")
  Remove-Item -Force -ErrorAction SilentlyContinue $Kubeconfig
}

function Set-TalosContext {
  $env:TALOSCONFIG = $TalosConfig
  & talosctl config endpoint $ControlPlaneIP | Out-Null
  & talosctl config node $ControlPlaneIP     | Out-Null
}

function Talos-Apply([string]$NodeIP,[string]$FilePath) {
  Write-Host "Applying config to ${NodeIP} ..." -ForegroundColor Gray
  $out = & talosctl apply-config --insecure --nodes $NodeIP --endpoints $ControlPlaneIP --file $FilePath 2>&1
  if ($LASTEXITCODE -ne 0) {
    $txt = ($out | Out-String)
    if ($txt -match "x509:" -or $txt -match "unknown authority" -or $txt -match "failed to verify certificate") {
      Fail-WithWipeInstructions $txt
    }
    throw "apply-config failed for ${NodeIP}:`n$txt"
  }
}

function Talos-Bootstrap {
  Write-Host "Bootstrapping etcd/Kubernetes on control plane..." -ForegroundColor Gray
  $out = & talosctl bootstrap --insecure --nodes $ControlPlaneIP --endpoints $ControlPlaneIP 2>&1
  if ($LASTEXITCODE -ne 0) {
    $txt = ($out | Out-String)
    if ($txt -match "x509:" -or $txt -match "unknown authority" -or $txt -match "failed to verify certificate") {
      Fail-WithWipeInstructions $txt
    }
    throw "bootstrap failed:`n$txt"
  }
}

function Talos-Kubeconfig {
  Write-Host "Fetching kubeconfig..." -ForegroundColor Gray
  $out = & talosctl kubeconfig $Kubeconfig --insecure --nodes $ControlPlaneIP --endpoints $ControlPlaneIP --force 2>&1
  if ($LASTEXITCODE -ne 0) {
    $txt = ($out | Out-String)
    if ($txt -match "x509:" -or $txt -match "unknown authority" -or $txt -match "failed to verify certificate") {
      Fail-WithWipeInstructions $txt
    }
    throw "kubeconfig failed:`n$txt"
  }
}

function Kube {
  param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
  & kubectl --kubeconfig $Kubeconfig @Args
}

function Install-MetalLB {
  Show-Header "Installing MetalLB" "Yellow"

  $metallbBase    = Join-Path $RepoRoot "02-metallb\base"
  $metallbOverlay = Join-Path $RepoRoot "02-metallb\overlays\example"
  if (-not (Test-Path $metallbBase))    { throw "Missing folder: $metallbBase" }
  if (-not (Test-Path $metallbOverlay)) { throw "Missing folder: $metallbOverlay" }

  Kube apply -f $metallbBase | Out-Null

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
  Show-Header "Deploying sample app + ingress" "Yellow"

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
Show-Header "== CITA 360 Talos + Kubernetes Bootstrap (Simple) ==" "Cyan"

Write-Host "Repo path: $RepoRoot" -ForegroundColor DarkGray
Write-Host ""

Assert-Command talosctl
Assert-Command kubectl
Assert-Command helm

Write-Host "ClusterName:    $ClusterName"
Write-Host "ControlPlaneIP: $ControlPlaneIP"
Write-Host "Workers:        $($WorkerIPs -join ', ')"
Write-Host "VIP (MetalLB):  $VipIP"
Write-Host ""

Assert-Reachable $ControlPlaneIP "Control Plane"
foreach ($w in $WorkerIPs) { Assert-Reachable $w "Worker" }

# Wait for Talos API
Show-Header "Waiting for Talos API (50000) on control plane" "Yellow"
Wait-ForPort $ControlPlaneIP 50000 $TimeoutTalosApiSeconds "Talos API"

# Generate configs cleanly (local-only)
Show-Header "Generating Talos configs (fresh PKI)" "Yellow"
New-CleanOverridesDir
& talosctl gen config $ClusterName "https://${ControlPlaneIP}:6443" --output-dir $OverridesDir --force | Out-Null
if (-not (Test-Path (Join-Path $OverridesDir "controlplane.yaml"))) { throw "controlplane.yaml missing." }
if (-not (Test-Path (Join-Path $OverridesDir "worker.yaml")))      { throw "worker.yaml missing." }
if (-not (Test-Path $TalosConfig))                                 { throw "talosconfig missing." }

Set-TalosContext

# Apply configs insecure (fresh nodes)
Show-Header "Applying configs (insecure)" "Yellow"
Talos-Apply $ControlPlaneIP (Join-Path $OverridesDir "controlplane.yaml")
foreach ($w in $WorkerIPs) { Talos-Apply $w (Join-Path $OverridesDir "worker.yaml") }

# Bootstrap
Show-Header "Bootstrapping control plane (insecure)" "Yellow"
Talos-Bootstrap

# Wait for K8s API
Show-Header "Waiting for Kubernetes API (6443)" "Yellow"
Wait-ForPort $ControlPlaneIP 6443 $TimeoutK8sApiSeconds "Kubernetes API"

# Kubeconfig + kubectl
Show-Header "Fetching kubeconfig + waiting for kubectl" "Yellow"
Talos-Kubeconfig
Wait-ForKubectl $Kubeconfig $TimeoutKubectlSeconds

Write-Host ""
Write-Host "Kubernetes is up." -ForegroundColor Green

# Add-ons
Install-MetalLB
Install-IngressNginx
Install-AppAndIngress

Show-Header "Cluster summary" "Cyan"
Kube get nodes -o wide
Kube get pods -A
Kube get svc -A
Kube get ingress

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "Test URL (inside lab network): http://$VipIP"
