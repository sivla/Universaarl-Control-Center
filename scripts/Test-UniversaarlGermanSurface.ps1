[CmdletBinding()]
param([string]$RunId)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
. (Join-Path $PSScriptRoot 'Universaarl-Control.Common.ps1')
if (-not [string]::IsNullOrWhiteSpace($RunId)) { Assert-UniversaarlRunId -RunId $RunId }
$ReportRoot = Join-Path $Root 'reports'
$files = [Collections.Generic.List[string]]::new()

function Add-ControlFile {
    param([Parameter(Mandatory)][string]$Path, [switch]$Required)
    if (Test-Path -LiteralPath $Path -PathType Leaf) { $files.Add([IO.Path]::GetFullPath($Path)); return }
    if ($Required) { throw "Erforderliche Laufdatei fehlt: $Path" }
}

function Read-SafeControlFile {
    param([Parameter(Mandatory)][string]$Path, [int64]$MaximumBytes = 2097152)
    Read-UniversaarlRegularUtf8File -Root $Root -Path $Path -MaximumBytes $MaximumBytes
}

foreach ($relative in @(
    'README.md', 'AGENTS.md', 'project-goals.json', 'monitor.config.json',
    'scripts\Invoke-UniversaarlAudit.ps1', 'scripts\Invoke-UniversaarlGoalReview.ps1',
    'scripts\Publish-UniversaarlCommit.ps1', 'scripts\Invoke-TwinContractSmoke.mjs',
    'scripts\Universaarl-Control.Common.ps1',
    'tools\Universaarl.ProcessRunner\Program.cs'
)) { Add-ControlFile (Join-Path $Root $relative) }

if (-not [string]::IsNullOrWhiteSpace($RunId)) {
    Add-ControlFile (Join-Path $ReportRoot "runs\$RunId.md") -Required
    Add-ControlFile (Join-Path $ReportRoot "runs\$RunId.json") -Required
    Add-ControlFile (Join-Path $ReportRoot "goal-runs\$RunId.md") -Required
    Add-ControlFile (Join-Path $ReportRoot "goal-runs\$RunId.json") -Required
}
else {
    Add-ControlFile (Join-Path $ReportRoot 'latest.md')
    Add-ControlFile (Join-Path $ReportRoot 'goals-latest.md')
}

$rules = @(
    [pscustomobject]@{ scope = 'markdown'; pattern = '(?i)read-only strategic goal review|read-only observation|isolated-validation'; message = 'englische Modusbezeichnung' },
    [pscustomobject]@{ scope = 'markdown'; pattern = '(?im)^\|[^\r\n]*\|\s*(passed|failed|not-run|clean|dirty|low|medium|high|critical)\s*\|'; message = 'englischer Tabellenstatus' },
    [pscustomobject]@{ scope = 'markdown'; pattern = '(?i)\*\*(True|False)(?:\s*/\s*(True|False))?\*\*'; message = 'englischer Wahrheitswert' },
    [pscustomobject]@{ scope = 'surface'; pattern = '(?i)Review-Datei|Runtime-Bindung|Evidence-Bilder|Empty State|Source-Contract|Write-back|Browserreview'; message = 'englischer oder gemischtsprachiger Sichttext' },
    [pscustomobject]@{ scope = 'surface'; pattern = '(?i)Commit- und Push-Ablauf|Publish-Bereitschaft|Dirty State|Sandbox-Validierung|Evidenzabdeckung|Read-only Darstellung'; message = 'englische Bezeichnung in der Dokumentation' },
    [pscustomobject]@{ scope = 'script'; pattern = '(?i)Publish-Gates|PUBLISH-BEREIT|PUSH BLOCKIERT|PUSH ERFOLGREICH|endete mit Exitcode|Auditbericht|Auditprozess'; message = 'englische Konsolenausgabe' },
    [pscustomobject]@{ scope = 'script'; pattern = '(?i)Branch/Commit'; message = 'englischer Feldtitel' },
    [pscustomobject]@{ scope = 'script'; pattern = 'Twin and Blueprint snapshot paths must be absolute'; message = 'englische Fehlermeldung' }
)

$findings = [Collections.Generic.List[string]]::new()
foreach ($file in $files) {
    $content = Read-SafeControlFile -Path $file
    foreach ($rule in $rules) {
        $extension = [IO.Path]::GetExtension($file)
        $isMarkdown = $extension -eq '.md'
        $isScript = $file.StartsWith((Join-Path $Root 'scripts') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or $extension -eq '.cs'
        $isSurface = $isMarkdown -or $file -in @((Join-Path $Root 'README.md'), (Join-Path $Root 'AGENTS.md'), (Join-Path $Root 'project-goals.json'), (Join-Path $Root 'monitor.config.json'))
        if (($rule.scope -eq 'markdown' -and -not $isMarkdown) -or ($rule.scope -eq 'script' -and -not $isScript) -or ($rule.scope -eq 'surface' -and -not $isSurface)) { continue }
        if ($content -match $rule.pattern) {
            $relative = $file.Substring($Root.Length).TrimStart([char[]]@('\', '/'))
            $findings.Add("$relative`: $($rule.message)")
        }
    }
}

if ($findings.Count -gt 0) {
    Write-Host 'DEUTSCH-PRUEFUNG FEHLGESCHLAGEN:'
    foreach ($finding in $findings) { Write-Host "- $finding" }
    exit 1
}
Write-Host "Ergaenzende Deutsch-Pruefung des Kontrollzentrums bestanden: $($files.Count) kleine regulaere Kontroll- und Berichtsdateien."
exit 0
