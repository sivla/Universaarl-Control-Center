[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$powerShell = (Get-Process -Id $PID).Path
$output = @(& $powerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts/Initialize-UniversaarlControlCenter.ps1') -Json 2>&1)
if ($LASTEXITCODE -ne 0) { throw "Doctor fehlgeschlagen: $($output -join ' ')" }
$result = ($output -join "`n") | ConvertFrom-Json
if ($result.status -cne 'passed' -or $result.releaseStatus -cne 'PENDING_MACOS_RUNNER_EVIDENCE') { throw 'Doctor meldet keinen ehrlichen lokalen Kandidatenstatus.' }
. (Join-Path $root 'scripts/Universaarl-Control.Common.ps1')
if (-not (Test-UniversaarlPortableAbsolutePath 'C:\portable\project') -or -not (Test-UniversaarlPortableAbsolutePath '/portable/project') -or (Test-UniversaarlPortableAbsolutePath 'portable/project') -or (Test-UniversaarlPortableAbsolutePath 'C:\portable\..\escape')) {
    throw 'Plattformneutrale absolute Konfigurationspfade werden nicht fail-closed erkannt.'
}
$fileSystemRoot = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))
$normalizedFileSystemRoot = Get-UniversaarlNormalizedPath -Path $fileSystemRoot
if ([string]::IsNullOrWhiteSpace($normalizedFileSystemRoot) -or -not (Test-UniversaarlPathEqual -Left $normalizedFileSystemRoot -Right $fileSystemRoot)) { throw 'Dateisystemwurzel wird leer oder falsch normalisiert.' }
$caseRoot = Join-Path ([IO.Path]::GetTempPath()) 'Universaarl-Portability-Case'
$caseChild = Join-Path $caseRoot 'Kind'
$caseSibling = "$caseRoot-sibling"
if (-not (Test-UniversaarlPathWithinRoot -Root $caseRoot -Path $caseChild) -or (Test-UniversaarlPathWithinRoot -Root $caseRoot -Path $caseSibling) -or (Test-UniversaarlPathWithinRoot -Root $caseRoot -Path $caseRoot) -or -not (Test-UniversaarlPathWithinRoot -Root $caseRoot -Path $caseRoot -AllowRoot)) { throw 'Pfad-Containment behandelt Wurzel, Kind oder gleichnamiges Geschwister falsch.' }
$differentCase = $caseRoot.ToLowerInvariant()
if (Test-UniversaarlIsWindows) {
    if (-not (Test-UniversaarlPathEqual -Left $caseRoot -Right $differentCase)) { throw 'Windows-Pfadvergleich ist nicht ordinal und gross-/kleinschreibungsunabhaengig.' }
}
elseif (Test-UniversaarlPathEqual -Left $caseRoot -Right $differentCase) { throw 'Unix-Pfadvergleich ist nicht ordinal und gross-/kleinschreibungsabhaengig.' }
$common = Get-Content -LiteralPath (Join-Path $root 'scripts/Universaarl-Control.Common.ps1') -Raw
$runner = Get-Content -LiteralPath (Join-Path $root 'tools/Universaarl.ProcessRunner/Program.cs') -Raw
if ($common -notmatch 'Resolve-UniversaarlTool' -or $common.Contains("throw 'Gesperrte Verzeichnisketten sind auf diesem Betriebssystem nicht verfuegbar.'")) { throw 'Portable Werkzeug- oder Pfadbehandlung fehlt.' }
if ($runner -notmatch 'RunUnixProcessAsync' -or $runner -notmatch 'Kill\(entireProcessTree: true\)') { throw 'Unix-Prozessbaumbegrenzung fehlt.' }
if ($runner -match 'Der sichere Prozesshelfer benoetigt Windows-Jobobjekte') { throw 'Der Prozesshelfer lehnt Unix weiterhin pauschal ab.' }
$candidate = Get-Content -LiteralPath (Join-Path $root 'release/control-center-portability-candidate.json') -Raw | ConvertFrom-Json
if ($null -ne $candidate.version -or $null -ne $candidate.sourceCommit -or $candidate.status -cne 'PENDING_MACOS_RUNNER_EVIDENCE') { throw 'Kandidatenmanifest erfindet Versions- oder macOS-Nachweise.' }
Write-Output 'Kontrollzentrum-Portabilitaet bestanden: Pfadlogik lokal verhaltensgeprueft; Unix-Laufzeit- und macOS-Gates ehrlich offen.'
