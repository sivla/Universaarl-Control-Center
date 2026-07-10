[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$ReportRoot = Join-Path $Root 'reports'
$files = [Collections.Generic.List[string]]::new()

foreach ($relative in @('README.md', 'AGENTS.md', 'project-goals.json', 'scripts\Invoke-UniversaarlAudit.ps1', 'scripts\Invoke-UniversaarlGoalReview.ps1', 'scripts\Publish-UniversaarlCommit.ps1', 'scripts\Invoke-TwinContractSmoke.mjs')) {
    $path = Join-Path $Root $relative
    if (Test-Path -LiteralPath $path -PathType Leaf) { $files.Add($path) }
}
if (Test-Path -LiteralPath $ReportRoot -PathType Container) {
    foreach ($file in Get-ChildItem -LiteralPath $ReportRoot -Recurse -File | Where-Object { $_.Extension -in @('.md', '.json') }) { $files.Add($file.FullName) }
}

$rules = @(
    [pscustomobject]@{ scope = 'markdown'; pattern = '(?i)read-only strategic goal review|read-only observation|isolated-validation'; message = 'englische Modusbezeichnung' },
    [pscustomobject]@{ scope = 'markdown'; pattern = '(?im)^\|[^\r\n]*\|\s*(passed|failed|not-run|clean|dirty|low|medium|high|critical)\s*\|'; message = 'englischer Tabellenstatus' },
    [pscustomobject]@{ scope = 'markdown'; pattern = '(?i)\*\*(True|False)(?:\s*/\s*(True|False))?\*\*'; message = 'englischer Wahrheitswert' },
    [pscustomobject]@{ scope = 'surface'; pattern = '(?i)Review-Datei|Runtime-Bindung|Evidence-Bilder|Empty State|Source-Contract|Write-back|Browserreview'; message = 'englischer oder gemischtsprachiger Sichttext' },
    [pscustomobject]@{ scope = 'surface'; pattern = '(?i)Commit- und Push-Ablauf|Publish-Bereitschaft|Dirty State|Sandbox-Validierung|Evidenzabdeckung|Read-only Darstellung'; message = 'englische Bezeichnung in der Dokumentation' },
    [pscustomobject]@{ scope = 'reportjson'; pattern = '(?i)evidenzbasierte Business-Central-Einfuehrung|Go-live und Hypercare|Toolchain-Voraussetzung|Human Approval und Archivierung|Browserreview uebergeben|Walkthrough-Consumervertrag'; message = 'englische oder gemischtsprachige Berichtserlaeuterung' },
    [pscustomobject]@{ scope = 'script'; pattern = '(?i)Publish-Gates|PUBLISH-BEREIT|PUSH BLOCKIERT|PUSH ERFOLGREICH|endete mit Exitcode|Auditbericht|Auditprozess'; message = 'englische Konsolenausgabe' },
    [pscustomobject]@{ scope = 'script'; pattern = 'Twin and Blueprint snapshot paths must be absolute'; message = 'englische Fehlermeldung' }
)

$findings = [Collections.Generic.List[string]]::new()
foreach ($file in $files) {
    $resolved = [IO.Path]::GetFullPath($file)
    if (-not $resolved.StartsWith($Root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsicherer Pruefpfad: $resolved"
    }
    $content = [IO.File]::ReadAllText($resolved)
    foreach ($rule in $rules) {
        $isMarkdown = [IO.Path]::GetExtension($resolved) -eq '.md'
        $isScript = $resolved.StartsWith((Join-Path $Root 'scripts') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
        $isReportJson = [IO.Path]::GetExtension($resolved) -eq '.json' -and $resolved.StartsWith($ReportRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
        $isSurface = $isMarkdown -or $resolved -eq (Join-Path $Root 'README.md') -or $resolved -eq (Join-Path $Root 'AGENTS.md') -or $resolved -eq (Join-Path $Root 'project-goals.json')
        if (($rule.scope -eq 'markdown' -and -not $isMarkdown) -or ($rule.scope -eq 'script' -and -not $isScript) -or ($rule.scope -eq 'surface' -and -not $isSurface) -or ($rule.scope -eq 'reportjson' -and -not $isReportJson)) { continue }
        if ($content -match $rule.pattern) {
            $relative = $resolved.Substring($Root.Length).TrimStart([char[]]@('\', '/'))
            $findings.Add("$relative`: $($rule.message)")
        }
    }
}

if ($findings.Count -gt 0) {
    Write-Host 'DEUTSCH-PRUEFUNG FEHLGESCHLAGEN:'
    foreach ($finding in $findings) { Write-Host "- $finding" }
    exit 1
}

Write-Host "Deutsch-Pruefung bestanden: $($files.Count) sichtbare Kontroll- und Berichtsdateien."
exit 0
