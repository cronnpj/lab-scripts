<#
bootstrap.ps1
Run this on the Talos CTL VM inside the isolated student network.

Examples:
  .\bootstrap.ps1
  .\bootstrap.ps1 -ControlPlaneIP 192.168.1.33 -Worker1IP 192.168.1.36 -Worker2IP 192.168.1.37 -VipIP 192.168.1.200 -ClusterName cita360
#>

[CmdletBinding()]
param(
  [string]$ClusterName    = "cita360",
  [string]$ControlPlaneIP = "192.168.1.3",
  [string]$Worker1IP      = "192.168.1.6",
  [string]$Worker2IP      = "192.168.1.7",
  [string]$VipIP          = "192.168.1.200",

  # If you want to skip applying manifests (Talos only), use -TalosOnly
  [switch]$TalosOnly
)

$ErrorActionPreference = "Stop"

function Assert-Command($name) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
    throw "Missing required command '$name'. Install it first (talosctl / kubectl / git)."
  }
}

function Assert-Reachable($ip, $label) {
  $ok = Test-Connection -ComputerName $ip -Count 1 -Quiet
  if (-not $ok) { throw "$label ($ip) is not reachable. Check IP/subnet/VM power state." }
}

Write-Host "== CITA 360 Talos + K8s Bootstrap ==" -ForegroundColor Cyan
Write-Host "ClusterName:    $ClusterName"
Write-Host "ControlPlaneIP: $ControlPlaneIP"
Write-Host "Worker1IP:      $Worker1IP"
Write-Host "Worker2IP:      $Worker2IP"
Write-Host "VIP (MetalLB):  $VipIP"
Write-Host ""

Assert-Command talosctl
Assert-Command kubectl

Assert-Reachable $ControlPlaneIP "Control Plane"
Assert-Reachable $Worker1IP      "Worker 1"
Assert-Reachable $Worker2IP      "Worker 2"

# Generate Talos configs locally (secrets stay local)
$OverridesDir = Join-Path $PSScriptRoot "01-talos\student-overrides"
New-Item -ItemType Directory -Force -Path $OverridesDir | Out-Null

Write-Host "Generating Talos configs into $OverridesDir ..." -ForegroundColor Yellow
talosctl gen config $ClusterName "https://$ControlPlaneIP`:6443" --output-dir $OverridesDir

Write-Host "Applying Talos configs..." -ForegroundColor Yellow
talosctl apply-config --insecure --nodes $ControlPlaneIP --file (Join-Path $OverridesDir "controlplane.yaml")
talosctl apply-config --insecure --nodes $Worker1IP      --file (Join-Path $OverridesDir "worker.yaml")
talosctl apply-config --insecure --nodes $Worker2IP      --file (Join-Path $OverridesDir "worker.yaml")

Write-Host "Bootstrapping cluster..." -ForegroundColor Yellow
talosctl bootstrap --nodes $ControlPlaneIP --endpoints $ControlPlaneIP

Write-Host "Fetching kubeconfig into repo root (kubeconfig)..." -ForegroundColor Yellow
talosctl kubeconfig $PSScriptRoot --nodes $ControlPlaneIP --endpoints $ControlPlaneIP

Write-Host "Waiting for nodes to show up..." -ForegroundColor Yellow
kubectl --kubeconfig (Join-Path $PSScriptRoot "kubeconfig") get nodes

if ($TalosOnly) {
  Write-Host "`nTalos-only mode complete." -ForegroundColor Green
  exit 0
}

# Apply lab manifests (assumes your repo folders exist)
Write-Host "`nApplying MetalLB + Ingress + App manifests..." -ForegroundColor Yellow
kubectl --kubeconfig (Join-Path $PSScriptRoot "kubeconfig") apply -f (Join-Path $PSScriptRoot "02-metallb\base")
kubectl --kubeconfig (Join-Path $PSScriptRoot "kubeconfig") apply -f (Join-Path $PSScriptRoot "02-metallb\overlays\example")
kubectl --kubeconfig (Join-Path $PSScriptRoot "kubeconfig") apply -f (Join-Path $PSScriptRoot "03-ingress")
kubectl --kubeconfig (Join-Path $PSScriptRoot "kubeconfig") apply -f (Join-Path $PSScriptRoot "04-app")

Write-Host "`nDone." -ForegroundColor Green
Write-Host "Test from inside the lab network: http://$VipIP"
