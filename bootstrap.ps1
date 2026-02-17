<#
bootstrap.ps1
Run this on the Talos CTL VM (inside the isolated lab network).

Defaults:
  CP  = 192.168.1.3
  W1  = 192.168.1.6
  W2  = 192.168.1.7
  VIP = 192.168.1.200

Examples:
  .\bootstrap.ps1
  .\bootstrap.ps1 -ControlPlaneIP 192.168.1.13 -WorkerIPs 192.168.1.16,192.168.1.17 -VipIP 192.168.1.210
  .\bootstrap.ps1 -TalosOnly

Legacy examples still work:
  .\bootstrap.ps1 -ControlPlaneIP 192.168.1.13 -Worker1IP 192.168.1.16 -Worker2IP 192.168.1.17 -VipIP 192.168.1.210
#>

[CmdletBinding()]
param(
  [string]$ClusterName    = "cita360",
  [string]$ControlPlaneIP = "192.168.1.3",

  # New preferred way: any number of workers
  [string[]]$WorkerIPs    = @(),

  # Legacy (kept for compatibility)
  [string]$Worker1IP      = "192.168.1.6",
  [string]$Worker2IP      = "192.168.1.7",

  [string]$VipIP          = "192.168.1.200",

  # If you want to stop after Talos bootstrap + kubeconfig, use -TalosOnly
  [switch]$TalosOnly
)

$ErrorActionPreference = "Stop"

# Single source of truth for kubeconfig path
$script:KubeconfigPath = Join-Path $PSScriptRoot "kubeconfig"

# -------------------------
# Helpers
# -------------------------
function Assert-Command($name) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
    throw "Missing required command '$name'. Install it first (talosctl / kubectl / git / helm)."
  }
}

function Assert-Reachable($ip, $label) {
  $ok = Test-Connection -ComputerName $ip -Count 1 -Quiet
  if (-not $ok) { throw "$label ($ip) is not reachable. Check IP/subnet/VM power state." }
}

function Assert-IPv4($ip, $label) {
  $ipObj = $null
  if (-not ([System.Net.IPAddress]::TryParse($ip, [ref]$ipObj) -and $ipObj.AddressFamily -eq 'InterNetwork')) {
    throw "$label '$ip' is not a valid IPv4 address."
  }
}

function Read-Default {
  param(
    [Parameter(Mandatory=$true)][string]$Prompt,
    [string]$Default = ""
  )
  $suffix = if ($Default) { " [$Default]" } else { "" }
  $v = Read-Host "$Prompt$suffix"
  if ([string]::IsNullOrWhiteSpace($v)) { return $Default }
  return $v.Trim()
}

function Read-IPv4Prompt {
  param(
    [Parameter(Mandatory=$true)][string]$Prompt,
    [Parameter(Mandatory=$true)][string]$Default
  )
  while ($true) {
    $v = Read-Default -Prompt $Prompt -Default $Default
    $ipObj = $null
    if ([System.Net.IPAddress]::TryParse($v, [ref]$ipObj) -and $ipObj.AddressFamily -eq 'InterNetwork') {
      return $v
    }
    Write-Host "Invalid IPv4 address. Try again." -ForegroundColor Yellow
  }
}

function Read-IPv4ListPrompt {
  param(
    [Parameter(Mandatory=$true)][string]$Prompt,
    [string[]]$Defaults = @()
  )

  Write-Host ""
  Write-Host $Prompt -ForegroundColor Cyan
  Write-Host "Enter one IP per line. Press Enter on a blank line to finish." -ForegroundColor DarkGray
  if ($Defaults.Count -gt 0) {
    Write-Host ("Default workers: {0}" -f ($Defaults -join ", ")) -ForegroundColor DarkGray
    Write-Host "Tip: Press Enter immediately to accept defaults." -ForegroundColor DarkGray
  }

  $items = @()

  $first = Read-Host "Worker IP (blank to finish)"
  if ([string]::IsNullOrWhiteSpace($first)) {
    if ($Defaults.Count -gt 0) { return $Defaults }
    Write-Host "Please enter at least one worker IP." -ForegroundColor Yellow
  } else {
    $items += $first.Trim()
  }

  while ($true) {
    $v = Read-Host "Worker IP (blank to finish)"
    if ([string]::IsNullOrWhiteSpace($v)) { break }
    $items += $v.Trim()
  }

  $out = @()
  foreach ($ip in $items) {
    $ipObj = $null
    if (-not ([System.Net.IPAddress]::TryParse($ip, [ref]$ipObj) -and $ipObj.AddressFamily -eq 'InterNetwork')) {
      Write-Host "Invalid IPv4 in list: $ip" -ForegroundColor Yellow
      return (Read-IPv4ListPrompt -Prompt $Prompt -Defaults $Defaults)
    }
    $out += $ip
  }
  return $out
}

function Invoke-Kube {
  param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)

  if (-not (Test-Path $script:KubeconfigPath)) {
    throw "kubeconfig not found at: $($script:KubeconfigPath). Talos kubeconfig step may have failed."
  }

  & kubectl --kubeconfig $script:KubeconfigPath @Args
}

function Wait-ForIngressExternalIP {
  param([int]$TimeoutSeconds = 240)

  $start = Get-Date
  while ($true) {
    $svcJson = Invoke-Kube -Args @("get","svc","-n","ingress-nginx","ingress-nginx-controller","-o","json") 2>$null
    if ($LASTEXITCODE -eq 0 -and $svcJson) {
      try {
        $obj = $svcJson | ConvertFrom-Json
        $ip  = $obj.status.loadBalancer.ingress[0].ip
        if ($ip) { return $ip }
      } catch { }
    }

    if (((Get-Date) - $start).TotalSeconds -gt $TimeoutSeconds) {
      throw "Timed out waiting for ingress-nginx-controller EXTERNAL-IP."
    }
    Start-Sleep -Seconds 5
  }
}

# -------------------------
# Decide whether to prompt
# -------------------------

# If WorkerIPs not provided, build it from legacy params (defaults or overrides)
if (-not $WorkerIPs -or $WorkerIPs.Count -eq 0) {
  $WorkerIPs = @($Worker1IP, $Worker2IP) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
}

# Determine if user explicitly passed any parameters (non-interactive intent)
$boundKeys = @($PSBoundParameters.Keys)

$ranWithExplicitValues =
  $boundKeys.Contains("ClusterName") -or
  $boundKeys.Contains("ControlPlaneIP") -or
  $boundKeys.Contains("WorkerIPs") -or
  $boundKeys.Contains("Worker1IP") -or
  $boundKeys.Contains("Worker2IP") -or
  $boundKeys.Contains("VipIP")

if (-not $ranWithExplicitValues) {
  Clear-Host
  Write-Host "== CITA 360 Talos + Kubernetes Bootstrap ==" -ForegroundColor Cyan
  Write-Host ""

  $defaultWorkers = @("192.168.1.6", "192.168.1.7")

  $ClusterName    = Read-Default         -Prompt "Cluster name"       -Default $ClusterName
  $ControlPlaneIP = Read-IPv4Prompt      -Prompt "Control Plane IP"   -Default $ControlPlaneIP
  $WorkerIPs      = Read-IPv4ListPrompt  -Prompt "Worker node IPs"    -Defaults $defaultWorkers
  $VipIP          = Read-IPv4Prompt      -Prompt "VIP (MetalLB) IP"   -Default $VipIP

  Write-Host ""
  Write-Host "Using configuration:" -ForegroundColor Green
  Write-Host ("ClusterName:      {0}" -f $ClusterName)
  Write-Host ("ControlPlaneIP:   {0}" -f $ControlPlaneIP)
  Write-Host ("WorkerIPs:        {0}" -f ($WorkerIPs -join ", "))
  Write-Host ("VIP (MetalLB):    {0}" -f $VipIP)
  Write-Host ""
}

# Validate IP formats (even in non-interactive mode)
Assert-IPv4 $ControlPlaneIP "ControlPlaneIP"
Assert-IPv4 $VipIP "VipIP"
if (-not $WorkerIPs -or $WorkerIPs.Count -lt 1) { throw "You must provide at least one worker IP." }
for ($i=0; $i -lt $WorkerIPs.Count; $i++) {
  Assert-IPv4 $WorkerIPs[$i] ("WorkerIPs[{0}]" -f $i)
}

Write-Host "== CITA 360 Talos + Kubernetes Bootstrap ==" -ForegroundColor Cyan
Write-Host "ClusterName:    $ClusterName"
Write-Host "ControlPlaneIP: $ControlPlaneIP"
Write-Host "Workers:        $($WorkerIPs -join ', ')"
Write-Host "VIP (MetalLB):  $VipIP"
Write-Host ""

# Required tools on the Talos CTL VM
Assert-Command talosctl
Assert-Command kubectl
Assert-Command git
Assert-Command helm

# Reachability checks (all nodes)
Assert-Reachable $ControlPlaneIP "Control Plane"
for ($i=0; $i -lt $WorkerIPs.Count; $i++) {
  Assert-Reachable $WorkerIPs[$i] ("Worker {0}" -f ($i+1))
}

# --- Talos: generate configs locally (secrets stay local)
$OverridesDir = Join-Path $PSScriptRoot "01-talos\student-overrides"
New-Item -ItemType Directory -Force -Path $OverridesDir | Out-Null

Write-Host "`n[1/6] Generating Talos configs..." -ForegroundColor Yellow
talosctl gen config $ClusterName "https://$ControlPlaneIP`:6443" --output-dir $OverridesDir

# Always use the generated talosconfig for subsequent calls
$TalosConfigPath = Join-Path $OverridesDir "talosconfig"
if (-not (Test-Path $TalosConfigPath)) { throw "Missing talosconfig at: $TalosConfigPath" }
$env:TALOSCONFIG = $TalosConfigPath
Write-Host "Using TALOSCONFIG: $TalosConfigPath" -ForegroundColor DarkGray

function Invoke-TalosApplyConfig {
  param(
    [Parameter(Mandatory=$true)][string]$NodeIP,
    [Parameter(Mandatory=$true)][ValidateSet("controlplane","worker")][string]$Role
  )

  $file = if ($Role -eq "controlplane") {
    Join-Path $OverridesDir "controlplane.yaml"
  } else {
    Join-Path $OverridesDir "worker.yaml"
  }

  if (-not (Test-Path $file)) { throw "Missing config file: $file" }

  Write-Host "Applying $Role config to $NodeIP..." -ForegroundColor Gray

  # Try insecure first (fresh nodes), then retry secure if Talos already has certs
  $out = talosctl apply-config --insecure --nodes $NodeIP --endpoints $ControlPlaneIP --file $file 2>&1 | Out-String
  if ($LASTEXITCODE -eq 0) { return }

  if ($out -match "certificate required") {
    Write-Host "Node requires TLS; retrying apply-config using TALOSCONFIG..." -ForegroundColor Yellow
    talosctl apply-config --nodes $NodeIP --endpoints $ControlPlaneIP --file $file
    if ($LASTEXITCODE -ne 0) { throw "apply-config failed for $NodeIP" }
    return
  }

  throw "apply-config failed for ${NodeIP}: $out"
}

Write-Host "`n[2/6] Applying Talos configs..." -ForegroundColor Yellow
Invoke-TalosApplyConfig -NodeIP $ControlPlaneIP -Role "controlplane"
foreach ($w in $WorkerIPs) { Invoke-TalosApplyConfig -NodeIP $w -Role "worker" }

Write-Host "`n[3/6] Bootstrapping Kubernetes control plane..." -ForegroundColor Yellow
talosctl bootstrap --nodes $ControlPlaneIP --endpoints $ControlPlaneIP

Write-Host "`n[4/6] Fetching kubeconfig into repo root..." -ForegroundColor Yellow
if (Test-Path $script:KubeconfigPath) { Remove-Item $script:KubeconfigPath -Force }
talosctl kubeconfig $script:KubeconfigPath --nodes $ControlPlaneIP --endpoints $ControlPlaneIP --force
if (-not (Test-Path $script:KubeconfigPath)) { throw "talosctl kubeconfig did not create: $($script:KubeconfigPath)" }

Write-Host "Kubeconfig created: $($script:KubeconfigPath)" -ForegroundColor Green

Write-Host "`nVerifying cluster access..." -ForegroundColor Yellow
Invoke-Kube -Args @("cluster-info")

Write-Host "`nVerifying nodes (may take a minute)..." -ForegroundColor Yellow
Invoke-Kube -Args @("get","nodes","-o","wide")

if ($TalosOnly) {
  Write-Host "`nTalos-only mode complete." -ForegroundColor Green
  exit 0
}

# --- MetalLB
Write-Host "`n[5/6] Installing MetalLB..." -ForegroundColor Yellow

$metallbBase    = Join-Path $PSScriptRoot "02-metallb\base"
$metallbOverlay = Join-Path $PSScriptRoot "02-metallb\overlays\example"

if (-not (Test-Path $metallbBase))    { throw "Missing folder: $metallbBase" }
if (-not (Test-Path $metallbOverlay)) { throw "Missing folder: $metallbOverlay" }

Invoke-Kube -Args @("apply","-f",$metallbBase)

# Optional: update the VIP in the MetalLB pool automatically (so students don't edit YAML)
$poolFile = Join-Path $PSScriptRoot "02-metallb\overlays\example\metallb-pool.yaml"
if (Test-Path $poolFile) {
  $content = Get-Content $poolFile -Raw
  $content = [regex]::Replace($content, '(?m)^\s*-\s*\d{1,3}(\.\d{1,3}){3}/32\s*$', "    - $VipIP/32")
  Set-Content -Path $poolFile -Value $content -Encoding utf8
}

Invoke-Kube -Args @("apply","-f",$metallbOverlay)

# --- Ingress-NGINX via Helm (LoadBalancer)
Write-Host "`n[6/6] Installing ingress-nginx via Helm..." -ForegroundColor Yellow

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx | Out-Null
helm repo update | Out-Null

# Use kubeconfig explicitly for helm
$env:KUBECONFIG = $script:KubeconfigPath

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx `
  --namespace ingress-nginx --create-namespace `
  --set controller.service.type=LoadBalancer | Out-Null

Write-Host "Waiting for ingress controller deployment to be ready..." -ForegroundColor Yellow
Invoke-Kube -Args @("rollout","status","deployment/ingress-nginx-controller","-n","ingress-nginx","--timeout=240s")

Write-Host "Waiting for EXTERNAL-IP from MetalLB..." -ForegroundColor Yellow
$assignedIP = Wait-ForIngressExternalIP -TimeoutSeconds 240
Write-Host "Ingress EXTERNAL-IP: $assignedIP" -ForegroundColor Green

# --- App + Ingress rule
Write-Host "`nDeploying sample NGINX app + Ingress rule..." -ForegroundColor Yellow

$appDir      = Join-Path $PSScriptRoot "04-app"
$ingressYaml = Join-Path $PSScriptRoot "03-ingress\nginx-ingress.yaml"

if (-not (Test-Path $appDir))      { throw "Missing folder: $appDir" }
if (-not (Test-Path $ingressYaml)) { throw "Missing file: $ingressYaml" }

Invoke-Kube -Args @("apply","-f",$appDir)
Invoke-Kube -Args @("apply","-f",$ingressYaml)

Write-Host "`nCluster summary:" -ForegroundColor Cyan
Invoke-Kube -Args @("get","nodes")
Invoke-Kube -Args @("get","pods","-A")
Invoke-Kube -Args @("get","svc","-A")
Invoke-Kube -Args @("get","ingress")

Write-Host "`nDone." -ForegroundColor Green
Write-Host "Test URL (inside your lab network): http://$VipIP"
Write-Host "Note: MetalLB assigned ingress EXTERNAL-IP: $assignedIP"
