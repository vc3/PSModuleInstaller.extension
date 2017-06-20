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
