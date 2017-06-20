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
