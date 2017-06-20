[CmdletBinding()]
param(
    [parameter(Mandatory=$false, Position=0)]
    [string]$PackageName = $env:chocolateyPackageName,

    [Parameter(Mandatory=$true, Position=1)]
    [string]$Name,

    [Parameter(Mandatory=$true, Position=2)]
    [string]$Version = $env:chocolateyPackageVersion,

    [Parameter(Mandatory=$true, Position=3)]
    [string]$Url ='',

    [Alias("url64")]
    [Parameter(Mandatory=$false, Position=4)]
    [string]$Url64bit = '',

    [Parameter(Mandatory=$false)]
    [string] $Checksum = '',
    [Parameter(Mandatory=$false)]
    [string] $ChecksumType = '',
    [Parameter(Mandatory=$false)]
    [string] $Checksum64 = '',
    [Parameter(Mandatory=$false)]
    [string] $ChecksumType64 = '',
    [Parameter(Mandatory=$false)]
    [hashtable] $Options = @{Headers=@{}},

    [switch]$Force = $($env:ChocolateyForce -and $env:ChocolateyForce -eq 'True'),

    [Parameter(ValueFromRemainingArguments = $true)]
    [Object[]] $IgnoredArguments
)

#ifdef SOURCE
# Required by Get-ChocolateyUnzip
$helpersPath = "$($env:ChocolateyInstall)\helpers"
Get-ChildItem "$($helpersPath)\functions" | ForEach-Object { . $_.FullName }
#endif

Write-Debug "Running 'Install-ChocolateyPowerShellModule' for $packageName with Name:`'$Name`', Version:`'$Version`'  "

Write-Debug "Checking for existing installation of module `'$Name`' "

$moduleDirs = & "$($PSScriptRoot)\Get-EnvironmentPath.ps1" -Name 'PSModulePath' -Persisted -Scope System

$availableModules = [array](Get-Module -ListAvailable | Where-Object { $_.Name -eq $Name })

$moduleFoldersToDelete = @()

if ($availableModules.Count -gt 0) {
    foreach ($module in $availableModules) {
        if ($moduleDirs | Where-Object { $module.Path.StartsWith($_.Path, $true, [Globalization.CultureInfo]::CurrentCulture) }) {
            if ($module.Version -eq $Version) {
                if ($Force.IsPresent) {
                    $moduleFoldersToDelete += (Split-Path $module.Path -Parent)
                } else {
                    Write-Warning "Module '$($Name)' v$($Version) is already installed at '$($module.Path)'."
                    return
                }
            } else {
                $moduleFolder = Split-Path $module.Path -Parent
                if ((Test-Path "$($moduleFolder)\.chocolateyModule") -or $Force.IsPresent) {
                    $moduleFoldersToDelete += (Split-Path $module.Path -Parent)
                } else {
                    Write-Error "Module '$($Name)' v$($Version) is currently installed at '$($module.Path)'."
                    return
                }
            }
        }
    }
}

$tempDir = "$($env:TEMP)\$([guid]::NewGuid())"

try {
    $filePath = Get-ChocolateyWebFile $packageName "$($tempDir)\$($Name).$($Version).nupkg" $url $url64bit -checksum $checksum -checksumType $checksumType -checksum64 $checksum64 -checksumType64 $checksumType64 -Options $options

    try {
        $dirPath = Get-ChocolateyUnzip $filePath "$($tempDir)\$($Name).$($Version)"

        if (Test-Path "$($dirPath)\_rels") {
            Remove-Item "$($dirPath)\_rels" -Recurse -Force -Confirm:$false | Out-Null
        }

        if (Test-Path "$($dirPath)\[Content_Types].xml") {
            Remove-Item "$($dirPath)\[Content_Types].xml" -Force -Confirm:$false | Out-Null
        }

        $moduleTargetDir = "$($env:ProgramFiles)\WindowsPowerShell\Modules"

        foreach ($moduleFolder in $moduleFoldersToDelete) {
            Write-Host "Removing module files from '$($moduleFolder)'..."
            Remove-Item $moduleFolder -Recurse -Force -Confirm:$false | Out-Null

            $moduleParentFolder = Split-Path $moduleFolder -Parent
            if (-not($moduleDirs -contains $moduleParentFolder) -and -not(Get-ChildItem $moduleParentFolder)) {
                Write-Debug "Removing empty directory '$($moduleParentFolder)'..."
                Remove-Item $moduleParentFolder -Recurse -Force -Confirm:$false | Out-Null
            }
        }

        Write-Host "Copying module files to '$($moduleTargetDir)\$($Name)\$($Version)'..."
        New-Item "$($moduleTargetDir)\$($Name)\$($Version)" -Type Directory | Out-Null
        & "$($PSScriptRoot)\Invoke-Application.ps1" -Name 'robocopy' -Arguments "`"$dirPath`" `"$($moduleTargetDir)\$($Name)\$($Version)`" /MIR" -ReturnType 'Output' -AllowExitCodes @(0, 1) | Out-Null

        "PackageName: $($PackageName)" | Out-File "$($moduleTargetDir)\$($Name)\$($Version)\.chocolateyModule" -Encoding UTF8
    } finally {
        if ($dirPath -and (Test-Path $dirPath)) {
            Remove-Item $dirPath -Recurse -Force -Confirm:$false | Out-Null
        }

        if (Test-Path "$($tempDir)\$($Name).$($Version)") {
            Remove-Item "$($tempDir)\$($Name).$($Version)" -Recurse -Force -Confirm:$false | Out-Null
        }
    }
} finally {
    if ($filePath -and (Test-Path $filePath)) {
        Remove-Item $filePath | Out-Null
    }

    if (Test-Path "$($tempDir)\$($Name).$($Version).nupkg") {
        Remove-Item "$($tempDir)\$($Name).$($Version).nupkg" | Out-Null
    }

    if (Test-Path $tempDir) {
        Remove-Item $tempDir -Recurse -Force -Confirm:$false | Out-Null
    }
}
