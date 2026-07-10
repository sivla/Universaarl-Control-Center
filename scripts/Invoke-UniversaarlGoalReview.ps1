[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$MonitorRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$MonitorConfig = Get-Content -LiteralPath (Join-Path $MonitorRoot 'monitor.config.json') -Raw | ConvertFrom-Json
$GoalConfig = Get-Content -LiteralPath (Join-Path $MonitorRoot 'project-goals.json') -Raw | ConvertFrom-Json
$ReportRoot = Join-Path $MonitorRoot $MonitorConfig.reportDirectory
New-Item -ItemType Directory -Path $ReportRoot -Force | Out-Null

function Get-ConfiguredPath {
    param([Parameter(Mandatory)]$Project)
    $override = [Environment]::GetEnvironmentVariable([string]$Project.pathEnvironmentVariable)
    $candidate = if ([string]::IsNullOrWhiteSpace($override)) { [string]$Project.defaultPath } else { $override }
    [IO.Path]::GetFullPath($candidate).TrimEnd([IO.Path]::DirectorySeparatorChar)
}

function Invoke-GitRead {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string[]]$Arguments
    )
    $oldLocks = [Environment]::GetEnvironmentVariable('GIT_OPTIONAL_LOCKS')
    $oldPrompt = [Environment]::GetEnvironmentVariable('GIT_TERMINAL_PROMPT')
    $oldPreference = $ErrorActionPreference
    [Environment]::SetEnvironmentVariable('GIT_OPTIONAL_LOCKS', '0')
    [Environment]::SetEnvironmentVariable('GIT_TERMINAL_PROMPT', '0')
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        $lines = @(& git -C $Repository @Arguments 2>$null)
        [pscustomobject]@{ exitCode = $LASTEXITCODE; output = ($lines -join "`n").Trim() }
    }
    finally {
        $ErrorActionPreference = $oldPreference
        [Environment]::SetEnvironmentVariable('GIT_OPTIONAL_LOCKS', $oldLocks)
        [Environment]::SetEnvironmentVariable('GIT_TERMINAL_PROMPT', $oldPrompt)
    }
}

function New-GoalFinding {
    param(
        [Parameter(Mandatory)][ValidateSet('high', 'medium', 'low', 'info')][string]$Severity,
        [Parameter(Mandatory)][string]$Code,
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][string]$Evidence,
        [Parameter(Mandatory)][string]$NextGoal
    )
    [pscustomobject]@{ severity = $Severity; code = $Code; message = $Message; evidence = $Evidence; nextGoal = $NextGoal }
}

function Get-GoalStatus {
    param([object[]]$Findings)
    $severities = @($Findings | ForEach-Object { $_.severity })
    if ($severities -contains 'high') { return 'ROT' }
    if ($severities -contains 'medium') { return 'GELB' }
    return 'GRUEN'
}

function Get-ActiveChanges {
    param([Parameter(Mandatory)][string]$Repository)
    $root = Join-Path $Repository 'openspec\changes'
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { return @() }
    @(Get-ChildItem -LiteralPath $root -Directory -Force | Where-Object { $_.Name -notin @('archive', 'archived') } | Select-Object -ExpandProperty Name)
}

function Read-Text {
    param([Parameter(Mandatory)][string]$Path)
    if (Test-Path -LiteralPath $Path -PathType Leaf) { return [string](Get-Content -LiteralPath $Path -Raw) }
    ''
}

function Get-RepositoryState {
    param([Parameter(Mandatory)]$Project, [Parameter(Mandatory)][string]$Repository)
    $branch = Invoke-GitRead -Repository $Repository -Arguments @('branch', '--show-current')
    $head = Invoke-GitRead -Repository $Repository -Arguments @('rev-parse', 'HEAD')
    $status = Invoke-GitRead -Repository $Repository -Arguments @('status', '--porcelain=v1', '--untracked-files=all')
    $remote = [string]$Project.publish.remote
    $remoteBranch = [string]$Project.publish.branch
    $publishedLookup = Invoke-GitRead -Repository $Repository -Arguments @('ls-remote', '--heads', $remote, "refs/heads/$remoteBranch")
    $publishedCommit = if ($publishedLookup.exitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($publishedLookup.output)) {
        ($publishedLookup.output -split '\s+')[0]
    }
    else { $null }
    $ahead = if ($head.exitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($publishedCommit)) {
        Invoke-GitRead -Repository $Repository -Arguments @('rev-list', '--count', "$publishedCommit..HEAD")
    } else { [pscustomobject]@{ exitCode = 1; output = '' } }
    [pscustomobject]@{
        branch = $branch.output
        head = $head.output
        dirty = -not [string]::IsNullOrWhiteSpace($status.output)
        publishedCommit = $publishedCommit
        commitsAhead = if ($ahead.exitCode -eq 0) { [int]$ahead.output } else { $null }
        activeChanges = @(Get-ActiveChanges -Repository $Repository)
    }
}

$projectById = @{}
foreach ($project in $MonitorConfig.projects) { $projectById[[string]$project.id] = $project }

$blueprintProject = $projectById['blueprint']
$twinProject = $projectById['project-twin']
$blueprintRoot = Get-ConfiguredPath -Project $blueprintProject
$twinRoot = Get-ConfiguredPath -Project $twinProject
$blueprintFindings = [Collections.Generic.List[object]]::new()
$twinFindings = [Collections.Generic.List[object]]::new()
$relationshipFindings = [Collections.Generic.List[object]]::new()

$blueprintState = Get-RepositoryState -Project $blueprintProject -Repository $blueprintRoot
$twinState = Get-RepositoryState -Project $twinProject -Repository $twinRoot

$blueprintOpenSpec = Read-Text (Join-Path $blueprintRoot 'openspec\config.yaml')
$blueprintArchitecture = Read-Text (Join-Path $blueprintRoot 'architecture\enterprise-blueprint.yaml')
$blueprintCapability = Read-Text (Join-Path $blueprintRoot 'capabilities\catalog.yaml')
$blueprintEnvironmentPage = Read-Text (Join-Path $blueprintRoot 'atlassian\confluence\pages\60-environment-baseline.md')
$blueprintReadme = Read-Text (Join-Path $blueprintRoot 'README.md')
$walkthroughBuilder = Read-Text (Join-Path $blueprintRoot 'scripts\build-walkthrough.mjs')
$walkthroughTests = Read-Text (Join-Path $blueprintRoot 'tests\artifacts\walkthrough.test.mjs')
$baselineApproved = $blueprintArchitecture -match '(?ms)^actualSandboxBaseline:\s*\r?\n\s+status:\s+approved\b'

if ($baselineApproved -and $blueprintOpenSpec -match 'actualSandboxBaseline:\s*currently unknown') {
    $blueprintFindings.Add((New-GoalFinding high 'GOAL-BP-001' 'Der OpenSpec-Kontext widerspricht dem kanonisch freigegebenen Sandbox-Ausgangsstand.' 'openspec/config.yaml; architecture/enterprise-blueprint.yaml' 'Auf `actualSandboxBaseline` als kanonischen Ausgangsstand verweisen, ohne Fakten zu duplizieren.'))
}
if ($baselineApproved -and $blueprintArchitecture -match 'targetEnvironment:\s*authorized-not-inspected') {
    $blueprintFindings.Add((New-GoalFinding medium 'GOAL-BP-002' 'Eine alte Zielumgebungs-Kurzfassung wirkt trotz des spaeteren nur lesend erhobenen Ausgangsstands weiterhin ungeprueft.' 'architecture/enterprise-blueprint.yaml' 'Kurzfassung auf `actualSandboxBaseline` beziehen und die Schreibbereitschaft getrennt halten.'))
}
if ($baselineApproved -and $blueprintArchitecture -match '(?ms)^localization:\s*\r?\n\s+target:.*\r?\n\s+actual:\s+unknown') {
    $blueprintFindings.Add((New-GoalFinding medium 'GOAL-BP-003' 'Die Lokalisierungs-Kurzfassung bildet den spaeteren Kandidaten- und Teilnachweis nicht ab.' 'architecture/enterprise-blueprint.yaml' 'Lokalisierungszusammenfassung auf den kanonischen Teilnachweis verweisen lassen.'))
}
if ($blueprintState.activeChanges.Count -eq 0 -and $blueprintEnvironmentPage -match '(?i)aktive[rn]?\s+Change.*establish-playthru-environment-baseline') {
    $blueprintFindings.Add((New-GoalFinding medium 'GOAL-BP-004' 'Confluence bezeichnet eine archivierte Ausgangsstands-Aenderung weiterhin als aktiv.' 'atlassian/confluence/pages/60-environment-baseline.md' 'Hauptspezifikation, kanonischen Ausgangsstand und Archivhistorie korrekt benennen.'))
}

$capabilityStatuses = @{}
foreach ($match in [regex]::Matches($blueprintCapability, '(?<![A-Za-z])status:\s*(planned|validated|approved|deferred|out-of-scope)\b')) {
    $key = $match.Groups[1].Value
    $current = if ($capabilityStatuses.ContainsKey($key)) { [int]$capabilityStatuses[$key] } else { 0 }
    $capabilityStatuses[$key] = 1 + $current
}
$jiraStatuses = @{}
$jiraRoot = Join-Path $blueprintRoot 'atlassian\jira\issues'
if (Test-Path -LiteralPath $jiraRoot -PathType Container) {
    foreach ($file in Get-ChildItem -LiteralPath $jiraRoot -File -Filter '*.yaml') {
        foreach ($match in [regex]::Matches((Read-Text $file.FullName), '(?m)^\s+status:\s*(Backlog|Ready|In Progress|Blocked|In Review|Done)\s*$')) {
            $key = $match.Groups[1].Value
            $current = if ($jiraStatuses.ContainsKey($key)) { [int]$jiraStatuses[$key] } else { 0 }
            $jiraStatuses[$key] = 1 + $current
        }
    }
}
$jiraMeasure = $jiraStatuses.Values | Measure-Object -Sum
$jiraTotal = if ($null -ne $jiraMeasure.Sum) { [int]$jiraMeasure.Sum } else { 0 }
$jiraDone = if ($jiraStatuses.ContainsKey('Done')) { [int]$jiraStatuses['Done'] } else { 0 }
$allJiraDone = $jiraTotal -gt 0 -and $jiraDone -eq $jiraTotal
$validatedCount = if ($capabilityStatuses.ContainsKey('validated')) { [int]$capabilityStatuses['validated'] } else { 0 }
$approvedCount = if ($capabilityStatuses.ContainsKey('approved')) { [int]$capabilityStatuses['approved'] } else { 0 }
$validatedCapabilities = $validatedCount + $approvedCount
if ($blueprintState.activeChanges.Count -eq 0 -and $allJiraDone -and $validatedCapabilities -eq 0) {
    $blueprintFindings.Add((New-GoalFinding medium 'GOAL-BP-005' 'Alle aktuellen Jira-Vorgaenge sind erledigt, aber keine fachliche Faehigkeit ist validiert; ein ausfuehrbares naechstes Ergebnis fehlt.' 'capabilities/catalog.yaml; atlassian/jira/issues/*.yaml' 'Genau ein kleines, vollstaendiges W1-Grundlagenergebnis mit fachlichen Fertigstellungskriterien waehlen.'))
}
if ($blueprintState.commitsAhead -gt 0) {
    $blueprintFindings.Add((New-GoalFinding low 'GOAL-BP-006' "Der lokale Blueprint ist dem veroeffentlichten Zweig um $($blueprintState.commitsAhead) Commit(s) voraus." 'Git HEAD gegen ls-remote origin/codex/universaarl-blueprint-v2' 'Erst nach bestandener technischer und strategischer Pruefstufe exakt den lokalen Stand veroeffentlichen.'))
}
if ($walkthroughBuilder -match "run\('ffmpeg'" -and $walkthroughTests -match "spawnSync\('ffprobe'" -and
    ($blueprintReadme -notmatch '(?i)ffmpeg' -or $blueprintReadme -notmatch '(?i)ffprobe')) {
    $blueprintFindings.Add((New-GoalFinding medium 'GOAL-BP-007' 'Der reproduzierbare Einstieg verschweigt die fuer `npm test` erforderliche FFmpeg-/ffprobe-Werkzeugkette und deren Versionsgrenze.' 'README.md; scripts/build-walkthrough.mjs; tests/artifacts/walkthrough.test.mjs' 'Werkzeugvoraussetzung und unterstuetzte Version dokumentieren sowie die Medienerzeugung bei einer Abweichung vor jeder Aenderung stoppen.'))
}

$twinMvpTasks = Read-Text (Join-Path $twinRoot 'openspec\changes\establish-read-only-project-twin-mvp\tasks.md')
$twinAdapter = Read-Text (Join-Path $twinRoot 'src\server\adapter.ts')
$twinMain = Read-Text (Join-Path $twinRoot 'src\main.tsx')
$twinResponsiveTasks = Read-Text (Join-Path $twinRoot 'openspec\changes\establish-responsive-project-operations-cockpit\tasks.md')
$mvpRef = Invoke-GitRead -Repository $twinRoot -Arguments @('rev-parse', 'codex/read-only-project-twin-mvp')
if ($twinState.branch -eq 'codex/responsive-project-operations-cockpit' -and $mvpRef.exitCode -eq 0) {
    $ancestor = Invoke-GitRead -Repository $twinRoot -Arguments @('merge-base', '--is-ancestor', $mvpRef.output, 'HEAD')
    if ($ancestor.exitCode -ne 0) {
        $twinFindings.Add((New-GoalFinding high 'GOAL-TW-001' 'Der responsive Arbeitszwischenstand basiert nicht auf dem veroeffentlichten MVP-Ausgangsstand.' 'Git codex/read-only-project-twin-mvp gegen HEAD' 'Arbeitszwischenstand verlustfrei auf den veroeffentlichten MVP-Ausgangsstand heben und danach neu pruefen.'))
    }
}
if ($twinState.activeChanges.Count -gt 1) {
    $twinFindings.Add((New-GoalFinding high 'GOAL-TW-002' "$($twinState.activeChanges.Count) aktive Twin-Aenderungen verletzen die klare Zielreihenfolge." 'openspec/changes/' 'MVP-Pruefstufe ehrlich abschliessen, bevor die responsive Aenderung freigegeben wird.'))
}
if ($twinMvpTasks -match '(?m)^\s*-\s*\[\s\]\s+Human approval and archive') {
    $twinFindings.Add((New-GoalFinding medium 'GOAL-TW-003' 'Menschliche Freigabe und Archivierung des MVP sind weiterhin offen.' 'openspec/changes/establish-read-only-project-twin-mvp/tasks.md' 'Keine Freigabe erfinden; ausdrueckliche Nutzerentscheidung einholen.'))
}
if ($twinMain -match '10\. Juli' -or $twinMain -match 'i\s*%\s*[34]') {
    $twinFindings.Add((New-GoalFinding high 'GOAL-TW-004' 'Die Oberflaeche des Arbeitszwischenstands enthaelt fest eingetragene oder indexbasiert erzeugte Zeitplandaten.' 'src/main.tsx' 'Ausschliesslich Quelltermine skalieren, sonst einen ehrlichen Leerzustand zeigen.'))
}
if ($twinAdapter -match "imagePath\.includes\('/run-1/'\)" -and $twinAdapter -match 'UABC-VER-ENV-RUN2-001') {
    $twinFindings.Add((New-GoalFinding high 'GOAL-TW-005' 'Nachweiskennungen werden aus dem Verzeichnispfad geraten statt aus dem Register aufgeloest.' 'src/server/adapter.ts' 'PNG-Nachweise ausschliesslich registerbasiert mit Pruefkennungen verknuepfen.'))
}
$responsiveOpenTasks = [regex]::Matches($twinResponsiveTasks, '(?m)^\s*-\s*\[\s\]\s+').Count
if ($responsiveOpenTasks -gt 0) {
    $twinFindings.Add((New-GoalFinding low 'GOAL-TW-006' "$responsiveOpenTasks Aufgabe(n) der responsiven Aenderung sind noch offen." 'openspec/changes/establish-responsive-project-operations-cockpit/tasks.md' 'Aenderung erst nach Datenvertrag, Tests und Browserpruefung uebergeben.'))
}
if ($twinState.dirty) {
    $twinFindings.Add((New-GoalFinding low 'GOAL-TW-007' 'Der aktuelle Twin-Stand ist ein lokaler Arbeitszwischenstand und keine veroeffentlichte Wahrheit.' 'git status --porcelain' 'Lokalen und veroeffentlichten Stand in jeder Bewertung getrennt ausweisen.'))
}

$blueprintExport = Join-Path $blueprintRoot 'exports\project-artifacts\v0.1\index.yaml'
$twinConsumesArtifactContract = $twinAdapter -match 'project-artifacts/v0\.1' -or $twinAdapter -match "safeRoots\s*=\s*\[[^\]]*'exports'"
if ((Test-Path -LiteralPath $blueprintExport -PathType Leaf) -and -not $twinConsumesArtifactContract) {
    $relationshipFindings.Add((New-GoalFinding medium 'GOAL-X-001' 'Das Blueprint veroeffentlicht einen Rundgang-Verbrauchervertrag, den der Twin noch nicht liest.' 'exports/project-artifacts/v0.1/index.yaml; Twin src/server/adapter.ts' 'Nach Abschluss der aktuellen Twin-Aenderung eine eigene Verbraucheranpassung planen oder die Luecke ausdruecklich akzeptieren.'))
}

$blueprintResult = [pscustomobject]@{
    id = 'blueprint'; objective = [string]$GoalConfig.projects.blueprint.objective; currentGoal = [string]$GoalConfig.projects.blueprint.currentGoal
    status = Get-GoalStatus -Findings @($blueprintFindings); repository = $blueprintRoot; state = $blueprintState
    metrics = [pscustomobject]@{ capabilityStatuses = $capabilityStatuses; jiraStatuses = $jiraStatuses }
    findings = @($blueprintFindings)
}
$twinResult = [pscustomobject]@{
    id = 'project-twin'; objective = [string]$GoalConfig.projects.'project-twin'.objective; currentGoal = [string]$GoalConfig.projects.'project-twin'.currentGoal
    status = Get-GoalStatus -Findings @($twinFindings); repository = $twinRoot; state = $twinState
    metrics = [pscustomobject]@{ responsiveOpenTasks = $responsiveOpenTasks }
    findings = @($twinFindings)
}
$relationshipResult = [pscustomobject]@{
    id = 'twin-reads-blueprint'; objective = [string]$GoalConfig.relationships.'twin-reads-blueprint'.objective
    status = Get-GoalStatus -Findings @($relationshipFindings); findings = @($relationshipFindings)
}
$allFindings = @($blueprintFindings) + @($twinFindings) + @($relationshipFindings)
$overall = Get-GoalStatus -Findings $allFindings
$report = [pscustomobject]@{
    schemaVersion = 1; generatedAt = (Get-Date).ToUniversalTime().ToString('o'); overallStatus = $overall
    projects = @($blueprintResult, $twinResult); relationships = @($relationshipResult)
    safety = [pscustomobject]@{ targetWrites = $false; prohibitedRuntimeMaterialRead = $false; gitOptionalLocksDisabled = $true }
}

$jsonPath = Join-Path $ReportRoot 'goals-latest.json'
$markdownPath = Join-Path $ReportRoot 'goals-latest.md'
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$severityText = @{ 'high' = 'hoch'; 'medium' = 'mittel'; 'low' = 'niedrig'; 'info' = 'Hinweis' }
$markdown = [Collections.Generic.List[string]]::new()
$markdown.Add('# Universaarl Zielbericht')
$markdown.Add('')
$markdown.Add("- Zeitpunkt (UTC): ``$($report.generatedAt)``")
$markdown.Add("- Gesamtstatus: **$overall**")
$markdown.Add('- Modus: ausschliesslich lesende strategische Zielpruefung')
$markdown.Add('')
$markdown.Add('| Projekt | Zielstatus | Zweig | Lokal | Veroeffentlicht | Aktive Aenderungen |')
$markdown.Add('|---|---:|---|---|---|---:|')
foreach ($project in $report.projects) {
    $local = if ($project.state.head) { $project.state.head.Substring(0, [Math]::Min(8, $project.state.head.Length)) } else { '(keiner)' }
    $published = if ($project.state.publishedCommit) { $project.state.publishedCommit.Substring(0, [Math]::Min(8, $project.state.publishedCommit.Length)) } else { '(unbekannt)' }
    $markdown.Add("| $($project.id) | $($project.status) | ``$($project.state.branch)`` | ``$local`` | ``$published`` | $($project.state.activeChanges.Count) |")
}
foreach ($project in $report.projects) {
    $markdown.Add('')
    $markdown.Add("## $($project.id)")
    $markdown.Add('')
    $markdown.Add("**Projektziel:** $($project.objective)")
    $markdown.Add('')
    $markdown.Add("**Naechstes Ergebnis:** $($project.currentGoal)")
    $markdown.Add('')
    if ($project.findings.Count -eq 0) { $markdown.Add('- Keine strategische Drift erkannt.') }
    foreach ($finding in $project.findings) {
        $displaySeverity = if ($severityText.ContainsKey([string]$finding.severity)) { $severityText[[string]$finding.severity] } else { 'unbekannt' }
        $markdown.Add("- **$displaySeverity / ``$($finding.code)``:** $($finding.message) Nachweis: ``$($finding.evidence)`` Naechstes Ziel: $($finding.nextGoal)")
    }
}
$markdown.Add('')
$markdown.Add('## Zusammenspiel')
$markdown.Add('')
if ($relationshipResult.findings.Count -eq 0) { $markdown.Add('- Der deklarierte Zielvertrag ist abgedeckt.') }
foreach ($finding in $relationshipResult.findings) {
    $displaySeverity = if ($severityText.ContainsKey([string]$finding.severity)) { $severityText[[string]$finding.severity] } else { 'unbekannt' }
    $markdown.Add("- **$displaySeverity / ``$($finding.code)``:** $($finding.message) Nachweis: ``$($finding.evidence)`` Naechstes Ziel: $($finding.nextGoal)")
}
$markdown.Add('')
$markdown.Add('> Die Zielpruefung veraendert keines der Zielprojekte und liest keine `.env*`, Authentifizierungszustaende, Geheimnisse, Ablaufspuren, Videos oder Laufzeitnachweise.')
$markdown | Set-Content -LiteralPath $markdownPath -Encoding UTF8

Write-Host "Universaarl Zielpruefung: $overall"
Write-Host "- Universaarl BC Blueprint V2: $($blueprintResult.status)"
Write-Host "- Universaarl Project Twin: $($twinResult.status)"
Write-Host "- Zusammenspiel: $($relationshipResult.status)"
Write-Host "Bericht: $markdownPath"
