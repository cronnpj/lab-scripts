<#
bootstrap.ps1 (simple + reliable)

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
  .\bootstrap.ps1 -ControlPlaneIP 192.168.1.13 -WorkerIPs 192.168.1.15,192.168.1.16 -VipIP 192.168.1.210

Dashboard (optional):
  .\bootstrap.ps1 -InstallDashboard
  .\bootstrap.ps1 -DashboardOnly -InstallDashboard

Notes:
- apply-config uses --insecure (maintenance API).
- bootstrap does NOT use --insecure (talosctl bootstrap doesn't support it).
- After apply-config, nodes reboot, so we WAIT for port 50000 to return before bootstrap.
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

  # Full flow toggles
  [switch]$SkipApply,
  [switch]$SkipAddons,

  # Dashboard
  [switch]$InstallDashboard,
  [switch]$DashboardOnly
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
      throw "apply-config got 'tls: certificate required' on ${NodeIP}. Node may not be in maintenance mode; re-check Talos stage + IP."
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

function Kube {
  param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
  & kubectl --kubeconfig $Kubeconfig @Args
}

function Wait-ForDeploymentReady([string]$Namespace,[string]$Deployment,[int]$TimeoutSeconds=300) {
  Kube rollout status ("deployment/$Deployment") -n $Namespace --timeout=("$TimeoutSeconds" + "s") | Out-Null
}

function Wait-ForDaemonSetReady([string]$Namespace,[string]$DaemonSet,[int]$TimeoutSeconds=300) {
  $start = Get-Date
  while ($true) {
    $ds = Kube get ds $DaemonSet -n $Namespace -o json | ConvertFrom-Json
    $desired = [int]$ds.status.desiredNumberScheduled
    $ready   = [int]$ds.status.numberReady
    if ($desired -gt 0 -and $desired -eq $ready) { return $true }

    if (((Get-Date)-$start).TotalSeconds -ge $TimeoutSeconds) {
      throw "DaemonSet not ready in time: $Namespace/$DaemonSet (ready $ready / desired $desired)"
    }
    Start-Sleep -Seconds 5
  }
}

# --------------------------------------------
# MetalLB (repo-independent core install)
# --------------------------------------------
function Install-MetalLB {
  Show-Header "Installing MetalLB" "Yellow"

  # Install MetalLB core from official manifest (no repo folder dependency)
  # Pin a known-good version for repeatable labs.
  $manifestUrl = "https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml"

  Write-Host "- Applying MetalLB manifest..." -ForegroundColor Gray
  Kube apply -f $manifestUrl | Out-Null

  Write-Host "- Waiting for CRDs..." -ForegroundColor Gray
  Kube wait --for=condition=Established crd/ipaddresspools.metallb.io --timeout=180s | Out-Null
  Kube wait --for=condition=Established crd/l2advertisements.metallb.io --timeout=180s | Out-Null

  Write-Host "- Waiting for controller deployment..." -ForegroundColor Gray
  Wait-ForDeploymentReady -Namespace "metallb-system" -Deployment "controller" -TimeoutSeconds 300

  Write-Host "- Waiting for speaker DaemonSet..." -ForegroundColor Gray
  Wait-ForDaemonSetReady -Namespace "metallb-system" -DaemonSet "speaker" -TimeoutSeconds 300

  # Prefer using your repo pool file if present; otherwise apply inline YAML
  $metallbOverlay = Join-Path $RepoRoot "02-metallb\overlays\example"
  $poolFile = Join-Path $metallbOverlay "metallb-pool.yaml"

  Write-Host "- Applying IPAddressPool/L2Advertisement (VIP: $VipIP)..." -ForegroundColor Gray

  if (Test-Path $poolFile) {
    # Update VIP inside the pool file
    $content = Get-Content $poolFile -Raw
    $content = [regex]::Replace(
      $content,
      '(?m)^\s*-\s*\d{1,3}(\.\d{1,3}){3}/32\s*$',
      "    - $VipIP/32"
    )
    Set-Content -Path $poolFile -Value $content -Encoding utf8

    Kube apply -f $poolFile | Out-Null
  }
  else {
    # Inline fallback if pool file is missing
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
    $poolYaml | Kube apply -f - | Out-Null
  }

  Write-Host "- Verifying IPAddressPool exists..." -ForegroundColor Gray
  Kube get ipaddresspool -n metallb-system | Out-Null
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

function Install-KubernetesDashboard {
  Show-Header "Installing Kubernetes Dashboard" "Yellow"

  # Install official recommended manifest (stable for labs)
  $dashUrl = "https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml"
  Write-Host "- Applying dashboard manifest..." -ForegroundColor Gray
  Kube apply -f $dashUrl | Out-Null

  Write-Host "- Waiting for dashboard deployments..." -ForegroundColor Gray
  Wait-ForDeploymentReady -Namespace "kubernetes-dashboard" -Deployment "kubernetes-dashboard" -TimeoutSeconds 300
  Wait-ForDeploymentReady -Namespace "kubernetes-dashboard" -Deployment "dashboard-metrics-scraper" -TimeoutSeconds 300

  Write-Host "- Creating admin ServiceAccount + ClusterRoleBinding..." -ForegroundColor Gray
  $rbac = @"
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user-kubernetes-dashboard
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
"@
  $rbac | Kube apply -f - | Out-Null

  # Example host without DNS (hosts-file later):
  $dashHost = "dashboard.$VipIP"

  Write-Host "- Creating Ingress (host: $dashHost)..." -ForegroundColor Gray
  $ing = @"
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kubernetes-dashboard
  namespace: kubernetes-dashboard
  annotations:
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
spec:
  rules:
  - host: $dashHost
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kubernetes-dashboard
            port:
              number: 443
"@
  $ing | Kube apply -f - | Out-Null

  Write-Host "- Generating login token..." -ForegroundColor Gray
  $token = (& kubectl --kubeconfig $Kubeconfig -n kubernetes-dashboard create token admin-user 2>$null).Trim()

  Write-Host ""
  Write-Host "Dashboard URL:" -ForegroundColor Green
  Write-Host ("  https://{0}" -f $dashHost) -ForegroundColor Green
  Write-Host ""
  Write-Host "If DNS isn't set yet, add this to the CTL VM HOSTS file:" -ForegroundColor Yellow
  Write-Host ("  {0}  {1}" -f $VipIP, $dashHost) -ForegroundColor Yellow
  Write-Host "HOSTS path: C:\Windows\System32\drivers\etc\hosts" -ForegroundColor Yellow
  Write-Host ""
  if ($token) {
    Write-Host "Login token (paste into Dashboard):" -ForegroundColor Cyan
    Write-Host $token -ForegroundColor Cyan
  } else {
    Write-Host "Token generation failed. Run:" -ForegroundColor DarkYellow
    Write-Host "  kubectl --kubeconfig `"$Kubeconfig`" -n kubernetes-dashboard create token admin-user" -ForegroundColor DarkYellow
  }
}

function Ensure-KubeReady {
  Assert-Command kubectl
  if (-not (Test-Path $Kubeconfig)) {
    Assert-Command talosctl
    Show-Header "kubeconfig missing; fetching via talosctl" "Yellow"
    Set-TalosContext
    Talos-Kubeconfig
  }
  Wait-ForKubectl $Kubeconfig $TimeoutKubectlSeconds
}

# -------------------------
# Main
# -------------------------
Clear-Host
Show-Header "== CITA 360 Talos + Kubernetes Bootstrap (Simple) ==" "Cyan"

Write-Host "Repo path: $RepoRoot" -ForegroundColor DarkGray
Write-Host ""

# Dashboard-only mode (no rebuild)
if ($DashboardOnly) {
  Show-Header "Dashboard-only mode" "DarkYellow"
  Ensure-KubeReady

  if ($InstallDashboard) {
    Install-KubernetesDashboard
  } else {
    Write-Host "Nothing to do: -DashboardOnly was set but -InstallDashboard was not." -ForegroundColor DarkYellow
  }

  Write-Host ""
  Write-Host "Done." -ForegroundColor Green
  return
}

# Full build requirements
Assert-Command talosctl
Assert-Command kubectl
Assert-Command helm

Write-Host "ClusterName:      $ClusterName"
Write-Host "ControlPlaneIP:   $ControlPlaneIP"
Write-Host "Workers:          $($WorkerIPs -join ', ')"
Write-Host "VIP (MetalLB):    $VipIP"
Write-Host "InstallDashboard: $InstallDashboard"
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

if (-not $SkipAddons) {
  Install-MetalLB
  Install-IngressNginx
  Install-AppAndIngress

  if ($InstallDashboard) {
    Install-KubernetesDashboard
  }
} else {
  Show-Header "Skipping add-ons (SkipAddons set)" "DarkYellow"
}

Show-Header "Cluster summary" "Cyan"
Kube get nodes -o wide
Kube get pods -A
Kube get svc -A
Kube get ingress -A

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "Test URL (inside lab network): http://$VipIP"
