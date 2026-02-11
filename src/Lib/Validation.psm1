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

    $states = @()
    foreach ($f in $FeatureNames) {
        $feature = Get-WindowsFeature -Name $f -ErrorAction SilentlyContinue
        $states += [pscustomobject]@{
            Feature   = $f
            Installed = [bool]($feature -and $feature.Installed)
        }
    }
    return $states
}
