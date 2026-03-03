function Assert-IsAdmin {
    $current = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $current.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "This tool must be run as Administrator."
    }
}

function Get-RoleInstallState {
    param(
        [Parameter(Mandatory=$true)][string[]]$FeatureNames
    )

    $hasWindowsFeatureCmd = [bool](Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue)

    if (-not $hasWindowsFeatureCmd) {
        $states = @()
        foreach ($f in $FeatureNames) {
            $states += [pscustomobject]@{
                Feature   = $f
                Installed = $false
                Available = $false
                Notes     = "Server feature query is unavailable on this OS"
            }
        }
        return $states
    }

    $states = @()
    foreach ($f in $FeatureNames) {
        $feature = Get-WindowsFeature -Name $f -ErrorAction SilentlyContinue
        $states += [pscustomobject]@{
            Feature   = $f
            Installed = [bool]($feature -and $feature.Installed)
            Available = $true
            Notes     = ""
        }
    }
    return $states
}
