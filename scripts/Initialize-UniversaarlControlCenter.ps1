[CmdletBinding()]
param([switch]$Bootstrap, [switch]$Json)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ControlRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
. (Join-Path $PSScriptRoot 'Universaarl-Control.Common.ps1')

function Get-VersionResult {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string[]]$Commands, [Parameter(Mandatory)][version]$Minimum, [string[]]$Arguments = @('--version'))
    try {
        $path = Resolve-UniversaarlTool -Names $Commands -Description $Name
        $versionOutput = @(& $path @Arguments 2>&1)
        $versionExitCode = $LASTEXITCODE
        $raw = if ($versionOutput.Count -gt 0) { $versionOutput[0].ToString().Trim() } else { '' }
        if ($versionExitCode -ne 0 -or $raw -notmatch '(?<version>\d+\.\d+(?:\.\d+)?)') { throw 'Versionsausgabe ist nicht auswertbar.' }
        $actual = [version]$Matches.version
        [pscustomobject]@{ name = $Name; status = if ($actual -ge $Minimum) { 'passed' } else { 'failed' }; version = $actual.ToString(); minimum = $Minimum.ToString(); path = $path; message = $null }
    }
    catch { [pscustomobject]@{ name = $Name; status = 'failed'; version = $null; minimum = $Minimum.ToString(); path = $null; message = $_.Exception.Message } }
}

$isMac = $null -ne (Get-Variable -Name IsMacOS -ErrorAction SilentlyContinue) -and [bool](Get-Variable -Name IsMacOS -ValueOnly)
$platform = if (Test-UniversaarlIsWindows) { 'windows' } elseif ($isMac) { 'macos' } else { 'unix' }
$checks = [Collections.Generic.List[object]]::new()
$checks.Add((Get-VersionResult -Name 'Git' -Commands @('git', 'git.exe') -Minimum ([version]'2.40')))
$checks.Add((Get-VersionResult -Name 'Node.js' -Commands @('node', 'node.exe') -Minimum ([version]'20.0')))
$checks.Add((Get-VersionResult -Name '.NET SDK' -Commands @('dotnet', 'dotnet.exe') -Minimum ([version]'6.0')))
$powerShellMinimum = if ($platform -eq 'windows') { [version]'5.1' } else { [version]'7.4' }
$checks.Add([pscustomobject]@{ name = 'PowerShell'; status = if ($PSVersionTable.PSVersion -ge $powerShellMinimum) { 'passed' } else { 'failed' }; version = $PSVersionTable.PSVersion.ToString(); minimum = $powerShellMinimum.ToString(); path = (Get-Process -Id $PID).Path; message = $null })
foreach ($relative in @('AGENTS.md', 'monitor.config.json', 'scripts/Invoke-UniversaarlAudit.ps1', 'tools/Universaarl.ProcessRunner/Universaarl.ProcessRunner.csproj')) {
    $present = Test-Path -LiteralPath (Join-Path $ControlRoot $relative) -PathType Leaf
    $checks.Add([pscustomobject]@{ name = "Repositorydatei $relative"; status = if ($present) { 'passed' } else { 'failed' }; version = $null; minimum = $null; path = $relative; message = if ($present) { $null } else { 'Pflichtdatei fehlt.' } })
}
if ($Bootstrap -and @($checks | Where-Object status -eq 'failed').Count -eq 0) {
    $workRoot = Join-Path $ControlRoot '.work'; $bootstrapRoot = Join-Path $workRoot 'bootstrap'
    $null = Initialize-UniversaarlSafeDirectory -TrustedRoot $ControlRoot -Directory $workRoot
    if (Test-Path -LiteralPath $bootstrapRoot) {
        Assert-UniversaarlNoReparseComponents -Root $workRoot -FullPath $bootstrapRoot
        Remove-Item -LiteralPath $bootstrapRoot -Recurse -Force
    }
    $null = Initialize-UniversaarlSafeDirectory -TrustedRoot $workRoot -Directory $bootstrapRoot
    try { $null = Initialize-UniversaarlProcessRunner -ControlRoot $ControlRoot -SandboxRoot $bootstrapRoot; $checks.Add([pscustomobject]@{ name = 'Sicherer Prozesshelfer'; status = 'passed'; version = $null; minimum = $null; path = '.work/bootstrap/prozesshelfer'; message = $null }) }
    catch { $checks.Add([pscustomobject]@{ name = 'Sicherer Prozesshelfer'; status = 'failed'; version = $null; minimum = $null; path = $null; message = $_.Exception.Message }) }
}
$failed = @($checks | Where-Object status -eq 'failed').Count
$result = [pscustomobject]@{ schemaVersion = 1; status = if ($failed -eq 0) { 'passed' } else { 'failed' }; platform = $platform; mode = if ($Bootstrap) { 'bootstrap' } else { 'doctor' }; releaseStatus = 'PENDING_MACOS_RUNNER_EVIDENCE'; checks = @($checks) }
if ($Json) { $result | ConvertTo-Json -Depth 5 -Compress } else { $result.checks | Format-Table name, status, version, minimum -AutoSize; Write-Output "Status: $($result.status); Release: $($result.releaseStatus)" }
if ($failed -gt 0) { exit 2 }
