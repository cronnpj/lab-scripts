<#
bootstrap.ps1 (simple + reliable + student-proof)

Assumptions (lab standard):
- Run on Win11 "CTL" VM.
- Talos nodes are fresh/wiped (no old STATE).
- Static IPs are set on Talos VMs BEFORE running this.
- IMPORTANT: The Win11 VM clock/timezone MUST be correct (TLS cert validity depends on it).

Defaults:
  CP  = 192.168.1.3
  W1  = 192.168.1.5
  W2  = 192.168.1.6
  VIP = 192.168.1.200

Usage:
  .\bootstrap.ps1
  .\bootstrap.ps1 -Interactive
  .\bootstrap.ps1 -AddonsOnly -InstallMetalLB
  .\bootstrap.ps1 -PortainerOnly -InstallPortainer
  .\bootstrap.ps1 -PortainerOnly -InstallPortainer -PortainerDomain doom.local
  .\bootstrap.ps1 -WipeAndRebuild -Interactive

Key flags:
  -Interactive      Prompt for CP/Workers/VIP (supports variable number of workers)
  -WipeAndRebuild   Best-effort student reset: remove local generated files, re-gen PKI, re-apply configs, re-bootstrap, re-install add-ons
  -AddonsOnly       Only do add-ons (assumes kubeconfig exists and cluster is reachable)
  -InstallMetalLB   Install/repair MetalLB + VIP pool
  -InstallIngress   Install ingress-nginx (Helm)
  -InstallNginx     Alias for -InstallIngress (menu compatibility)
  -InstallApp       Deploy sample app + ingress
  -InstallPortainer Install Portainer CE (Helm + Ingress)
  -PortainerDomain  Base domain for Portainer host (e.g., doom.local -> portainer.doom.local)
  -PortainerOnly    Only Portainer install (assumes ingress + VIP already working)

Notes:
- apply-config uses --insecure (maintenance API).
- bootstrap does NOT use --insecure (talosctl has no such flag for bootstrap).
- MetalLB webhook endpoints can be slow; we wait, but we DO NOT hard-fail the lab if MetalLB is otherwise healthy.
#>

[CmdletBinding()]
param(
  [string]  $ClusterName    = "cita360",
  [string]  $ControlPlaneIP = "192.168.1.3",
  [string[]]$WorkerIPs      = @("192.168.1.5","192.168.1.6"),
  [string]  $VipIP          = "192.168.1.200",

  [int]$TimeoutTalosApiSeconds = 420,
  [int]$TimeoutK8sApiSeconds   = 600,
  [int]$TimeoutKubectlSeconds  = 600,

  [switch]$Interactive,
  [switch]$WipeAndRebuild,

  [switch]$SkipApply,
  [switch]$SkipAddons,

  # Mode controls
  [switch]$AddonsOnly,
  [Alias('DashboardOnly')]
  [switch]$PortainerOnly,

  # Add-on selectors (can be combined with -AddonsOnly)
  [switch]$InstallMetalLB,
  [Alias('InstallNginx')]
  [switch]$InstallIngress,
  [switch]$InstallApp,
  [Alias('InstallDashboard')]
  [switch]$InstallPortainer,
  [Alias('DashboardDomain')]
  [string]$PortainerDomain = ""
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
# Small helpers
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

function Wait-ForK8s {
  param(
    [Parameter(Mandatory)][int]$TimeoutSeconds,
    [Parameter(Mandatory)][scriptblock]$Test,
    [string]$What = "resource"
  )
  $start = Get-Date
  while ($true) {
    try {
      if (& $Test) { return $true }
    } catch {}
    if (((Get-Date)-$start).TotalSeconds -ge $TimeoutSeconds) {
      throw "$What not ready in time."
    }
    Start-Sleep -Seconds 5
  }
}

function Fail-WithWipeInstructions([string]$Details) {
  Write-Host ""
  Write-Host "TLS/x509 mismatch detected." -ForegroundColor Red
  Write-Host "This almost always means either:" -ForegroundColor Red
  Write-Host "  - The Talos node has old STATE/CA on disk, OR" -ForegroundColor Red
  Write-Host "  - The Win11 VM clock/timezone is wrong." -ForegroundColor Red
  Write-Host ""
  Write-Host "Lab Fix (guaranteed):" -ForegroundColor Yellow
  Write-Host "1) Fix Win11 time/timezone (sync time)." -ForegroundColor Yellow
  Write-Host "2) In Proxmox: delete Talos node VM(s) AND their disks (do not keep disks)." -ForegroundColor Yellow
  Write-Host "3) Recreate nodes, boot them, then rerun .\bootstrap.ps1" -ForegroundColor Yellow
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
    if ($txt -match "x509:" -or $txt -match "unknown authority" -or $txt -match "failed to verify certificate" -or $txt -match "expired certificate") {
      Fail-WithWipeInstructions $txt
    }
    if ($txt -match "tls: certificate required") {
      throw "apply-config got 'tls: certificate required' on ${NodeIP}. Node may not be in maintenance API state. Re-check Talos stage + IP."
    }
    throw "apply-config failed for ${NodeIP}:`n$txt"
  }
}

function Talos-Bootstrap {
  Write-Host "Bootstrapping etcd/Kubernetes on control plane..." -ForegroundColor Gray
  $out = & talosctl bootstrap --nodes $ControlPlaneIP --endpoints $ControlPlaneIP 2>&1

  if ($LASTEXITCODE -ne 0) {
    $txt = ($out | Out-String)

    if ($txt -match "x509:" -or $txt -match "unknown authority" -or $txt -match "failed to verify certificate" -or $txt -match "expired certificate") {
      Fail-WithWipeInstructions $txt
    }

    if ($txt -match "connectex:" -or $txt -match "connection refused" -or $txt -match "No connection could be made") {
      Write-Host "Bootstrap hit connection issue; waiting for Talos API to settle and retrying once..." -ForegroundColor Yellow
      Wait-ForPort $ControlPlaneIP 50000 180 "Talos API (post-apply)"
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
    if ($txt -match "x509:" -or $txt -match "unknown authority" -or $txt -match "failed to verify certificate" -or $txt -match "expired certificate") {
      Fail-WithWipeInstructions $txt
    }
    throw "kubeconfig failed:`n$txt"
  }
}

function Kube {
  param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
  & kubectl --kubeconfig $Kubeconfig @Args
}

# -------------------------
# Interactive inputs
# -------------------------
function Read-NonEmpty([string]$Prompt,[string]$Default="") {
  $p = if ($Default) { "$Prompt [$Default]" } else { $Prompt }
  while ($true) {
    $v = Read-Host $p
    if ([string]::IsNullOrWhiteSpace($v)) {
      if ($Default) { return $Default }
      continue
    }
    return $v.Trim()
  }
}

function Read-WorkerIPs([string[]]$DefaultWorkers) {
  Write-Host ""
  Write-Host "Enter worker IPs (one per line). Press Enter on a blank line to finish." -ForegroundColor Gray
  Write-Host "Default workers: $($DefaultWorkers -join ', ')" -ForegroundColor DarkGray
  $list = New-Object System.Collections.Generic.List[string]
  while ($true) {
    $ip = Read-Host "Worker IP"
    if ([string]::IsNullOrWhiteSpace($ip)) { break }
    $list.Add($ip.Trim())
  }
  if ($list.Count -eq 0) { return $DefaultWorkers }
  return $list.ToArray()
}

function Resolve-PortainerHost([string]$VipIP,[string]$ConfiguredDomain="") {
  $candidate = $ConfiguredDomain

  while ($true) {
    if ([string]::IsNullOrWhiteSpace($candidate)) {
      $candidate = Read-Host "Portainer base domain (example doom.local). Leave blank for $VipIP.sslip.io"
    }

    if ([string]::IsNullOrWhiteSpace($candidate)) {
      return "portainer.$VipIP.sslip.io"
    }

    $base = $candidate.Trim().TrimStart('.')
    if ($base -match '^[A-Za-z0-9][A-Za-z0-9.-]*$') {
      if ($base.ToLower().StartsWith('portainer.')) { return $base }
      return "portainer.$base"
    }

    Write-Host "Invalid domain format. Try again (example: doom.local)." -ForegroundColor DarkYellow
    $candidate = ""
  }
}

# -------------------------
# Add-ons
# -------------------------
function Ensure-CoreDNSReady {
  Show-Header "Ensuring CoreDNS is ready" "Yellow"
  Wait-ForK8s -TimeoutSeconds 300 -What "CoreDNS" -Test {
    $p = & kubectl --kubeconfig $Kubeconfig -n kube-system get pods -l k8s-app=kube-dns -o json 2>$null
    if ([string]::IsNullOrWhiteSpace($p)) { return $false }
    $o = $p | ConvertFrom-Json
    if (-not $o.items) { return $false }
    foreach ($item in $o.items) {
      if ($item.status.phase -ne "Running") { return $false }
      $ready = $false
      foreach ($cs in $item.status.containerStatuses) {
        if ($cs.ready -eq $true) { $ready = $true }
      }
      if (-not $ready) { return $false }
    }
    return $true
  } | Out-Null
}

function Install-MetalLB {
  Show-Header "Installing MetalLB" "Yellow"

  # Repo-independent apply (official manifests)
  $manifestUrl = "https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml"

  Write-Host "- Applying MetalLB manifest..." -ForegroundColor Gray
  Kube -- apply -f $manifestUrl | Out-Null

  Write-Host "- Waiting for CRDs..." -ForegroundColor Gray
  Wait-ForK8s -TimeoutSeconds 240 -What "MetalLB CRDs" -Test {
    $x = & kubectl --kubeconfig $Kubeconfig get crd ipaddresspools.metallb.io 2>$null
    return ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($x))
  } | Out-Null

  Write-Host "- Waiting for controller deployment..." -ForegroundColor Gray
  & kubectl --kubeconfig $Kubeconfig -n metallb-system rollout status deployment/controller --timeout="240s" | Out-Null

  Write-Host "- Waiting for speaker DaemonSet..." -ForegroundColor Gray
  & kubectl --kubeconfig $Kubeconfig -n metallb-system rollout status daemonset/speaker --timeout="240s" | Out-Null

  # NEW: student-proof webhook endpoints check (SOFT fail / continue)
  Write-Host "- Waiting for webhook endpoints..." -ForegroundColor Gray

$maxSeconds = 360
$start = Get-Date

while ($true) {

  # Use EndpointSlice instead of deprecated Endpoints API
  $epRaw = & kubectl --kubeconfig $Kubeconfig `
      -n metallb-system `
      get endpointslice `
      -l kubernetes.io/service-name=metallb-webhook-service `
      -o json 2>&1

  # If kubectl failed entirely, ignore and retry
  if ($LASTEXITCODE -ne 0) {
      Start-Sleep -Seconds 5
      if (((Get-Date) - $start).TotalSeconds -gt $maxSeconds) {
          Write-Host ""
          Write-Host "WARNING: Could not confirm webhook endpoints." -ForegroundColor Yellow
          Write-Host "Continuing install (MetalLB pods appear healthy)." -ForegroundColor Yellow
          break
      }
      continue
  }

  # Parse EndpointSlice JSON structure
  try {
      $jsonStart = $epRaw.IndexOf("{")
      if ($jsonStart -ge 0) {
          $json = $epRaw.Substring($jsonStart)
          $obj = $json | ConvertFrom-Json

          # EndpointSlice structure: items[].endpoints[].addresses
          if ($obj.items -and $obj.items.Count -gt 0) {
              $hasAddresses = $false
              foreach ($item in $obj.items) {
                  if ($item.endpoints -and $item.endpoints.Count -gt 0) {
                      foreach ($ep in $item.endpoints) {
                          if ($ep.addresses -and $ep.addresses.Count -gt 0) {
                              $hasAddresses = $true
                              break
                          }
                      }
                  }
                  if ($hasAddresses) { break }
              }
              if ($hasAddresses) {
                  break
              }
          }
      }
  } catch {
      # JSON not ready yet
  }

  if (((Get-Date) - $start).TotalSeconds -gt $maxSeconds) {
      Write-Host ""
      Write-Host "WARNING: MetalLB webhook endpoints not ready after $maxSeconds seconds." -ForegroundColor Yellow
      Write-Host "Continuing lab install." -ForegroundColor Yellow
      break
  }

  Start-Sleep -Seconds 5
}


  # Apply VIP pool + L2Advertisement
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

  $tmp = Join-Path $env:TEMP ("metallb-pool-" + [Guid]::NewGuid().ToString() + ".yaml")
  Set-Content -Path $tmp -Value $poolYaml -Encoding utf8
  try {
    Kube -- apply -f $tmp | Out-Null
  } finally {
    Remove-Item -Force -ErrorAction SilentlyContinue $tmp
  }

  Write-Host "- Verifying IPAddressPool exists..." -ForegroundColor Gray
  Kube -- -n metallb-system get ipaddresspools ingress-pool 2>$null | Out-Null
}

function Install-IngressNginx {
  Show-Header "Installing ingress-nginx (Helm)" "Yellow"

  $env:KUBECONFIG = $Kubeconfig

  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx | Out-Null
  helm repo update | Out-Null

  helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx `
    --namespace ingress-nginx --create-namespace `
    --set controller.service.type=LoadBalancer | Out-Null

  Kube -- rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=240s | Out-Null
}

function Install-AppAndIngress {
  Show-Header "Deploying sample app + ingress" "Yellow"

  $appDir      = Join-Path $RepoRoot "04-app"
  $ingressYaml = Join-Path $RepoRoot "03-ingress\nginx-ingress.yaml"

  if (-not (Test-Path $appDir))      { throw "Missing folder: $appDir" }
  if (-not (Test-Path $ingressYaml)) { throw "Missing file: $ingressYaml" }

  Kube -- apply -f $appDir | Out-Null
  Kube -- apply -f $ingressYaml | Out-Null
}

function Validate-VIPHttp {
  Show-Header "Final health validation (HTTP check)" "Yellow"

  $url = "http://$VipIP"
  Write-Host "Testing: $url" -ForegroundColor Gray

  try {
    $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10
    if ($r.StatusCode -eq 200) {
      Write-Host "HTTP 200 OK from $url" -ForegroundColor Green
    } else {
      Write-Host "HTTP responded with status $($r.StatusCode) from $url" -ForegroundColor Yellow
    }
  } catch {
    Write-Host "WARNING: Could not confirm HTTP 200 from $url yet (ingress/app may still be starting)." -ForegroundColor Yellow
    Write-Host $_.Exception.Message -ForegroundColor DarkGray
  }
}

function Install-Portainer {
  param([Parameter(Mandatory)][string]$PortainerHost)

  Show-Header "Installing Portainer CE (Helm + Ingress)" "Yellow"

  $env:KUBECONFIG = $Kubeconfig

  Write-Host "- Adding Portainer Helm repo..." -ForegroundColor Gray
  helm repo add portainer https://portainer.github.io/k8s/ | Out-Null
  helm repo update | Out-Null

  Write-Host "- Installing/upgrading Portainer release..." -ForegroundColor Gray
  helm upgrade --install portainer portainer/portainer `
    --namespace portainer --create-namespace `
    --set service.type=ClusterIP | Out-Null

  Write-Host "- Waiting for Portainer deployment..." -ForegroundColor Gray
  & kubectl --kubeconfig $Kubeconfig -n portainer rollout status deployment/portainer --timeout="300s" | Out-Null

  Write-Host "- Discovering Portainer service port..." -ForegroundColor Gray
  $svcRaw = & kubectl --kubeconfig $Kubeconfig -n portainer get svc portainer -o json
  $svcObj = $svcRaw | ConvertFrom-Json

  $portainerSvcPort = $null
  foreach ($p in $svcObj.spec.ports) {
    if ($p.port -eq 9000) {
      $portainerSvcPort = 9000
      break
    }
  }
  if ($null -eq $portainerSvcPort -and $svcObj.spec.ports -and $svcObj.spec.ports.Count -gt 0) {
    $portainerSvcPort = [int]$svcObj.spec.ports[0].port
  }
  if ($null -eq $portainerSvcPort) {
    throw "Unable to determine Portainer service port."
  }

  $backendProtocol = if ($portainerSvcPort -eq 9443) { "HTTPS" } else { "HTTP" }

  Write-Host "- Creating Ingress (host: $PortainerHost, port: $portainerSvcPort)..." -ForegroundColor Gray

  $ingYaml = @"
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: portainer-ingress
  namespace: portainer
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "$backendProtocol"
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  ingressClassName: nginx
  rules:
  - host: $PortainerHost
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: portainer
            port:
              number: $portainerSvcPort
"@

  $tmp = Join-Path $env:TEMP ("portainer-ing-" + [Guid]::NewGuid().ToString() + ".yaml")
  Set-Content -Path $tmp -Value $ingYaml -Encoding utf8
  try {
    Kube -- apply -f $tmp | Out-Null
  } finally {
    Remove-Item -Force -ErrorAction SilentlyContinue $tmp
  }

  Write-Host ""
  Write-Host "Portainer URL: http://$PortainerHost" -ForegroundColor Cyan
  Write-Host "If DNS is not configured, add hosts entry: $VipIP $PortainerHost" -ForegroundColor DarkGray
}

function Remove-LocalGeneratedFiles {
  Write-Host "Removing local generated files (kubeconfig + student-overrides)..." -ForegroundColor Yellow
  Remove-Item -Force -ErrorAction SilentlyContinue $Kubeconfig
  if (Test-Path $OverridesDir) {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $OverridesDir
  }
}

# -------------------------
# Main
# -------------------------
Clear-Host
Show-Header "== CITA 360 Talos + Kubernetes Bootstrap (Simple) ==" "Cyan"

Write-Host "Repo path: $RepoRoot" -ForegroundColor DarkGray
Write-Host ""

if ($Interactive) {
  Show-Header "Interactive mode" "Yellow"
  $ClusterName    = Read-NonEmpty "Cluster name" $ClusterName
  $ControlPlaneIP = Read-NonEmpty "Control plane IP" $ControlPlaneIP
  $WorkerIPs      = Read-WorkerIPs $WorkerIPs
  $VipIP          = Read-NonEmpty "VIP (MetalLB) IP" $VipIP
}

# Defaults for add-on selectors
if (-not ($InstallMetalLB -or $InstallIngress -or $InstallApp -or $InstallPortainer)) {
  $InstallMetalLB = $true
  $InstallIngress = $true
  $InstallApp     = $true
}

Assert-Command talosctl
Assert-Command kubectl
Assert-Command helm

Write-Host "ClusterName:    $ClusterName"
Write-Host "ControlPlaneIP: $ControlPlaneIP"
Write-Host "Workers:        $($WorkerIPs -join ', ')"
Write-Host "VIP (MetalLB):  $VipIP"
Write-Host ""

$ResolvedPortainerHost = $null
if ($PortainerOnly -or $InstallPortainer) {
  $ResolvedPortainerHost = Resolve-PortainerHost -VipIP $VipIP -ConfiguredDomain $PortainerDomain
  Write-Host "Portainer host: $ResolvedPortainerHost" -ForegroundColor DarkGray
}

# Portainer-only: assumes kubeconfig exists and cluster is reachable
if ($PortainerOnly) {
  Show-Header "Portainer-only mode" "DarkYellow"
  if (-not (Test-Path $Kubeconfig)) { throw "kubeconfig not found at: $Kubeconfig (run bootstrap first)" }
  Ensure-CoreDNSReady
  Install-Portainer -PortainerHost $ResolvedPortainerHost
  Write-Host ""
  Write-Host "Done." -ForegroundColor Green
  return
}

# Add-ons only: assumes kubeconfig exists
if ($AddonsOnly) {
  Show-Header "Add-ons only mode" "DarkYellow"
  if (-not (Test-Path $Kubeconfig)) { throw "kubeconfig not found at: $Kubeconfig (run bootstrap first)" }

  Ensure-CoreDNSReady

  if ($InstallMetalLB) { Install-MetalLB }
  if ($InstallIngress) { Install-IngressNginx }
  if ($InstallApp)     { Install-AppAndIngress }
  if ($InstallPortainer) { Install-Portainer -PortainerHost $ResolvedPortainerHost }

  Validate-VIPHttp

  Show-Header "Cluster summary" "Cyan"
  Kube -- get nodes -o wide
  Kube -- get pods -A
  Kube -- get svc -A
  Kube -- get ingress

  Write-Host ""
  Write-Host "Done." -ForegroundColor Green
  Write-Host "Test URL (inside lab network): http://$VipIP"
  return
}

# Wipe + rebuild (student reset mode)
if ($WipeAndRebuild) {
  Show-Header "Wipe + Rebuild mode (student reset)" "Yellow"
  Remove-LocalGeneratedFiles
}

# Full bootstrap
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
  if ($InstallMetalLB) { Install-MetalLB }
  if ($InstallIngress) { Install-IngressNginx }
  if ($InstallApp)     { Install-AppAndIngress }
  if ($InstallPortainer) { Install-Portainer -PortainerHost $ResolvedPortainerHost }
} else {
  Show-Header "Skipping add-ons (SkipAddons set)" "DarkYellow"
}

Validate-VIPHttp

Show-Header "Cluster summary" "Cyan"
Kube -- get nodes -o wide
Kube -- get pods -A
Kube -- get svc -A
Kube -- get ingress

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "Test URL (inside lab network): http://$VipIP"
