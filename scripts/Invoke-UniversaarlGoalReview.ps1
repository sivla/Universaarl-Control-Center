[CmdletBinding()]
param(
    [string]$RunId,
    [string]$ConfigPath,
    [string]$GoalConfigPath,
    [string]$ReportRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$MonitorRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
. (Join-Path $PSScriptRoot 'Universaarl-Control.Common.ps1')
if ([string]::IsNullOrWhiteSpace($RunId)) { $RunId = New-UniversaarlRunId -Prefix 'ziel' }
Assert-UniversaarlRunId -RunId $RunId
if ([string]::IsNullOrWhiteSpace($ConfigPath)) { $ConfigPath = Join-Path $MonitorRoot 'monitor.config.json' }
if ([string]::IsNullOrWhiteSpace($GoalConfigPath)) { $GoalConfigPath = Join-Path $MonitorRoot 'project-goals.json' }
$MonitorConfig = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$GoalConfig = Get-Content -LiteralPath $GoalConfigPath -Raw | ConvertFrom-Json
Assert-UniversaarlMonitorConfiguration -Configuration $MonitorConfig
Assert-UniversaarlGoalConfiguration -Configuration $GoalConfig
if ([string]::IsNullOrWhiteSpace($ReportRoot)) { $ReportRoot = Join-Path $MonitorRoot ([string]$MonitorConfig.reportDirectory) }
$ReportRoot = [IO.Path]::GetFullPath($ReportRoot)
if (-not $ReportRoot.StartsWith($MonitorRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Zielberichtverzeichnis muss innerhalb des Kontrollzentrums liegen.' }
$ReportTrustedRoot = $MonitorRoot
$GoalRunRoot = Join-Path $ReportRoot 'goal-runs'
$null = Initialize-UniversaarlSafeDirectory -TrustedRoot $ReportTrustedRoot -Directory $ReportRoot
$null = Initialize-UniversaarlSafeDirectory -TrustedRoot $ReportRoot -Directory $GoalRunRoot
$runJsonPath = Join-Path $GoalRunRoot "$RunId.json"
$runMarkdownPath = Join-Path $GoalRunRoot "$RunId.md"
if ((Test-Path -LiteralPath $runJsonPath) -or (Test-Path -LiteralPath $runMarkdownPath)) { throw 'Die Laufkennung wurde bereits verwendet.' }

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
    $severities = @($Findings | ForEach-Object severity)
    if ($severities -contains 'high') { return 'ROT' }
    if ($severities -contains 'medium') { return 'GELB' }
    'GRUEN'
}

function Get-HeadCommit {
    param([Parameter(Mandatory)][string]$Repository)
    $head = Invoke-UniversaarlGitRead -Repository $Repository -Arguments @('rev-parse', '--verify', 'HEAD^{commit}')
    if ($head.exitCode -ne 0) { throw 'HEAD kann nicht als Commit aufgeloest werden.' }
    Assert-FullCommitSha -Commit $head.output
    $head.output
}

function Read-RequiredGoalText {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$Commit,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.List[object]]$Findings,
        [Parameter(Mandatory)][string]$Code,
        [int64]$MaximumBytes = 1048576
    )
    try {
        $content = [string](Read-UniversaarlCommitText -Repository $Repository -Commit $Commit -Path $Path -MaximumBytes $MaximumBytes -Required).content
        if ([string]::IsNullOrWhiteSpace($content) -or $content.IndexOf([char]0) -ge 0) { throw 'Pflichtartefakt ist leer oder kein zulaessiger Text.' }
        $extension = [IO.Path]::GetExtension($Path).ToLowerInvariant()
        if ($extension -in @('.yaml', '.yml') -and $content -notmatch '(?m)^\s*(?:-\s+)?[A-Za-z0-9_.-]+\s*:\s*') { throw 'YAML-Pflichtartefakt besitzt keine erkennbare Schluesselstruktur.' }
        if ($extension -eq '.md' -and $content -notmatch '(?m)^\s*#{1,6}\s+\S') { throw 'Markdown-Pflichtartefakt besitzt keine Ueberschriftenstruktur.' }
        if ($extension -in @('.mjs', '.js', '.ts', '.tsx') -and $content -notmatch '(?m)\b(?:import|export|const|let|function|class|interface|type)\b') { throw 'Code-Pflichtartefakt besitzt keine erkennbare Programmstruktur.' }
        $content
    }
    catch {
        $Findings.Add((New-GoalFinding high $Code "Pflichtartefakt '$Path' fehlt oder kann nicht sicher commitgebunden gelesen werden: $($_.Exception.Message)" $Path 'Pflichtartefakt als kleinen regulaeren Textblob im geprueften Commit bereitstellen.'))
        ''
    }
}

function Get-ActiveChangesFromTree {
    param([object[]]$Tree)
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in $Tree) {
        if ([string]$entry.path -match '^openspec/changes/([^/]+)/') {
            $name = $Matches[1]
            if ($name -notin @('archive', 'archived')) { $null = $names.Add($name) }
        }
    }
    @($names | Sort-Object)
}

function Get-GoalRepositoryState {
    param(
        [Parameter(Mandatory)]$Project,
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.List[object]]$Findings,
        [Parameter(Mandatory)][string]$CodePrefix
    )
    try {
        $head = Get-HeadCommit -Repository $Repository
        $tree = @(Get-UniversaarlCommitTree -Repository $Repository -Commit $head)
        Assert-UniversaarlCommitRuntimeSafe -Repository $Repository -Commit $head -AllowedVersionedMedia @($Project.allowedVersionedMedia)
        $fingerprint = Get-UniversaarlRepositoryFingerprint -Repository $Repository
    }
    catch {
        $Findings.Add((New-GoalFinding high "$CodePrefix-STATE" "Der commitgebundene Repositoryzustand ist unbekannt: $($_.Exception.Message)" 'Git HEAD, Commit-Baum, Status und Index' 'Repositoryzustand sicher lesbar machen; unbekannt darf nicht als gruen gelten.'))
        return [pscustomobject]@{ head = $null; branch = $null; dirty = $null; publishedCommit = $null; commitsAhead = $null; activeChanges = @(); tree = @(); fingerprint = $null }
    }
    $publishedCommit = $null
    $url = [string]$Project.publish.expectedPushUrl
    $branch = [string]$Project.publish.branch
    if ([string]::IsNullOrWhiteSpace($url) -or [string]::IsNullOrWhiteSpace($branch)) {
        $Findings.Add((New-GoalFinding high "$CodePrefix-REMOTE" 'Positivlisten-URL oder Zielzweig fehlt fuer den veroeffentlichten Vergleich.' 'monitor.config.json' 'Remotevergleich vollstaendig konfigurieren.'))
    }
    else {
        $published = Invoke-UniversaarlCleanLsRemote -Url $url -Ref "refs/heads/$branch"
        if ($published.exitCode -ne 0) {
            $Findings.Add((New-GoalFinding medium "$CodePrefix-REMOTE" 'Der veroeffentlichte Zielzweig konnte nicht sicher gelesen werden.' 'Positivlisten-URL und Zielzweig' 'Remotezustand erneut lesbar pruefen; unbekannt bleibt gelb.'))
        }
        elseif (-not [string]::IsNullOrWhiteSpace($published.output)) {
            $publishedCommit = ($published.output -split '\s+')[0]
            if ($publishedCommit -notmatch '^[0-9a-f]{40}$') {
                $Findings.Add((New-GoalFinding high "$CodePrefix-REMOTE" 'Der veroeffentlichte Zielzweig lieferte keine vollstaendige Commit-SHA.' 'git ls-remote' 'Remotezustand eindeutig aufloesen.'))
                $publishedCommit = $null
            }
        }
    }
    $ahead = $null
    if ($publishedCommit) {
        $count = Invoke-UniversaarlGitRead -Repository $Repository -Arguments @('rev-list', '--count', "$publishedCommit..$head")
        if ($count.exitCode -eq 0 -and $count.output -match '^\d+$') { $ahead = [int]$count.output }
        else { $Findings.Add((New-GoalFinding medium "$CodePrefix-AHEAD" 'Der Abstand zum veroeffentlichten Commit ist unbekannt.' 'git rev-list' 'Remote-Commit lokal verfuegbar machen oder den unbekannten Abstand offen halten.')) }
    }
    [pscustomobject]@{
        head = $head
        branch = $fingerprint.branch
        dirty = $fingerprint.dirty
        publishedCommit = $publishedCommit
        commitsAhead = $ahead
        activeChanges = @(Get-ActiveChangesFromTree -Tree $tree)
        tree = @($tree)
        fingerprint = $fingerprint
    }
}

$projectById = @{}
foreach ($project in $MonitorConfig.projects) { $projectById[[string]$project.id] = $project }
$blueprintProject = $projectById['blueprint']
$twinProject = $projectById['project-twin']
$blueprintRoot = Get-UniversaarlConfiguredPath -Project $blueprintProject
$twinRoot = Get-UniversaarlConfiguredPath -Project $twinProject
$blueprintFindings = [Collections.Generic.List[object]]::new()
$twinFindings = [Collections.Generic.List[object]]::new()
$relationshipFindings = [Collections.Generic.List[object]]::new()
$spectraFindings = [Collections.Generic.List[object]]::new()
$blueprintState = Get-GoalRepositoryState -Project $blueprintProject -Repository $blueprintRoot -Findings $blueprintFindings -CodePrefix 'GOAL-BP'
$twinState = Get-GoalRepositoryState -Project $twinProject -Repository $twinRoot -Findings $twinFindings -CodePrefix 'GOAL-TW'
$verificationSourceConfig = $MonitorConfig.verificationSources.bcprojectos
$verificationSourceRoot = Get-UniversaarlConfiguredPath -Project $verificationSourceConfig
$verificationInput = [pscustomobject][ordered]@{ id = 'bcprojectos'; technicalProjectName = 'BCProjectOS'; productName = 'Spectra'; productId = 'spectra'; sourceCommit = $null; branch = '(nicht verfuegbar)'; remoteUrl = $null; fingerprintBefore = $null; fingerprintAfter = $null; targetUnchanged = $false; status = 'failed' }
$verificationFingerprint = $null
try {
    $verificationInput.sourceCommit = Get-HeadCommit -Repository $verificationSourceRoot
    $verificationFingerprint = Get-UniversaarlRepositoryFingerprint -Repository $verificationSourceRoot
    $verificationInput.fingerprintBefore = $verificationFingerprint
    $verificationInput.branch = $verificationFingerprint.branch
    $verificationInput.remoteUrl = Get-UniversaarlRawFetchUrl -Repository $verificationSourceRoot -Remote ([string]$verificationSourceConfig.remote)
    if ([string]$verificationInput.remoteUrl -cne [string]$verificationSourceConfig.canonicalRemoteUrl) { throw 'Rohe Remote-URL stimmt nicht mit der Positivliste ueberein.' }
    $verificationInput.status = 'observed'
}
catch { $spectraFindings.Add((New-GoalFinding high 'GOAL-SPECTRA-SOURCE' "Die technische Spectra-Evidence-Quelle BCProjectOS kann nicht sicher gelesen werden: $($_.Exception.Message)" 'BCProjectOS-Commit und Remote' 'Evidence-Quelle mit kanonischem Remote und stabiler Commit-SHA bereitstellen.')) }

$blueprintOpenSpec = ''
$blueprintArchitecture = ''
$blueprintCapability = ''
$blueprintEnvironmentPage = ''
$blueprintReadme = ''
$walkthroughBuilder = ''
$walkthroughTests = ''
$blueprintConsumerBinding = ''
$spectraBindingArtifactPresent = $false
$spectraBindingIdentityValid = $false
if ($blueprintState.head) {
    $blueprintOpenSpec = Read-RequiredGoalText -Repository $blueprintRoot -Commit $blueprintState.head -Path 'openspec/config.yaml' -Findings $blueprintFindings -Code 'GOAL-BP-ARTIFACT'
    $blueprintArchitecture = Read-RequiredGoalText -Repository $blueprintRoot -Commit $blueprintState.head -Path 'architecture/enterprise-blueprint.yaml' -Findings $blueprintFindings -Code 'GOAL-BP-ARTIFACT'
    $blueprintCapability = Read-RequiredGoalText -Repository $blueprintRoot -Commit $blueprintState.head -Path 'capabilities/catalog.yaml' -Findings $blueprintFindings -Code 'GOAL-BP-ARTIFACT'
    $blueprintEnvironmentPage = Read-RequiredGoalText -Repository $blueprintRoot -Commit $blueprintState.head -Path 'atlassian/confluence/pages/60-environment-baseline.md' -Findings $blueprintFindings -Code 'GOAL-BP-ARTIFACT'
    $blueprintReadme = Read-RequiredGoalText -Repository $blueprintRoot -Commit $blueprintState.head -Path 'README.md' -Findings $blueprintFindings -Code 'GOAL-BP-ARTIFACT'
    $walkthroughBuilder = Read-RequiredGoalText -Repository $blueprintRoot -Commit $blueprintState.head -Path 'scripts/build-walkthrough.mjs' -Findings $blueprintFindings -Code 'GOAL-BP-ARTIFACT'
    $walkthroughTests = Read-RequiredGoalText -Repository $blueprintRoot -Commit $blueprintState.head -Path 'tests/artifacts/walkthrough.test.mjs' -Findings $blueprintFindings -Code 'GOAL-BP-ARTIFACT'
    $blueprintConsumerBinding = Read-RequiredGoalText -Repository $blueprintRoot -Commit $blueprintState.head -Path 'governance/consumer-bindings.yaml' -Findings $spectraFindings -Code 'GOAL-SPECTRA-BINDING' -MaximumBytes 262144
}

if (-not [string]::IsNullOrWhiteSpace($blueprintConsumerBinding)) {
    $spectraBindingArtifactPresent = $true
    $spectraSection = [regex]::Match($blueprintConsumerBinding, '(?ms)^spectraReleaseBinding:\s*\r?\n(?<body>(?:^[ \t]+.*(?:\r?\n|$))+)')
    if (-not $spectraSection.Success -or [string]$spectraSection.Groups['body'].Value -notmatch '(?m)^  productId:\s*spectra\s*$' -or
        [string]$spectraSection.Groups['body'].Value -notmatch '(?m)^  technicalRepositoryName:\s*BCProjectOS\s*$' -or
        [string]$spectraSection.Groups['body'].Value -notmatch '(?m)^  repositoryUrl:\s*https://github\.com/sivla/BCProjectOS\.git\s*$') {
        $spectraFindings.Add((New-GoalFinding high 'GOAL-SPECTRA-IDENTITY' 'Die Kundeninstanz bindet nicht eindeutig das Produkt Spectra aus dem technischen Repository BCProjectOS.' 'governance/consumer-bindings.yaml' 'Produkt-ID spectra und die kanonische BCProjectOS-Repository-URL exakt binden.'))
    }
    elseif ([string]$spectraSection.Groups['body'].Value -match '(?m)^  bindingStatus:\s*PENDING_BCPROJECTOS_RELEASE\s*$') {
        $spectraBindingIdentityValid = $true
        $spectraFindings.Add((New-GoalFinding high 'GOAL-SPECTRA-PENDING' 'Der Spectra-Release ist weiterhin ausstehend; Kundenbindung und Snapshot duerfen nicht freigegeben werden.' 'governance/consumer-bindings.yaml' 'Echten installierbaren Spectra-Release separat mit Tag, Commit, Manifest und Digest nachweisen.'))
    }
    else {
        $spectraBindingIdentityValid = $true
        $spectraFindings.Add((New-GoalFinding high 'GOAL-SPECTRA-UNVERIFIED' 'Eine nicht ausstehende Spectra-Bindung ist noch nicht durch den vollstaendigen Kontrollzentrum-Releasevalidator nachgewiesen.' 'governance/consumer-bindings.yaml; BCProjectOS-Releaseevidence' 'Bound-Zustand erst nach vollstaendiger commitgebundener Releasevalidierung akzeptieren.'))
    }
}

foreach ($requiredShape in @(
    @{ text = $blueprintOpenSpec; pattern = '(?m)^\s*(?:schema|context|project|actualSandboxBaseline)\s*:'; path = 'openspec/config.yaml' },
    @{ text = $blueprintArchitecture; pattern = '(?m)^actualSandboxBaseline\s*:'; path = 'architecture/enterprise-blueprint.yaml' },
    @{ text = $blueprintCapability; pattern = '(?m)^\s*(?:capabilities|id|status|-\s+id)\s*:'; path = 'capabilities/catalog.yaml' },
    @{ text = $walkthroughBuilder; pattern = '(?m)\b(?:ffmpeg|spawn|execFile|execFileSync)\b'; path = 'scripts/build-walkthrough.mjs' },
    @{ text = $walkthroughTests; pattern = '(?m)\b(?:test|describe|it)\s*\('; path = 'tests/artifacts/walkthrough.test.mjs' }
)) {
    if (-not [string]::IsNullOrWhiteSpace([string]$requiredShape.text) -and [string]$requiredShape.text -notmatch [string]$requiredShape.pattern) {
        $blueprintFindings.Add((New-GoalFinding high 'GOAL-BP-STRUCTURE' "Pflichtartefakt '$($requiredShape.path)' besitzt nicht die erwartete fachliche Struktur." $requiredShape.path 'Pflichtartefakt strukturell gueltig und mit den erwarteten kanonischen Markern bereitstellen.'))
    }
}

$baselineApproved = $blueprintArchitecture -match '(?ms)^actualSandboxBaseline:\s*\r?\n\s+status:\s*approved\b'
if ($baselineApproved -and $blueprintOpenSpec -match 'actualSandboxBaseline:\s*currently unknown') { $blueprintFindings.Add((New-GoalFinding high 'GOAL-BP-001' 'Der OpenSpec-Kontext widerspricht dem kanonisch freigegebenen Sandbox-Ausgangsstand.' 'openspec/config.yaml; architecture/enterprise-blueprint.yaml' 'Auf den kanonischen Ausgangsstand verweisen, ohne Fakten zu duplizieren.')) }
if ($baselineApproved -and $blueprintArchitecture -match 'targetEnvironment:\s*authorized-not-inspected') { $blueprintFindings.Add((New-GoalFinding medium 'GOAL-BP-002' 'Eine Zielumgebungs-Kurzfassung bleibt trotz des spaeteren Ausgangsstands ungeprueft.' 'architecture/enterprise-blueprint.yaml' 'Kurzfassung auf den kanonischen Ausgangsstand beziehen.')) }
if ($baselineApproved -and $blueprintArchitecture -match '(?ms)^localization:\s*\r?\n\s+target:.*\r?\n\s+actual:\s+unknown') { $blueprintFindings.Add((New-GoalFinding medium 'GOAL-BP-003' 'Die Lokalisierungs-Kurzfassung bildet den spaeteren Kandidaten- und Teilnachweis nicht ab.' 'architecture/enterprise-blueprint.yaml' 'Lokalisierungszusammenfassung auf den kanonischen Teilnachweis verweisen lassen.')) }
if ($blueprintState.activeChanges.Count -eq 0 -and $blueprintEnvironmentPage -match '(?i)aktive[rn]?\s+Change.*establish-playthru-environment-baseline') { $blueprintFindings.Add((New-GoalFinding medium 'GOAL-BP-004' 'Confluence bezeichnet eine archivierte Ausgangsstands-Aenderung weiterhin als aktiv.' 'atlassian/confluence/pages/60-environment-baseline.md' 'Kanonischen Ausgangsstand und Archivhistorie korrekt benennen.')) }
$capabilityStatuses = @{}
foreach ($match in [regex]::Matches($blueprintCapability, '(?<![A-Za-z])status:\s*(planned|validated|approved|deferred|out-of-scope)\b')) {
    $key = $match.Groups[1].Value
    $capabilityStatuses[$key] = 1 + $(if ($capabilityStatuses.ContainsKey($key)) { [int]$capabilityStatuses[$key] } else { 0 })
}
$jiraStatuses = @{}
$jiraEntries = @($blueprintState.tree | Where-Object { $_.path -match '^atlassian/jira/issues/[^/]+\.yaml$' })
if ($blueprintState.head -and $jiraEntries.Count -eq 0) { $blueprintFindings.Add((New-GoalFinding high 'GOAL-BP-JIRA' 'Commitgebundene Jira-Vorgangsexporte fehlen.' 'atlassian/jira/issues/*.yaml' 'Jira-Ausgangsstand als kleine regulaere YAML-Blobs bereitstellen.')) }
foreach ($entry in $jiraEntries) {
    $jiraText = Read-RequiredGoalText -Repository $blueprintRoot -Commit $blueprintState.head -Path $entry.path -Findings $blueprintFindings -Code 'GOAL-BP-JIRA' -MaximumBytes 524288
    foreach ($match in [regex]::Matches($jiraText, '(?m)^\s+status:\s*(Backlog|Ready|In Progress|Blocked|In Review|Done)\s*$')) {
        $key = $match.Groups[1].Value
        $jiraStatuses[$key] = 1 + $(if ($jiraStatuses.ContainsKey($key)) { [int]$jiraStatuses[$key] } else { 0 })
    }
}
$jiraTotalMeasure = $jiraStatuses.Values | Measure-Object -Sum
$jiraTotal = if ($null -ne $jiraTotalMeasure.Sum) { [int]$jiraTotalMeasure.Sum } else { 0 }
$jiraDone = if ($jiraStatuses.ContainsKey('Done')) { [int]$jiraStatuses['Done'] } else { 0 }
$validatedCapabilities = $(if ($capabilityStatuses.ContainsKey('validated')) { [int]$capabilityStatuses['validated'] } else { 0 }) + $(if ($capabilityStatuses.ContainsKey('approved')) { [int]$capabilityStatuses['approved'] } else { 0 })
if ($blueprintState.activeChanges.Count -eq 0 -and $jiraTotal -gt 0 -and $jiraDone -eq $jiraTotal -and $validatedCapabilities -eq 0) { $blueprintFindings.Add((New-GoalFinding medium 'GOAL-BP-005' 'Alle aktuellen Jira-Vorgaenge sind erledigt, aber keine fachliche Faehigkeit ist validiert.' 'capabilities/catalog.yaml; Jira-Vorgangsexporte' 'Genau ein kleines, vollstaendiges W1-Grundlagenergebnis mit fachlichen Fertigstellungskriterien waehlen.')) }
if ($walkthroughBuilder -match "run\('ffmpeg'" -and $walkthroughTests -match "spawnSync\('ffprobe'" -and ($blueprintReadme -notmatch '(?i)ffmpeg' -or $blueprintReadme -notmatch '(?i)ffprobe')) { $blueprintFindings.Add((New-GoalFinding medium 'GOAL-BP-007' 'Der reproduzierbare Einstieg verschweigt die erforderliche FFmpeg-/ffprobe-Werkzeugkette.' 'README.md; Medienwerkzeuge und Tests' 'Werkzeugvoraussetzung und unterstuetzte Version dokumentieren.')) }
if ($blueprintState.commitsAhead -gt 0) { $blueprintFindings.Add((New-GoalFinding low 'GOAL-BP-006' "Der lokale Blueprint ist dem veroeffentlichten Zweig um $($blueprintState.commitsAhead) Commit(s) voraus." 'volle lokale und veroeffentlichte Commit-SHA' 'Nur nach bestandenen Pruefstufen exakt den lokalen Commit veroeffentlichen.')) }

$twinMvpTasks = ''
$twinCurrentTasks = ''
$twinAdapter = ''
$twinMain = ''
$twinRegistry = ''
if ($twinState.head) {
    $requiredBase = [string]$GoalConfig.projects.'project-twin'.requiredBaseCommit
    try {
        Assert-FullCommitSha -Commit $requiredBase
        $base = Invoke-UniversaarlGitRead -Repository $twinRoot -Arguments @('cat-file', '-e', "$requiredBase^{commit}")
        if ($base.exitCode -ne 0) { throw 'Basis-Commit ist nicht lokal aufloesbar.' }
        $ancestor = Invoke-UniversaarlGitRead -Repository $twinRoot -Arguments @('merge-base', '--is-ancestor', $requiredBase, $twinState.head)
        if ($ancestor.exitCode -ne 0) { $twinFindings.Add((New-GoalFinding high 'GOAL-TW-001' 'Der Twin-Commit basiert nicht auf dem explizit geforderten MVP-Ausgangsstand.' "Git $requiredBase gegen $($twinState.head)" 'Arbeitsstand verlustfrei auf den geforderten Ausgangsstand heben.')) }
    }
    catch { $twinFindings.Add((New-GoalFinding high 'GOAL-TW-001' "Der explizite Twin-Basisnachweis ist nicht aufloesbar: $($_.Exception.Message)" 'project-goals.json und Git-Objektbestand' 'Vollstaendige Basis-SHA sicher bereitstellen und Vorfahrbeziehung nachweisen.')) }

    $mvpCandidates = @($twinState.tree | Where-Object { $_.path -match '^openspec/changes/(?:archive/)?[^/]*establish-read-only-project-twin-mvp/tasks\.md$' })
    if ($mvpCandidates.Count -ne 1) { $twinFindings.Add((New-GoalFinding high 'GOAL-TW-003' 'Der commitgebundene MVP-Freigabenachweis fehlt oder ist nicht eindeutig.' 'OpenSpec MVP tasks.md' 'MVP-Freigabenachweis eindeutig im Commit halten.')) }
    else {
        $mvpPath = [string]$mvpCandidates[0].path
        $twinMvpTasks = Read-RequiredGoalText -Repository $twinRoot -Commit $twinState.head -Path $mvpPath -Findings $twinFindings -Code 'GOAL-TW-003'
        if ($mvpPath -notmatch '^openspec/changes/archive/') { $twinFindings.Add((New-GoalFinding medium 'GOAL-TW-003' 'Der MVP-Freigabenachweis liegt fuer den Zwischenstand noch nicht in einer archivierten Aenderung.' $mvpPath 'MVP erst nach ausdruecklicher Freigabe regulaer archivieren.')) }
        $approvalState = Get-UniversaarlApprovalTaskState -Text $twinMvpTasks
        if ($approvalState -eq 'invalid') { $twinFindings.Add((New-GoalFinding high 'GOAL-TW-003' 'Die exakt affirmative menschliche Freigabeaufgabe fehlt oder ist nicht eindeutig.' $mvpPath 'Genau eine vollstaendig verankerte Aufgabe `Human approval and archive` oder `Menschliche Freigabe und Archivierung` fuehren.')) }
        elseif ($approvalState -eq 'open') { $twinFindings.Add((New-GoalFinding medium 'GOAL-TW-003' 'Die ausdrueckliche menschliche Freigabe ist fuer den Zwischenstand weiterhin offen.' $mvpPath 'Keine Freigabe erfinden; vor der endgueltigen Freigabe ausdrueckliche menschliche Zustimmung einholen.')) }
    }

    $currentChange = [string]$GoalConfig.projects.'project-twin'.currentChange
    if ([string]::IsNullOrWhiteSpace($currentChange) -or $currentChange -notmatch '^[a-z0-9][a-z0-9-]+$') { $twinFindings.Add((New-GoalFinding high 'GOAL-TW-006' 'Die aktuelle Mehrprojekt-Aenderung ist nicht sicher konfiguriert.' 'project-goals.json' 'Aktuelle Change-ID explizit konfigurieren.')) }
    else {
        $currentTaskPath = "openspec/changes/$currentChange/tasks.md"
        $twinCurrentTasks = Read-RequiredGoalText -Repository $twinRoot -Commit $twinState.head -Path $currentTaskPath -Findings $twinFindings -Code 'GOAL-TW-006'
        if (-not [string]::IsNullOrWhiteSpace($twinCurrentTasks) -and $twinCurrentTasks -notmatch '(?m)^\s*-\s*\[[ xX]\]\s+') { $twinFindings.Add((New-GoalFinding high 'GOAL-TW-006' 'Die aktuelle Aenderung besitzt keine strukturell erkennbare Aufgabenliste.' $currentTaskPath 'Aufgaben als eindeutige OpenSpec-Checkboxen dokumentieren.')) }
        $openTasks = [regex]::Matches($twinCurrentTasks, '(?m)^\s*-\s*\[\s\]\s+').Count
        if ($openTasks -gt 0) { $twinFindings.Add((New-GoalFinding medium 'GOAL-TW-006' "$openTasks Aufgabe(n) der Mehrprojekt-Aenderung sind im Zwischenstand noch offen." $currentTaskPath 'Offene Aufgaben vor der endgueltigen Freigabe abschliessen.')) }
    }
    $twinAdapter = Read-RequiredGoalText -Repository $twinRoot -Commit $twinState.head -Path 'src/server/adapter.ts' -Findings $twinFindings -Code 'GOAL-TW-ARTIFACT'
    $twinMain = Read-RequiredGoalText -Repository $twinRoot -Commit $twinState.head -Path 'src/main.tsx' -Findings $twinFindings -Code 'GOAL-TW-ARTIFACT'
    $twinRegistry = Read-RequiredGoalText -Repository $twinRoot -Commit $twinState.head -Path 'src/projects/registry.ts' -Findings $twinFindings -Code 'GOAL-TW-ARTIFACT'
}

if ($twinState.activeChanges.Count -gt 1) { $twinFindings.Add((New-GoalFinding medium 'GOAL-TW-002' "$($twinState.activeChanges.Count) aktive Twin-Aenderungen sind fuer den Zwischenstand noch nicht in die endgueltige Zielreihenfolge ueberfuehrt." 'commitgebundener OpenSpec-Baum' 'MVP-Freigabe vor der endgueltigen Mehrprojekt-Freigabe abschliessen.')) }
if ($twinMain -match '10\. Juli' -or $twinMain -match 'i\s*%\s*[34]') { $twinFindings.Add((New-GoalFinding high 'GOAL-TW-004' 'Die Oberflaeche enthaelt fest eingetragene oder indexbasiert erzeugte Zeitplandaten.' 'src/main.tsx' 'Nur belegte Quelltermine darstellen, sonst einen ehrlichen Leerzustand zeigen.')) }
if ($twinAdapter -match "imagePath\.includes\('/run-1/'\)" -and $twinAdapter -match 'UABC-VER-ENV-RUN2-001') { $twinFindings.Add((New-GoalFinding high 'GOAL-TW-005' 'Nachweiskennungen werden aus einem Verzeichnispfad geraten.' 'src/server/adapter.ts' 'Nachweise ausschliesslich registerbasiert verknuepfen.')) }
if ($twinState.dirty -eq $true) { $twinFindings.Add((New-GoalFinding low 'GOAL-TW-007' 'Der aktuelle Twin-Arbeitsbaum ist lokal unsauber.' 'git status --porcelain' 'Lokalen und veroeffentlichten Stand getrennt ausweisen.')) }

if ($blueprintState.head -and $twinState.head) {
    $legacyExportEntry = Get-UniversaarlBlobEntry -Repository $blueprintRoot -Commit $blueprintState.head -Path 'exports/project-artifacts/v0.1/index.yaml'
    $projectDataEntry = Get-UniversaarlBlobEntry -Repository $blueprintRoot -Commit $blueprintState.head -Path 'exports/project-data/v1/index.yaml'
    $branchIndexPresent = $null -ne $projectDataEntry
    $branchIndexProof = $null
    $twinConsumesLegacy = $twinAdapter -match 'project-artifacts/v0\.1' -or $twinAdapter -match "safeRoots\s*=\s*\[[^\]]*'exports'"
    $twinConsumesProjectData = ($twinRegistry -match 'exports/project-data/v1/index\.yaml' -or $twinAdapter -match 'exports/project-data/v1/index\.yaml') -and $twinAdapter -match 'allowedBranch' -and $twinAdapter -match 'rev-parse'
    if ($null -ne $legacyExportEntry -and -not $twinConsumesLegacy) { $relationshipFindings.Add((New-GoalFinding medium 'GOAL-X-001' 'Der Twin liest den bisherigen Blueprint-Verbrauchervertrag noch nicht.' 'exports/project-artifacts/v0.1/index.yaml; Twin-Adapter' 'Verbraucheranpassung abschliessen oder die Luecke im Zwischenstand ausdruecklich ausweisen.')) }
    if ($null -ne $projectDataEntry -and -not $twinConsumesProjectData) { $relationshipFindings.Add((New-GoalFinding medium 'GOAL-X-002' 'Der Twin liest den projektbezogenen Blueprint-Datenvertrag noch nicht vollstaendig.' 'exports/project-data/v1/index.yaml; Twin-Registry; Twin-Adapter' 'Projektbezogene Indexbindung vor der endgueltigen Freigabe abschliessen.')) }
    if (-not $branchIndexPresent) { $relationshipFindings.Add((New-GoalFinding high 'GOAL-X-BRANCH-INDEX' 'Der commitgebundene BC-Basic-Branch-Index fehlt; der Twin darf den Projektstand nicht lesen.' 'exports/project-data/v1/index.yaml im Blueprint-HEAD' 'Indexvertrag im normalen Projektcommit erzeugen und validieren.')) }
    else {
        try { $branchIndexProof = Test-UniversaarlBranchIndex -Repository $blueprintRoot -Commit $blueprintState.head -ExpectedBranch 'codex/universaarl-projekt' }
        catch { $relationshipFindings.Add((New-GoalFinding high 'GOAL-X-BRANCH-INDEX-INVALID' "Der Branch-Index ist ungueltig: $($_.Exception.Message)" 'commitgebundener Index und positivgelistete Git-Blobs' 'BC-Basic-Branchvertrag korrigieren und erneut pruefen.')) }
    }
}
else {
    $branchIndexPresent = $false
    $branchIndexProof = $null
    $twinConsumesProjectData = $false
    $relationshipFindings.Add((New-GoalFinding high 'GOAL-X-STATE' 'Das Zusammenspiel kann ohne beide vollstaendigen Eingabe-SHAs nicht bewertet werden.' 'Blueprint- und Twin-HEAD' 'Beide Commitzustaende sicher lesbar machen.'))
}

foreach ($pair in @(@{ state = $blueprintState; root = $blueprintRoot; findings = $blueprintFindings; code = 'GOAL-BP-CHANGED' }, @{ state = $twinState; root = $twinRoot; findings = $twinFindings; code = 'GOAL-TW-CHANGED' })) {
    if ($pair.state.fingerprint) {
        try {
            $after = Get-UniversaarlRepositoryFingerprint -Repository $pair.root
            if (-not (Test-UniversaarlFingerprintEqual -Expected $pair.state.fingerprint -Actual $after)) { $pair.findings.Add((New-GoalFinding high $pair.code 'HEAD-, Status- oder Index-Fingerprint hat sich waehrend der Zielpruefung veraendert.' 'Git-Fingerprints vor und nach der Zielpruefung' 'Zielpruefung auf einem unveraenderten Commit erneut ausfuehren.')) }
        }
        catch { $pair.findings.Add((New-GoalFinding high $pair.code 'Abschliessender Git-Fingerprint ist unbekannt.' 'Git-Fingerprint' 'Zielpruefung erneut auf einem stabilen Commit ausfuehren.')) }
    }
}
if ($null -ne $verificationFingerprint) {
    try {
        $verificationAfter = Get-UniversaarlRepositoryFingerprint -Repository $verificationSourceRoot
        $verificationInput.fingerprintAfter = $verificationAfter
        $verificationInput.targetUnchanged = Test-UniversaarlFingerprintEqual -Expected $verificationFingerprint -Actual $verificationAfter
        if (-not $verificationInput.targetUnchanged) {
            $verificationInput.status = 'failed'
            $spectraFindings.Add((New-GoalFinding high 'GOAL-SPECTRA-CHANGED' 'HEAD-, Status- oder Index-Fingerprint der BCProjectOS-Evidence-Quelle hat sich waehrend der Zielpruefung veraendert.' 'BCProjectOS-Fingerprints vor und nach der Zielpruefung' 'Zielpruefung mit stabiler Evidence-Quelle wiederholen.'))
        }
    }
    catch {
        $verificationInput.status = 'failed'
        $spectraFindings.Add((New-GoalFinding high 'GOAL-SPECTRA-CHANGED' 'Der abschliessende Fingerprint der BCProjectOS-Evidence-Quelle ist unbekannt.' 'BCProjectOS-Git-Fingerprint' 'Zielpruefung mit stabiler Evidence-Quelle wiederholen.'))
    }
}

$blueprintCoverage = if ($blueprintState.head -match '^[0-9a-f]{40}$') { 100 } else { 0 }
$twinCoverage = if ($twinState.head -match '^[0-9a-f]{40}$') { 100 } else { 0 }
$spectraCoverage = 0
if ($blueprintCoverage -eq 100) { $spectraCoverage += 20 }
if ($verificationInput.sourceCommit -is [string] -and $verificationInput.sourceCommit -match '^[0-9a-f]{40}$') { $spectraCoverage += 20 }
if ($spectraBindingArtifactPresent) { $spectraCoverage += 20 }
if ($spectraBindingIdentityValid) { $spectraCoverage += 20 }
# Die letzten 20 Prozent erfordern den noch nicht implementierten Vollvalidator.
$relationshipCoverage = 0
if ($blueprintCoverage -eq 100) { $relationshipCoverage += 20 }
if ($twinCoverage -eq 100) { $relationshipCoverage += 20 }
if ($branchIndexPresent) { $relationshipCoverage += 20 }
if ($twinConsumesProjectData) { $relationshipCoverage += 20 }
# Die letzten 20 Prozent erfordern die vollstaendige commitgebundene Index-/Blobvalidierung.
if ($null -ne $branchIndexProof -and $branchIndexProof.fullValidationPassed -eq $true) { $relationshipCoverage += 20 }
$blueprintResult = [pscustomobject]@{ id = 'blueprint'; objective = [string]$GoalConfig.projects.blueprint.objective; currentGoal = [string]$GoalConfig.projects.blueprint.currentGoal; status = Get-GoalStatus @($blueprintFindings); evidenceCoverage = $blueprintCoverage; state = $blueprintState; findings = @($blueprintFindings) }
$twinResult = [pscustomobject]@{ id = 'project-twin'; objective = [string]$GoalConfig.projects.'project-twin'.objective; currentGoal = [string]$GoalConfig.projects.'project-twin'.currentGoal; status = Get-GoalStatus @($twinFindings); evidenceCoverage = $twinCoverage; state = $twinState; findings = @($twinFindings) }
$spectraRelationshipResult = [pscustomobject]@{ id = 'blueprint-binds-spectra'; contractType = 'versioned-product-release'; objective = [string]$GoalConfig.relationships.'blueprint-binds-spectra'.objective; status = Get-GoalStatus @($spectraFindings); fullValidationPassed = $false; evidenceCoverage = $spectraCoverage; productName = 'Spectra'; productId = 'spectra'; technicalProjectName = 'BCProjectOS'; sourceCommit = $verificationInput.sourceCommit; consumerCommit = $blueprintState.head; findings = @($spectraFindings) }
$relationshipResult = [pscustomobject]@{ id = 'twin-reads-blueprint'; contractType = 'validated-branch-index'; objective = [string]$GoalConfig.relationships.'twin-reads-blueprint'.objective; status = Get-GoalStatus @($relationshipFindings); fullValidationPassed = ($null -ne $branchIndexProof -and $branchIndexProof.fullValidationPassed -eq $true -and $twinConsumesProjectData); evidenceCoverage = $relationshipCoverage; providerCommit = $blueprintState.head; consumerCommit = $twinState.head; proof = $branchIndexProof; findings = @($relationshipFindings) }
$allFindings = @($blueprintFindings) + @($twinFindings) + @($spectraFindings) + @($relationshipFindings)
$overall = Get-GoalStatus $allFindings
$inputShas = [ordered]@{ blueprint = $blueprintState.head; 'project-twin' = $twinState.head }
$overallCoverage = [int][Math]::Floor(($blueprintCoverage + $twinCoverage + $spectraCoverage + $relationshipCoverage) / 4)
$report = [pscustomobject]@{ schemaVersion = 2; kind = 'goal'; runId = $RunId; completed = $true; generatedAt = (Get-Date).ToUniversalTime().ToString('o'); overallStatus = $overall; evidenceCoverage = $overallCoverage; inputShas = [pscustomobject]$inputShas; verificationInputs = [pscustomobject]@{ bcprojectos = $verificationInput }; projects = @($blueprintResult, $twinResult); relationships = @($spectraRelationshipResult, $relationshipResult); safety = [pscustomobject]@{ commitBoundTextReads = $true; realEnvironmentFilesRead = $false; gitOptionalLocksDisabled = $true } }

$severityText = @{ high = 'hoch'; medium = 'mittel'; low = 'niedrig'; info = 'Hinweis' }
$markdown = [Collections.Generic.List[string]]::new()
$markdown.Add('# Universaarl Zielbericht')
$markdown.Add('')
$markdown.Add("- Lauf: ``$RunId``")
$markdown.Add("- Zeitpunkt (UTC): ``$($report.generatedAt)``")
$markdown.Add("- Gesamtstatus: **$overall**")
$markdown.Add("- Nachweisabdeckung: **$overallCoverage %**")
$markdown.Add('- Modus: ausschliesslich commitgebundene lesende Zielpruefung')
foreach ($project in $report.projects) {
    $markdown.Add('')
    $markdown.Add("## $($project.id)")
    $markdown.Add('')
    $projectCommitText = if ($project.state.head -match '^[0-9a-f]{40}$') { $project.state.head } else { 'unbekannt' }
    $markdown.Add("- Commit: ``$projectCommitText``")
    $markdown.Add("- Zielstatus: **$($project.status)**")
    $markdown.Add("- Nachweisabdeckung: **$($project.evidenceCoverage) %**")
    $markdown.Add("- Projektziel: $($project.objective)")
    $markdown.Add("- Naechstes Ergebnis: $($project.currentGoal)")
    if ($project.findings.Count -eq 0) { $markdown.Add('- Keine strategische Abweichung erkannt.') }
    foreach ($finding in $project.findings) { $markdown.Add("- **$($severityText[[string]$finding.severity]) / ``$($finding.code)``:** $($finding.message) Nachweis: ``$($finding.evidence)`` Naechstes Ziel: $($finding.nextGoal)") }
}
$markdown.Add('')
$markdown.Add('## Spectra-Bindungsziel')
$markdown.Add('')
$markdown.Add("- Zielstatus: **$($spectraRelationshipResult.status)**")
$markdown.Add("- Nachweisabdeckung: **$($spectraRelationshipResult.evidenceCoverage) %**")
$spectraSourceCommitText = if ($spectraRelationshipResult.sourceCommit -match '^[0-9a-f]{40}$') { $spectraRelationshipResult.sourceCommit } else { 'unbekannt' }
$spectraConsumerCommitText = if ($spectraRelationshipResult.consumerCommit -match '^[0-9a-f]{40}$') { $spectraRelationshipResult.consumerCommit } else { 'unbekannt' }
$markdown.Add("- BCProjectOS-Evidence-Commit: ``$spectraSourceCommitText``")
$markdown.Add("- Blueprint-Commit: ``$spectraConsumerCommitText``")
foreach ($finding in $spectraFindings) { $markdown.Add("- **$($severityText[[string]$finding.severity]) / ``$($finding.code)``:** $($finding.message)") }
$markdown.Add('')
$markdown.Add('## Zusammenspiel')
$markdown.Add('')
$markdown.Add("- Zielstatus: **$($relationshipResult.status)**")
$providerCommitText = if ($relationshipResult.providerCommit -match '^[0-9a-f]{40}$') { $relationshipResult.providerCommit } else { 'unbekannt' }
$consumerCommitText = if ($relationshipResult.consumerCommit -match '^[0-9a-f]{40}$') { $relationshipResult.consumerCommit } else { 'unbekannt' }
$markdown.Add("- Nachweisabdeckung: **$($relationshipResult.evidenceCoverage) %**")
$markdown.Add("- Blueprint-Commit: ``$providerCommitText``")
$markdown.Add("- Twin-Commit: ``$consumerCommitText``")
foreach ($finding in $relationshipFindings) { $markdown.Add("- **$($severityText[[string]$finding.severity]) / ``$($finding.code)``:** $($finding.message)") }
$markdown.Add('')
$markdown.Add('> Die Zielpruefung liest ausschliesslich kleine regulaere Textblobs aus den festgehaltenen Commits und keine realen `.env*` oder Laufzeitnachweise.')

$jsonText = $report | ConvertTo-Json -Depth 14
$markdownText = $markdown -join "`r`n"
$null = Write-UniversaarlNewUtf8File -TrustedRoot $ReportRoot -Path $runJsonPath -Text $jsonText
$null = Write-UniversaarlNewUtf8File -TrustedRoot $ReportRoot -Path $runMarkdownPath -Text $markdownText
$null = Write-UniversaarlAtomicUtf8File -TrustedRoot $ReportRoot -Path (Join-Path $ReportRoot 'goals-latest.json') -Text $jsonText
$null = Write-UniversaarlAtomicUtf8File -TrustedRoot $ReportRoot -Path (Join-Path $ReportRoot 'goals-latest.md') -Text $markdownText
Write-Host "Universaarl Zielpruefung: $overall"
Write-Host "Laufbericht: $runMarkdownPath"
if ($overall -eq 'ROT') { exit 1 }
exit 0
