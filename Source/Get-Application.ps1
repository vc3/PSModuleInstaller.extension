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
