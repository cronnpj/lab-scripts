<#
bootstrap.ps1 (simple + reliable + student-proof)

Assumptions (lab standard):
- Run on Win11 "CTL" VM.
- Talos nodes are fresh/wiped (no old STATE).
- Static IPs are set on Talos VMs BEFORE running this.

Defaults:
  CP  = 192.168.1.3
  W1  = 192.168.1.5
  W2  = 192.168.1.6
  VIP = 192.168.1.200

Usage:
  .\bootstrap.ps1
  .\bootstrap.ps1 -Interactive
  .\bootstrap.ps1 -AddonsOnly -InstallMetalLB
  .\bootstrap.ps1 -DashboardOnly -InstallDashboard
  .\bootstrap.ps1 -WipeAndRebuild -Interactive

Notes:
- apply-config uses --insecure (maintenance API).
- bootstrap does NOT use --insecure (talosctl has no such flag for bootstrap).
- After apply-config, nodes reboot, so we WAIT for port 50000 to return before bootstrap.
#>

[CmdletBinding()]
param(
  # --- cluster inputs ---
  [string]  $ClusterName    = "cita360",
  [string]  $ControlPlaneIP = "192.168.1.3",
  [string[]]$WorkerIPs      = @("192.168.1.5","192.168.1.6"),
  [string]  $VipIP          = "192.168.1.200",

  # --- timeouts (seconds) ---
  [int]$TimeoutTalosApiSeconds = 420,
  [int]$TimeoutK8sApiSeconds   = 600,
  [int]$TimeoutKubectlSeconds  = 600,

  # --- modes / switches ---
  [switch]$Interactive,
  [switch]$WipeAndRebuild,

  [switch]$AddonsOnly,        # run only addons section (assumes kubeconfig exists)
  [switch]$DashboardOnly,     # run only dashboard install (assumes ingress-nginx + kubeconfig exists)

  [switch]$InstallMetalLB,    # addon selector
  [switch]$InstallIngress,    # addon selector
  [switch]$InstallApp,        # addon selector
  [switch]$InstallDashboard,  # dashboard selector

  # legacy compatibility
  [switch]$SkipApply,
  [switch]$SkipAddons
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -------------------------
# Paths (repo-relative)
# -------------------------
$RepoRoot     = $PSScriptRoot
$OverridesDir = Join-Path $RepoRoot "01-talos\student-overrides"
$TalosConfig  = Join-Path $OverridesDir "talosconfig"
$Kubeconfig   = Join-Path $RepoRoot "kubeconfig"

# -------------------------
# Console helpers
# -------------------------
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

function Wait-ForPortDownThenUp([string]$Ip,[int]$Port,[int]$TimeoutSeconds,[string]$Label) {
  $start = Get-Date
  $sawDown = $false

  while ($true) {
    $open = Test-TcpPort $Ip $Port
    if (-not $open) { $sawDown = $true }
    if ($sawDown -and $open) { return $true }

    if (((Get-Date)-$start).TotalSeconds -ge $TimeoutSeconds) {
      if ($open) { return $true }
      throw "${Label} did not restart in time: ${Ip}:${Port}"
    }
    Start-Sleep -Seconds 3
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
  Write-Host "This almost always means the Talos node still has old STATE/CA on disk." -ForegroundColor Red
  Write-Host ""
  Write-Host "Lab Fix (guaranteed):" -ForegroundColor Yellow
  Write-Host "1) In Proxmox: delete the Talos node VM(s) AND their disks (do not keep disks)." -ForegroundColor Yellow
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

  $out = & talosctl apply-config --insecure --nodes $NodeIP --endpoints $NodeIP --file $FilePath 2>&1

  if ($LASTEXITCODE -ne 0) {
    $txt = ($out | Out-String)

    if ($txt -match "x509:" -or $txt -match "unknown authority" -or $txt -match "failed to verify certificate") {
      Fail-WithWipeInstructions $txt
    }

    if ($txt -match "tls: certificate required") {
      throw "apply-config got 'tls: certificate required' on ${NodeIP}. Node likely not in maintenance mode (or IP mismatch)."
    }

    throw "apply-config failed for ${NodeIP}:`n$txt"
  }
}

function Talos-Bootstrap {
  Write-Host "Bootstrapping etcd/Kubernetes on control plane..." -ForegroundColor Gray

  $out = & talosctl bootstrap --nodes $ControlPlaneIP --endpoints $ControlPlaneIP 2>&1
  if ($LASTEXITCODE -ne 0) {
    $txt = ($out | Out-String)

    if ($txt -match "x509:" -or $txt -match "unknown authority" -or $txt -match "failed to verify certificate") {
      Fail-WithWipeInstructions $txt
    }

    if ($txt -match "connectex:" -or $txt -match "connection refused" -or $txt -match "No connection could be made") {
      Write-Host "Bootstrap hit connection issue; waiting and retrying once..." -ForegroundColor Yellow
      Wait-ForPort $ControlPlaneIP 50000 120 "Talos API (post-apply)"
      Start-Sleep -Seconds 5
      $out2 = & talosctl bootstrap --nodes $ControlPlaneIP --endpoints $ControlPlaneIP 2>&1
      if ($LASTEXITCODE -ne 0) { throw "bootstrap failed after retry:`n$($out2 | Out-String)" }
      return
    }

    throw "bootstrap failed:`n$txt"
  }
}

function Talos-Kubeconfig {
  Write-Host "Fetching kubeconfig..." -ForegroundColor Gray

  $out = & talosctl kubeconfig $Kubeconfig --nodes $ControlPlaneIP --endpoints $ControlPlaneIP --force 2>&1
  if ($LASTEXITCODE -ne 0) {
    $txt = ($out | Out-String)
    if ($txt -match "x509:" -or $txt -match "unknown authority" -or $txt -match "failed to verify certificate") {
      Fail-WithWipeInstructions $txt
    }
    throw "kubeconfig failed:`n$txt"
  }
}

# -------------------------
# IMPORTANT:
# Kube wrapper MUST be SIMPLE (NO CmdletBinding),
# otherwise PowerShell will steal '-o' as a common param.
# -------------------------
function Kube {
  param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
  & kubectl --kubeconfig $Kubeconfig @Args
  return $LASTEXITCODE
}

function Ensure-CoreDNSReady {
  Show-Header "Ensuring CoreDNS is ready" "Yellow"
  & kubectl --kubeconfig $Kubeconfig -n kube-system rollout status deployment/coredns --timeout="300s" | Out-Null
}

function Wait-ForK8sResource {
  param(
    [Parameter(Mandatory)][string]$What,
    [Parameter(Mandatory)][scriptblock]$Test,
    [int]$TimeoutSeconds = 240
  )

  $start = Get-Date
  while ($true) {
    try { if (& $Test) { return $true } } catch {}
    if (((Get-Date)-$start).TotalSeconds -ge $TimeoutSeconds) {
      throw $What
    }
    Start-Sleep -Seconds 5
  }
}

function Install-MetalLB {
  Show-Header "Installing MetalLB" "Yellow"

  $env:KUBECONFIG = $Kubeconfig

  Write-Host "- Applying MetalLB manifest..." -ForegroundColor Gray
  & kubectl --kubeconfig $Kubeconfig apply -f "https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml" | Out-Null

  Write-Host "- Waiting for CRDs..." -ForegroundColor Gray
  Wait-ForK8sResource -What "CRDs not ready in time." -TimeoutSeconds 180 -Test {
    $crd = (& kubectl --kubeconfig $Kubeconfig get crd ipaddresspools.metallb.io -o name 2>$null)
    return -not [string]::IsNullOrWhiteSpace($crd)
  } | Out-Null

  Write-Host "- Waiting for controller deployment..." -ForegroundColor Gray
  & kubectl --kubeconfig $Kubeconfig -n metallb-system rollout status deployment/controller --timeout="240s" | Out-Null

  Write-Host "- Waiting for speaker DaemonSet..." -ForegroundColor Gray
  & kubectl --kubeconfig $Kubeconfig -n metallb-system rollout status ds/speaker --timeout="240s" | Out-Null

  Write-Host "- Waiting for webhook endpoints..." -ForegroundColor Gray
  Wait-ForK8sResource -What "Endpoints not ready in time: metallb-system/metallb-webhook-service" -TimeoutSeconds 240 -Test {
    $epJson = (& kubectl --kubeconfig $Kubeconfig -n metallb-system get endpoints metallb-webhook-service -o json 2>$null)
    if ([string]::IsNullOrWhiteSpace($epJson)) { return $false }
    $ep = $epJson | ConvertFrom-Json
    if ($null -eq $ep.subsets) { return $false }
    foreach ($s in $ep.subsets) {
      if ($s.ports -and $s.addresses) { return $true }
    }
    return $false
  } | Out-Null

  Write-Host "- Applying IPAddressPool/L2Advertisement (VIP: $VipIP)..." -ForegroundColor Gray

  $poolYaml = @"
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: ingress-pool
  namespace: metallb-system
spec:
  addresses:
  - $VipIP/32
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2adv
  namespace: metallb-system
spec:
  ipAddressPools:
  - ingress-pool
"@

  $tmp = Join-Path $env:TEMP "metallb-pool.yaml"
  Set-Content -Path $tmp -Value $poolYaml -Encoding utf8
  & kubectl --kubeconfig $Kubeconfig apply -f $tmp | Out-Null
  Remove-Item -Force -ErrorAction SilentlyContinue $tmp

  Write-Host "- Verifying IPAddressPool exists..." -ForegroundColor Gray
  & kubectl --kubeconfig $Kubeconfig -n metallb-system get ipaddresspools.metallb.io ingress-pool | Out-Null
}

function Install-IngressNginx {
  Show-Header "Installing ingress-nginx (Helm)" "Yellow"

  $env:KUBECONFIG = $Kubeconfig

  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx | Out-Null
  helm repo update | Out-Null

  helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx `
    --namespace ingress-nginx --create-namespace `
    --set controller.service.type=LoadBalancer | Out-Null

  & kubectl --kubeconfig $Kubeconfig rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout="300s" | Out-Null
}

function Install-AppAndIngress {
  Show-Header "Deploying sample app + ingress" "Yellow"

  $appDir      = Join-Path $RepoRoot "04-app"
  $ingressYaml = Join-Path $RepoRoot "03-ingress\nginx-ingress.yaml"

  if (-not (Test-Path $appDir))      { throw "Missing folder: $appDir" }
  if (-not (Test-Path $ingressYaml)) { throw "Missing file: $ingressYaml" }

  & kubectl --kubeconfig $Kubeconfig apply -f $appDir | Out-Null
  & kubectl --kubeconfig $Kubeconfig apply -f $ingressYaml | Out-Null
}

function Install-KubernetesDashboard {
  Show-Header "Kubernetes Dashboard install is not implemented in this file yet." "DarkYellow"
  Write-Host "Next step: wire Helm + Ingress + token flow using your preferred hostname." -ForegroundColor DarkYellow
}

function Show-ClusterSummary {
  Show-Header "Cluster summary" "Cyan"
  & kubectl --kubeconfig $Kubeconfig get nodes -o wide
  & kubectl --kubeconfig $Kubeconfig get pods -A
  & kubectl --kubeconfig $Kubeconfig get svc -A
  & kubectl --kubeconfig $Kubeconfig get ingress 2>$null
}

function Prompt-ClusterInputs {
  Show-Header "Interactive cluster inputs" "Yellow"

  $cp = Read-Host "Control plane IP (default: $ControlPlaneIP)"
  if ($cp) { $script:ControlPlaneIP = $cp }

  $vip = Read-Host "VIP IP for MetalLB (default: $VipIP)"
  if ($vip) { $script:VipIP = $vip }

  Write-Host ""
  Write-Host "Enter worker IPs (one per line). Leave blank to finish." -ForegroundColor Gray
  $workers = New-Object System.Collections.Generic.List[string]
  while ($true) {
    $w = Read-Host "Worker IP"
    if ([string]::IsNullOrWhiteSpace($w)) { break }
    $workers.Add($w)
  }
  if ($workers.Count -gt 0) { $script:WorkerIPs = $workers.ToArray() }

  Write-Host ""
  Write-Host "Using:" -ForegroundColor Gray
  Write-Host "  CP:   $ControlPlaneIP"
  Write-Host "  VIP:  $VipIP"
  Write-Host "  WKR:  $($WorkerIPs -join ', ')"
}

function Invoke-StudentReset {
  Show-Header "Student reset mode" "Yellow"
  Write-Host "Removing local generated files (kubeconfig + overrides)..." -ForegroundColor Gray

  Remove-Item -Force -ErrorAction SilentlyContinue $Kubeconfig
  if (Test-Path $OverridesDir) { Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $OverridesDir }

  Write-Host "Local kubeconfig + overrides removed." -ForegroundColor Green
}

# -------------------------
# Main
# -------------------------
Clear-Host
Show-Header "== CITA 360 Talos + Kubernetes Bootstrap (Simple) ==" "Cyan"
Write-Host "Repo path: $RepoRoot" -ForegroundColor DarkGray
Write-Host ""

Assert-Command kubectl
Assert-Command talosctl

if ($Interactive) { Prompt-ClusterInputs }
if ($WipeAndRebuild) { Invoke-StudentReset }

# ----- Add-ons only mode -----
if ($AddonsOnly) {
  Show-Header "Add-ons only mode" "DarkYellow"

  if (-not (Test-Path $Kubeconfig)) {
    throw "kubeconfig not found at: $Kubeconfig. Run full bootstrap once first."
  }

  Ensure-CoreDNSReady

  # If no selectors provided, do normal lab defaults
  if (-not ($InstallMetalLB -or $InstallIngress -or $InstallApp -or $InstallDashboard)) {
    $InstallMetalLB = $true
    $InstallIngress = $true
    $InstallApp     = $true
  }

  if ($InstallMetalLB) { Install-MetalLB }
  if ($InstallIngress -or $InstallDashboard) { Assert-Command helm }
  if ($InstallIngress) { Install-IngressNginx }
  if ($InstallApp)     { Install-AppAndIngress }
  if ($InstallDashboard) { Install-KubernetesDashboard }

  Show-ClusterSummary
  Write-Host ""
  Write-Host "Done." -ForegroundColor Green
  Write-Host "Test URL (inside lab network): http://$VipIP"
  return
}

# ----- Dashboard only mode -----
if ($DashboardOnly) {
  Show-Header "Dashboard only mode" "DarkYellow"

  if (-not (Test-Path $Kubeconfig)) { throw "kubeconfig not found at: $Kubeconfig. Run bootstrap first." }

  Assert-Command helm
  Ensure-CoreDNSReady

  if (-not $InstallDashboard) { $InstallDashboard = $true }
  Install-KubernetesDashboard

  Show-ClusterSummary
  Write-Host ""
  Write-Host "Done." -ForegroundColor Green
  return
}

# ----- Normal full bootstrap -----
Assert-Command helm

Write-Host "ClusterName:    $ClusterName"
Write-Host "ControlPlaneIP: $ControlPlaneIP"
Write-Host "Workers:        $($WorkerIPs -join ', ')"
Write-Host "VIP (MetalLB):  $VipIP"
Write-Host ""

Assert-Reachable $ControlPlaneIP "Control Plane"
foreach ($w in $WorkerIPs) { Assert-Reachable $w "Worker" }

Show-Header "Waiting for Talos API (50000) on control plane" "Yellow"
Wait-ForPort $ControlPlaneIP 50000 $TimeoutTalosApiSeconds "Talos API"

Show-Header "Generating Talos configs (fresh PKI)" "Yellow"
New-CleanOverridesDir
& talosctl gen config $ClusterName "https://${ControlPlaneIP}:6443" --output-dir $OverridesDir --force | Out-Null

if (-not (Test-Path (Join-Path $OverridesDir "controlplane.yaml"))) { throw "controlplane.yaml missing." }
if (-not (Test-Path (Join-Path $OverridesDir "worker.yaml")))      { throw "worker.yaml missing." }
if (-not (Test-Path $TalosConfig))                                 { throw "talosconfig missing." }

Set-TalosContext

if (-not $SkipApply) {
  Show-Header "Applying configs (maintenance API uses --insecure)" "Yellow"

  Talos-Apply $ControlPlaneIP (Join-Path $OverridesDir "controlplane.yaml")
  foreach ($w in $WorkerIPs) { Talos-Apply $w (Join-Path $OverridesDir "worker.yaml") }

  Show-Header "Waiting for Talos API to restart after apply-config" "Yellow"
  Wait-ForPortDownThenUp $ControlPlaneIP 50000 240 "Talos API restart (CP)"
} else {
  Show-Header "Skipping apply-config (SkipApply set)" "DarkYellow"
}

Show-Header "Bootstrapping control plane" "Yellow"
Talos-Bootstrap

Show-Header "Waiting for Kubernetes API (6443)" "Yellow"
Wait-ForPort $ControlPlaneIP 6443 $TimeoutK8sApiSeconds "Kubernetes API"

Show-Header "Fetching kubeconfig + waiting for kubectl" "Yellow"
Talos-Kubeconfig
Wait-ForKubectl $Kubeconfig $TimeoutKubectlSeconds

Write-Host ""
Write-Host "Kubernetes is up." -ForegroundColor Green

Ensure-CoreDNSReady

if (-not $SkipAddons) {
  Install-MetalLB
  Install-IngressNginx
  Install-AppAndIngress
} else {
  Show-Header "Skipping add-ons (SkipAddons set)" "DarkYellow"
}

Show-ClusterSummary

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "Test URL (inside lab network): http://$VipIP"
