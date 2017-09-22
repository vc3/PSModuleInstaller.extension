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
