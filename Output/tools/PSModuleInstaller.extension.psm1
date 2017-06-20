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
	
	
	Write-Debug "Running 'Install-ChocolateyPowerShellModule' for $packageName with Name:`'$Name`', Version:`'$Version`'  "
	
	Write-Debug "Checking for existing installation of module `'$Name`' "
	
	$moduleDirs = Get-EnvironmentPath -Name 'PSModulePath' -Persisted -Scope System
	
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
	        Invoke-Application -Name 'robocopy' -Arguments "`"$dirPath`" `"$($moduleTargetDir)\$($Name)\$($Version)`" /MIR" -ReturnType 'Output' -AllowExitCodes @(0, 1) | Out-Null
	
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


