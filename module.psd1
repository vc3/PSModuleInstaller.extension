@{
    Name = "PSModuleInstaller.extension"
    Version = '0.2.1'
    Author = 'Bryan Matthews'
    Company = 'VC3, Inc.'
    Description = "A Chocolatey extension that supports installing PowerShell modules from a Chocolatey package."
    Source = '.\Source'
    DefinedSymbols = @('Get-ChocolateyWebFile', 'Get-ChocolateyUnzip')
    SuppressSymbolExport = $true
}
