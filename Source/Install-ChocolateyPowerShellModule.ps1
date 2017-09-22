[CmdletBinding(DefaultParameterSetName='UseLocalFiles')]
param(
    [parameter(Mandatory=$false, Position=0)]
    [string]$PackageName = $env:chocolateyPackageName,

    [Parameter(Mandatory=$true, Position=1)]
    [string]$Name,

    [Parameter(Mandatory=$true, Position=2, ParameterSetName='UseFileDownload')]
    [string]$Version = $env:chocolateyPackageVersion,

    [Parameter(Mandatory=$true, Position=2, ParameterSetName='UseLocalFiles')]
    [string]$ModulesFolder,

    [Parameter(Mandatory=$true, Position=3, ParameterSetName='UseFileDownload')]
    [string]$Url ='',
    [Alias("url64")]
    [Parameter(Mandatory=$false, Position=4, ParameterSetName='UseFileDownload')]
    [string]$Url64bit = '',
    [Parameter(Mandatory=$false, ParameterSetName='UseFileDownload')]
    [string] $Checksum = '',
    [Parameter(Mandatory=$false, ParameterSetName='UseFileDownload')]
    [string] $ChecksumType = '',
    [Parameter(Mandatory=$false, ParameterSetName='UseFileDownload')]
    [string] $Checksum64 = '',
    [Parameter(Mandatory=$false, ParameterSetName='UseFileDownload')]
    [string] $ChecksumType64 = '',
    [Parameter(Mandatory=$false, ParameterSetName='UseFileDownload')]
    [hashtable] $Options = @{Headers=@{}},

    [switch]$Force = $($env:ChocolateyForce -and $env:ChocolateyForce -eq 'True'),

    [Parameter(ValueFromRemainingArguments = $true)]
    [Object[]] $IgnoredArguments
)

#ifdef SOURCE
. "$($PSScriptRoot)\Functions\Resolve-Module.ps1"
. "$($PSScriptRoot)\Functions\Expand-ModulePackage.ps1"

# Required for Get-ChocolateyUnzip
if ($PSCmdlet.ParameterSetName -eq 'UseFileDownload') {
    $helpersPath = "$($env:ChocolateyInstall)\helpers"
    Get-ChildItem "$($helpersPath)\functions" | ForEach-Object { . $_.FullName }
}
#endif

Write-Debug "Running 'Install-ChocolateyPowerShellModule' for $packageName with Name:`'$Name`', Version:`'$Version`'  "

Write-Debug "Checking for existing installation of module `'$Name`' "

$moduleFoldersToDelete = @()

if ($PSCmdlet.ParameterSetName -eq 'UseLocalFiles') {
    $LocalModule = Resolve-Module -ModuleName $Name -ModulesFolder $ModulesFolder
    $Version = $LocalModule.Version
    Write-Verbose "Found local module $($Name)@$($Version) at path '$($LocalModule.Path)'."
}

$installedModules = [array](Resolve-Module $Name -Global -Scope 'System' -EA 0)

if ($installedModules.Count -gt 0) {
    foreach ($module in $installedModules) {
        if ($module.Version -eq $Version) {
            if ($Force.IsPresent) {
                $moduleFoldersToDelete += (Split-Path $module.Path -Parent)
            } else {
                Write-Warning "Module '$($Name)' v$($module.Version) is already installed at '$($module.Path)'."
                return
            }
        } else {
            $moduleFolder = Split-Path $module.Path -Parent
            if ((Test-Path "$($moduleFolder)\.chocolateyModule") -or $Force.IsPresent) {
                $moduleFoldersToDelete += (Split-Path $module.Path -Parent)
            } else {
                Write-Error "Module '$($Name)' v$($module.Version) is currently installed at '$($module.Path)'."
                return
            }
        }
    }
}

$moduleTargetDir = "$($env:ProgramFiles)\WindowsPowerShell\Modules"

if ($PSVersionTable.PSVersion.Major -ge 5) {
    $moduleDestination = "$($moduleTargetDir)\$($Name)\$($Version)"
} else {
    $moduleDestination = "$($moduleTargetDir)\$($Name)"
}

$tempDir = $null
$tempFile = $null

try {
    if ($PSCmdlet.ParameterSetName -eq 'UseLocalFiles') {
        $SourcePath = Split-Path $LocalModule.Path -Parent
    } elseif ($PSCmdlet.ParameterSetName -eq 'UseFileDownload') {
        $tempFile = "$($env:TEMP)\$($Name).$($Version).nupkg"

        $filePath = Get-ChocolateyWebFile $packageName $tempFile $url $url64bit -checksum $checksum -checksumType $checksumType -checksum64 $checksum64 -checksumType64 $checksumType64 -Options $options

        $tempDir = "$($env:TEMP)\$($Name).$($Version)"

        Expand-ModulePackage $filePath -ModuleName $Name -DestinationPath $tempDir -UnzipScript {
            Get-ChocolateyUnzip $Args[0] $Args[1]
        }

        $SourcePath = $tempDir
    }

    foreach ($moduleFolder in $moduleFoldersToDelete) {
        Write-Host "Removing module files from '$($moduleFolder)'..."
        Remove-Item $moduleFolder -Recurse -Force -Confirm:$false | Out-Null

        $moduleParentFolder = Split-Path $moduleFolder -Parent
        if ((Split-Path $moduleParentFolder -Leaf) -eq $Name) {
            if (-not(Get-ChildItem $moduleParentFolder)) {
                Write-Debug "Removing empty directory '$($moduleParentFolder)'..."
                Remove-Item $moduleParentFolder -Recurse -Force -Confirm:$false | Out-Null
            }
        }
    }

    Write-Host "Copying module files to '$($moduleDestination)'..."
    New-Item $moduleDestination -Type Directory | Out-Null
    & "$($PSScriptRoot)\Invoke-Application.ps1" -Name 'robocopy' -Arguments "`"$SourcePath`" `"$($moduleDestination)`" /MIR" -ReturnType 'Output' -AllowExitCodes @(0, 1) | Out-Null
} finally {
    if ($tempDir -and (Test-Path $tempDir)) {
        Remove-Item $tempDir -Recurse -Force -Confirm:$false | Out-Null
    }

    if ($tempFile -and (Test-Path $tempFile)) {
        Remove-Item $tempFile | Out-Null
    }
}

"PackageName: $($PackageName)`r`nInstallDate: $([DateTime]::Now)" | Out-File "$($moduleDestination)\.chocolateyModule" -Encoding UTF8
