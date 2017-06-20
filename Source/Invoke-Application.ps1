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
    $filePath = (& "$($PSScriptRoot)\Get-Application.ps1" -Name $Name -Single).Definition
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
        $paramEscaped = & "$($PSScriptRoot)\ConvertTo-ApplicationArgument.ps1" -Value $param
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
