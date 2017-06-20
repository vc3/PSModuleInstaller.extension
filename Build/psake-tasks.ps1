Write-Verbose "Loading 'Build\psake-tasks.ps1'..."

properties {
    Write-Verbose "Applying properties from 'Build\psake-tasks.ps1'..."

    if ($env:ChocolateyLocal -and (Test-Path $env:ChocolateyLocal)) {
        $outDir = $env:ChocolateyLocal
    } else {
        $outDir = Join-Path $env:LOCALAPPDATA 'PSModuleInstaller.extension'
        if (-not(Test-Path $outDir)) {
            New-Item $outDir -Type Directory | Out-Null
        }
    }

    $chocoOutDir = $outDir
    $chocoPkgsDir = "$root\Output"

    $moduleSpecFile = "$root\module.psd1"
    $moduleDestination = ".\Output\tools"
}

include '.\Build\Modules\Psake-Choco\psake-tasks.ps1'
include '.\Build\Modules\Psake-ModuleBuilder\psake-tasks.ps1'

task EnsureApiKey {
	if (-not $chocoApiKey) {
		throw "Psake property 'chocoApiKey' must be configured."
	}
}

task Build -depends EnsureApiKey,Choco:BuildPackages

task Deploy -depends EnsureApiKey,Choco:DeployPackages
