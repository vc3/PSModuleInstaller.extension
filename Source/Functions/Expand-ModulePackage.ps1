################################################################################
#  Expand-ModulePackage v0.1.0                                                 #
#  --------------------------------------------------------------------------  #
#  Extract a module package and clean up package files.                        #
#  --------------------------------------------------------------------------  #
#  Author(s): Bryan Matthews                                                   #
#  Company: VC3, Inc.                                                          #
#  --------------------------------------------------------------------------  #
#  Change Log:                                                                 #
#  [0.1.0] - 2017-09-21                                                        #
#  Added:                                                                      #
#  - Unzip via 'Expand-Archive' or custom script.                              #
#  - Delete 'package' and '_rels' folders.                                     #
#  - Delete '[Content_Types].xml' and '*.nuspec' files.                        #
################################################################################
function Expand-ModulePackage {
    [CmdletBinding()]
    param(
        [Alias('Path')]
        [Alias('FullName')]
        [Parameter(Mandatory=$true, Position=0, ValueFromPipelineByPropertyName=$true)]
        [string]$PackageFileName,

        [Parameter(Mandatory=$true)]
        [string]$ModuleName,

        [Parameter(Mandatory=$true)]
        [string]$DestinationPath,

        [ScriptBlock]$UnzipScript,

        [switch]$Force
    )

    if (Test-Path $DestinationPath -Type Container) {
        if ($Force.IsPresent) {
            Write-Verbose "Removing destination directory '$($DestinationPath)'."
            Remove-Item $DestinationPath -Recurse -Force -Confirm:$false -EA 0 | Out-Null
            Remove-Item $DestinationPath -Recurse -Force -Confirm:$false | Out-Null
        } else {
            Write-Error "Destination path '$($DestinationPath)' already exists."
            return
        }
    }

    $PackageFileExtension = [IO.Path]::GetExtension($PackageFileName)

    if ($UnzipScript) {
        Write-Verbose "Running custom unzip script..."
        $unzipPath = & $UnzipScript $PackageFileName $DestinationPath
        if ($unzipPath) {
            if ($unzipPath -ne $DestinationPath) {
                Write-Warning "Custom script unzipped file into unexpected destination '$($unzipPath)'."
            }
        } else {
            Write-Error "Failed to unzip file '$($PackageFileName)' with custom script."
            return
        }
    } else {
        Write-Verbose "Searching for 'Expand-Archive' command."

        $expandArchiveCommands = Get-Command 'Expand-Archive' -All -EA 0

        if ($expandArchiveCommands) {
            if ($expandArchiveCommands -is [array]) {
                Write-Verbose "Found $($expandArchiveCommands.Count) 'Expand-Archive' commands."
            } else {
                Write-Verbose "Found 1 'Expand-Archive' command."
            }

            if ($expandArchiveCommands | Where-Object { $_.Module -eq 'Microsoft.PowerShell.Archive' }) {
                Write-Verbose "Using 'Expand-Archive' command in module 'Microsoft.PowerShell.Archive'."
                $usingSystemUnzip = $true
                $unzipCmd = Get-Command 'Expand-Archive' -Module 'Microsoft.PowerShell.Archive'
            } else {
                Write-Verbose "Module 'Microsoft.PowerShell.Archive' is not present, using the first available 'Expand-Archive' command."
                $usingSystemUnzip = $false
                $unzipCmd = Get-Command 'Expand-Archive'
            }

            # Expand-Archive will fail on extension other than .zip
            if ($usingSystemUnzip -and $PackageFileExtension -ne '.zip') {
                Write-Verbose "Renaming file to '.zip' to avoid error."
                $tmpFile = "$($env:TEMP)\$([guid]::NewGuid()).zip"
                Copy-Item $Path $tmpFile
                $PackageFileName = $tmpFile
            }

            & $unzipCmd -Path $PackageFileName -DestinationPath $DestinationPath
        } else {
            Write-Error "Command 'Expand-Archive' does not exist."
        }
    }

    if (-not(Test-Path $DestinationPath -Type Container)) {
        Write-Error "Destination path '$($DestinationPath)' does not exist after unzip operation."
        return
    }

    Write-Verbose "Cleaning up unzipped module output..."

    if (Test-Path "$($DestinationPath)\_rels") {
        Write-Verbose "Removing '_rels' folder."
        Remove-Item "$($DestinationPath)\_rels" -Recurse -Force -Confirm:$false | Out-Null
    }

    if (Test-Path "$($DestinationPath)\package") {
        Write-Verbose "Removing 'package' folder."
        Remove-Item "$($DestinationPath)\package" -Recurse -Force -Confirm:$false | Out-Null
    }

    if (Test-Path -LiteralPath "$($DestinationPath)\[Content_Types].xml") {
        Write-Verbose "Removing '[Content_Types].xml' file."
        Remove-Item -LiteralPath "$($DestinationPath)\[Content_Types].xml" -Force -Confirm:$false | Out-Null
    }

    if (Test-Path "$($DestinationPath)\$($ModuleName).nuspec") {
        Write-Verbose "Removing nuspec file."
        Remove-Item "$($DestinationPath)\$($ModuleName).nuspec" -Force -Confirm:$false | Out-Null
    }
}
