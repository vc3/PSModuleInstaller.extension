function ConvertTo-ApplicationArgument {
	[CmdletBinding()]
	param(
	    # The raw argument value to convert.
		[Parameter(Mandatory=$true)]
		[object]$Value
	)
	
	$isEscaped = $false
	
	for ($i = 0; $i -lt $Value.Length; $i += 1) {
		$c = $Value[$i]
		if ($c -eq '"') {
			$isEscaped = -not($isEscaped)
		} elseif ($c -eq " " -or $c -eq "`t") {
			if (-not($isEscaped)) {
				Write-Verbose "Escaping argument '$($Value)'..."
				return """$($Value)"""
			}
		}
	}
	
	return "$($Value)"
}

function Expand-ModulePackage {
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
    Write-Verbose "Expanding module package '$($PackageFileName)'..."
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
    Write-Verbose "Package file extension is '$($PackageFileExtension)'."
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
function Get-Application {
	[CmdletBinding(PositionalBinding=$false)]
	param(
	    # The name of the application.
	    [Parameter(Mandatory=$false, Position=0)]
	    [string]$Name,
	
	    # The version of the application.
	    [Parameter(Mandatory=$false)]
	    [string]$Version,
	
	    # Ensures that there is only one matching application on the path.
	    [Parameter(Mandatory=$false)]
	    [switch]$Single
	)
	
	if ($Name) {
	    $apps = Get-Command -CommandType Application -Name $Name
	} else {
	    $apps = Get-Command -CommandType Application
	}
	
	if ($Version) {
	    $versionNumber = -1
	    [int]::TryParse($Version, [ref]$versionNumber)
	    $apps = $apps | where {
	        if ($versionNumber -ge 0) {
	            return $_.Version.Major -eq $versionNumber
	        } else {
	            return $_.Version -like $Version
	        }
	    }
	}
	
	if ($Single.IsPresent) {
	    if ($apps -is [Array] -and $apps.Count -gt 1) {
	        Write-Error "Application '$($Name)'$(if ($Version) { ' @v' + $Version }) returned $($apps.Count) results."
	        return
	    }
	    if (-not($apps) -or ($apps -is [Array] -and $apps.Count -eq 0)) {
	        Write-Error "Application '$($Name)'$(if ($Version) { ' @v' + $Version }) returned 0 results."
	        return
	    }
	    if ($apps -is [Array]) {
	        return $apps[0]
	    } else {
	        return $apps
	    }
	}
	
	return $apps
}

function Get-EnvironmentPath {
	Param (
	    # The name of the environment variable to return.
		[Parameter()]
		[string]$Name="Path",
	
	    # If specified, returns the value of the variable as a semicolon-delimited string.
	    [Parameter(Mandatory=$false)]
	    [switch]$AsString,
	
	    # If specified, returns the persisted value of path variable.
	    [Parameter(Mandatory=$false, ParameterSetName='Persisted')]
	    [switch]$Persisted,
	
	    [ValidateSet('CurrentUser', 'System')]
	    [Parameter(Mandatory=$false, ParameterSetName='Persisted')]
	    [string]$Scope = 'CurrentUser'
	)
	
	$currentVar = Get-Item "env:$($Name)" -ErrorAction SilentlyContinue
	if ($currentVar) {
	    $currentValue = (Get-Item "env:$($Name)").Value.Split(@(';'), 'RemoveEmptyEntries') -join ';'
	} else {
	    $currentValue = ""
	}
	
	if ($PSCmdlet.ParameterSetName -eq 'Persisted') {
	    $pathItems = @()
	
	    if (-not($Persisted.IsPresent)) {
	        Write-Warning "Getting persisted environment path based on the presence of the scope parameter."
	    }
	
	    if ($Name -eq 'PSModulePath') {
	        if ($Scope -eq 'CurrentUser') {
	            $userValue = [Environment]::GetEnvironmentVariable($Name, 'User')
	            if ($userValue) {
	                $pathItems += $userValue.Split(@(';'), 'RemoveEmptyEntries')
	            }
	        }
	
	        $pathItems += "$($env:ProgramFiles)\WindowsPowerShell\Modules"
	    }
	
	    $systemValue = [Environment]::GetEnvironmentVariable($Name, 'Machine')
	    if ($systemValue) {
	        $pathItems += $systemValue.Split(@(';'), 'RemoveEmptyEntries')
	    }
	
	    if ($Name -ne 'PSModulePath') {
	        if ($Scope -eq 'CurrentUser') {
	            $userValue = [Environment]::GetEnvironmentVariable($Name, 'User')
	            if ($userValue) {
	                $pathItems += $userValue.Split(@(';'), 'RemoveEmptyEntries')
	            }
	        }
	    }
	
	    $persistedValue = ($pathItems -join ';')
	
	    if ($Scope -eq 'CurrentUser' -and $currentValue -ne $persistedValue) {
	        <#
	        $currentPath = [System.IO.Path]::GetTempFileName()
	        $persistedPath = [System.IO.Path]::GetTempFileName()
	        Write-Verbose "Writing current to '$($currentPath)' and persisted to '$($persistedPath)'."
	        $currentValue | Out-File $currentPath -Encoding UTF8
	        $persistedValue | Out-File $persistedPath -Encoding UTF8
	        #>
	
	        Write-Warning "Current and persisted value for environment variable '$($Name)' do not match."
	    }
	
	    if ($AsString.IsPresent) {
	        $returnValue = ($pathItems -join ';')
	    } else {
	        $returnItems = $pathItems
	    }
	} else {
	    if ($AsString.IsPresent) {
	        $returnValue = $currentValue
	    } else {
	        $returnItems = $currentValue.Split(@(';'), 'RemoveEmptyEntries')
	    }
	}
	
	if ($AsString.IsPresent) {
	    return $returnValue
	} else {
	    $returnItems | foreach {
			$item = New-Object 'PSObject'
			$item | Add-Member -Type NoteProperty -Name 'Path' -Value $_
			Write-Output $item
	    }
	}
}

function Install-ChocolateyPowerShellModule {
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
	    Invoke-Application -Name 'robocopy' -Arguments "`"$SourcePath`" `"$($moduleDestination)`" /MIR" -ReturnType 'Output' -AllowExitCodes @(0, 1) | Out-Null
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
}

function Invoke-Application {
	[CmdletBinding(PositionalBinding=$false, DefaultParameterSetName='Name')]
	param(
	    [Parameter(Mandatory=$true, Position=0, ParameterSetName='Name')]
	    [string]$Name,
	
	    [Alias('Path')]
	    [Parameter(Mandatory=$true, Position=0, ParameterSetName='Path')]
	    [string]$FilePath,
	
	    [Parameter(Mandatory=$true, ValueFromPipeline=$true, ParameterSetName='App')]
	    [System.Management.Automation.ApplicationInfo]$Application,
	
	    [Alias('Args')]
	    [Parameter(Mandatory=$true)]
	    [string]$Arguments,
	
	    [ValidateSet('None', 'ExitCode', 'Output')]
	    [Parameter(Mandatory=$true)]
	    [string]$ReturnType,
	
	    [Parameter(Mandatory=$false)]
	    [int[]]$AllowExitCodes = @(0),
	
	    [Alias('SIEL')]
	    [Parameter(Mandatory=$false)]
	    [switch]$SuppressInconsistentErrorLogging
	)
	
	if ($Name) {
	    Write-Verbose "Searching for application '$($Name)'..."
	    $filePath = (Get-Application -Name $Name -Single).Definition
	    Write-Verbose "Search resulted in '$($filePath)'."
	} elseif ($FilePath) {
	    if (-not(Test-Path $FilePath)) {
	        Write-Error "Application '$($FilePath)' doesn't exist."
	        return
	    }
	} elseif ($Application) {
	    $filePath = $Application.Definition
	} else {
	    Write-Error "Parameter binding error."
	    return
	}
	
	if (-not($Arguments)) {
	    $paramIndex = 0
	    foreach ($param in $Params) {
	        Write-Verbose "Params[$paramIndex]=$param"
	        $paramEscaped = ConvertTo-ApplicationArgument -Value $param
	        $Arguments += ("$(if ($Arguments) { ' ' })" + $paramEscaped)
	    }
	}
	
	Write-Verbose "$> '$($FilePath)' $Arguments"
	
	if ($ReturnType -eq "Output") {
	    $process = New-Object 'System.Diagnostics.Process'
	
	    $process.StartInfo.FileName = $FilePath
	    $process.StartInfo.WorkingDirectory = (Get-Location).Path
	    $process.StartInfo.Arguments = $Arguments
	    $process.StartInfo.UseShellExecute = $false
	    $process.StartInfo.RedirectStandardOutput = $true
	    $process.StartInfo.RedirectStandardError = $true
	
	    # start the process and begin reading stdout and stderr
	    [void]$process.Start()
	
	    $outStream = $process.StandardOutput
	    $out = $outStream.ReadToEnd()
	
	    $errStream = $process.StandardError
	    $err = $errStream.ReadToEnd()
	
	    # Shutdown async read events
	    $exitCode = $process.ExitCode
	    $process.Close()
	
	    if ($err.Length -ne 0 -and (-not($AllowExitCodes -contains $exitCode) -or -not($SuppressInconsistentErrorLogging.IsPresent))) {
	        Write-Host $err.ToString() -ForegroundColor Red
	    }
	
	    if (-not($AllowExitCodes -contains $exitCode)) {
	        Write-Error "Command '$(Split-Path $FilePath -Leaf)' failed with exit code $($exitCode)."
	    }
	
	    return $out
	} else {
	    $process = Start-Process -FilePath "$FilePath" -ArgumentList $Arguments -NoNewWindow -Wait -PassThru
	
	    if (-not($AllowExitCodes -contains $process.ExitCode)) {
	        Write-Error "Command '$(Split-Path $FilePath -Leaf)' failed with exit code $($process.ExitCode)."
	    }
	
	    if ($ReturnType -eq "ExitCode") {
	        return $process.ExitCode
	    }
	}
}

function Resolve-Module {
    ################################################################################
    #  Resolve-Module v0.3.0                                                       #
    #  --------------------------------------------------------------------------  #
    #  Discover PowerShell modules in the NPM "require" style.                     #
    #  --------------------------------------------------------------------------  #
    #  Author(s): Bryan Matthews                                                   #
    #  Company: VC3, Inc.                                                          #
    #  --------------------------------------------------------------------------  #
    #  Change Log:                                                                 #
    #  [0.3.0] - 2017-09-21                                                        #
    #  Added:                                                                      #
    #  - Support installing from local directory path                              #
    #  - Support specifying and/or local vs. global search                         #
    #  - Support searching a specific folder                                       #
    #  - Support searching -only- user or machine scope                            #
    #  [0.2.0] - 2017-08-04                                                        #
    #  Fixed:                                                                      #
    #  - Use 'BindingVariable' in 'Import-LocalizedData' call                      #
    #  [0.1.0] - 2017-07-13                                                        #
    #  Added:                                                                      #
    #  - Support for finding and importing '.psm1' and '.psd1' files.              #
    #  - Support for finding module files in a nested version folder.              #
    ################################################################################
    [CmdletBinding(DefaultParameterSetName='SearchLocalAndGlobal')]
    param(
        [Alias('Name')]
        [Parameter(Mandatory=$true, Position=0)]
        [string]$ModuleName,
        [Parameter(ParameterSetName='SearchLocal')]
        [string]$ModulesFolder,
        [Parameter(ParameterSetName='SearchGlobal')]
        [switch]$Global,
        [Parameter(ParameterSetName='SearchLocalAndGlobal')]
        [Parameter(ParameterSetName='SearchGlobal')]
        [ValidateSet('CurrentUser', 'System')]
        [string]$Scope
    )
    Write-Verbose "Attempting to resolve module '$($ModuleName)'..."
    if ($PSCmdlet.ParameterSetName -like 'SearchLocal*') {
        $localModules = @()
        if (-not($ModulesFolder)) {
            if ($MyInvocation.PSScriptRoot) {
                Write-Verbose "Searching from script file '$($MyInvocation.PSCommandPath)..."
                $searchDir = $MyInvocation.PSScriptRoot
            } else {
                Write-Verbose "Searching from current working directory '$($PWD.Path)..."
                $searchDir = $PWD.Path
            }
            $ModulesFolder = Join-Path $searchDir 'Modules'
        }
        do {
            if (-not($ModulesFolder)) {
                $ModulesFolder = Join-Path $searchDir 'Modules'
            }
            if (Test-Path ($ModulesFolder)) {
                Get-ChildItem $ModulesFolder | Where-Object { $_.PSIsContainer } | ForEach-Object {
                    Write-Verbose "Searching '$($_.FullName)'..."
                    $moduleVersion = $null
                    Write-Verbose "Checking for module manifest in root folder..."
                    $moduleFile = Join-Path $_.FullName "$($ModuleName).psd1"
                    if (Test-Path $moduleFile) {
                        Import-LocalizedData -BindingVariable 'moduleManifest' -FileName "$($ModuleName).psd1" -BaseDirectory $_.FullName
                        $moduleVersion = $moduleManifest.ModuleVersion
                        Write-Verbose "Found module manifest for '$($ModuleName)' v$($moduleVersion)."
                    } else {
                        Write-Verbose "Checking for module file in root folder..."
                        $moduleFile = Join-Path $_.FullName "$($ModuleName).psm1"
                        if (Test-Path $moduleFile) {
                            Write-Verbose "Found module file for '$($ModuleName)'."
                        } else {
                            # NOTE: Check for a single *version* folder (simplification).
                            $versionFolder = $null
                            Write-Verbose "Looking for version folder..."
                            $children = [array](Get-ChildItem $_.FullName)
                            Write-Verbose "Found $($children.Count) children: $(($children | Select-Object -ExpandProperty Name) -join ', ')."
                            if (($children.Count -eq 1) -and $children[0].PSIsContainer) {
                                try {
                                    [System.Version]::Parse($children[0].Name) | Out-Null
                                    $versionFolder = $children[0]
                                } catch {
                                    # Not a version, do nothing
                                    Write-Verbose "Unable to parse '$($children[0].Name)' as a .NET version."
                                }
                            }
                            if ($versionFolder) {
                                Write-Verbose "Checking for module manifest in '$($versionFolder.Name)' folder..."
                                $moduleFile = Join-Path $versionFolder.FullName "$($ModuleName).psd1"
                                if (Test-Path $moduleFile) {
                                    Write-Verbose "Found module manifest for '$($ModuleName)'."
                                } else {
                                    Write-Verbose "Module manifest couldn't be found in version folder."
                                    $moduleFile = $null
                                }
                            } else {
                                Write-Verbose "No version folder was found."
                                $moduleFile = $null
                            }
                        }
                    }
                    if ($moduleFile) {
                        Write-Verbose "Found module '$($ModuleName)' at '$($moduleFile)'."
                        $module = New-Object 'PSObject'
                        $module | Add-Member -Type 'NoteProperty' -Name 'Name' -Value $ModuleName
                        $module | Add-Member -Type 'NoteProperty' -Name 'Version' -Value $moduleVersion
                        $module | Add-Member -Type 'NoteProperty' -Name 'Path' -Value $moduleFile
                        $localModules += $module
                    }
                }
                if ($localModules.Count -gt 0) {
                    Write-Output $localModules
                    return;
                }
                $searchDir = $null
            } elseif ($searchDir) {
                $searchDir = Split-Path $searchDir -Parent
            }
        } while ($searchDir)
    }
    if ($PSCmdlet.ParameterSetName -like 'Search*Global') {
        Write-Verbose "Attempting to find global '$($ModuleName)' module on the %PSModulePath%..."
        $candidateRootPaths = $null
        if ($Scope -eq 'System') {
            $candidateRootPaths = @()
            $candidateRootPaths += "$($env:ProgramFiles)\WindowsPowerShell\Modules"
            $systemValue = [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine')
            if ($systemValue) {
                $candidateRootPaths += $systemValue.Split(@(';'), 'RemoveEmptyEntries')
            }
            Write-Verbose "Using candidate root paths '$($candidateRootPaths -join ';')'."
        } elseif ($Scope -eq 'CurrentUser') {
            $candidateRootPaths = @()
            $candidateRootPaths += "$(Split-Path $PROFILE -Parent)\Modules"
            $userValue = [Environment]::GetEnvironmentVariable('PSModulePath', 'User')
            if ($userValue) {
                $systemValues = [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine').Split(@(';'), 'RemoveEmptyEntries')
                $candidateRootPaths += $userValue.Split(@(';'), 'RemoveEmptyEntries') | Where-Object { -not($systemValues -contains $_) }
            }
            Write-Verbose "Using candidate root paths '$($candidateRootPaths -join ';')'."
        }
        $globalModules = @()
        Get-Module -Name $ModuleName -ListAvailable | ForEach-Object {
            $moPath = $_.Path
            if (-not($candidateRootPaths) -or ($candidateRootPaths | Where-Object { $moPath.StartsWith($_, $true, [Globalization.CultureInfo]::CurrentCulture) })) {
                Write-Verbose "Found installed module '$($ModuleName)' at '$($_.Path)'."
                $module = New-Object 'PSObject'
                $module | Add-Member -Type 'NoteProperty' -Name 'Name' -Value $ModuleName
                $module | Add-Member -Type 'NoteProperty' -Name 'Version' -Value $_.Version
                $module | Add-Member -Type 'NoteProperty' -Name 'Path' -Value $_.Path
                $globalModules += $module
            }
        }
        if ($globalModules.Count -gt 0) {
            Write-Output $globalModules
            return
        }
    }
    Write-Error "Couldn't resolve module '$($ModuleName)'."
}
function Uninstall-ChocolateyPowerShellModule {
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
	    $moduleDirs = Get-EnvironmentPath -Name 'PSModulePath' -Persisted -Scope System
	
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
}

Export-ModuleMember -Function 'Install-ChocolateyPowerShellModule'
Export-ModuleMember -Function 'Uninstall-ChocolateyPowerShellModule'


