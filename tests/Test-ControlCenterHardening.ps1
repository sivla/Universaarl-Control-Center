[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ControlRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
. (Join-Path $ControlRoot 'scripts\Universaarl-Control.Common.ps1')
$TestPowerShell = (Get-Process -Id $PID).Path
$TempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
$TestRoot = Join-Path $TempBase "universaarl-control-tests-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null
$ControlWorkParent = Join-Path $ControlRoot '.work'
New-Item -ItemType Directory -Path $ControlWorkParent -Force | Out-Null
$ControlWorkRoot = Join-Path $ControlWorkParent "universaarl-control-tests-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $ControlWorkRoot -Force | Out-Null
$script:Passed = 0
$script:Skipped = 0

function Assert-True {
    param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw "TEST FEHLGESCHLAGEN: $Message" }
    $script:Passed++
}

function Assert-Throws {
    param([Parameter(Mandatory)][scriptblock]$Action, [Parameter(Mandatory)][string]$Message)
    $thrown = $false
    try { & $Action | Out-Null } catch { $thrown = $true }
    Assert-True -Condition $thrown -Message $Message
}

function Write-FixtureText {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Relative, [AllowEmptyString()][string]$Content)
    $path = Join-Path $Root $Relative
    $parent = Split-Path -Parent $path
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [IO.File]::WriteAllText($path, $Content, [Text.UTF8Encoding]::new($false))
}

function Invoke-FixtureGit {
    param([Parameter(Mandatory)][string]$Repository, [Parameter(Mandatory)][string[]]$Arguments)
    $output = @(& git -C $Repository @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Fixture-Git fehlgeschlagen: $((($output | ForEach-Object { [string]$_ }) -join ' ').Trim())" }
    (($output | ForEach-Object { [string]$_ }) -join "`n").Trim()
}

function New-FixtureRepository {
    param([Parameter(Mandatory)][string]$Name, [hashtable]$Files = @{})
    $repo = Join-Path $TestRoot $Name
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    $null = & git -C $repo init --quiet -b main
    if ($LASTEXITCODE -ne 0) { throw 'Fixture-Repository konnte nicht initialisiert werden.' }
    $null = Invoke-FixtureGit -Repository $repo -Arguments @('config', 'user.name', 'Universaarl Test')
    $null = Invoke-FixtureGit -Repository $repo -Arguments @('config', 'user.email', 'test@localhost')
    $null = Invoke-FixtureGit -Repository $repo -Arguments @('config', 'core.autocrlf', 'false')
    foreach ($entry in $Files.GetEnumerator()) { Write-FixtureText -Root $repo -Relative ([string]$entry.Key) -Content ([string]$entry.Value) }
    $null = Invoke-FixtureGit -Repository $repo -Arguments @('add', '--all')
    $null = Invoke-FixtureGit -Repository $repo -Arguments @('commit', '--quiet', '-m', 'Fixture')
    $sha = Invoke-FixtureGit -Repository $repo -Arguments @('rev-parse', 'HEAD')
    [pscustomobject]@{ path = $repo; sha = $sha }
}

function Commit-FixtureChange {
    param([Parameter(Mandatory)]$Fixture, [Parameter(Mandatory)][string]$Path, [AllowEmptyString()][string]$Content)
    Write-FixtureText -Root $Fixture.path -Relative $Path -Content $Content
    $null = Invoke-FixtureGit -Repository $Fixture.path -Arguments @('add', '--all')
    $null = Invoke-FixtureGit -Repository $Fixture.path -Arguments @('commit', '--quiet', '-m', 'Fixture-Aenderung')
    $Fixture.sha = Invoke-FixtureGit -Repository $Fixture.path -Arguments @('rev-parse', 'HEAD')
}

try {
    $canonicalMediaPath = 'artifacts/walkthrough/generated/UABC-WT-ENV-001/walkthrough.webm'
    $blueprintMediaAllowlist = @([pscustomobject]@{ path = $canonicalMediaPath; maxBytes = 1048576; mode = '100644' })
    $snapshotFixture = New-FixtureRepository -Name 'snapshot-source' -Files @{
        '.gitignore' = "ignored.marker`n"
        '.env.example' = "TOKEN=<TOKEN>`n"
        $canonicalMediaPath = 'kleines kanonisches Produktmedienfixture'
        'README.md' = "# Fixture`n"
        'REVIEW.md' = ''
        'tracked.txt' = 'versioniert'
    }
    $snapshotParent = $snapshotFixture.sha
    Commit-FixtureChange -Fixture $snapshotFixture -Path 'tracked.txt' -Content 'versioniert-zwei'
    Write-FixtureText -Root $snapshotFixture.path -Relative 'ignored.marker' -Content 'darf nicht kopiert werden'
    Write-FixtureText -Root $snapshotFixture.path -Relative 'untracked.marker' -Content 'darf nicht kopiert werden'
    $snapshotSandbox = Join-Path $TestRoot 'snapshot-sandbox'
    New-Item -ItemType Directory -Path $snapshotSandbox -Force | Out-Null
    $snapshot = Join-Path $snapshotSandbox 'kopie'
    Assert-Throws -Action { Assert-UniversaarlCommitRuntimeSafe -Repository $snapshotFixture.path -Commit $snapshotFixture.sha } -Message 'Kanonischer Blueprint-WebM wurde ohne projektbezogene Positivliste akzeptiert.'
    Assert-UniversaarlCommitRuntimeSafe -Repository $snapshotFixture.path -Commit $snapshotFixture.sha -AllowedVersionedMedia $blueprintMediaAllowlist
    New-UniversaarlCommitSnapshot -SourceRepository $snapshotFixture.path -Commit $snapshotFixture.sha -Destination $snapshot -SandboxRoot $snapshotSandbox -AllowedVersionedMedia $blueprintMediaAllowlist | Out-Null
    Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $snapshot 'ignored.marker'))) -Message 'Ignorierte Datei gelangte in die Commit-Kopie.'
    Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $snapshot 'untracked.marker'))) -Message 'Unversionierte Datei gelangte in die Commit-Kopie.'
    Assert-True -Condition ((Get-Content -Raw -LiteralPath (Join-Path $snapshot '.env.example')).Trim() -eq 'TOKEN=<TOKEN>') -Message 'Die gepruefte Root-Umgebungsvorlage fehlt in der Dokumentationskopie oder wurde veraendert.'
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $snapshot $canonicalMediaPath) -PathType Leaf) -Message 'Exakt positivgelisteter regulaerer Blueprint-Produktblob fehlte in der Commit-Kopie.'
    Assert-True -Condition ((Invoke-FixtureGit -Repository $snapshot -Arguments @('rev-parse', 'HEAD')) -eq $snapshotFixture.sha) -Message 'Commit-Kopie besitzt nicht die exakte SHA.'
    Assert-True -Condition ([string]::IsNullOrWhiteSpace((Invoke-FixtureGit -Repository $snapshot -Arguments @('remote')))) -Message 'Commit-Kopie besitzt ein Remote.'
    Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $snapshot '.git\FETCH_HEAD'))) -Message 'Commit-Kopie verraet die Quelladresse ueber FETCH_HEAD.'
    $snapshotHeadFile = [IO.File]::ReadAllText((Join-Path $snapshot '.git\HEAD'), [Text.Encoding]::ASCII).Trim()
    Assert-True -Condition ($snapshotHeadFile -eq $snapshotFixture.sha) -Message 'Commit-Kopie besitzt keinen direkt an die exakte SHA gebundenen abgeloesten HEAD.'
    $historySnapshot = Join-Path $snapshotSandbox 'historien-kopie'
    New-UniversaarlCommitSnapshot -SourceRepository $snapshotFixture.path -Commit $snapshotFixture.sha -Destination $historySnapshot -SandboxRoot $snapshotSandbox -IncludeHistory -AllowedVersionedMedia $blueprintMediaAllowlist | Out-Null
    $null = Invoke-FixtureGit -Repository $historySnapshot -Arguments @('cat-file', '-e', "$snapshotParent^{commit}")
    Assert-True -Condition ([string]::IsNullOrWhiteSpace((Invoke-FixtureGit -Repository $historySnapshot -Arguments @('remote')))) -Message 'Historien-Kopie besitzt ein Remote.'
    Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $historySnapshot '.git\FETCH_HEAD'))) -Message 'Historien-Kopie verraet die Quelladresse ueber FETCH_HEAD.'
    $branchSnapshot = Join-Path $snapshotSandbox 'zweig-kopie'
    New-UniversaarlCommitSnapshot -SourceRepository $snapshotFixture.path -Commit $snapshotFixture.sha -Destination $branchSnapshot -SandboxRoot $snapshotSandbox -ExpectedBranch 'codex/commit-pruefung' -AllowedVersionedMedia $blueprintMediaAllowlist | Out-Null
    Assert-True -Condition ((Invoke-FixtureGit -Repository $branchSnapshot -Arguments @('rev-parse', 'HEAD')) -eq $snapshotFixture.sha) -Message 'Zweiggebundene Commit-Kopie besitzt nicht die exakte SHA.'
    Assert-True -Condition ((Invoke-FixtureGit -Repository $branchSnapshot -Arguments @('branch', '--show-current')) -eq 'codex/commit-pruefung') -Message 'Zweiggebundene Commit-Kopie besitzt nicht den erwarteten lokalen Pruefzweig.'
    Assert-True -Condition ([string]::IsNullOrWhiteSpace((Invoke-FixtureGit -Repository $branchSnapshot -Arguments @('remote')))) -Message 'Zweiggebundene Commit-Kopie besitzt ein Remote.'
    Assert-Throws -Action { New-UniversaarlCommitSnapshot -SourceRepository $snapshotFixture.path -Commit $snapshotFixture.sha -Destination (Join-Path $snapshotSandbox 'ungueltiger-zweig') -SandboxRoot $snapshotSandbox -ExpectedBranch '../ungueltig' -AllowedVersionedMedia $blueprintMediaAllowlist } -Message 'Ungueltiger lokaler Pruefzweig wurde akzeptiert.'
    $snapshotLock = Open-UniversaarlLockedDirectoryChain -Directory $snapshot
    try {
        $lockedRead = Invoke-UniversaarlIsolatedGit -GitHome (Join-Path $snapshotSandbox 'git-home') -Repository $snapshot -UseExplicitRepositoryPaths -Arguments @('rev-parse', 'HEAD')
        Assert-True -Condition ($lockedRead.exitCode -eq 0 -and $lockedRead.output -eq $snapshotFixture.sha) -Message 'Explizite Git-Pfade konnten die umbenennungsgesperrte Commit-Kopie nicht lesen.'
        Assert-UniversaarlCleanPushRepositoryConfiguration -Repository $snapshot -GitHome (Join-Path $snapshotSandbox 'git-home') -ExpectedHooksPath (Join-Path $snapshotSandbox 'leere-hooks') -TrustedSandboxRoot $snapshotSandbox
    }
    finally { Close-UniversaarlDirectoryLock -Lock $snapshotLock }
    Assert-Throws -Action { Assert-UniversaarlCommitRuntimeSafe -Repository $snapshotFixture.path -Commit $snapshotFixture.sha -AllowedVersionedMedia $blueprintMediaAllowlist -MaximumBytes 5 } -Message 'Gesamtgroessengrenze des Commit-Snapshots wurde nicht erzwungen.'

    Assert-True -Condition (Test-UniversaarlBoundReportExitCode -ExitCode 0) -Message 'Erfolgreicher Berichtsrueckgabecode wurde abgelehnt.'
    Assert-True -Condition (Test-UniversaarlBoundReportExitCode -ExitCode 1) -Message 'Vollstaendig erzeugter global roter Bericht wurde vor der projektspezifischen Auswertung abgelehnt.'
    Assert-True -Condition (-not (Test-UniversaarlBoundReportExitCode -ExitCode 2)) -Message 'Unerwarteter Berichtsrueckgabecode wurde akzeptiert.'
    $scopedProject = [pscustomobject]@{ status = 'GELB'; validation = 'passed'; germanValidation = 'passed'; targetUnchanged = $true }
    $scopedTechnicalRelationships = @(
        [pscustomobject]@{ id = 'blueprint-binds-spectra'; status = 'passed'; fullValidationPassed = $true },
        [pscustomobject]@{ id = 'twin-reads-blueprint'; status = 'passed'; fullValidationPassed = $true }
    )
    $scopedProjectGoal = [pscustomobject]@{ status = 'GRUEN' }
    $scopedGoalRelationships = @(
        [pscustomobject]@{ id = 'blueprint-binds-spectra'; status = 'GELB'; fullValidationPassed = $true },
        [pscustomobject]@{ id = 'twin-reads-blueprint'; status = 'GELB'; fullValidationPassed = $true }
    )
    $oldFullValidatorAvailability = $script:UniversaarlFullContractValidatorAvailable
    try {
        $script:UniversaarlFullContractValidatorAvailable = $false
        Assert-True -Condition (@(Get-UniversaarlScopedPublishGateBlockers -ProjectResult $scopedProject -TechnicalRelationships $scopedTechnicalRelationships -ProjectGoalResult $scopedProjectGoal -GoalRelationships $scopedGoalRelationships).Count -gt 0) -Message 'Explizit deaktivierter Vollvalidator blockierte die Veroeffentlichung nicht.'
        $script:UniversaarlFullContractValidatorAvailable = $true
        Assert-True -Condition (@(Get-UniversaarlScopedPublishGateBlockers -ProjectResult $scopedProject -TechnicalRelationships $scopedTechnicalRelationships -ProjectGoalResult $scopedProjectGoal -GoalRelationships $scopedGoalRelationships).Count -eq 0) -Message 'Vollstaendig validierte Beziehungen mit gelber dokumentierter Folgearbeit wurden abgelehnt.'
        $scopedTechnicalRelationships[1].status = 'warning'
        Assert-True -Condition (@(Get-UniversaarlScopedPublishGateBlockers -ProjectResult $scopedProject -TechnicalRelationships $scopedTechnicalRelationships -ProjectGoalResult $scopedProjectGoal -GoalRelationships $scopedGoalRelationships).Count -gt 0) -Message 'Eine technische Vertragswarnung wurde als publishbar akzeptiert.'
        $scopedTechnicalRelationships[1].status = 'passed'
        $scopedProject.status = 'ROT'
        Assert-True -Condition (@(Get-UniversaarlScopedPublishGateBlockers -ProjectResult $scopedProject -TechnicalRelationships $scopedTechnicalRelationships -ProjectGoalResult $scopedProjectGoal -GoalRelationships $scopedGoalRelationships).Count -gt 0) -Message 'Roter Status des ausgewaehlten Projekts wurde akzeptiert.'
        $scopedProject.status = 'GRUEN'
        $scopedTechnicalRelationships[0].status = 'failed'
        Assert-True -Condition (@(Get-UniversaarlScopedPublishGateBlockers -ProjectResult $scopedProject -TechnicalRelationships $scopedTechnicalRelationships -ProjectGoalResult $scopedProjectGoal -GoalRelationships $scopedGoalRelationships).Count -gt 0) -Message 'Fehlgeschlagener technischer Spectra-Nachweis wurde akzeptiert.'
        $scopedTechnicalRelationships[0].status = 'passed'
        Assert-True -Condition (@(Get-UniversaarlScopedPublishGateBlockers -ProjectResult $scopedProject -TechnicalRelationships @($scopedTechnicalRelationships[0]) -ProjectGoalResult $scopedProjectGoal -GoalRelationships $scopedGoalRelationships).Count -gt 0) -Message 'Fehlende technische Snapshot-Beziehung wurde akzeptiert.'
        $scopedTechnicalRelationships[0].fullValidationPassed = $false
        Assert-True -Condition (@(Get-UniversaarlScopedPublishGateBlockers -ProjectResult $scopedProject -TechnicalRelationships $scopedTechnicalRelationships -ProjectGoalResult $scopedProjectGoal -GoalRelationships $scopedGoalRelationships).Count -gt 0) -Message 'Fehlender typstrenger Vollvalidatornachweis wurde akzeptiert.'
        $scopedTechnicalRelationships[0].fullValidationPassed = $true
    }
    finally { $script:UniversaarlFullContractValidatorAvailable = $oldFullValidatorAvailability }

    Assert-True -Condition (Test-UniversaarlProhibitedRuntimePath -Path $canonicalMediaPath) -Message 'Produktmedien-Endung wurde ohne Positivliste global freigegeben.'
    Assert-True -Condition (Test-UniversaarlProhibitedRuntimePath -Path 'test-results/videos/run.webm' -AllowVersionedProductMedia) -Message 'Browser-/Testvideo konnte die Laufzeitpfadsperre mit einer Medienfreigabe umgehen.'
    Assert-True -Condition (Test-UniversaarlProhibitedRuntimePath -Path 'beliebig/video.webm') -Message 'Generischer WebM-Pfad wurde pauschal freigegeben.'
    $oversizeMediaFixture = New-FixtureRepository -Name 'oversize-media-source' -Files @{ $canonicalMediaPath = ('M' * 1048577); 'REVIEW.md' = '' }
    Assert-Throws -Action { Assert-UniversaarlCommitRuntimeSafe -Repository $oversizeMediaFixture.path -Commit $oversizeMediaFixture.sha -AllowedVersionedMedia $blueprintMediaAllowlist } -Message 'Positivgelisteter Blueprint-WebM oberhalb von 1 MiB wurde akzeptiert.'
    $executableMediaFixture = New-FixtureRepository -Name 'executable-media-source' -Files @{ $canonicalMediaPath = 'ausfuehrbares Medienfixture'; 'REVIEW.md' = '' }
    $null = Invoke-FixtureGit -Repository $executableMediaFixture.path -Arguments @('update-index', '--chmod=+x', '--', $canonicalMediaPath)
    $null = Invoke-FixtureGit -Repository $executableMediaFixture.path -Arguments @('commit', '--quiet', '-m', 'Ausfuehrbarer Medienmodus')
    $executableMediaFixture.sha = Invoke-FixtureGit -Repository $executableMediaFixture.path -Arguments @('rev-parse', 'HEAD')
    Assert-Throws -Action { Assert-UniversaarlCommitRuntimeSafe -Repository $executableMediaFixture.path -Commit $executableMediaFixture.sha -AllowedVersionedMedia $blueprintMediaAllowlist } -Message 'Ausfuehrbarer Medienblob 100755 wurde trotz Positivliste fuer 100644 akzeptiert.'

    $runtimeFixture = New-FixtureRepository -Name 'runtime-source' -Files @{ '.envrc' = 'ECHTES_MATERIAL=fixture'; 'REVIEW.md' = '' }
    $runtimeSandbox = Join-Path $TestRoot 'runtime-sandbox'
    New-Item -ItemType Directory -Path $runtimeSandbox -Force | Out-Null
    Assert-Throws -Action { New-UniversaarlCommitSnapshot -SourceRepository $runtimeFixture.path -Commit $runtimeFixture.sha -Destination (Join-Path $runtimeSandbox 'kopie') -SandboxRoot $runtimeSandbox } -Message 'Versionierte reale `.env*` wurde nicht vor der Kopie blockiert.'
    foreach ($runtimePath in @('test-results/result.json', 'playwright-report/index.html', '.playwright-cli/state.json', '.azure/accessTokens.json', 'browser/logins.json', '.docker/config.json', '.config/gh/hosts.yml', '.kube/config', 'NuGet.Config')) {
        Assert-True -Condition (Test-UniversaarlProhibitedRuntimePath -Path $runtimePath) -Message "Verbotenes Laufzeit- oder Authentifizierungsartefakt wurde nicht erkannt: $runtimePath"
    }

    $rewriteFixture = New-FixtureRepository -Name 'rewrite-source' -Files @{ 'README.md' = '# Rewrite'; 'REVIEW.md' = '' }
    $null = Invoke-FixtureGit -Repository $rewriteFixture.path -Arguments @('remote', 'add', 'origin', 'alias:FiBu.git')
    $null = Invoke-FixtureGit -Repository $rewriteFixture.path -Arguments @('config', 'url.https://github.com/sivla/.insteadOf', 'alias:')
    $null = Invoke-FixtureGit -Repository $rewriteFixture.path -Arguments @('config', 'url.https://evil.invalid/.insteadOf', 'https://github.com/')
    Assert-Throws -Action { Assert-UniversaarlExpectedPushRemote -Repository $rewriteFixture.path -Remote 'origin' -ExpectedUrl 'https://github.com/sivla/FiBu.git' } -Message 'Zweistufige Git-URL-Umschreibung wurde von der rohen Positivlistenpruefung akzeptiert.'
    $rewriteSandbox = Join-Path $TestRoot 'rewrite-sandbox'
    New-Item -ItemType Directory -Path $rewriteSandbox -Force | Out-Null
    $rewriteCopy = Join-Path $rewriteSandbox 'kopie'
    New-UniversaarlCommitSnapshot -SourceRepository $rewriteFixture.path -Commit $rewriteFixture.sha -Destination $rewriteCopy -SandboxRoot $rewriteSandbox | Out-Null
    $rewriteCheck = Invoke-UniversaarlIsolatedGit -GitHome (Join-Path $rewriteSandbox 'git-home') -Repository $rewriteCopy -Arguments @('config', '--local', '--get-regexp', '^url\..*\.(insteadof|pushinsteadof)$')
    Assert-True -Condition ($rewriteCheck.exitCode -ne 0 -and [string]::IsNullOrWhiteSpace($rewriteCheck.output)) -Message 'Frische remotelose Git-Kopie erbte eine URL-Umschreibung.'

    $maliciousTemplate = Join-Path $TestRoot 'malicious-template'
    Write-FixtureText -Root $maliciousTemplate -Relative 'config' -Content "[url `"file:///umgeleitet/`"]`n  pushInsteadOf = https://github.com/`n[include]`n  path = C:/fremd/gitconfig`n[remote `"origin`"]`n  url = file:///fremd.git`n[core]`n  hooksPath = C:/fremd/hooks`n"
    Write-FixtureText -Root $maliciousTemplate -Relative 'hooks/pre-push' -Content '#!/bin/sh'
    $oldTemplateDirectory = [Environment]::GetEnvironmentVariable('GIT_TEMPLATE_DIR')
    try {
        [Environment]::SetEnvironmentVariable('GIT_TEMPLATE_DIR', $maliciousTemplate)
        $templateCopy = Join-Path $rewriteSandbox 'template-copy'
        $templateInit = Invoke-UniversaarlIsolatedGit -GitHome (Join-Path $rewriteSandbox 'template-git-home') -Arguments @('init', '--quiet', $templateCopy)
        if ($templateInit.exitCode -ne 0) { throw 'Template-Fixture konnte nicht initialisiert werden.' }
        $templateNames = Invoke-UniversaarlIsolatedGit -GitHome (Join-Path $rewriteSandbox 'template-git-home') -Repository $templateCopy -Arguments @('config', '--local', '--name-only', '--list')
        $templateHooks = Join-Path $templateCopy '.git\hooks'
        $templateWasInjected = $templateNames.output -match '(?im)^(?:url\.|include\.|remote\.|core\.hookspath)' -or ((Test-Path -LiteralPath $templateHooks) -and @(Get-ChildItem -LiteralPath $templateHooks -Force).Count -gt 0)
        Assert-True -Condition (-not $templateWasInjected) -Message 'Geerbtes GIT_TEMPLATE_DIR schleuste Konfiguration oder Hooks in ein isoliertes Git-Repository.'
    }
    finally { [Environment]::SetEnvironmentVariable('GIT_TEMPLATE_DIR', $oldTemplateDirectory) }
    $oldConfigCount = [Environment]::GetEnvironmentVariable('GIT_CONFIG_COUNT')
    $oldConfigKey = [Environment]::GetEnvironmentVariable('GIT_CONFIG_KEY_0')
    $oldConfigValue = [Environment]::GetEnvironmentVariable('GIT_CONFIG_VALUE_0')
    try {
        [Environment]::SetEnvironmentVariable('GIT_CONFIG_COUNT', '1')
        [Environment]::SetEnvironmentVariable('GIT_CONFIG_KEY_0', 'url.https://evil.invalid/.insteadOf')
        [Environment]::SetEnvironmentVariable('GIT_CONFIG_VALUE_0', 'https://github.com/')
        $isolatedRemoteConfig = Invoke-UniversaarlIsolatedGit -GitHome (Join-Path $rewriteSandbox 'git-home') -Repository $rewriteCopy -Arguments @('config', 'remote.fixture.url', 'https://github.com/sivla/FiBu.git')
        $isolatedResolution = Invoke-UniversaarlIsolatedGit -GitHome (Join-Path $rewriteSandbox 'git-home') -Repository $rewriteCopy -Arguments @('remote', 'get-url', 'fixture')
        Assert-True -Condition ($isolatedRemoteConfig.exitCode -eq 0 -and $isolatedResolution.exitCode -eq 0 -and $isolatedResolution.output -ceq 'https://github.com/sivla/FiBu.git') -Message "Geerbte GIT_CONFIG-URL-Umschreibung erreichte die bereinigte Git-Kopie (Code $($isolatedResolution.exitCode), Ausgabe '$($isolatedResolution.output)')."
    }
    finally {
        [Environment]::SetEnvironmentVariable('GIT_CONFIG_COUNT', $oldConfigCount)
        [Environment]::SetEnvironmentVariable('GIT_CONFIG_KEY_0', $oldConfigKey)
        [Environment]::SetEnvironmentVariable('GIT_CONFIG_VALUE_0', $oldConfigValue)
    }
    $environmentProbeAlias = '!echo $GIT_INDEX_FILE $GIT_EXEC_PATH $GIT_SSL_NO_VERIFY $GIT_TRACE2_EVENT $SSL_CERT_FILE $SSL_CERT_DIR $CURL_CA_BUNDLE $GCM_INTERACTIVE $SSH_ASKPASS_REQUIRE $HTTPS_PROXY $gIt_UnIvErSaArL_CaSe'
    $environmentProbeConfig = Invoke-UniversaarlIsolatedGit -GitHome (Join-Path $rewriteSandbox 'git-home') -Repository $rewriteCopy -Arguments @('config', 'alias.universaarl-environment-probe', $environmentProbeAlias)
    if ($environmentProbeConfig.exitCode -ne 0) { throw 'Git-Umgebungsfixture konnte nicht konfiguriert werden.' }
    $environmentTrace = Join-Path $TestRoot 'verbotene-git-trace.json'
    $proxySentinel = 'http://universaarl-erhaltener-proxy.invalid:3128'
    $environmentFixtureValues = [ordered]@{
        GIT_INDEX_FILE = (Join-Path $TestRoot 'verbotener-index')
        GIT_EXEC_PATH = (Join-Path $TestRoot 'verbotener-exec-path')
        GIT_SSL_NO_VERIFY = 'universaarl-keine-tls-pruefung'
        GIT_TRACE2_EVENT = $environmentTrace
        SSL_CERT_FILE = (Join-Path $TestRoot 'verbotene-ca.pem')
        SSL_CERT_DIR = (Join-Path $TestRoot 'verbotene-ca-sammlung')
        CURL_CA_BUNDLE = (Join-Path $TestRoot 'verbotenes-ca-buendel.pem')
        GCM_INTERACTIVE = 'universaarl-verbotener-helper-wert'
        SSH_ASKPASS_REQUIRE = 'force'
        HTTPS_PROXY = $proxySentinel
        gIt_UnIvErSaArL_CaSe = 'universaarl-gemischte-schreibweise'
    }
    $oldEnvironmentFixtureValues = @{}
    foreach ($name in $environmentFixtureValues.Keys) {
        $oldEnvironmentFixtureValues[$name] = [Environment]::GetEnvironmentVariable([string]$name)
        [Environment]::SetEnvironmentVariable([string]$name, [string]$environmentFixtureValues[$name])
    }
    $getSanitizedEnvironmentSnapshot = {
        $entries = @(
            foreach ($entry in [Environment]::GetEnvironmentVariables().GetEnumerator()) {
                $name = [string]$entry.Key
                $selected = $name.StartsWith('GIT_', [StringComparison]::OrdinalIgnoreCase) -or $name.StartsWith('GCM_', [StringComparison]::OrdinalIgnoreCase)
                if (-not $selected) {
                    foreach ($fixedName in @('SSL_CERT_FILE', 'SSL_CERT_DIR', 'CURL_CA_BUNDLE', 'SSH_ASKPASS', 'SSH_ASKPASS_REQUIRE')) {
                        if ([string]::Equals($name, $fixedName, [StringComparison]::OrdinalIgnoreCase)) { $selected = $true; break }
                    }
                }
                if ($selected) { [pscustomobject]@{ name = $name; value = [string]$entry.Value } }
            }
        )
        (@($entries | Sort-Object -Property name | ForEach-Object {
            [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(([string]$_.name + "`0" + [string]$_.value)))
        }) -join ',')
    }
    $expectedSanitizedEnvironment = & $getSanitizedEnvironmentSnapshot
    try {
        $gitReadEnvironmentProbe = Invoke-UniversaarlGitRead -Repository $rewriteCopy -Arguments @('universaarl-environment-probe')
        Assert-True -Condition ($gitReadEnvironmentProbe.exitCode -eq 0) -Message "Lesender Git-Umgebungsfixture konnte nicht ausgefuehrt werden (Code $($gitReadEnvironmentProbe.exitCode), Ausgabe '$($gitReadEnvironmentProbe.output)')."
        foreach ($name in @('GIT_INDEX_FILE', 'GIT_EXEC_PATH', 'GIT_SSL_NO_VERIFY', 'GIT_TRACE2_EVENT', 'SSL_CERT_FILE', 'SSL_CERT_DIR', 'CURL_CA_BUNDLE', 'GCM_INTERACTIVE', 'SSH_ASKPASS_REQUIRE', 'gIt_UnIvErSaArL_CaSe')) {
            Assert-True -Condition ($gitReadEnvironmentProbe.output -notlike "*$($environmentFixtureValues[$name])*") -Message "Lesender Git-Aufruf erbte die verbotene Umgebungsvariable $name."
            Assert-True -Condition ([Environment]::GetEnvironmentVariable($name) -ceq [string]$environmentFixtureValues[$name]) -Message "Lesender Git-Aufruf stellte $name nicht exakt wieder her."
        }
        Assert-True -Condition ((& $getSanitizedEnvironmentSnapshot) -ceq $expectedSanitizedEnvironment) -Message 'Lesender Git-Aufruf stellte die vollstaendige bereinigte Umgebung nicht exakt wieder her.'
        Assert-True -Condition ($gitReadEnvironmentProbe.output -like "*$proxySentinel*") -Message 'Lesender Git-Aufruf entfernte den bewusst erhaltenen Standardproxy.'
        Assert-True -Condition (-not (Test-Path -LiteralPath $environmentTrace)) -Message 'Lesender Git-Aufruf schrieb ueber geerbtes GIT_TRACE2_EVENT.'

        $isolatedEnvironmentProbe = Invoke-UniversaarlIsolatedGit -GitHome (Join-Path $rewriteSandbox 'git-home') -Repository $rewriteCopy -Arguments @('universaarl-environment-probe')
        Assert-True -Condition ($isolatedEnvironmentProbe.exitCode -eq 0) -Message "Isolierter Git-Umgebungsfixture konnte nicht ausgefuehrt werden (Code $($isolatedEnvironmentProbe.exitCode), Ausgabe '$($isolatedEnvironmentProbe.output)')."
        foreach ($name in @('GIT_INDEX_FILE', 'GIT_EXEC_PATH', 'GIT_SSL_NO_VERIFY', 'GIT_TRACE2_EVENT', 'SSL_CERT_FILE', 'SSL_CERT_DIR', 'CURL_CA_BUNDLE', 'GCM_INTERACTIVE', 'SSH_ASKPASS_REQUIRE', 'gIt_UnIvErSaArL_CaSe')) {
            Assert-True -Condition ($isolatedEnvironmentProbe.output -notlike "*$($environmentFixtureValues[$name])*") -Message "Isolierter Git-Aufruf erbte die verbotene Umgebungsvariable $name."
            Assert-True -Condition ([Environment]::GetEnvironmentVariable($name) -ceq [string]$environmentFixtureValues[$name]) -Message "Isolierter Git-Aufruf stellte $name nicht exakt wieder her."
        }
        Assert-True -Condition ((& $getSanitizedEnvironmentSnapshot) -ceq $expectedSanitizedEnvironment) -Message 'Isolierter Git-Aufruf stellte die vollstaendige bereinigte Umgebung nicht exakt wieder her.'
        Assert-True -Condition ($isolatedEnvironmentProbe.output -like "*$proxySentinel*") -Message 'Isolierter Git-Aufruf entfernte den bewusst erhaltenen Standardproxy.'
        Assert-True -Condition (-not (Test-Path -LiteralPath $environmentTrace)) -Message 'Isolierter Git-Aufruf schrieb ueber geerbtes GIT_TRACE2_EVENT.'
    }
    finally {
        foreach ($name in $environmentFixtureValues.Keys) { [Environment]::SetEnvironmentVariable([string]$name, $oldEnvironmentFixtureValues[$name]) }
        $null = Invoke-UniversaarlIsolatedGit -GitHome (Join-Path $rewriteSandbox 'git-home') -Repository $rewriteCopy -Arguments @('config', '--unset-all', 'alias.universaarl-environment-probe')
    }
    $null = Invoke-UniversaarlIsolatedGit -GitHome (Join-Path $rewriteSandbox 'git-home') -Repository $rewriteCopy -Arguments @('config', '--unset-all', 'remote.fixture.url')

    $rewriteGitHome = Join-Path $rewriteSandbox 'git-home'
    $credentialFixture = Invoke-UniversaarlIsolatedGit -GitHome $rewriteGitHome -Repository $rewriteCopy -Arguments @('config', 'credential.helper', 'manager')
    if ($credentialFixture.exitCode -ne 0) { throw 'Credential-Positivlistenfixture konnte nicht konfiguriert werden.' }
    Assert-UniversaarlCleanPushRepositoryConfiguration -Repository $rewriteCopy -GitHome $rewriteGitHome -ExpectedHooksPath (Join-Path $rewriteSandbox 'leere-hooks') -TrustedSandboxRoot $rewriteSandbox -RequireCredentialManager

    $allowedBare = Join-Path $TestRoot 'allowed-remote.git'
    $redirectedBare = Join-Path $TestRoot 'redirected-remote.git'
    $null = & git init --quiet --bare $allowedBare
    if ($LASTEXITCODE -ne 0) { throw 'Erlaubtes Bare-Fixture konnte nicht erstellt werden.' }
    $null = & git init --quiet --bare $redirectedBare
    if ($LASTEXITCODE -ne 0) { throw 'Umgeleitetes Bare-Fixture konnte nicht erstellt werden.' }
    $allowedUri = 'file:///' + $allowedBare.Replace('\', '/')
    $redirectedUri = 'file:///' + $redirectedBare.Replace('\', '/')
    $pushInsteadKey = "url.$redirectedUri.pushInsteadOf"
    $null = Invoke-FixtureGit -Repository $rewriteCopy -Arguments @('config', $pushInsteadKey, $allowedUri)
    Assert-Throws -Action { Assert-UniversaarlCleanPushRepositoryConfiguration -Repository $rewriteCopy -GitHome $rewriteGitHome -ExpectedHooksPath (Join-Path $rewriteSandbox 'leere-hooks') -TrustedSandboxRoot $rewriteSandbox -RequireCredentialManager } -Message '`pushInsteadOf` wurde von der vollstaendigen Push-Konfigurationspositivliste akzeptiert.'
    $null = Invoke-FixtureGit -Repository $rewriteCopy -Arguments @('config', '--unset-all', $pushInsteadKey)
    $null = Invoke-FixtureGit -Repository $rewriteFixture.path -Arguments @('config', $pushInsteadKey, $allowedUri)
    $oldPushPreference = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try { $redirectPush = @(& git -C $rewriteFixture.path -c protocol.file.allow=always push $allowedUri "$($rewriteFixture.sha)`:refs/heads/redirect-test" 2>&1); $redirectPushExitCode = $LASTEXITCODE }
    finally { $ErrorActionPreference = $oldPushPreference }
    if ($redirectPushExitCode -ne 0) { throw "Lokales URL-Umleitungsfixture konnte nicht pushen (Code $redirectPushExitCode): $($redirectPush -join ' ')" }
    $redirectedHead = Invoke-FixtureGit -Repository $redirectedBare -Arguments @('rev-parse', '--verify', 'refs/heads/redirect-test')
    $allowedCheck = Invoke-UniversaarlGitRead -Repository $allowedBare -Arguments @('rev-parse', '--verify', 'refs/heads/redirect-test')
    $allowedHasRef = $allowedCheck.exitCode -eq 0
    Assert-True -Condition ($redirectedHead -eq $rewriteFixture.sha -and -not $allowedHasRef) -Message 'Lokales Fixture bewies die tatsaechliche `pushInsteadOf`-Umleitung nicht.'
    $null = Invoke-FixtureGit -Repository $rewriteFixture.path -Arguments @('config', '--unset-all', $pushInsteadKey)

    $hookFixture = New-FixtureRepository -Name 'hook-source' -Files @{ 'README.md' = '# Hook-Fixture'; 'REVIEW.md' = '' }
    $targetHookPath = Join-Path $hookFixture.path '.git\hooks\pre-push'
    Write-FixtureText -Root $hookFixture.path -Relative '.git/hooks/pre-push' -Content "#!/bin/sh`nprintf ausgefuehrt > `"`$0.ran`"`nexit 1`n"
    $targetHookMarker = "$targetHookPath.ran"
    $hookRemote = Join-Path $TestRoot 'hook-remote.git'
    $null = & git init --quiet --bare $hookRemote
    if ($LASTEXITCODE -ne 0) { throw 'Hook-Bare-Fixture konnte nicht erstellt werden.' }
    $null = Invoke-FixtureGit -Repository $hookRemote -Arguments @('config', 'receive.shallowUpdate', 'true')
    $oldHookPreference = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try { $targetHookPush = @(& git -C $hookFixture.path -c protocol.file.allow=always push $hookRemote "$($hookFixture.sha)`:refs/heads/target-hook-proof" 2>&1); $targetHookExitCode = $LASTEXITCODE }
    finally { $ErrorActionPreference = $oldHookPreference }
    Assert-True -Condition ($targetHookExitCode -ne 0 -and (Test-Path -LiteralPath $targetHookMarker)) -Message "Boesartiger Ziel-pre-push-Hook war im Fixture nicht wirksam: $($targetHookPush -join ' ')"
    Remove-Item -LiteralPath $targetHookMarker -Force

    $hookSandbox = Join-Path $TestRoot 'hook-sandbox'
    New-Item -ItemType Directory -Path $hookSandbox -Force | Out-Null
    $hookCopy = Join-Path $hookSandbox 'push-copy'
    New-UniversaarlCommitSnapshot -SourceRepository $hookFixture.path -Commit $hookFixture.sha -Destination $hookCopy -SandboxRoot $hookSandbox | Out-Null
    $hookGitHome = Join-Path $hookSandbox 'git-home'
    $publisherHooks = Join-Path $hookSandbox 'publisher-hooks'
    $null = Initialize-UniversaarlSafeDirectory -TrustedRoot $hookSandbox -Directory $publisherHooks
    $publisherHooksLock = Open-UniversaarlLockedDirectoryChain -Directory $publisherHooks
    try {
        $publisherHookConfig = Invoke-UniversaarlIsolatedGit -GitHome $hookGitHome -Repository $hookCopy -Arguments @('config', 'core.hooksPath', $publisherHooks)
        if ($publisherHookConfig.exitCode -ne 0) { throw 'Kontrollierter Publisher-Hookpfad konnte im Fixture nicht konfiguriert werden.' }
        Assert-UniversaarlCleanPushRepositoryConfiguration -Repository $hookCopy -GitHome $hookGitHome -ExpectedHooksPath $publisherHooks -TrustedSandboxRoot $hookSandbox
        Assert-Throws -Action { Assert-UniversaarlCleanPushRepositoryConfiguration -Repository $hookCopy -GitHome $hookGitHome -ExpectedHooksPath (Split-Path -Parent $targetHookPath) -TrustedSandboxRoot $hookSandbox } -Message 'Zielprojekt-Hookpfad wurde ausserhalb der Publisher-Wegwerfkopie akzeptiert.'
        $copyHookPush = Invoke-UniversaarlIsolatedGit -GitHome $hookGitHome -Repository $hookCopy -Arguments @('-c', 'protocol.file.allow=always', 'push', '--porcelain', $hookRemote, "$($hookFixture.sha)`:refs/heads/publisher-hook-proof")
        Assert-True -Condition ($copyHookPush.exitCode -eq 0 -and -not (Test-Path -LiteralPath $targetHookMarker)) -Message "Boesartiger Ziel-pre-push-Hook lief aus der frischen Push-Kopie: $($copyHookPush.output)"
        $publisherHookHead = Invoke-FixtureGit -Repository $hookRemote -Arguments @('rev-parse', '--verify', 'refs/heads/publisher-hook-proof')
        Assert-True -Condition ($publisherHookHead -eq $hookFixture.sha) -Message 'Hook-isolierter Fixture-Push uebertrug nicht die exakte Commit-SHA.'
    }
    finally { Close-UniversaarlDirectoryLock -Lock $publisherHooksLock }

    $environmentFixture = New-FixtureRepository -Name 'environment-source' -Files @{ '.env.example' = "TOKEN=<TOKEN>`nPORT=<PORT>`n"; 'REVIEW.md' = '' }
    $safeEnvironment = Test-UniversaarlEnvironmentExample -Repository $environmentFixture.path -Commit $environmentFixture.sha
    Assert-True -Condition ($safeEnvironment.present -and $safeEnvironment.safe) -Message 'Sichere Umgebungsvorlage wurde abgelehnt.'
    Commit-FixtureChange -Fixture $environmentFixture -Path '.env.example' -Content "# CLIENT_SECRET: echter-wert`nTOKEN=<TOKEN>`n"
    $commentNamedSecret = Test-UniversaarlEnvironmentExample -Repository $environmentFixture.path -Commit $environmentFixture.sha
    Assert-True -Condition (-not $commentNamedSecret.safe) -Message 'Vertraulicher Kommentarwert mit Doppelpunkt wurde uebersehen.'
    Commit-FixtureChange -Fixture $environmentFixture -Path '.env.example' -Content "# Pfad: (/etc/secret)`nTOKEN=<TOKEN>`n"
    $commentPosixPath = Test-UniversaarlEnvironmentExample -Repository $environmentFixture.path -Commit $environmentFixture.sha
    Assert-True -Condition (-not $commentPosixPath.safe) -Message 'Geklammerter absoluter POSIX-Pfad im Kommentar wurde uebersehen.'
    Commit-FixtureChange -Fixture $environmentFixture -Path '.env.example' -Content "# Pfad: (C:\secret)`nTOKEN=<TOKEN>`n"
    $commentWindowsPath = Test-UniversaarlEnvironmentExample -Repository $environmentFixture.path -Commit $environmentFixture.sha
    Assert-True -Condition (-not $commentWindowsPath.safe) -Message 'Geklammerter absoluter Windows-Pfad im Kommentar wurde uebersehen.'
    Commit-FixtureChange -Fixture $environmentFixture -Path '.env.example' -Content "# Erwartet werden https://github.com/sivla/FiBu.git und der Branch codex/universaarl-projekt.`nSOURCE_REPO=`n"
    $commentHttpsUrl = Test-UniversaarlEnvironmentExample -Repository $environmentFixture.path -Commit $environmentFixture.sha
    Assert-True -Condition $commentHttpsUrl.safe -Message 'HTTPS-URL im Kommentar wurde faelschlich als absoluter Windows-Hostpfad bewertet.'
    Commit-FixtureChange -Fixture $environmentFixture -Path '.env.example' -Content "# ghp_abcdefghijklmnopqrstuvwxyz123456`nTOKEN=<TOKEN>`n"
    $commentSecret = Test-UniversaarlEnvironmentExample -Repository $environmentFixture.path -Commit $environmentFixture.sha
    Assert-True -Condition (-not $commentSecret.safe) -Message 'Geheimnisform in Kommentar wurde uebersehen.'
    Commit-FixtureChange -Fixture $environmentFixture -Path '.env.example' -Content "DATABASE_URL=postgres://user:pass@example.invalid/db`n"
    $databaseSecret = Test-UniversaarlEnvironmentExample -Repository $environmentFixture.path -Commit $environmentFixture.sha
    Assert-True -Condition (-not $databaseSecret.safe) -Message 'Datenbank-Zugangswert wurde uebersehen.'
    Commit-FixtureChange -Fixture $environmentFixture -Path '.env.example' -Content "ROOT_PATH=/etc/universaarl`n"
    $absolutePath = Test-UniversaarlEnvironmentExample -Repository $environmentFixture.path -Commit $environmentFixture.sha
    Assert-True -Condition (-not $absolutePath.safe) -Message 'Absoluter POSIX-Pfad wurde uebersehen.'
    Commit-FixtureChange -Fixture $environmentFixture -Path '.env.example' -Content ("A" * 70000)
    $largeEnvironment = Test-UniversaarlEnvironmentExample -Repository $environmentFixture.path -Commit $environmentFixture.sha
    Assert-True -Condition (-not $largeEnvironment.safe -and @($largeEnvironment.findings | Where-Object code -eq 'ENV-EXAMPLE-001').Count -eq 1) -Message 'Groessengrenze wurde nicht vor dem Einlesen wirksam.'
    $unsafeSnapshotRoot = Join-Path $TestRoot 'unsafe-environment-snapshot'
    New-Item -ItemType Directory -Path $unsafeSnapshotRoot -Force | Out-Null
    Assert-Throws -Action { New-UniversaarlCommitSnapshot -SourceRepository $environmentFixture.path -Commit $environmentFixture.sha -Destination (Join-Path $unsafeSnapshotRoot 'kopie') -SandboxRoot $unsafeSnapshotRoot } -Message 'Unsichere Umgebungsvorlage gelangte in die Commit-Kopie.'

    $reportPath = Join-Path $TestRoot 'alter-bericht.json'
    [IO.File]::WriteAllText($reportPath, '{"schemaVersion":2,"kind":"audit","runId":"alter-lauf","completed":true,"inputShas":{"blueprint":"0000000000000000000000000000000000000000"}}', [Text.UTF8Encoding]::new($false))
    Assert-Throws -Action { Read-UniversaarlBoundReport -Path $reportPath -RunId 'neuer-lauf' -Kind audit -TrustedRoot $TestRoot } -Message 'Alter Laufbericht wurde akzeptiert.'
    Assert-Throws -Action { Read-UniversaarlBoundReport -Path $reportPath -RunId 'alter-lauf' -Kind audit -TrustedRoot $TestRoot } -Message 'Laufbericht ohne beide exakt benannten Eingabe-SHAs wurde akzeptiert.'

    $reportSha = '0123456789abcdef0123456789abcdef01234567'
    $reportHash = 'a' * 64
    $reportFingerprint = [pscustomobject]@{ head = $reportSha; branch = 'main'; dirty = $false; statusHash = $reportHash; indexHash = $reportHash; fingerprint = $reportHash }
    $validReport = [pscustomobject]@{
        schemaVersion = 2; kind = 'audit'; runId = 'vertrag-lauf'; completed = $true
        overallStatus = 'ROT'
        inputShas = [pscustomobject]@{ blueprint = $reportSha; 'project-twin' = $reportSha }
        verificationInputs = [pscustomobject]@{ bcprojectos = [pscustomobject]@{ technicalProjectName = 'BCProjectOS'; productName = 'Spectra'; productId = 'spectra'; remoteUrl = 'https://github.com/sivla/BCProjectOS.git'; sourceCommit = $reportSha; fingerprintAfter = $reportFingerprint; targetUnchanged = $true; status = 'observed' } }
        projects = @(
            [pscustomobject]@{ id = 'blueprint'; status = 'ROT'; commit = $reportSha; validation = 'failed'; germanValidation = 'not-run'; targetUnchanged = $true; fingerprintAfter = $reportFingerprint },
            [pscustomobject]@{ id = 'project-twin'; status = 'ROT'; commit = $reportSha; validation = 'failed'; germanValidation = 'not-run'; targetUnchanged = $true; fingerprintAfter = $reportFingerprint }
        )
        relationships = @(
            [pscustomobject]@{ id = 'blueprint-binds-spectra'; contractType = 'versioned-product-release'; productName = 'Spectra'; productId = 'spectra'; technicalProjectName = 'BCProjectOS'; sourceCommit = $reportSha; consumerCommit = $reportSha; status = 'failed'; fullValidationPassed = $false },
            [pscustomobject]@{ id = 'twin-reads-blueprint'; contractType = 'portable-snapshot-release'; providerCommit = $reportSha; consumerCommit = $reportSha; status = 'failed'; fullValidationPassed = $false }
        )
    }
    [IO.File]::WriteAllText($reportPath, ($validReport | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
    $null = Read-UniversaarlBoundReport -Path $reportPath -RunId 'vertrag-lauf' -Kind audit -TrustedRoot $TestRoot

    foreach ($coercionCase in @(
        @{ message = 'Zeichenketten-Schemaversion wurde akzeptiert.'; mutate = { param($value) $value.schemaVersion = '2' } },
        @{ message = 'Zeichenketten-Completed-Markierung wurde akzeptiert.'; mutate = { param($value) $value.completed = 'true' } },
        @{ message = 'Array statt exakt typisierter Eingabe-SHA wurde akzeptiert.'; mutate = { param($value) $value.inputShas.blueprint = @($reportSha) } },
        @{ message = 'BCProjectOS targetUnchanged false wurde vom gebundenen Reader akzeptiert.'; mutate = { param($value) $value.verificationInputs.bcprojectos.targetUnchanged = $false } },
        @{ message = 'Array statt exakt typisierter Spectra-Bindungs-SHA wurde akzeptiert.'; mutate = { param($value) $value.relationships[0].sourceCommit = @($reportSha) } },
        @{ message = 'Technisch abweichender Projektname wurde als BCProjectOS-Bindung akzeptiert.'; mutate = { param($value) $value.relationships[0].technicalProjectName = 'Spectra' } },
        @{ message = 'Bestandenbehauptung ohne typstrengen Vollnachweis wurde akzeptiert.'; mutate = { param($value) $value.relationships[0].status = 'passed'; $value.relationships[0].fullValidationPassed = $false } }
    )) {
        $candidate = (($validReport | ConvertTo-Json -Depth 12) | ConvertFrom-Json)
        & $coercionCase.mutate $candidate
        [IO.File]::WriteAllText($reportPath, ($candidate | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
        Assert-Throws -Action { Read-UniversaarlBoundReport -Path $reportPath -RunId 'vertrag-lauf' -Kind audit -TrustedRoot $TestRoot } -Message $coercionCase.message
    }

    $missingRelationshipReport = (($validReport | ConvertTo-Json -Depth 12) | ConvertFrom-Json)
    $missingRelationshipReport.relationships = @($missingRelationshipReport.relationships[0])
    [IO.File]::WriteAllText($reportPath, ($missingRelationshipReport | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
    Assert-Throws -Action { Read-UniversaarlBoundReport -Path $reportPath -RunId 'vertrag-lauf' -Kind audit -TrustedRoot $TestRoot } -Message 'Laufbericht ohne Snapshot-Lesebeziehung wurde akzeptiert.'
    $duplicateRelationshipReport = (($validReport | ConvertTo-Json -Depth 12) | ConvertFrom-Json)
    $duplicateRelationshipReport.relationships = @($duplicateRelationshipReport.relationships[0], $duplicateRelationshipReport.relationships[0])
    [IO.File]::WriteAllText($reportPath, ($duplicateRelationshipReport | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
    Assert-Throws -Action { Read-UniversaarlBoundReport -Path $reportPath -RunId 'vertrag-lauf' -Kind audit -TrustedRoot $TestRoot } -Message 'Laufbericht mit doppelter Spectra-Beziehung wurde akzeptiert.'

    $pushSha = '0123456789abcdef0123456789abcdef01234567'
    Assert-True -Condition ((Get-UniversaarlExactPushRefSpec -Commit $pushSha -Branch 'codex/test') -eq "$pushSha`:refs/heads/codex/test") -Message 'Push-Refspec ist nicht an die volle SHA gebunden.'
    Assert-Throws -Action { Get-UniversaarlExactPushRefSpec -Commit '0123456' -Branch 'codex/test' } -Message 'Abgekuerzte Push-SHA wurde akzeptiert.'
    $languagePayload = "{`"schemaVersion`":1,`"status`":`"passed`",`"language`":`"de`",`"projectId`":`"project-twin`",`"commit`":`"$pushSha`",`"userVisibleOwnContentGerman`":true}"
    Assert-True -Condition (Test-UniversaarlGermanEvidencePayload -Json $languagePayload -ProjectId 'project-twin' -Commit $pushSha) -Message 'Gueltiger commitgebundener Deutsch-Nachweis wurde abgelehnt.'
    Assert-True -Condition (-not (Test-UniversaarlGermanEvidencePayload -Json $languagePayload -ProjectId 'blueprint' -Commit $pushSha)) -Message 'Deutsch-Nachweis wurde fuer ein anderes Projekt akzeptiert.'
    $coercedLanguagePayload = "{`"schemaVersion`":`"1`",`"status`":`"passed`",`"language`":`"de`",`"projectId`":`"project-twin`",`"commit`":`"$pushSha`",`"userVisibleOwnContentGerman`":1}"
    Assert-True -Condition (-not (Test-UniversaarlGermanEvidencePayload -Json $coercedLanguagePayload -ProjectId 'project-twin' -Commit $pushSha)) -Message 'Typumgewandelter Deutsch-Nachweis wurde akzeptiert.'
    $extraLanguagePayload = $languagePayload.TrimEnd('}') + ',"extra":true}'
    Assert-True -Condition (-not (Test-UniversaarlGermanEvidencePayload -Json $extraLanguagePayload -ProjectId 'project-twin' -Commit $pushSha)) -Message 'Deutsch-Nachweis mit unbekanntem Zusatzfeld wurde akzeptiert.'
    $wrongCaseLanguagePayload = $languagePayload.Replace('"status"', '"Status"')
    Assert-True -Condition (-not (Test-UniversaarlGermanEvidencePayload -Json $wrongCaseLanguagePayload -ProjectId 'project-twin' -Commit $pushSha)) -Message 'Deutsch-Nachweis mit nicht exakt geschriebenem Property-Namen wurde akzeptiert.'

    Assert-True -Condition ((Get-UniversaarlApprovalTaskState -Text "- [x] Human approval and archive`n") -eq 'approved') -Message 'Exakte affirmative Legacy-Freigabeaufgabe wurde abgelehnt.'
    Assert-True -Condition ((Get-UniversaarlApprovalTaskState -Text "- [X] Menschliche Freigabe und Archivierung`n") -eq 'approved') -Message 'Exakte affirmative deutsche Freigabeaufgabe wurde abgelehnt.'
    Assert-True -Condition ((Get-UniversaarlApprovalTaskState -Text "- [ ] Human approval and archive`n") -eq 'open') -Message 'Exakte offene Freigabeaufgabe wurde nicht als offen erkannt.'
    foreach ($negativeApproval in @(
        "- [x] Human approval and archive wurde nicht erteilt`n",
        "- [x] Do not treat this as Human approval and archive`n",
        "- [x] Menschliche Freigabe nicht erteilt; Ablehnung dokumentiert`n",
        "- [x] Human approval and archive`n- [x] Menschliche Freigabe und Archivierung`n"
    )) { Assert-True -Condition ((Get-UniversaarlApprovalTaskState -Text $negativeApproval) -eq 'invalid') -Message 'Negierte, erweiterte oder mehrdeutige Freigabezeile wurde akzeptiert.' }

    $before = Get-UniversaarlRepositoryFingerprint -Repository $snapshotFixture.path
    Commit-FixtureChange -Fixture $snapshotFixture -Path 'tracked.txt' -Content 'neuer Commit'
    $after = Get-UniversaarlRepositoryFingerprint -Repository $snapshotFixture.path
    Assert-True -Condition (-not (Test-UniversaarlFingerprintEqual -Expected $before -Actual $after)) -Message 'SHA-Race wurde vom Fingerprint nicht erkannt.'

    $linkRoot = Join-Path $TestRoot 'reparse'
    New-Item -ItemType Directory -Path $linkRoot -Force | Out-Null
    $outside = Join-Path $TestRoot 'ausserhalb.txt'
    Write-FixtureText -Root $TestRoot -Relative 'ausserhalb.txt' -Content 'nicht lesen'
    $link = Join-Path $linkRoot 'REVIEW.md'
    $linkCreated = $false
    try { New-Item -ItemType SymbolicLink -Path $link -Target $outside -ErrorAction Stop | Out-Null; $linkCreated = $true }
    catch {
        $script:Skipped++
        Write-Host 'HINWEIS: Reparse-Test lokal nicht moeglich; Sicherheitspruefung wurde uebersprungen.'
    }
    if ($linkCreated) { Assert-Throws -Action { Read-UniversaarlWorkingText -Repository $linkRoot -Path 'REVIEW.md' } -Message 'Reparse-Punkt wurde als REVIEW-Text gelesen.' }

    $junctionTrusted = Join-Path $TestRoot 'junction-trusted'
    $junctionOutside = Join-Path $TestRoot 'junction-outside'
    New-Item -ItemType Directory -Path $junctionTrusted, $junctionOutside -Force | Out-Null
    $junction = Join-Path $junctionTrusted 'reports'
    $junctionCreated = $false
    try { New-Item -ItemType Junction -Path $junction -Target $junctionOutside -ErrorAction Stop | Out-Null; $junctionCreated = $true }
    catch {
        $script:Skipped++
        Write-Host 'HINWEIS: Junction-Test lokal nicht moeglich; Ausgabepfadpruefung wurde uebersprungen.'
    }
    if ($junctionCreated) {
        Assert-Throws -Action { Initialize-UniversaarlSafeDirectory -TrustedRoot $junctionTrusted -Directory $junction } -Message 'Junction wurde als sicheres Ausgabeverzeichnis akzeptiert.'
        [IO.Directory]::Delete($junction, $false)
    }

    $ancestorOutside = Join-Path $TestRoot 'ancestor-outside'
    $ancestorTrusted = Join-Path $ancestorOutside 'trusted'
    New-Item -ItemType Directory -Path $ancestorTrusted -Force | Out-Null
    $ancestorLink = Join-Path $TestRoot 'ancestor-link'
    $ancestorCreated = $false
    try { New-Item -ItemType Junction -Path $ancestorLink -Target $ancestorOutside -ErrorAction Stop | Out-Null; $ancestorCreated = $true }
    catch {
        $script:Skipped++
        Write-Host 'HINWEIS: Ancestor-Junction-Test lokal nicht moeglich; Volumepfadpruefung wurde uebersprungen.'
    }
    if ($ancestorCreated) {
        Assert-Throws -Action { Initialize-UniversaarlSafeDirectory -TrustedRoot (Join-Path $ancestorLink 'trusted') -Directory (Join-Path $ancestorLink 'trusted\reports') } -Message 'Junction in einer Vorfahrenkomponente oberhalb der vertrauenswuerdigen Wurzel wurde akzeptiert.'
        [IO.Directory]::Delete($ancestorLink, $false)
    }

    $lockedParent = Join-Path $TestRoot 'locked-parent'
    New-Item -ItemType Directory -Path $lockedParent -Force | Out-Null
    $directoryLock = Open-UniversaarlLockedDirectoryChain -Directory $lockedParent
    try { Assert-Throws -Action { Move-Item -LiteralPath $lockedParent -Destination (Join-Path $TestRoot 'locked-parent-moved') -ErrorAction Stop } -Message 'Gesperrte Parent-Kette konnte waehrend des Create-/Rename-Fensters ausgetauscht werden.' }
    finally { Close-UniversaarlDirectoryLock -Lock $directoryLock }

    $safeOutputRoot = Join-Path $TestRoot 'safe-output'
    New-Item -ItemType Directory -Path $safeOutputRoot -Force | Out-Null
    $safeOutputPath = Join-Path $safeOutputRoot 'bericht.txt'
    $null = Write-UniversaarlNewUtf8File -TrustedRoot $safeOutputRoot -Path $safeOutputPath -Text 'erste Fassung' -MaximumBytes 1024
    $null = Write-UniversaarlAtomicUtf8File -TrustedRoot $safeOutputRoot -Path $safeOutputPath -Text 'zweite Fassung' -MaximumBytes 1024
    Assert-True -Condition ((Read-UniversaarlRegularUtf8File -Root $safeOutputRoot -Path $safeOutputPath -MaximumBytes 1024) -ceq 'zweite Fassung') -Message 'Sicheres atomar ersetztes Berichtsziel wurde nicht verifiziert.'

    $renameTemp = Join-Path $safeOutputRoot '.universaarl-adversarial.tmp'
    $renameTarget = Join-Path $safeOutputRoot 'adversarial.txt'
    $renameParentLock = Open-UniversaarlLockedDirectoryChain -Directory $safeOutputRoot
    $renameStream = $null
    try {
        $renameHandle = [Universaarl.NativeFile]::CreateFile($renameTemp, [uint32]3221291008, 0, [IntPtr]::Zero, 1, 0x00000080, [IntPtr]::Zero)
        if ($renameHandle.IsInvalid) { throw 'Adversarialer Temp-Handle konnte nicht erstellt werden.' }
        $renameStream = [IO.FileStream]::new($renameHandle, [IO.FileAccess]::ReadWrite)
        $renameBytes = [Text.UTF8Encoding]::new($false).GetBytes('gebundener Inhalt')
        $renameStream.Write($renameBytes, 0, $renameBytes.Length)
        Assert-UniversaarlStreamBytes -Stream $renameStream -Expected $renameBytes
        Assert-Throws -Action { Move-Item -LiteralPath $renameTemp -Destination (Join-Path $safeOutputRoot 'ausgetauscht.tmp') -ErrorAction Stop } -Message 'Exklusiver Temp-Handle erlaubte einen Namensaustausch vor dem handlegebundenen Rename.'
        if (-not [Universaarl.NativeFile]::RenameOpenFile($renameStream.SafeFileHandle, $renameTarget, $true)) { throw 'Adversarialer handlegebundener Rename ist fehlgeschlagen.' }
        Assert-True -Condition ([string]::Equals((Get-UniversaarlFinalPathFromStream -Stream $renameStream), $renameTarget, [StringComparison]::OrdinalIgnoreCase)) -Message 'Handlegebundener Rename endete nicht am erwarteten Zielpfad.'
    }
    finally {
        if ($null -ne $renameStream) { $renameStream.Dispose() }
        Close-UniversaarlDirectoryLock -Lock $renameParentLock
    }
    Assert-True -Condition ((Read-UniversaarlRegularUtf8File -Root $safeOutputRoot -Path $renameTarget -MaximumBytes 1024) -ceq 'gebundener Inhalt') -Message 'Adversarialer Rename hinterliess nicht den handlegebundenen Inhalt.'

    $runnerSandbox = Join-Path $TestRoot 'runner-sandbox'
    New-Item -ItemType Directory -Path $runnerSandbox -Force | Out-Null
    $runner = Initialize-UniversaarlProcessRunner -ControlRoot $ControlRoot -SandboxRoot $runnerSandbox
    $runnerScript = Join-Path $runnerSandbox 'ausgabe.mjs'
    [IO.File]::WriteAllText($runnerScript, "console.log('ghp_abcdefghijklmnopqrstuvwxyz123456'); console.log('PASSWORD=fixture-password'); console.log('A'.repeat(200000));", [Text.UTF8Encoding]::new($false))
    $node = Resolve-UniversaarlTool -Names @('node', 'node.exe') -Description 'Node.js'
    $runnerResult = Invoke-UniversaarlSanitizedProcess -Runner $runner -FilePath $node -Arguments @($runnerScript) -WorkingDirectory $runnerSandbox -SandboxRoot $runnerSandbox -LogPath (Join-Path $runnerSandbox 'ausgabe.log') -LogRoot $runnerSandbox -TimeoutSeconds 30
    Assert-True -Condition ($runnerResult.output -match '<GEHEIMNIS>' -and $runnerResult.output -notmatch 'fixture-password' -and $runnerResult.outputTruncated) -Message 'Prozessausgabe wurde nicht begrenzt und redigiert.'

    $pipeScript = Join-Path $runnerSandbox 'offene-pipe.mjs'
    $pipePidPath = Join-Path $runnerSandbox 'kindprozess-normal.pid'
    [IO.File]::WriteAllText($pipeScript, "import { spawn } from 'node:child_process'; import { writeFileSync } from 'node:fs'; const child = spawn(process.execPath, ['-e', 'setTimeout(() => {}, 60000)'], { detached: true, stdio: ['ignore', 'inherit', 'inherit'] }); writeFileSync(process.argv[2], String(child.pid)); console.log(child.pid); child.unref();", [Text.UTF8Encoding]::new($false))
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    $pipeResult = Invoke-UniversaarlSanitizedProcess -Runner $runner -FilePath $node -Arguments @($pipeScript, $pipePidPath) -WorkingDirectory $runnerSandbox -SandboxRoot $runnerSandbox -LogPath (Join-Path $runnerSandbox 'offene-pipe.log') -LogRoot $runnerSandbox -TimeoutSeconds 20
    $stopwatch.Stop()
    $childPid = 0
    if (Test-Path -LiteralPath $pipePidPath -PathType Leaf) { $childPid = [int]([IO.File]::ReadAllText($pipePidPath, [Text.Encoding]::UTF8).Trim()) }
    $childEnded = $false
    for ($attempt = 0; $childPid -gt 0 -and $attempt -lt 50; $attempt++) {
        try { $null = Get-Process -Id $childPid -ErrorAction Stop }
        catch { $childEnded = $true; break }
        Start-Sleep -Milliseconds 100
    }
    Assert-True -Condition (-not $pipeResult.timedOut -and $pipeResult.exitCode -eq 0 -and $stopwatch.Elapsed.TotalSeconds -lt 10) -Message 'Normaler Elternexit mit geerbter offener Ausgabepipe wurde nicht unmittelbar abgeschlossen.'
    Assert-True -Condition ($childPid -gt 0 -and $childEnded) -Message 'Kindprozess ueberlebte den normalen Elternexit ausserhalb des Jobobjekts.'

    $timeoutTreeScript = Join-Path $runnerSandbox 'zeitlimit-prozessbaum.mjs'
    $timeoutChildPidPath = Join-Path $runnerSandbox 'kindprozess-zeitlimit.pid'
    [IO.File]::WriteAllText($timeoutTreeScript, "import { spawn } from 'node:child_process'; import { writeFileSync } from 'node:fs'; const child = spawn(process.execPath, ['-e', 'setTimeout(() => {}, 60000)'], { detached: true, stdio: ['ignore', 'inherit', 'inherit'] }); writeFileSync(process.argv[2], String(child.pid)); console.log(child.pid); child.unref(); setTimeout(() => {}, 60000);", [Text.UTF8Encoding]::new($false))
    $timeoutStopwatch = [Diagnostics.Stopwatch]::StartNew()
    $timeoutTreeResult = Invoke-UniversaarlSanitizedProcess -Runner $runner -FilePath $node -Arguments @($timeoutTreeScript, $timeoutChildPidPath) -WorkingDirectory $runnerSandbox -SandboxRoot $runnerSandbox -LogPath (Join-Path $runnerSandbox 'zeitlimit-prozessbaum.log') -LogRoot $runnerSandbox -TimeoutSeconds 2
    $timeoutStopwatch.Stop()
    $timeoutChildPid = 0
    if (Test-Path -LiteralPath $timeoutChildPidPath -PathType Leaf) { $timeoutChildPid = [int]([IO.File]::ReadAllText($timeoutChildPidPath, [Text.Encoding]::UTF8).Trim()) }
    $timeoutChildEnded = $false
    for ($attempt = 0; $timeoutChildPid -gt 0 -and $attempt -lt 50; $attempt++) {
        try { $null = Get-Process -Id $timeoutChildPid -ErrorAction Stop }
        catch { $timeoutChildEnded = $true; break }
        Start-Sleep -Milliseconds 100
    }
    Assert-True -Condition ($timeoutTreeResult.timedOut -and $timeoutTreeResult.exitCode -eq 124 -and $timeoutStopwatch.Elapsed.TotalSeconds -lt 10) -Message 'Zeitlimit beendete den zugewiesenen Prozessbaum nicht rechtzeitig.'
    Assert-True -Condition ($timeoutChildPid -gt 0 -and $timeoutChildEnded) -Message 'Kindprozess ueberlebte die Zeitlimitbeendigung des Jobobjekts.'
    Assert-True -Condition ($script:UniversaarlDirectoryLockRegistry.Count -eq 0) -Message "Verzeichnissperren wurden nach sicheren Schreib- und Prozessoperationen nicht vollstaendig freigegeben: $($script:UniversaarlDirectoryLockRegistry.Keys -join ', ')"

    $goalBlueprint = New-FixtureRepository -Name 'goal-blueprint' -Files @{ 'README.md' = '# Unvollstaendig'; 'REVIEW.md' = '' }
    $goalTwin = New-FixtureRepository -Name 'goal-twin' -Files @{ 'README.md' = '# Unvollstaendig'; 'REVIEW.md' = '' }
    $null = Invoke-FixtureGit -Repository $goalBlueprint.path -Arguments @('remote', 'add', 'origin', 'https://github.com/sivla/BCProjectOS.git')
    $goalConfigPath = Join-Path $TestRoot 'monitor.fixture.json'
    $goalDefinitionPath = Join-Path $TestRoot 'goals.fixture.json'
    $goalReports = Join-Path $ControlWorkRoot 'goal-reports'
    $fixtureConfig = [pscustomobject]@{ schemaVersion = 1; reportDirectory = 'unused'; validationTimeoutSeconds = 30; projects = @(
        [pscustomobject]@{ id = 'blueprint'; name = 'Blueprint-Fixture'; pathAlias = '<FIXTURE_BP>'; defaultPath = $goalBlueprint.path; pathEnvironmentVariable = 'UNIVERSAARL_FIXTURE_BP_PATH'; reviewFile = 'REVIEW.md'; requiredNpmScript = 'test'; validationArguments = @('test'); germanCheck = [pscustomobject]@{ npmScript = 'test:german'; resultSchemaVersion = 1 }; allowedVersionedMedia = $blueprintMediaAllowlist; maxActiveChanges = 1; publish = [pscustomobject]@{ enabled = $true; remote = 'origin'; expectedPushUrl = $goalBlueprint.path; branch = 'main' } },
        [pscustomobject]@{ id = 'project-twin'; name = 'Twin-Fixture'; pathAlias = '<FIXTURE_TW>'; defaultPath = $goalTwin.path; pathEnvironmentVariable = 'UNIVERSAARL_FIXTURE_TW_PATH'; reviewFile = 'REVIEW.md'; requiredNpmScript = 'check'; validationArguments = @('run', 'check'); germanCheck = [pscustomobject]@{ npmScript = 'test:german'; resultSchemaVersion = 1 }; allowedVersionedMedia = @(); maxActiveChanges = 1; publish = [pscustomobject]@{ enabled = $true; remote = 'origin'; expectedPushUrl = $goalTwin.path; branch = 'main' } }
    ); verificationSources = [pscustomobject]@{
        bcprojectos = [pscustomobject]@{ verificationOnly = $true; technicalProjectName = 'BCProjectOS'; expectedProduct = [pscustomobject]@{ name = 'Spectra'; productId = 'spectra' }; pathAlias = '<BCPROJECTOS_ROOT>'; defaultPath = $goalBlueprint.path; pathEnvironmentVariable = 'UNIVERSAARL_BCPROJECTOS_PATH'; remote = 'origin'; canonicalRemoteUrl = 'https://github.com/sivla/BCProjectOS.git' }
    }; relationships = @(
        [pscustomobject]@{ id = 'blueprint-binds-spectra'; consumerProjectId = 'blueprint'; providerVerificationSourceId = 'bcprojectos'; contractType = 'versioned-product-release'; productId = 'spectra'; contractMarker = 'BOUND_BCPROJECTOS_RELEASE' },
        [pscustomobject]@{ id = 'twin-reads-blueprint'; consumerProjectId = 'project-twin'; providerProjectId = 'blueprint'; contractType = 'portable-snapshot-release'; pointerPath = 'exports/project-data/v1/snapshots/current.json'; contractMarker = 'uabc-portable-snapshot-current-v1' }
    ) }
    $fixtureGoals = [pscustomobject]@{ schemaVersion = 1; projects = [pscustomobject]@{
        blueprint = [pscustomobject]@{ objective = 'Fixture'; currentGoal = 'Fixture' }
        'project-twin' = [pscustomobject]@{ objective = 'Fixture'; currentGoal = 'Fixture'; requiredBaseCommit = '0000000000000000000000000000000000000000'; currentChange = 'establish-responsive-multi-project-shell-foundation' }
    }; relationships = [pscustomobject]@{
        'blueprint-binds-spectra' = [pscustomobject]@{ objective = 'Fixture' }
        'twin-reads-blueprint' = [pscustomobject]@{ objective = 'Fixture' }
    } }
    Assert-UniversaarlMonitorConfiguration -Configuration $fixtureConfig
    Assert-UniversaarlGoalConfiguration -Configuration $fixtureGoals
    $verificationFingerprint = Get-UniversaarlRepositoryFingerprint -Repository $goalBlueprint.path
    $verificationReport = [pscustomobject]@{ verificationInputs = [pscustomobject]@{ bcprojectos = [pscustomobject]@{ sourceCommit = $goalBlueprint.sha; targetUnchanged = $true; fingerprintAfter = $verificationFingerprint } } }
    $oldVerificationOverride = [Environment]::GetEnvironmentVariable('UNIVERSAARL_BCPROJECTOS_PATH')
    try {
        [Environment]::SetEnvironmentVariable('UNIVERSAARL_BCPROJECTOS_PATH', $goalBlueprint.path)
        $boundVerification = Assert-UniversaarlBoundVerificationSourceState -AuditReport $verificationReport -GoalReport $verificationReport -Configuration $fixtureConfig
        Assert-True -Condition ($boundVerification.commit -ceq $goalBlueprint.sha -and $boundVerification.remoteUrl -ceq 'https://github.com/sivla/BCProjectOS.git') -Message 'BCProjectOS-Evidence-Quelle wurde nicht exakt erneut an Commit und Remote gebunden.'
        $wrongVerificationCommit = (($verificationReport | ConvertTo-Json -Depth 8) | ConvertFrom-Json)
        $wrongVerificationCommit.verificationInputs.bcprojectos.sourceCommit = '0' * 40
        Assert-Throws -Action { Assert-UniversaarlBoundVerificationSourceState -AuditReport $wrongVerificationCommit -GoalReport $wrongVerificationCommit -Configuration $fixtureConfig } -Message 'Abweichender BCProjectOS-HEAD wurde bei der Publisher-Neubindung akzeptiert.'
        $wrongVerificationFingerprint = (($verificationReport | ConvertTo-Json -Depth 8) | ConvertFrom-Json)
        $wrongVerificationFingerprint.verificationInputs.bcprojectos.fingerprintAfter.fingerprint = 'b' * 64
        Assert-Throws -Action { Assert-UniversaarlBoundVerificationSourceState -AuditReport $wrongVerificationFingerprint -GoalReport $wrongVerificationFingerprint -Configuration $fixtureConfig } -Message 'Abweichender BCProjectOS-Fingerprint wurde bei der Publisher-Neubindung akzeptiert.'
        $null = Invoke-FixtureGit -Repository $goalBlueprint.path -Arguments @('remote', 'set-url', '--push', 'origin', 'https://github.com/sivla/BCProjectOS.git')
        $null = Invoke-FixtureGit -Repository $goalBlueprint.path -Arguments @('remote', 'set-url', 'origin', 'https://github.com/sivla/FiBu.git')
        Assert-Throws -Action { Assert-UniversaarlBoundVerificationSourceState -AuditReport $verificationReport -GoalReport $verificationReport -Configuration $fixtureConfig } -Message 'Fremde BCProjectOS-Fetch-URL wurde trotz kanonischer Push-URL bei der Publisher-Neubindung akzeptiert.'
        $null = Invoke-FixtureGit -Repository $goalBlueprint.path -Arguments @('remote', 'set-url', 'origin', 'https://github.com/sivla/BCProjectOS.git')
        $null = Invoke-FixtureGit -Repository $goalBlueprint.path -Arguments @('config', '--add', 'remote.origin.url', 'https://github.com/sivla/BCProjectOS.git')
        Assert-Throws -Action { Assert-UniversaarlBoundVerificationSourceState -AuditReport $verificationReport -GoalReport $verificationReport -Configuration $fixtureConfig } -Message 'Mehrdeutige BCProjectOS-Fetch-URLs wurden bei der Publisher-Neubindung akzeptiert.'
    }
    finally {
        $null = & git -C $goalBlueprint.path config --unset-all remote.origin.pushurl 2>$null
        $null = & git -C $goalBlueprint.path config --unset-all remote.origin.url 2>$null
        $null = Invoke-FixtureGit -Repository $goalBlueprint.path -Arguments @('remote', 'set-url', 'origin', 'https://github.com/sivla/BCProjectOS.git')
        [Environment]::SetEnvironmentVariable('UNIVERSAARL_BCPROJECTOS_PATH', $oldVerificationOverride)
    }
    $wrongProductNameConfig = (($fixtureConfig | ConvertTo-Json -Depth 12) | ConvertFrom-Json)
    $wrongProductNameConfig.verificationSources.bcprojectos.expectedProduct.name = 'BCProjectOS'
    Assert-Throws -Action { Assert-UniversaarlMonitorConfiguration -Configuration $wrongProductNameConfig } -Message 'Falscher erwarteter Produktname wurde fuer die Spectra-Pruefquelle akzeptiert.'
    $wrongProductIdConfig = (($fixtureConfig | ConvertTo-Json -Depth 12) | ConvertFrom-Json)
    $wrongProductIdConfig.verificationSources.bcprojectos.expectedProduct.productId = 'bcprojectos'
    Assert-Throws -Action { Assert-UniversaarlMonitorConfiguration -Configuration $wrongProductIdConfig } -Message 'Falsche Spectra-Produkt-ID wurde fuer die Pruefquelle akzeptiert.'
    $wrongTechnicalProjectConfig = (($fixtureConfig | ConvertTo-Json -Depth 12) | ConvertFrom-Json)
    $wrongTechnicalProjectConfig.verificationSources.bcprojectos.technicalProjectName = 'Spectra'
    Assert-Throws -Action { Assert-UniversaarlMonitorConfiguration -Configuration $wrongTechnicalProjectConfig } -Message 'Falscher technischer Projektname wurde fuer die Spectra-Pruefquelle akzeptiert.'
    $wrongSourceIdConfig = (($fixtureConfig | ConvertTo-Json -Depth 12) | ConvertFrom-Json)
    $wrongSourceIdConfig.verificationSources = [pscustomobject]@{ spectra = $wrongSourceIdConfig.verificationSources.bcprojectos }
    Assert-Throws -Action { Assert-UniversaarlMonitorConfiguration -Configuration $wrongSourceIdConfig } -Message 'Falsche Kennung der BCProjectOS-Verifikationsquelle wurde akzeptiert.'
    $wrongRemoteNameConfig = (($fixtureConfig | ConvertTo-Json -Depth 12) | ConvertFrom-Json)
    $wrongRemoteNameConfig.verificationSources.bcprojectos.remote = 'upstream'
    Assert-Throws -Action { Assert-UniversaarlMonitorConfiguration -Configuration $wrongRemoteNameConfig } -Message 'Falscher Remote-Name wurde fuer die BCProjectOS-Verifikationsquelle akzeptiert.'
    $coercedRemoteNameConfig = (($fixtureConfig | ConvertTo-Json -Depth 12) | ConvertFrom-Json)
    $coercedRemoteNameConfig.verificationSources.bcprojectos.remote = @('origin')
    Assert-Throws -Action { Assert-UniversaarlMonitorConfiguration -Configuration $coercedRemoteNameConfig } -Message 'Array statt exakt typisiertem BCProjectOS-Remote-Namen wurde akzeptiert.'
    $wrongRemoteUrlConfig = (($fixtureConfig | ConvertTo-Json -Depth 12) | ConvertFrom-Json)
    $wrongRemoteUrlConfig.verificationSources.bcprojectos.canonicalRemoteUrl = 'https://github.com/sivla/FiBu.git'
    Assert-Throws -Action { Assert-UniversaarlMonitorConfiguration -Configuration $wrongRemoteUrlConfig } -Message 'Falsche kanonische Remote-URL wurde fuer die BCProjectOS-Verifikationsquelle akzeptiert.'
    $coercedRemoteUrlConfig = (($fixtureConfig | ConvertTo-Json -Depth 12) | ConvertFrom-Json)
    $coercedRemoteUrlConfig.verificationSources.bcprojectos.canonicalRemoteUrl = @('https://github.com/sivla/BCProjectOS.git')
    Assert-Throws -Action { Assert-UniversaarlMonitorConfiguration -Configuration $coercedRemoteUrlConfig } -Message 'Array statt exakt typisierter kanonischer BCProjectOS-Remote-URL wurde akzeptiert.'
    $writableVerificationSourceConfig = (($fixtureConfig | ConvertTo-Json -Depth 12) | ConvertFrom-Json)
    $writableVerificationSourceConfig.verificationSources.bcprojectos.verificationOnly = $false
    Assert-Throws -Action { Assert-UniversaarlMonitorConfiguration -Configuration $writableVerificationSourceConfig } -Message 'BCProjectOS wurde mit verificationOnly false als Verifikationsquelle akzeptiert.'
    $coercedVerificationSourceConfig = (($fixtureConfig | ConvertTo-Json -Depth 12) | ConvertFrom-Json)
    $coercedVerificationSourceConfig.verificationSources.bcprojectos.verificationOnly = 'true'
    Assert-Throws -Action { Assert-UniversaarlMonitorConfiguration -Configuration $coercedVerificationSourceConfig } -Message 'Zeichenkette true wurde als typstrenge verificationOnly-Markierung akzeptiert.'
    $coercedPublisherConfig = (($fixtureConfig | ConvertTo-Json -Depth 12) | ConvertFrom-Json)
    $coercedPublisherConfig.projects[0].publish.enabled = 'true'
    Assert-Throws -Action { Assert-UniversaarlMonitorConfiguration -Configuration $coercedPublisherConfig } -Message 'Zeichenkette true wurde als Publisherfreigabe akzeptiert.'
    $coercedTimeoutConfig = (($fixtureConfig | ConvertTo-Json -Depth 12) | ConvertFrom-Json)
    $coercedTimeoutConfig.validationTimeoutSeconds = '30'
    Assert-Throws -Action { Assert-UniversaarlMonitorConfiguration -Configuration $coercedTimeoutConfig } -Message 'Zeichenketten-Zeitlimit wurde als Ganzzahl akzeptiert.'
    $publisherVerificationSourceConfig = (($fixtureConfig | ConvertTo-Json -Depth 12) | ConvertFrom-Json)
    $publisherVerificationSourceConfig.verificationSources.bcprojectos | Add-Member -NotePropertyName publish -NotePropertyValue ([pscustomobject]@{ enabled = $true })
    Assert-Throws -Action { Assert-UniversaarlMonitorConfiguration -Configuration $publisherVerificationSourceConfig } -Message 'BCProjectOS-Verifikationsquelle durfte ein Publish-Feld besitzen.'
    $missingRelationshipConfig = (($fixtureConfig | ConvertTo-Json -Depth 12) | ConvertFrom-Json)
    $missingRelationshipConfig.relationships = @($missingRelationshipConfig.relationships | Where-Object { [string]$_.id -cne 'blueprint-binds-spectra' })
    Assert-Throws -Action { Assert-UniversaarlMonitorConfiguration -Configuration $missingRelationshipConfig } -Message 'Fehlende Spectra-Beziehung wurde akzeptiert.'
    $duplicateRelationshipConfig = (($fixtureConfig | ConvertTo-Json -Depth 12) | ConvertFrom-Json)
    $duplicateRelationshipConfig.relationships = @($duplicateRelationshipConfig.relationships) + $duplicateRelationshipConfig.relationships[0]
    Assert-Throws -Action { Assert-UniversaarlMonitorConfiguration -Configuration $duplicateRelationshipConfig } -Message 'Doppelte Spectra-Beziehung wurde akzeptiert.'
    $wrongSpectraRelationshipProductConfig = (($fixtureConfig | ConvertTo-Json -Depth 12) | ConvertFrom-Json)
    $wrongSpectraRelationshipProductConfig.relationships[0].productId = 'bcprojectos'
    Assert-Throws -Action { Assert-UniversaarlMonitorConfiguration -Configuration $wrongSpectraRelationshipProductConfig } -Message 'Falsche Produkt-ID in der Spectra-Bindungsbeziehung wurde akzeptiert.'
    $wrongSpectraContractConfig = (($fixtureConfig | ConvertTo-Json -Depth 12) | ConvertFrom-Json)
    $wrongSpectraContractConfig.relationships[0].contractMarker = 'PENDING_BCPROJECTOS_RELEASE'
    Assert-Throws -Action { Assert-UniversaarlMonitorConfiguration -Configuration $wrongSpectraContractConfig } -Message 'Erfundener Spectra-Vertragsmarker wurde akzeptiert.'
    $wrongSnapshotContractConfig = (($fixtureConfig | ConvertTo-Json -Depth 12) | ConvertFrom-Json)
    $wrongSnapshotContractConfig.relationships[1].contractType = 'working-tree'
    Assert-Throws -Action { Assert-UniversaarlMonitorConfiguration -Configuration $wrongSnapshotContractConfig } -Message 'Twin-Beziehung ohne portable-snapshot-release-Vertrag wurde akzeptiert.'
    $missingGoalRelationshipConfig = (($fixtureGoals | ConvertTo-Json -Depth 12) | ConvertFrom-Json)
    $missingGoalRelationshipConfig.relationships.PSObject.Properties.Remove('blueprint-binds-spectra')
    Assert-Throws -Action { Assert-UniversaarlGoalConfiguration -Configuration $missingGoalRelationshipConfig } -Message 'Fehlendes Spectra-Ziel im Zusammenspiel wurde akzeptiert.'
    $extraGoalRelationshipConfig = (($fixtureGoals | ConvertTo-Json -Depth 12) | ConvertFrom-Json)
    $extraGoalRelationshipConfig.relationships | Add-Member -NotePropertyName 'blueprint-binds-spectra-copy' -NotePropertyValue ([pscustomobject]@{ objective = 'Fixture' })
    Assert-Throws -Action { Assert-UniversaarlGoalConfiguration -Configuration $extraGoalRelationshipConfig } -Message 'Zusaetzliches beziehungsweise dupliziertes Zusammenspielziel wurde akzeptiert.'
    $wrongProjectMediaConfig = (($fixtureConfig | ConvertTo-Json -Depth 8) | ConvertFrom-Json)
    $wrongProjectMediaConfig.projects[1].allowedVersionedMedia = @([pscustomobject]@{ path = $canonicalMediaPath; maxBytes = 1048576; mode = '100644' })
    Assert-Throws -Action { Assert-UniversaarlMonitorConfiguration -Configuration $wrongProjectMediaConfig } -Message 'Twin-Konfiguration durfte die Blueprint-Produktmedienausnahme uebernehmen.'
    $wideMediaConfig = (($fixtureConfig | ConvertTo-Json -Depth 8) | ConvertFrom-Json)
    $wideMediaConfig.projects[0].allowedVersionedMedia[0].maxBytes = 1048577
    Assert-Throws -Action { Assert-UniversaarlMonitorConfiguration -Configuration $wideMediaConfig } -Message 'Blueprint-Konfiguration akzeptierte eine andere als die enge 1-MiB-Mediengrenze.'
    [IO.File]::WriteAllText($goalConfigPath, ($fixtureConfig | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($goalDefinitionPath, ($fixtureGoals | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    $externalReportRoot = Join-Path $TestRoot 'verbotene-berichte'
    $oldExternalPreference = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        & $TestPowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ControlRoot 'scripts\Invoke-UniversaarlGoalReview.ps1') -RunId 'fixture-external-report-root' -ConfigPath $goalConfigPath -GoalConfigPath $goalDefinitionPath -ReportRoot $externalReportRoot *> $null
        $externalReportExit = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $oldExternalPreference }
    Assert-True -Condition ($externalReportExit -ne 0 -and -not (Test-Path -LiteralPath $externalReportRoot)) -Message 'Externes Zielberichtverzeichnis wurde nicht vor jedem Schreibzugriff abgelehnt.'
    $goalRunId = 'fixture-goal-fail-closed'
    & $TestPowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ControlRoot 'scripts\Invoke-UniversaarlGoalReview.ps1') -RunId $goalRunId -ConfigPath $goalConfigPath -GoalConfigPath $goalDefinitionPath -ReportRoot $goalReports | Out-Null
    $goalExit = $LASTEXITCODE
    $goalReportPath = Join-Path $goalReports "goal-runs\$goalRunId.json"
    $goalReport = Read-UniversaarlBoundReport -Path $goalReportPath -RunId $goalRunId -Kind goal -TrustedRoot $goalReports
    Assert-True -Condition ($goalExit -ne 0 -and $goalReport.overallStatus -eq 'ROT') -Message 'Fehlende Pflichtartefakte oder nicht aufloesbare Basis wurden nicht fail-closed bewertet.'
    Assert-True -Condition ($goalReport.evidenceCoverage -is [int] -and $goalReport.evidenceCoverage -ge 0 -and $goalReport.evidenceCoverage -le 100) -Message 'Zielbericht enthaelt keine ehrliche numerische Nachweisabdeckung.'
    $goalMarkdown = Read-UniversaarlRegularUtf8File -Root $goalReports -Path (Join-Path $goalReports "goal-runs\$goalRunId.md") -MaximumBytes 8388608
    Assert-True -Condition ($goalMarkdown -match 'Nachweisabdeckung' -and $goalMarkdown -match 'Blueprint-Commit:' -and $goalMarkdown -match 'Twin-Commit:') -Message 'Zielbericht-Markdown nennt Nachweisabdeckung oder beide SHA-Felder nicht.'

    $auditRunId = 'fixture-audit-bound-inputs'
    & $TestPowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ControlRoot 'scripts\Invoke-UniversaarlAudit.ps1') -RunId $auditRunId -ConfigPath $goalConfigPath -ReportRoot $goalReports | Out-Null
    $auditReportPath = Join-Path $goalReports "runs\$auditRunId.json"
    $auditReport = Read-UniversaarlBoundReport -Path $auditReportPath -RunId $auditRunId -Kind audit -TrustedRoot $goalReports
    Assert-True -Condition ([string]$auditReport.inputShas.blueprint -eq $goalBlueprint.sha -and [string]$auditReport.inputShas.'project-twin' -eq $goalTwin.sha) -Message 'Auditbericht ist nicht an beide vollen Eingabe-SHAs gebunden.'
    $auditMarkdown = Read-UniversaarlRegularUtf8File -Root $goalReports -Path (Join-Path $goalReports "runs\$auditRunId.md") -MaximumBytes 8388608
    Assert-True -Condition ($auditMarkdown -match 'Nachweisabdeckung' -and $auditMarkdown -match 'Zweig/Commit:' -and $auditMarkdown -notmatch 'Branch/Commit') -Message 'Audit-Markdown nennt Nachweisabdeckung oder den deutschen Zweig-/Commit-Titel nicht exakt.'

    $unknownConfig = (($fixtureConfig | ConvertTo-Json -Depth 8) | ConvertFrom-Json)
    $unknownConfig.projects[0].defaultPath = Join-Path $TestRoot 'fehlendes-blueprint'
    $unknownConfig.projects[0].pathEnvironmentVariable = 'UNIVERSAARL_UNKNOWN_BP_PATH'
    $unknownConfig.projects[1].defaultPath = Join-Path $TestRoot 'fehlender-twin'
    $unknownConfig.projects[1].pathEnvironmentVariable = 'UNIVERSAARL_UNKNOWN_TW_PATH'
    $unknownConfigPath = Join-Path $TestRoot 'monitor.unknown.fixture.json'
    [IO.File]::WriteAllText($unknownConfigPath, ($unknownConfig | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    $oldUnknownBp = [Environment]::GetEnvironmentVariable('UNIVERSAARL_UNKNOWN_BP_PATH')
    $oldUnknownTwin = [Environment]::GetEnvironmentVariable('UNIVERSAARL_UNKNOWN_TW_PATH')
    try {
        [Environment]::SetEnvironmentVariable('UNIVERSAARL_UNKNOWN_BP_PATH', $null)
        [Environment]::SetEnvironmentVariable('UNIVERSAARL_UNKNOWN_TW_PATH', $null)
        $oldUnknownPreference = $ErrorActionPreference
        $ErrorActionPreference = 'SilentlyContinue'
        try {
            $unknownGoalRunId = 'fixture-goal-unknown-inputs'
            & $TestPowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ControlRoot 'scripts\Invoke-UniversaarlGoalReview.ps1') -RunId $unknownGoalRunId -ConfigPath $unknownConfigPath -GoalConfigPath $goalDefinitionPath -ReportRoot $goalReports *> $null
            $unknownGoalExit = $LASTEXITCODE
            $unknownAuditRunId = 'fixture-audit-unknown-inputs'
            & $TestPowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ControlRoot 'scripts\Invoke-UniversaarlAudit.ps1') -RunId $unknownAuditRunId -ConfigPath $unknownConfigPath -ReportRoot $goalReports *> $null
            $unknownAuditExit = $LASTEXITCODE
        }
        finally { $ErrorActionPreference = $oldUnknownPreference }
    }
    finally {
        [Environment]::SetEnvironmentVariable('UNIVERSAARL_UNKNOWN_BP_PATH', $oldUnknownBp)
        [Environment]::SetEnvironmentVariable('UNIVERSAARL_UNKNOWN_TW_PATH', $oldUnknownTwin)
    }
    $unknownGoalPath = Join-Path $goalReports "goal-runs\$unknownGoalRunId.json"
    $unknownAuditPath = Join-Path $goalReports "runs\$unknownAuditRunId.json"
    $unknownGoalReport = (Read-UniversaarlRegularUtf8File -Root $goalReports -Path $unknownGoalPath -MaximumBytes 8388608) | ConvertFrom-Json
    $unknownAuditReport = (Read-UniversaarlRegularUtf8File -Root $goalReports -Path $unknownAuditPath -MaximumBytes 8388608) | ConvertFrom-Json
    foreach ($unknownReport in @($unknownGoalReport, $unknownAuditReport)) {
        $unknownShaNames = @($unknownReport.inputShas.PSObject.Properties.Name)
        Assert-True -Condition ($unknownShaNames.Count -eq 2 -and $unknownShaNames -ccontains 'blueprint' -and $unknownShaNames -ccontains 'project-twin' -and $null -eq $unknownReport.inputShas.blueprint -and $null -eq $unknownReport.inputShas.'project-twin') -Message 'Bericht mit unbekanntem Zustand fuehrte nicht beide SHA-Felder explizit als null.'
    }
    Assert-True -Condition ($unknownGoalExit -ne 0 -and $unknownAuditExit -ne 0) -Message 'Unbekannte Eingabe-SHAs wurden nicht fail-closed bewertet.'
    $unknownGoalMarkdown = Read-UniversaarlRegularUtf8File -Root $goalReports -Path (Join-Path $goalReports "goal-runs\$unknownGoalRunId.md") -MaximumBytes 8388608
    $unknownAuditMarkdown = Read-UniversaarlRegularUtf8File -Root $goalReports -Path (Join-Path $goalReports "runs\$unknownAuditRunId.md") -MaximumBytes 8388608
    Assert-True -Condition ($unknownGoalMarkdown -match 'unbekannt' -and $unknownAuditMarkdown -match 'unbekannt') -Message 'Markdownberichte stellten unbekannte Eingabe-SHAs leer statt ehrlich als unbekannt dar.'
    Assert-Throws -Action { Read-UniversaarlBoundReport -Path $unknownGoalPath -RunId $unknownGoalRunId -Kind goal -TrustedRoot $goalReports } -Message 'Publisher-gebundener Leser akzeptierte unbekannte Eingabe-SHAs.'

    Write-Host "Kontrollzentrum-Fixture-Tests bestanden: $script:Passed; uebersprungen: $script:Skipped."
    exit 0
}
finally {
    $resolvedWork = [IO.Path]::GetFullPath($ControlWorkRoot)
    if ($resolvedWork.StartsWith([IO.Path]::GetFullPath($ControlWorkParent).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolvedWork).StartsWith('universaarl-control-tests-')) {
        Remove-Item -LiteralPath $resolvedWork -Recurse -Force -ErrorAction SilentlyContinue
    }
    $resolved = [IO.Path]::GetFullPath($TestRoot)
    if ($resolved.StartsWith($TempBase + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved).StartsWith('universaarl-control-tests-')) {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}
