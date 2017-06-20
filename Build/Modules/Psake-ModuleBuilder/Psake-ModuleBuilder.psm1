Import-Module "$PSScriptRoot\Modules\Assemble\Assemble.psd1"
Import-Module "$PSScriptRoot\Modules\EPS\EPS.psd1"
Import-Module "$PSScriptRoot\Modules\Psake-Utils\Psake-Utils.psm1"
Import-Module "$PSScriptRoot\Modules\PsData\PsData.psd1"

function Build-Module {
    [CmdletBinding()]
    param(
        [Alias('Spec')]
        [Parameter(Mandatory=$true)]
        [object]$ModuleSpec,

        [string]$WorkingDirectory = "$($PWD.Path)"
    )

    $internalParams = @('GenerateManifest')

    $manifestParams = @('Version', 'Author', 'Company', 'Guid', 'Description', 'DefaultCommandPrefix', 'RequiredModules')

    $scriptBuildParams = @('Name', 'SourcePath', 'TargetPath', 'Exclude', 'OutputType', 'DependenciesToValidate',
                    'DefinedSymbols', 'SuppressSymbolExport', 'NoSymbols', 'SymbolsToExport', 'Export'
                    'OutputMode', 'AsScript', 'Flags', 'Silent', 'Force')

    $scriptBuildParamsMap = @{
        Source = 'SourcePath'
        Destination = 'TargetPath'
    }

    $params = @{}

    if ($ModuleSpec -is [Hashtable]) {
        $moduleSpecProperties = $ModuleSpec.Keys
    } elseif ($ModuleSpec -is [PSObject]) {
        $moduleSpecProperties = $ModuleSpec.PSObject.Properties | Select-Object -ExpandProperty 'Name'
    } else {
        Write-Error "Unknown value of type '$($ModuleSpec.GetType().Name)' for parameter 'ModuleSpec'."
        return
    }

    # http://stackoverflow.com/a/3740403/170990
    $moduleSpecProperties | Foreach-Object {
        if ($manifestParams -contains $_) {
            Write-Verbose "Removing manifest parameter '$($_)'."
        } elseif ($scriptBuildParams -contains $_) {
            Write-Verbose "Using script build parameter '$($_)'."
            $params[$_] = $ModuleSpec.$_
        } elseif ($scriptBuildParamsMap.Keys -contains $_) {
            $newName = $scriptBuildParamsMap[$_]
            Write-Verbose "Using script build parameter '$($newName)' (from '$($_)')."
            $params[$newName] = $ModuleSpec.$_
        } elseif ($internalParams -contains $_) {
            Write-Verbose "Ignoring internal parameter '$($_)'."
        } elseif ($coreParams -contains $_) {
            Write-Verbose "Ignoring core parameter '$($_)'."
        } else {
            Write-Warning "Unknown parameter '$($_)'."
        }
    }

    if (-not($params.Keys -contains 'Force')) {
        $params['Force'] = $true
    }

    Write-Message "Building module '$($ModuleSpec.Name)'..."

    $priorWorkingDirectory = $null

    try {
        if ($WorkingDirectory -and $WorkingDirectory -ne $PWD.Path) {
            $priorWorkingDirectory = $PWD.Path
            Set-Location $WorkingDirectory
        }

        Invoke-ScriptBuild @params
    } finally {
        if ($priorWorkingDirectory) {
            Set-Location $priorWorkingDirectory
        }
    }

    $generateManifest = $true

    if ($moduleSpecProperties -contains 'GenerateManifest') {
        $generateManifest = $ModuleSpec.GenerateManifest
    }

    if ($generateManifest) {
        Write-Message "Generating module manifest '$($ModuleSpec.Name).psd1' from template..."
        $manifestFile = Join-Path $ModuleSpec.Destination "$($ModuleSpec.Name).psd1"
        $manifestTemplateFile = Join-Path $PSScriptRoot "Templates\ModuleManifest.psd1.tmpl"
        $manifestContent = Expand-Template -File $manifestTemplateFile -Binding $ModuleSpec
        ($manifestContent.Trim() -split "`n") -join "`r`n" | Out-File "$($manifestFile)" -Encoding UTF8
    }
}
