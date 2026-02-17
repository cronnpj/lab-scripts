<#
bootstrap.ps1 - Student-proof Talos + Kubernetes lab bootstrap

Goals:
- Safe to re-run (idempotent)
- Avoids regenerating secrets unless explicitly forced
- Blocks MetalLB/Ingress until kubectl works
- Provides reset/retry path if etcd/API is wedged
- Prompts for IPs so each student/project can differ

Usage:
  .\bootstrap.ps1
  .\bootstrap.ps1 -ControlPlaneIP 192.168.1.3 -WorkerIPs 192.168.1.5,192.168.1.6 -VipIP 192.168.1.200
  .\bootstrap.ps1 -InstallOnly           # skip Talos apply/bootstrap, only installs MetalLB/Ingress/App if kubectl works
  .\bootstrap.ps1 -ForceRegenTalos       # only for fresh nodes
  .\bootstrap.ps1 -AutoResetOnEtcdFail   # automatically resets if etcd is failed
#>

[CmdletBinding()]
param(
  [string]$ClusterName    = "cita360",
  [string]$ControlPlaneIP = "192.168.1.3",
  [string[]]$WorkerIPs    = @("192.168.1.5","192.168.1.6"),
  [string]$VipIP          = "192.168.1.200",

  [switch]$InstallOnly,
  [switch]$ForceRegenTalos,
  [switch]$AutoResetOnEtcdFail
)

$ErrorActionPreference = "Stop"

# Paths
$RepoRoot        = $PSScriptRoot
$OverridesDir    = Join-Path $RepoRoot "01-talos\student-overrides"
$TalosConfigPath = Join-Path $OverridesDir "talosconfig"
$KubeconfigPath  = Join-Path $RepoRoot "kubeconfig"

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

function Test-KubectlOK {
  param([string]$Path)
  if (-not $Path -or -not (Test-Path $Path)) { return $false }
  & kubectl --kubeconfig $Path get nodes -o name 2>$null | Out-Null
  return ($LASTEXITCODE -eq 0)
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
  param([string]$Ip,[int]$Port,[int]$TimeoutSeconds=300)
  $start = Get-Date
  while ($true) {
    if (Test-TcpPort -Ip $Ip -Port $Port) { return $true }
    if (((Get-Date)-$start).TotalSeconds -gt $TimeoutSeconds) { return $false }
    Start-Sleep -Seconds 5
  }
}

function Wait-ForKubectl {
  param([string]$Path,[int]$TimeoutSeconds=300)
  $start = Get-Date
  while ($true) {
    if (Test-KubectlOK -Path $Path) { return $true }
    if (((Get-Date)-$start).TotalSeconds -gt $TimeoutSeconds) { return $false }
    Start-Sleep -Seconds 5
  }
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

function Assert-TalosConfigNotEmpty($path) {
  if (-not (Test-Path $path)) { throw "talosconfig not found: $path" }
  if ((Get-Item $path).Length -lt 50) { throw "talosconfig appears empty/corrupt: $path" }
}

function Set-TalosContext($cp) {
  Assert-TalosConfigNotEmpty $TalosConfigPath
  $env:TALOSCONFIG = $TalosConfigPath
  talosctl config endpoint $cp | Out-Null
  talosctl config node $cp | Out-Null
}

function Get-EtcdStatusLine {
  try {
    $line = (talosctl service | Select-String -Pattern "etcd").Line
    return $line
  } catch { return $null }
}

function Etcd-IsFailed {
  $line = Get-EtcdStatusLine
  if (-not $line) { return $false }
  return ($line -match "\betcd\b" -and $line -match "\bFailed\b")
}

function Reset-ControlPlane {
  param([string]$cp)
  Write-Host ""
  Write-Host "RESETTING control plane Talos state on $cp (this wipes Kubernetes/etcd state)..." -ForegroundColor Yellow
  Write-Host "If this is not what you want, press Ctrl+C now." -ForegroundColor Yellow
  Start-Sleep -Seconds 3

  talosctl reset --nodes $cp --graceful=false --reboot `
    --system-labels-to-wipe STATE --system-labels-to-wipe EPHEMERAL

  Write-Host "Waiting for node to come back..." -ForegroundColor Yellow
  Start-Sleep -Seconds 10
  if (-not (Wait-ForPort -Ip $cp -Port 50000 -TimeoutSeconds 240)) {
    Write-Host "Talos API port 50000 not reachable yet; continue anyway." -ForegroundColor DarkGray
  }
}

# -------------------------
# Header + prompts
# -------------------------
Clear-Host
Write-Host "== CITA 360 Talos + Kubernetes Bootstrap ==" -ForegroundColor Cyan
Write-Host ""

# Only prompt if user didn't supply explicit params (simple heuristic)
if ($PSBoundParameters.Count -eq 0) {
  $ClusterName    = Prompt-Default "Cluster name" $ClusterName
  $ControlPlaneIP = Prompt-Default "Control Plane IP" $ControlPlaneIP
  $WorkerIPs      = Prompt-WorkerIPs $WorkerIPs
  $VipIP          = Prompt-Default "VIP (MetalLB) IP" $VipIP
}

Write-Host ""
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

# Ping checks
Assert-Reachable $ControlPlaneIP "Control Plane"
foreach ($w in $WorkerIPs) { Assert-Reachable $w "Worker" }

# Ensure dirs
New-Item -ItemType Directory -Force -Path $OverridesDir | Out-Null

# -------------------------
# Fast path: if kubectl already works, skip Talos
# -------------------------
if (Test-KubectlOK -Path $KubeconfigPath) {
  Write-Host "kubectl already works with repo kubeconfig. Skipping Talos." -ForegroundColor Green
}
elseif ($InstallOnly) {
  throw "InstallOnly set but kubectl is not working yet. Fix control plane first (etcd/apiserver), then re-run."
}
else {
  # -------------------------
  # Talos config handling
  # -------------------------
  if (-not (Test-Path $TalosConfigPath) -or $ForceRegenTalos) {
    Write-Host "[1/6] Generating Talos configs (fresh)..." -ForegroundColor Yellow
    talosctl gen config $ClusterName "https://$ControlPlaneIP`:6443" --output-dir $OverridesDir
  }

  # Set TALOSCONFIG + node/endpoint
  Set-TalosContext -cp $ControlPlaneIP

  # Apply configs (insecure first; secure retry if needed)
  function Apply-NodeConfig {
    param([string]$ip,[string]$role)

    $file = if ($role -eq "controlplane") { Join-Path $OverridesDir "controlplane.yaml" } else { Join-Path $OverridesDir "worker.yaml" }
    if (-not (Test-Path $file)) { throw "Missing $role config file: $file" }

    Write-Host "Applying $role config to $ip ..." -ForegroundColor Gray
    $out = talosctl apply-config --insecure --nodes $ip --endpoints $ControlPlaneIP --file $file 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) { return }

    if ($out -match "certificate required") {
      Write-Host "TLS required; retrying apply-config securely..." -ForegroundColor Yellow
      talosctl apply-config --nodes $ip --endpoints $ControlPlaneIP --file $file
      if ($LASTEXITCODE -ne 0) { throw "apply-config failed for $ip" }
      return
    }

    throw "apply-config failed for ${ip}:`n$out"
  }

  Write-Host "[2/6] Applying Talos configs..." -ForegroundColor Yellow
  Apply-NodeConfig -ip $ControlPlaneIP -role "controlplane"
  foreach ($w in $WorkerIPs) { Apply-NodeConfig -ip $w -role "worker" }

  Write-Host "[3/6] Bootstrapping Kubernetes control plane..." -ForegroundColor Yellow
  talosctl bootstrap --nodes $ControlPlaneIP --endpoints $ControlPlaneIP 2>$null | Out-Null

  # If etcd failed, offer reset/retry
  Set-TalosContext -cp $ControlPlaneIP
  if (Etcd-IsFailed) {
    Write-Host ""
    Write-Host "Detected etcd FAILED. Kubernetes API will not come up until etcd is healthy." -ForegroundColor Red

    if ($AutoResetOnEtcdFail) {
      Reset-ControlPlane -cp $ControlPlaneIP
      Write-Host "Re-run bootstrap.ps1 now (fresh) after the node returns." -ForegroundColor Yellow
      exit 1
    } else {
      $ans = Read-Host "Reset control plane and try again? (y/n)"
      if ($ans.Trim().ToLower() -eq "y") {
        Reset-ControlPlane -cp $ControlPlaneIP
        Write-Host "Re-run bootstrap.ps1 now (fresh) after the node returns." -ForegroundColor Yellow
        exit 1
      } else {
        Write-Host "Not resetting. Check: talosctl logs etcd --tail 200" -ForegroundColor Yellow
        exit 1
      }
    }
  }

  # Wait for API port
  Write-Host "[4/6] Waiting for Kubernetes API (6443)..." -ForegroundColor Yellow
  if (-not (Wait-ForPort -Ip $ControlPlaneIP -Port 6443 -TimeoutSeconds 300)) {
    Write-Host "API port still not reachable. Check etcd/apiserver logs:" -ForegroundColor Red
    Write-Host "  talosctl logs etcd --tail 200" -ForegroundColor DarkGray
    Write-Host "  talosctl logs kube-apiserver --tail 200" -ForegroundColor DarkGray
    exit 1
  }

  # Fetch kubeconfig
  Write-Host "[5/6] Fetching kubeconfig into repo root..." -ForegroundColor Yellow
  talosctl kubeconfig $KubeconfigPath --nodes $ControlPlaneIP --endpoints $ControlPlaneIP --force | Out-Null

  if (-not (Test-Path $KubeconfigPath)) { throw "kubeconfig not created at $KubeconfigPath" }

  # Wait for kubectl
  Write-Host "Waiting for kubectl..." -ForegroundColor Yellow
  if (-not (Wait-ForKubectl -Path $KubeconfigPath -TimeoutSeconds 300)) {
    Write-Host "kubectl still not working. Check:" -ForegroundColor Red
    Write-Host "  talosctl logs kube-apiserver --tail 200" -ForegroundColor DarkGray
    exit 1
  }
}

# -------------------------
# MetalLB / Ingress / App
# -------------------------
Write-Host "[6/6] Installing MetalLB + ingress-nginx + sample app..." -ForegroundColor Yellow

function Kube {
  param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
  & kubectl --kubeconfig $KubeconfigPath @Args
}

# MetalLB
$metallbBase    = Join-Path $RepoRoot "02-metallb\base"
$metallbOverlay = Join-Path $RepoRoot "02-metallb\overlays\example"
if (-not (Test-Path $metallbBase))    { throw "Missing folder: $metallbBase" }
if (-not (Test-Path $metallbOverlay)) { throw "Missing folder: $metallbOverlay" }

Kube apply -f $metallbBase | Out-Null

# Auto-update VIP in pool
$poolFile = Join-Path $RepoRoot "02-metallb\overlays\example\metallb-pool.yaml"
if (Test-Path $poolFile) {
  $content = Get-Content $poolFile -Raw
  $content = [regex]::Replace($content, '(?m)^\s*-\s*\d{1,3}(\.\d{1,3}){3}/32\s*$', "    - $VipIP/32")
  Set-Content -Path $poolFile -Value $content -Encoding utf8
}
Kube apply -f $metallbOverlay | Out-Null

# Ingress via helm
$env:KUBECONFIG = $KubeconfigPath
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx | Out-Null
helm repo update | Out-Null
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx `
  --namespace ingress-nginx --create-namespace `
  --set controller.service.type=LoadBalancer | Out-Null

Kube rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=240s | Out-Null

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "Next: kubectl --kubeconfig .\kubeconfig get svc -A"