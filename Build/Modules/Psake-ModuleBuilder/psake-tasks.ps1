$psakeModuleBuilderDir = Split-Path $MyInvocation.MyCommand.Path -Parent

properties {
    if (-not($moduleSpecFile) -and -not($moduleAutoDiscover)) {
        if (Test-Path "$root\module.psd1") {
            $moduleSpecFile = "$root\module.psd1"
        } else {
            throw "Couldn't auto-discover module spec file 'module.psd1'."
        }
    }
}

task ModuleBuilder:List {
    if ($moduleAutoDiscover) {
        throw "Module auto-discovery is not yet implemented."
    } else {
        Resolve-Path $moduleSpecFile | foreach {
            Write-Host $_.Path
        }
    }
}

task ModuleBuilder:Build {
    if ($moduleAutoDiscover) {
        throw "Module auto-discovery is not yet implemented."
    } else {
        Resolve-Path $moduleSpecFile | foreach {
            $moduleSpec = Import-PSData $_.Path

            if (-not($moduleSpec.Guid)) {
                $md5 = [System.Security.Cryptography.MD5]::Create()
                $moduleGuidData = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($moduleSpec.Name.ToLower()));
                $moduleGuid = New-Object 'System.Guid' -ArgumentList (,$moduleGuidData)
                $moduleSpec.Guid = "$($moduleGuid.ToString().ToLowerInvariant())"
            }

            if (-not($moduleSpec.Source)) {
                if ($moduleSource) {
                    $moduleSpec.Source = Resolve-Path (Join-Path (Split-Path $_.Path) $moduleSource)
                } else {
                    if (Test-Path "$root\Source") {
                        $moduleSpec.Source = "$root\Source"
                    } else {
                        throw "Couldn't auto-discover module source folder 'Source'."
                    }
                }
            }

            if ($moduleDestination) {
                $moduleSpec.Destination = Resolve-Path (Join-Path (Split-Path $_.Path) $moduleDestination)
            } elseif ($moduleSpec.Destination) {
                $moduleSpec.Destination = Resolve-Path (Join-Path (Split-Path $_.Path) $moduleSpec.Destination)
            } else {
                if (-not($moduleDestination)) {
                    throw "Module destination path not configured."
                }
            }

            Build-Module $moduleSpec -WorkingDirectory (Split-Path $_.Path -Parent)
        }
    }
}
