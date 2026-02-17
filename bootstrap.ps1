<#
bootstrap.ps1
Run this on the Talos CTL VM (inside the isolated lab network).

Behavior:
- If cluster is already reachable (kubectl works), Talos config/apply/bootstrap is SKIPPED.
- If cluster is not reachable, script performs Talos bootstrap then continues.

Examples:
  .\bootstrap.ps1
  .\bootstrap.ps1 -ControlPlaneIP 192.168.1.13 -WorkerIPs 192.168.1.16,192.168.1.17 -VipIP 192.168.1.210
  .\bootstrap.ps1 -TalosOnly
#>

[CmdletBinding()]
param(
  [string]$ClusterName    = "cita360",
  [string]$ControlPlaneIP = "192.168.1.3",

  # Preferred: any number of workers
  [string[]]$WorkerIPs    = @(),

  # Legacy (compat)
  [string]$Worker1IP      = "192.168.1.6",
  [string]$Worker2IP      = "192.168.1.7",

  [string]$VipIP          = "192.168.1.200",

  [switch]$TalosOnly
)

$ErrorActionPreference = "Stop"

$script:RepoKubeconfigPath = Join-Path $PSScriptRoot "kubeconfig"

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
  param([Parameter(Mandatory=$true)][string]$Prompt, [string]$Default = "")
  $suffix = if ($Default) { " [$Default]" } else { "" }
  $v = Read-Host "$Prompt$suffix"
  if ([string]::IsNullOrWhiteSpace($v)) { return $Default }
  return $v.Trim()
}

function Read-IPv4Prompt {
  param([Parameter(Mandatory=$true)][string]$Prompt, [Parameter(Mandatory=$true)][string]$Default)
  while ($true) {
    $v = Read-Default -Prompt $Prompt -Default $Default
    $ipObj = $null
    if ([System.Net.IPAddress]::TryParse($v, [ref]$ipObj) -and $ipObj.AddressFamily -eq 'InterNetwork') { return $v }
    Write-Host "Invalid IPv4 address. Try again." -ForegroundColor Yellow
  }
}

function Read-IPv4ListPrompt {
  param([Parameter(Mandatory=$true)][string]$Prompt, [string[]]$Defaults = @())

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

function Test-KubectlWithKubeconfig {
  param([string]$Path)
  if (-not $Path) { return $false }
  if (-not (Test-Path $Path)) { return $false }

  & kubectl --kubeconfig $Path get nodes -o name 2>$null | Out-Null
  return ($LASTEXITCODE -eq 0)
}

function Resolve-WorkingKubeconfig {
  # 1) repo-local kubeconfig (preferred for class)
  if (Test-KubectlWithKubeconfig -Path $script:RepoKubeconfigPath) { return $script:RepoKubeconfigPath }

  # 2) default kubeconfig
  $default = Join-Path $HOME ".kube\config"
  if (Test-KubectlWithKubeconfig -Path $default) { return $default }

  return $null
}

function Invoke-Kube {
  param(
    [Parameter(Mandatory=$true)][string]$KubeconfigPath,
    [Parameter(ValueFromRemainingArguments=$true)][string[]]$Args
  )
  & kubectl --kubeconfig $KubeconfigPath @Args
}

function Wait-ForIngressExternalIP {
  param(
    [Parameter(Mandatory=$true)][string]$KubeconfigPath,
    [int]$TimeoutSeconds = 240
  )

  $start = Get-Date
  while ($true) {
    $svcJson = Invoke-Kube -KubeconfigPath $KubeconfigPath -Args @("get","svc","-n","ingress-nginx","ingress-nginx-controller","-o","json") 2>$null
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
# Prompt logic
# -------------------------
if (-not $WorkerIPs -or $WorkerIPs.Count -eq 0) {
  $WorkerIPs = @($Worker1IP, $Worker2IP) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
}

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
}

Assert-IPv4 $ControlPlaneIP "ControlPlaneIP"
Assert-IPv4 $VipIP "VipIP"
if (-not $WorkerIPs -or $WorkerIPs.Count -lt 1) { throw "You must provide at least one worker IP." }
for ($i=0; $i -lt $WorkerIPs.Count; $i++) { Assert-IPv4 $WorkerIPs[$i] ("WorkerIPs[{0}]" -f $i) }

Write-Host "== CITA 360 Talos + Kubernetes Bootstrap ==" -ForegroundColor Cyan
Write-Host "ClusterName:    $ClusterName"
Write-Host "ControlPlaneIP: $ControlPlaneIP"
Write-Host "Workers:        $($WorkerIPs -join ', ')"
Write-Host "VIP (MetalLB):  $VipIP"
Write-Host ""

# Tools
Assert-Command talosctl
Assert-Command kubectl
Assert-Command git
Assert-Command helm

# Basic reachability
Assert-Reachable $ControlPlaneIP "Control Plane"
for ($i=0; $i -lt $WorkerIPs.Count; $i++) { Assert-Reachable $WorkerIPs[$i] ("Worker {0}" -f ($i+1)) }

# -------------------------
# NEW: If cluster is already reachable, skip Talos steps
# -------------------------
$KubeconfigPath = Resolve-WorkingKubeconfig
if ($KubeconfigPath) {
  Write-Host "Cluster appears reachable already. Skipping Talos apply/bootstrap." -ForegroundColor Green
  Write-Host "Using kubeconfig: $KubeconfigPath" -ForegroundColor DarkGray

  if ($TalosOnly) {
    Write-Host "`nTalos-only mode requested, but cluster is already up. Nothing to do." -ForegroundColor Green
    exit 0
  }
}
else {
  # --- Talos bootstrap path
  $OverridesDir = Join-Path $PSScriptRoot "01-talos\student-overrides"
  New-Item -ItemType Directory -Force -Path $OverridesDir | Out-Null

  Write-Host "`n[1/6] Generating Talos configs..." -ForegroundColor Yellow
  talosctl gen config $ClusterName "https://$ControlPlaneIP`:6443" --output-dir $OverridesDir

  $TalosConfigPath = Join-Path $OverridesDir "talosconfig"
  if (-not (Test-Path $TalosConfigPath)) { throw "Missing talosconfig at: $TalosConfigPath" }
  $env:TALOSCONFIG = $TalosConfigPath
  Write-Host "Using TALOSCONFIG: $TalosConfigPath" -ForegroundColor DarkGray

  function Invoke-TalosApplyConfig {
    param(
      [Parameter(Mandatory=$true)][string]$NodeIP,
      [Parameter(Mandatory=$true)][ValidateSet("controlplane","worker")][string]$Role
    )

    $file = if ($Role -eq "controlplane") { Join-Path $OverridesDir "controlplane.yaml" } else { Join-Path $OverridesDir "worker.yaml" }
    if (-not (Test-Path $file)) { throw "Missing config file: $file" }

    Write-Host "Applying $Role config to $NodeIP..." -ForegroundColor Gray

    # Try insecure first (fresh nodes); if TLS required, retry using talosconfig
    $out = talosctl apply-config --insecure --nodes $NodeIP --endpoints $ControlPlaneIP --file $file 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) { return }

    if ($out -match "certificate required") {
      Write-Host "Node requires TLS; retrying apply-config using TALOSCONFIG..." -ForegroundColor Yellow
      talosctl apply-config --nodes $NodeIP --endpoints $ControlPlaneIP --file $file
      if ($LASTEXITCODE -ne 0) { throw "apply-config failed for ${NodeIP}" }
      return
    }

    throw "apply-config failed for ${NodeIP}: $out"
  }

  Write-Host "`n[2/6] Applying Talos configs..." -ForegroundColor Yellow
  Invoke-TalosApplyConfig -NodeIP $ControlPlaneIP -Role "controlplane"
  foreach ($w in $WorkerIPs) { Invoke-TalosApplyConfig -NodeIP $w -Role "worker" }

  Write-Host "`n[3/6] Bootstrapping Kubernetes control plane..." -ForegroundColor Yellow
  talosctl bootstrap --nodes $ControlPlaneIP --endpoints $ControlPlaneIP

  Write-Host "`n[4/6] Fetching kubeconfig..." -ForegroundColor Yellow
  if (Test-Path $script:RepoKubeconfigPath) { Remove-Item $script:RepoKubeconfigPath -Force }
  talosctl kubeconfig $script:RepoKubeconfigPath --nodes $ControlPlaneIP --endpoints $ControlPlaneIP --force
  if (-not (Test-Path $script:RepoKubeconfigPath)) { throw "talosctl kubeconfig did not create: $($script:RepoKubeconfigPath)" }

  $KubeconfigPath = $script:RepoKubeconfigPath
  Write-Host "Kubeconfig created: $KubeconfigPath" -ForegroundColor Green

  Write-Host "`nVerifying nodes (may take a minute)..." -ForegroundColor Yellow
  Invoke-Kube -KubeconfigPath $KubeconfigPath -Args @("get","nodes","-o","wide")

  if ($TalosOnly) {
    Write-Host "`nTalos-only mode complete." -ForegroundColor Green
    exit 0
  }
}

# -------------------------
# MetalLB + Ingress + App
# -------------------------

Write-Host "`n[5/6] Installing MetalLB..." -ForegroundColor Yellow

$metallbBase    = Join-Path $PSScriptRoot "02-metallb\base"
$metallbOverlay = Join-Path $PSScriptRoot "02-metallb\overlays\example"

if (-not (Test-Path $metallbBase))    { throw "Missing folder: $metallbBase" }
if (-not (Test-Path $metallbOverlay)) { throw "Missing folder: $metallbOverlay" }

Invoke-Kube -KubeconfigPath $KubeconfigPath -Args @("apply","-f",$metallbBase)

# Update VIP in pool automatically
$poolFile = Join-Path $PSScriptRoot "02-metallb\overlays\example\metallb-pool.yaml"
if (Test-Path $poolFile) {
  $content = Get-Content $poolFile -Raw
  $content = [regex]::Replace($content, '(?m)^\s*-\s*\d{1,3}(\.\d{1,3}){3}/32\s*$', "    - $VipIP/32")
  Set-Content -Path $poolFile -Value $content -Encoding utf8
}

Invoke-Kube -KubeconfigPath $KubeconfigPath -Args @("apply","-f",$metallbOverlay)

Write-Host "`n[6/6] Installing ingress-nginx via Helm..." -ForegroundColor Yellow
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx | Out-Null
helm repo update | Out-Null

$env:KUBECONFIG = $KubeconfigPath

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx `
  --namespace ingress-nginx --create-namespace `
  --set controller.service.type=LoadBalancer | Out-Null

Write-Host "Waiting for ingress controller deployment to be ready..." -ForegroundColor Yellow
Invoke-Kube -KubeconfigPath $KubeconfigPath -Args @("rollout","status","deployment/ingress-nginx-controller","-n","ingress-nginx","--timeout=240s")

Write-Host "Waiting for EXTERNAL-IP from MetalLB..." -ForegroundColor Yellow
$assignedIP = Wait-ForIngressExternalIP -KubeconfigPath $KubeconfigPath -TimeoutSeconds 240
Write-Host "Ingress EXTERNAL-IP: $assignedIP" -ForegroundColor Green

Write-Host "`nDeploying sample NGINX app + Ingress rule..." -ForegroundColor Yellow

$appDir      = Join-Path $PSScriptRoot "04-app"
$ingressYaml = Join-Path $PSScriptRoot "03-ingress\nginx-ingress.yaml"

if (-not (Test-Path $appDir))      { throw "Missing folder: $appDir" }
if (-not (Test-Path $ingressYaml)) { throw "Missing file: $ingressYaml" }

Invoke-Kube -KubeconfigPath $KubeconfigPath -Args @("apply","-f",$appDir)
Invoke-Kube -KubeconfigPath $KubeconfigPath -Args @("apply","-f",$ingressYaml)

Write-Host "`nCluster summary:" -ForegroundColor Cyan
Invoke-Kube -KubeconfigPath $KubeconfigPath -Args @("get","nodes")
Invoke-Kube -KubeconfigPath $KubeconfigPath -Args @("get","pods","-A")
Invoke-Kube -KubeconfigPath $KubeconfigPath -Args @("get","svc","-A")
Invoke-Kube -KubeconfigPath $KubeconfigPath -Args @("get","ingress")

Write-Host "`nDone." -ForegroundColor Green
Write-Host "Test URL (inside your lab network): http://$VipIP"
Write-Host "Note: MetalLB assigned ingress EXTERNAL-IP: $assignedIP"
