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
    if (-not($LocalModule)) {
        Write-Error "Didn't find local module '$($Name)' in folder '$($ModulesFolder)'."
        return
    }

    $Version = $LocalModule.Version

    Write-Verbose "Found local module $($Name)@$($Version) at path '$($LocalModule.Path)'."
}

$installedModules = [array](Get-Module $Name -ListAvailable -EA 0)

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
} else {
    Write-Verbose "Found $($installedModules.Count) installed modules with the name '$($Name)'."
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

        Write-Verbose "Expanding module package '$($filePath)'..."

        Expand-ModulePackage $filePath -ModuleName $Name -DestinationPath $tempDir -UnzipScript {
            Write-Host "Using chocolatey to unzip '$($Args[0])' into directory '$($Args[1])'..."
            Get-ChocolateyUnzip $Args[0] $Args[1]
        }

        if (-not(Test-Path $tempDir)) {
            throw "Directory '$($tempDir)' does not exist."
        }

        $SourcePath = $tempDir
    }

    foreach ($moduleFolder in $moduleFoldersToDelete) {
        Write-Verbose "Removing module files from '$($moduleFolder)'..."
        Remove-Item $moduleFolder -Recurse -Force -Confirm:$false | Out-Null

        $moduleParentFolder = Split-Path $moduleFolder -Parent
        if ((Split-Path $moduleParentFolder -Leaf) -eq $Name) {
            if (-not(Get-ChildItem $moduleParentFolder)) {
                Write-Verbose "Removing empty directory '$($moduleParentFolder)'..."
                Remove-Item $moduleParentFolder -Recurse -Force -Confirm:$false | Out-Null
            }
        }
    }

    Write-Host "Copying module files to '$($moduleDestination)'..."
    New-Item $moduleDestination -Type Directory | Out-Null
    & "$($PSScriptRoot)\Invoke-Application.ps1" -Name 'robocopy' -Arguments "`"$SourcePath`" `"$($moduleDestination)`" /MIR" -ReturnType 'Output' -AllowExitCodes @(0, 1) | Out-Null
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
} finally {
    if ($tempDir -and (Test-Path $tempDir)) {
        Write-Verbose "Deleting directory '$($tempDir)'..."
        Remove-Item $tempDir -Recurse -Force -Confirm:$false | Out-Null
    }

    if ($tempFile -and (Test-Path $tempFile)) {
        Write-Verbose "Deleting file '$($tempFile)'..."
        Remove-Item $tempFile | Out-Null
    }
}

Write-Verbose "Writing file '.chocolateyModule' to '$($moduleDestination)'."
"PackageName: $($PackageName)`r`nInstallDate: $([DateTime]::Now)" | Out-File "$($moduleDestination)\.chocolateyModule" -Encoding UTF8
