<#
bootstrap.ps1 (interactive + reliable)

What this does (end-to-end):
1) Generates Talos cluster config + PKI
2) Applies controlplane/worker configs (maintenance API, --insecure)
3) Bootsraps etcd/Kubernetes
4) Fetches kubeconfig
5) Installs MetalLB (official manifest) + waits for webhook via EndpointSlice
6) Installs ingress-nginx (Helm)
7) Deploys sample nginx app + ingress
8) Final health validation (HTTP 200 from VIP)

NEW FEATURES:
- Interactive input for CP/W1/W2.../VIP (press Enter to accept defaults)
- Variable number of workers (comma-separated list)
- Final health validation (Invoke-WebRequest -> confirm HTTP 200)
- Optional -WipeAndRebuild mode:
    * Best-effort Talos reset on all nodes (no Proxmox access needed)
    * Cleans local generated configs/kubeconfig
    * Then proceeds with a normal rebuild
  NOTE: If a node still has old STATE/CA on disk and reset doesn't truly wipe it,
        the guaranteed fix is still: delete VM disks in Proxmox.

Assumptions (lab standard):
- Run on Win11 "CTL" VM (management workstation).
- Talos nodes are reachable on the lab network.
- Static IPs already set on Talos VMs BEFORE running this.

Defaults:
  CP  = 192.168.1.3
  W1  = 192.168.1.5
  W2  = 192.168.1.6
  VIP = 192.168.1.200

Usage:
  .\bootstrap.ps1
  .\bootstrap.ps1 -Interactive
  .\bootstrap.ps1 -ControlPlaneIP 192.168.1.13 -WorkerIPs 192.168.1.15,192.168.1.16 -VipIP 192.168.1.210
  .\bootstrap.ps1 -WipeAndRebuild
#>

[CmdletBinding()]
param(
  # If you don't pass these, the script will prompt (press Enter for defaults)
  [string]  $ClusterName    = "cita360",
  [string]  $ControlPlaneIP = "192.168.1.3",
  [string[]]$WorkerIPs      = @("192.168.1.5","192.168.1.6"),
  [string]  $VipIP          = "192.168.1.200",

  [switch]$Interactive,
  [switch]$WipeAndRebuild,

  [int]$TimeoutTalosApiSeconds = 420,
  [int]$TimeoutK8sApiSeconds   = 600,
  [int]$TimeoutKubectlSeconds  = 600,
  [int]$TimeoutMetalLbWebhookSeconds = 420,

  # Final health check
  [int]$TimeoutHttpSeconds = 180,

  # If you ever need to re-run after configs already applied:
  [switch]$SkipApply,
  [switch]$SkipAddons
)

$ErrorActionPreference = "Stop"

# -------------------------
# Paths (repo-relative)
# -------------------------
$RepoRoot     = $PSScriptRoot
$OverridesDir = Join-Path $RepoRoot "01-talos\student-overrides"
$TalosConfig  = Join-Path $OverridesDir "talosconfig"
$Kubeconfig   = Join-Path $RepoRoot "kubeconfig"

# -------------------------
# Helpers
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

function Test-IPv4([string]$ip) {
  return $ip -match '^(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)$'
}

function Normalize-WorkerIPs([string[]]$ips) {
  $clean = @()
  foreach ($x in $ips) {
    if (-not $x) { continue }
    $t = $x.Trim()
    if (-not $t) { continue }
    $clean += $t
  }
  # de-dupe while preserving order
  $seen = @{}
  $out = @()
  foreach ($i in $clean) {
    if (-not $seen.ContainsKey($i)) { $seen[$i] = $true; $out += $i }
  }
  return $out
}

function Prompt-Value([string]$Label,[string]$Default) {
  $v = Read-Host "$Label [$Default]"
  if ([string]::IsNullOrWhiteSpace($v)) { return $Default }
  return $v.Trim()
}

function Prompt-WorkerList([string[]]$DefaultWorkers) {
  $d = ($DefaultWorkers -join ",")
  $raw = Read-Host "Worker IPs (comma-separated) [$d]"
  if ([string]::IsNullOrWhiteSpace($raw)) { return $DefaultWorkers }
  return (Normalize-WorkerIPs ($raw.Split(",") | ForEach-Object { $_.Trim() }))
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
    & kubectl --kubeconfig $KubeconfigPath get nodes 2>$null | Out-Null
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
      throw "apply-config got 'tls: certificate required' on ${NodeIP}. This suggests the node is NOT in maintenance API state (or IP mismatch). Check Talos node stage + IP."
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
      Write-Host "Bootstrap hit connection issue; waiting for Talos API to settle and retrying once..." -ForegroundColor Yellow
      Wait-ForPort $ControlPlaneIP 50000 120 "Talos API (post-apply)"
      Start-Sleep -Seconds 5
      $out2 = & talosctl bootstrap --nodes $ControlPlaneIP --endpoints $ControlPlaneIP 2>&1
      if ($LASTEXITCODE -ne 0) {
        $txt2 = ($out2 | Out-String)
        throw "bootstrap failed after retry:`n$txt2"
      }
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

# IMPORTANT: dumb passthrough so kubectl flags like -o/-A aren't treated as PowerShell parameters
function Kube {
  & kubectl --kubeconfig $Kubeconfig @args
}

function Wait-ForMetalLbWebhookReady {
  param(
    [string]$Namespace = "metallb-system",
    [string]$ServiceName = "metallb-webhook-service",
    [int]$TimeoutSeconds = 420
  )

  $start = Get-Date
  while ($true) {
    # Use EndpointSlice (avoids Endpoints deprecation warning and stderr Stop)
    $json = & kubectl --kubeconfig $Kubeconfig -n $Namespace `
      get endpointslice -l "kubernetes.io/service-name=$ServiceName" -o json 2>$null

    if ($LASTEXITCODE -eq 0 -and $json) {
      try {
        $obj = $json | ConvertFrom-Json
        foreach ($item in @($obj.items)) {
          foreach ($ep in @($item.endpoints)) {
            foreach ($addr in @($ep.addresses)) {
              if ($addr -match '^\d+\.\d+\.\d+\.\d+$') { return $true }
            }
          }
        }
      } catch { }
    }

    if (((Get-Date) - $start).TotalSeconds -ge $TimeoutSeconds) {
      Write-Host ""
      Write-Host "Webhook endpoints not ready after ${TimeoutSeconds}s. Dumping diagnostics..." -ForegroundColor Yellow

      & kubectl --kubeconfig $Kubeconfig -n $Namespace get pods -o wide
      & kubectl --kubeconfig $Kubeconfig -n $Namespace get svc -o wide
      & kubectl --kubeconfig $Kubeconfig -n $Namespace get endpointslice -l "kubernetes.io/service-name=$ServiceName" -o wide

      Write-Host ""
      Write-Host "Recent metallb-system events:" -ForegroundColor Yellow
      & kubectl --kubeconfig $Kubeconfig -n $Namespace get events --sort-by=.lastTimestamp | Select-Object -Last 40

      Write-Host ""
      Write-Host "controller logs (tail):" -ForegroundColor Yellow
      & kubectl --kubeconfig $Kubeconfig -n $Namespace logs deploy/controller --tail=120

      throw "Webhook EndpointSlice not ready in time: ${Namespace}/${ServiceName}"
    }

    Start-Sleep -Seconds 3
  }
}

function Install-MetalLB {
  Show-Header "Installing MetalLB" "Yellow"

  # Option A: official manifest (includes CRDs)
  $manifest = "https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml"

  Write-Host " - Applying MetalLB manifest..." -ForegroundColor Gray
  Kube apply -f $manifest | Out-Null

  Write-Host " - Waiting for CRDs..." -ForegroundColor Gray
  Kube wait --for=condition=Established crd/ipaddresspools.metallb.io --timeout=180s | Out-Null
  Kube wait --for=condition=Established crd/l2advertisements.metallb.io --timeout=180s | Out-Null

  Write-Host " - Waiting for controller deployment..." -ForegroundColor Gray
  Kube rollout status deployment/controller -n metallb-system --timeout=240s | Out-Null

  Write-Host " - Waiting for speaker DaemonSet..." -ForegroundColor Gray
  Kube rollout status daemonset/speaker -n metallb-system --timeout=240s | Out-Null

  Write-Host " - Waiting for webhook endpoints..." -ForegroundColor Gray
  Wait-ForMetalLbWebhookReady -Namespace "metallb-system" -ServiceName "metallb-webhook-service" -TimeoutSeconds $TimeoutMetalLbWebhookSeconds | Out-Null

  Write-Host " - Applying IPAddressPool/L2Advertisement (VIP: $VipIP)..." -ForegroundColor Gray
  $poolFile = Join-Path $RepoRoot "02-metallb\overlays\example\metallb-pool.yaml"
  if (-not (Test-Path $poolFile)) { throw "Missing file: $poolFile" }

  $content = Get-Content $poolFile -Raw
  $content = [regex]::Replace(
    $content,
    '(?m)^\s*-\s*\d{1,3}(\.\d{1,3}){3}/32\s*$',
    "    - $VipIP/32"
  )
  Set-Content -Path $poolFile -Value $content -Encoding utf8

  Kube apply -f $poolFile | Out-Null

  Write-Host " - Verifying IPAddressPool exists..." -ForegroundColor Gray
  $start = Get-Date
  while ($true) {
    $out2 = & kubectl --kubeconfig $Kubeconfig -n metallb-system get ipaddresspools 2>$null
    if ($LASTEXITCODE -eq 0 -and $out2 -match "ingress-pool") { break }
    if (((Get-Date) - $start).TotalSeconds -ge 60) { throw "MetalLB IPAddressPool did not appear after apply." }
    Start-Sleep -Seconds 2
  }
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

function Wait-ForHttp200 {
  param(
    [string]$Url,
    [int]$TimeoutSeconds = 180
  )

  $start = Get-Date
  while ($true) {
    try {
      $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 15
      if ($resp.StatusCode -eq 200) {
        return $true
      }
    } catch {
      # ignore until timeout
    }

    if (((Get-Date) - $start).TotalSeconds -ge $TimeoutSeconds) {
      throw "HTTP health check failed (no 200) within ${TimeoutSeconds}s: $Url"
    }
    Start-Sleep -Seconds 3
  }
}

function Invoke-TalosResetBestEffort {
  param(
    [string[]]$NodeIPs
  )

  Show-Header "WipeAndRebuild: Best-effort Talos reset" "Yellow"
  Write-Host "Attempting to reset nodes via talosctl (best effort)..." -ForegroundColor Gray
  Write-Host "If a node still has old STATE/CA on disk after this, the guaranteed fix is deleting VM disks in Proxmox." -ForegroundColor DarkYellow
  Write-Host ""

  foreach ($ip in $NodeIPs) {
    Write-Host "Resetting Talos node: $ip" -ForegroundColor Gray
    # Use node itself as endpoint (most reliable)
    $out = & talosctl reset --nodes $ip --endpoints $ip --graceful=false --reboot 2>&1
    if ($LASTEXITCODE -ne 0) {
      Write-Host "Reset command failed on $ip (continuing):" -ForegroundColor Yellow
      Write-Host ($out | Out-String) -ForegroundColor DarkGray
    }
  }

  Write-Host ""
  Write-Host "Waiting briefly for nodes to reboot..." -ForegroundColor Gray
  Start-Sleep -Seconds 20
}

# -------------------------
# Main
# -------------------------
Clear-Host
Show-Header "== CITA 360 Talos + Kubernetes Bootstrap (Interactive) ==" "Cyan"

Write-Host "Repo path: $RepoRoot" -ForegroundColor DarkGray
Write-Host ""

Assert-Command talosctl
Assert-Command kubectl
Assert-Command helm

# Auto-prompt if user didn't pass explicit IP args OR if -Interactive is set
$shouldPrompt = $Interactive
if (-not $Interactive) {
  # If they didn't explicitly pass any of these, prompt anyway for student-friendliness
  if (-not $PSBoundParameters.ContainsKey("ControlPlaneIP") -and
      -not $PSBoundParameters.ContainsKey("WorkerIPs") -and
      -not $PSBoundParameters.ContainsKey("VipIP")) {
    $shouldPrompt = $true
  }
}

if ($shouldPrompt) {
  Show-Header "Interactive configuration (press Enter to accept defaults)" "Yellow"

  $ClusterName    = Prompt-Value "Cluster name" $ClusterName
  $ControlPlaneIP = Prompt-Value "Control plane IP" $ControlPlaneIP
  $WorkerIPs      = Prompt-WorkerList $WorkerIPs
  $VipIP          = Prompt-Value "VIP (MetalLB)" $VipIP
}

# Normalize worker list
$WorkerIPs = Normalize-WorkerIPs $WorkerIPs

# Basic validation
if (-not (Test-IPv4 $ControlPlaneIP)) { throw "Invalid ControlPlaneIP: $ControlPlaneIP" }
if (-not (Test-IPv4 $VipIP))          { throw "Invalid VipIP: $VipIP" }
if ($WorkerIPs.Count -lt 1)           { throw "You must provide at least one worker IP." }
foreach ($w in $WorkerIPs) { if (-not (Test-IPv4 $w)) { throw "Invalid worker IP: $w" } }

Show-Header "Time sanity check (Windows)" "Yellow"
Write-Host "Windows time: $(Get-Date)" -ForegroundColor Gray

Write-Host ""
Write-Host "ClusterName:    $ClusterName"
Write-Host "ControlPlaneIP: $ControlPlaneIP"
Write-Host "Workers:        $($WorkerIPs -join ', ')"
Write-Host "VIP (MetalLB):  $VipIP"
Write-Host ""

# Optional wipe/rebuild path
if ($WipeAndRebuild) {
  # Clean local artifacts first
  Show-Header "WipeAndRebuild: cleaning local generated files" "Yellow"
  New-CleanOverridesDir

  # Set a context if we can (may fail if Talosconfig not present yet, that's OK)
  try { Set-TalosContext } catch { }

  # Attempt reset on all nodes
  $allNodes = @($ControlPlaneIP) + @($WorkerIPs)
  Invoke-TalosResetBestEffort -NodeIPs $allNodes

  # After reset, we wait for CP Talos API
  Show-Header "WipeAndRebuild: waiting for Talos API (50000) on control plane" "Yellow"
  Wait-ForPort $ControlPlaneIP 50000 $TimeoutTalosApiSeconds "Talos API (after reset)"
}

# Reachability checks
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

if (-not $SkipAddons) {
  Show-Header "Ensuring CoreDNS is ready" "Yellow"
  Kube rollout status deployment/coredns -n kube-system --timeout=240s | Out-Null

  Install-MetalLB
  Install-IngressNginx
  Install-AppAndIngress
} else {
  Show-Header "Skipping add-ons (SkipAddons set)" "DarkYellow"
}

Show-Header "Cluster summary" "Cyan"
Kube get nodes -o wide
Kube get pods -A
Kube get svc -A
Kube get ingress

# Final health validation
Show-Header "Final health validation" "Yellow"
$testUrl = "http://$VipIP"
Write-Host "Checking: $testUrl (expect HTTP 200)..." -ForegroundColor Gray
Wait-ForHttp200 -Url $testUrl -TimeoutSeconds $TimeoutHttpSeconds | Out-Null
Write-Host "HTTP 200 confirmed: $testUrl" -ForegroundColor Green

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "Test URL (inside lab network): $testUrl"
