[CmdletBinding()]
param(
    [parameter(Mandatory=$false, Position=0)]
    [string]$PackageName = $env:chocolateyPackageName,

    [Parameter(Mandatory=$true, Position=1)]
    [string]$Name,

    [Parameter(Mandatory=$true, Position=2)]
    [string]$Version = $env:chocolateyPackageVersion,

    [Parameter(ValueFromRemainingArguments = $true)]
    [Object[]] $IgnoredArguments
)

Write-Debug "Running 'Uninstall-ChocolateyPowerShellModule' for $packageName with Name:`'$Name`', Version:`'$Version`' "

Write-Debug "Checking for installation of module `'$Name`' "

$foundModule = $false

$availableModules = [array](Get-Module -ListAvailable | Where-Object { $_.Name -eq $Name })

if ($availableModules.Count -gt 0) {
    $moduleDirs = & "$($PSScriptRoot)\Get-EnvironmentPath.ps1" -Name 'PSModulePath' -Persisted -Scope System

    foreach ($module in $availableModules) {
        if ($moduleDirs | Where-Object { $module.Path.StartsWith($_.Path, $true, [Globalization.CultureInfo]::CurrentCulture) }) {
            if ($module.Version -eq $Version) {
                $foundModule = $true
                if (Test-Path "$(Split-Path $module.Path -Parent)\.chocolateyModule") {
                    $moduleFolder = Split-Path $module.Path -Parent

                    Write-Host "Removing module files from '$($moduleFolder)'..."
                    Remove-Item $moduleFolder -Recurse -Force -Confirm:$false | Out-Null

                    $moduleParentFolder = Split-Path $moduleFolder -Parent
                    if (-not($moduleDirs -contains $moduleParentFolder) -and -not(Get-ChildItem $moduleParentFolder)) {
                        Write-Debug "Removing empty directory '$($moduleParentFolder)'..."
                        Remove-Item $moduleParentFolder -Recurse -Force -Confirm:$false | Out-Null
                    }
                } else {
                    Write-Warning "Leaving non-managed install of module '$($Name)' v$($Version) at '$($module.Path)'."
                    return
                }
            }
        }
    }
}

if (-not($foundModule)) {
    Write-Warning "Didn't find module '$($Name)' v$($Version) on the system module path."
}
