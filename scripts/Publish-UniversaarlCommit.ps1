[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('blueprint', 'project-twin')]
    [string]$Project,
    [switch]$Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$MonitorRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
. (Join-Path $PSScriptRoot 'Universaarl-Control.Common.ps1')
$ConfigPath = Join-Path $MonitorRoot 'monitor.config.json'
$Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
Assert-UniversaarlMonitorConfiguration -Configuration $Config
if ([string]$Config.reportDirectory -ne 'reports') { throw 'Die Veroeffentlichung akzeptiert nur das feste Berichtverzeichnis `reports`.' }
$ProjectConfig = @($Config.projects | Where-Object id -eq $Project)[0]
if ($null -eq $ProjectConfig) { throw "Unbekanntes Projekt '$Project'." }
$RunId = New-UniversaarlRunId -Prefix "publish-$Project"
Assert-UniversaarlRunId -RunId $RunId
$ReportRoot = Join-Path $MonitorRoot ([string]$Config.reportDirectory)
$AuditReportPath = Join-Path $ReportRoot "runs\$RunId.json"
$GoalReportPath = Join-Path $ReportRoot "goal-runs\$RunId.json"
$AuditPath = Join-Path $PSScriptRoot 'Invoke-UniversaarlAudit.ps1'
$GoalPath = Join-Path $PSScriptRoot 'Invoke-UniversaarlGoalReview.ps1'
$ControlGermanPath = Join-Path $PSScriptRoot 'Test-UniversaarlGermanSurface.ps1'
$Blockers = [Collections.Generic.List[string]]::new()

function Add-Blocker { param([Parameter(Mandatory)][string]$Message) $Blockers.Add($Message) }

function Get-ProjectResult {
    param([Parameter(Mandatory)]$Report, [Parameter(Mandatory)][string]$Id)
    @($Report.projects | Where-Object id -eq $Id)[0]
}

function Get-InputSha {
    param([Parameter(Mandatory)]$Report, [Parameter(Mandatory)][string]$Id)
    $property = $Report.inputShas.PSObject.Properties[$Id]
    if ($null -eq $property) { throw "Eingabe-SHA fuer '$Id' fehlt im Laufbericht." }
    $sha = [string]$property.Value
    Assert-FullCommitSha -Commit $sha
    $sha
}

function Test-ConfiguredRemote {
    param([Parameter(Mandatory)][string]$Repository, [Parameter(Mandatory)]$Entry)
    $remote = [string]$Entry.publish.remote
    $expected = [string]$Entry.publish.expectedPushUrl
    Assert-UniversaarlExpectedPushRemote -Repository $Repository -Remote $remote -ExpectedUrl $expected
}

function New-PublisherTemporaryRoot {
    $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
    # Die Laufkennung bleibt im gebundenen Bericht. Im Dateisystem genuegt eine
    # GUID; der kuerzere Name haelt tiefe, gueltige Repositorypfade unter der
    # klassischen Windows-Pfadgrenze.
    $root = Join-Path $tempBase ("universaarl-publish-{0}" -f [Guid]::NewGuid().ToString('N'))
    $null = Initialize-UniversaarlSafeDirectory -TrustedRoot $tempBase -Directory $root
    $root
}

function Remove-PublisherTemporaryRoot {
    param([Parameter(Mandatory)][string]$Root)
    $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $resolved = [IO.Path]::GetFullPath($Root)
    if (-not $resolved.StartsWith($tempBase + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or -not (Split-Path -Leaf $resolved).StartsWith('universaarl-publish-')) { throw 'Unsichere temporaere Veroeffentlichungswurzel.' }
    if (Test-Path -LiteralPath $resolved) {
        $item = Get-Item -LiteralPath $resolved -Force -ErrorAction SilentlyContinue
        if ($null -ne $item -and (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { Remove-Item -LiteralPath $resolved -Force -ErrorAction SilentlyContinue }
        else { Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Invoke-CleanRemoteQuery {
    param([Parameter(Mandatory)][string]$Url, [Parameter(Mandatory)][string]$Branch)
    Invoke-UniversaarlCleanLsRemote -Url $Url -Ref "refs/heads/$Branch"
}

function Assert-ReviewGate {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$Commit,
        [Parameter(Mandatory)][string]$ReviewFile
    )
    $headReview = Read-UniversaarlCommitText -Repository $Repository -Commit $Commit -Path $ReviewFile -MaximumBytes 65536 -Required
    if (-not [string]::IsNullOrWhiteSpace([string]$headReview.content)) { throw "Pruefdatei '$ReviewFile' ist im geprueften Commit nicht leer." }
    $workingReview = Read-UniversaarlWorkingText -Repository $Repository -Path $ReviewFile -MaximumBytes 65536 -RequireCleanRepository
    if (-not [string]::IsNullOrWhiteSpace($workingReview)) { throw "Pruefdatei '$ReviewFile' ist in der Arbeitskopie nicht leer." }
}

function Assert-BoundProjectStates {
    param(
        [Parameter(Mandatory)]$AuditReport,
        [Parameter(Mandatory)]$Configuration,
        [Parameter(Mandatory)][string]$SelectedProject
    )
    $states = @{}
    foreach ($entry in $Configuration.projects) {
        $id = [string]$entry.id
        $path = Get-UniversaarlConfiguredPath -Project $entry
        $expectedSha = Get-InputSha -Report $AuditReport -Id $id
        Assert-UniversaarlCommitRuntimeSafe -Repository $path -Commit $expectedSha -AllowedVersionedMedia @($entry.allowedVersionedMedia)
        $current = Get-UniversaarlRepositoryFingerprint -Repository $path
        $projectResult = Get-ProjectResult -Report $AuditReport -Id $id
        if ($null -eq $projectResult -or $null -eq $projectResult.fingerprintAfter) { throw "Abschliessender Fingerprint fuer '$id' fehlt." }
        if ($projectResult.targetUnchanged -isnot [bool] -or -not $projectResult.targetUnchanged) { throw "Der Audit hat fuer '$id' keinen typstrengen unveraenderten Zielzustand nachgewiesen." }
        if ($current.head -ne $expectedSha -or -not (Test-UniversaarlFingerprintEqual -Expected $projectResult.fingerprintAfter -Actual $current)) { throw "Repositoryzustand von '$id' hat sich seit dem Audit veraendert." }
        if ($id -eq $SelectedProject) {
            if ($current.branch -ne [string]$entry.publish.branch) { throw "Aktueller Zweig von '$id' stimmt nicht mit dem freigegebenen Zielzweig ueberein." }
            if ($current.dirty) { throw "Arbeitsbaum von '$id' ist nicht sauber." }
            Assert-ReviewGate -Repository $path -Commit $expectedSha -ReviewFile ([string]$entry.reviewFile)
            $null = Test-ConfiguredRemote -Repository $path -Entry $entry
        }
        $states[$id] = [pscustomobject]@{ path = $path; commit = $expectedSha; fingerprint = $current; config = $entry }
    }
    $states
}

Write-Host "Pruefe Veroeffentlichungsbedingungen fuer '$Project' im Lauf '$RunId' ..."
$auditOutput = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $AuditPath -RunValidations -RunId $RunId 2>&1)
$auditExitCode = $LASTEXITCODE
$auditOutput | ForEach-Object { Write-Host $_ }
if (-not (Test-UniversaarlBoundReportExitCode -ExitCode $auditExitCode)) { Add-Blocker "Der aktuelle technische Lauf ist mit unerwartetem Rueckgabecode $auditExitCode fehlgeschlagen." }
if (-not (Test-Path -LiteralPath $AuditReportPath -PathType Leaf)) { Add-Blocker "Der aktuelle technische Lauf erzeugte keinen gebundenen Bericht; Rueckgabecode $auditExitCode." }

$AuditReport = $null
if ($Blockers.Count -eq 0) {
    try { $AuditReport = Read-UniversaarlBoundReport -Path $AuditReportPath -RunId $RunId -Kind audit -TrustedRoot $ReportRoot }
    catch { Add-Blocker "Der technische Laufbericht ist nicht verwendbar: $($_.Exception.Message)" }
}

$goalOutput = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $GoalPath -RunId $RunId 2>&1)
$goalExitCode = $LASTEXITCODE
$goalOutput | ForEach-Object { Write-Host $_ }
if (-not (Test-UniversaarlBoundReportExitCode -ExitCode $goalExitCode)) { Add-Blocker "Der aktuelle Zielpruefungslauf ist mit unerwartetem Rueckgabecode $goalExitCode fehlgeschlagen." }
if (-not (Test-Path -LiteralPath $GoalReportPath -PathType Leaf)) { Add-Blocker "Der aktuelle Zielpruefungslauf erzeugte keinen gebundenen Bericht; Rueckgabecode $goalExitCode." }

$GoalReport = $null
if (Test-Path -LiteralPath $GoalReportPath -PathType Leaf) {
    try { $GoalReport = Read-UniversaarlBoundReport -Path $GoalReportPath -RunId $RunId -Kind goal -TrustedRoot $ReportRoot }
    catch { Add-Blocker "Der Zielbericht ist nicht verwendbar: $($_.Exception.Message)" }
}

$languageOutput = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ControlGermanPath -RunId $RunId 2>&1)
$languageExitCode = $LASTEXITCODE
$languageOutput | ForEach-Object { Write-Host $_ }
if ($languageExitCode -ne 0) { Add-Blocker "Die ergaenzende Deutsch-Pruefung des Kontrollzentrums endete mit Rueckgabecode $languageExitCode." }

if ($null -ne $AuditReport -and $null -ne $GoalReport) {
    foreach ($id in @($Config.projects | ForEach-Object { [string]$_.id })) {
        try {
            $auditSha = Get-InputSha -Report $AuditReport -Id $id
            $goalSha = Get-InputSha -Report $GoalReport -Id $id
            if ($auditSha -ne $goalSha) { Add-Blocker "Audit und Zielpruefung verwendeten fuer '$id' unterschiedliche Commits." }
        }
        catch { Add-Blocker $_.Exception.Message }
    }
    if ($AuditReport.verificationInputs.bcprojectos.sourceCommit -cne $GoalReport.verificationInputs.bcprojectos.sourceCommit) {
        Add-Blocker 'Audit und Zielpruefung verwendeten unterschiedliche BCProjectOS-Evidence-Commits fuer Spectra.'
    }
    $ProjectResult = Get-ProjectResult -Report $AuditReport -Id $Project
    $ProjectGoalResult = Get-ProjectResult -Report $GoalReport -Id $Project
    $TechnicalRelationships = @($AuditReport.relationships)
    $GoalRelationships = @($GoalReport.relationships)
    $SpectraTechnicalRelationship = @($TechnicalRelationships | Where-Object id -eq 'blueprint-binds-spectra')[0]
    $SnapshotTechnicalRelationship = @($TechnicalRelationships | Where-Object id -eq 'twin-reads-blueprint')[0]
    $SpectraGoalRelationship = @($GoalRelationships | Where-Object id -eq 'blueprint-binds-spectra')[0]
    $SnapshotGoalRelationship = @($GoalRelationships | Where-Object id -eq 'twin-reads-blueprint')[0]
    if ($null -eq $ProjectResult) { Add-Blocker 'Projekt fehlt im technischen Laufbericht.' }
    if ($null -eq $SpectraTechnicalRelationship -or $null -eq $SnapshotTechnicalRelationship) { Add-Blocker 'Technischer Spectra- oder Snapshot-Vertragsnachweis fehlt im Laufbericht.' }
    if ($null -eq $ProjectGoalResult) { Add-Blocker 'Projekt fehlt im strategischen Laufbericht.' }
    if ($null -eq $SpectraGoalRelationship -or $null -eq $SnapshotGoalRelationship) { Add-Blocker 'Strategischer Spectra- oder Snapshot-Vertragsnachweis fehlt im Laufbericht.' }
    if ($null -ne $ProjectResult -and $null -ne $ProjectGoalResult) {
        foreach ($message in @(Get-UniversaarlScopedPublishGateBlockers -ProjectResult $ProjectResult -TechnicalRelationships $TechnicalRelationships -ProjectGoalResult $ProjectGoalResult -GoalRelationships $GoalRelationships)) { Add-Blocker $message }
    }
    if ($null -ne $SpectraTechnicalRelationship) {
        if ($SpectraTechnicalRelationship.sourceCommit -cne $AuditReport.verificationInputs.bcprojectos.sourceCommit -or $SpectraTechnicalRelationship.consumerCommit -cne (Get-InputSha $AuditReport 'blueprint')) { Add-Blocker 'Der technische Spectra-Vertragsnachweis ist nicht an Evidence- und Blueprint-Commit gebunden.' }
    }
    if ($null -ne $SnapshotTechnicalRelationship) {
        if ($SnapshotTechnicalRelationship.providerCommit -cne (Get-InputSha $AuditReport 'blueprint') -or $SnapshotTechnicalRelationship.consumerCommit -cne (Get-InputSha $AuditReport 'project-twin')) { Add-Blocker 'Der technische Snapshot-Vertragsnachweis ist nicht an beide Eingabe-SHAs gebunden.' }
    }
    if ($null -ne $SpectraGoalRelationship) {
        if ($SpectraGoalRelationship.sourceCommit -cne $GoalReport.verificationInputs.bcprojectos.sourceCommit -or $SpectraGoalRelationship.consumerCommit -cne (Get-InputSha $GoalReport 'blueprint')) { Add-Blocker 'Der strategische Spectra-Vertragsnachweis ist nicht an Evidence- und Blueprint-Commit gebunden.' }
    }
    if ($null -ne $SnapshotGoalRelationship) {
        if ($SnapshotGoalRelationship.providerCommit -cne (Get-InputSha $GoalReport 'blueprint') -or $SnapshotGoalRelationship.consumerCommit -cne (Get-InputSha $GoalReport 'project-twin')) { Add-Blocker 'Der strategische Snapshot-Vertragsnachweis ist nicht an beide Eingabe-SHAs gebunden.' }
    }
}

if ($null -eq $ProjectConfig.publish -or $ProjectConfig.publish.enabled -isnot [bool] -or -not $ProjectConfig.publish.enabled) { Add-Blocker 'Die Veroeffentlichung ist fuer dieses Projekt nicht typstreng aktiviert.' }

$verificationState = $null
if ($null -ne $AuditReport -and $null -ne $GoalReport) {
    try { $verificationState = Assert-UniversaarlBoundVerificationSourceState -AuditReport $AuditReport -GoalReport $GoalReport -Configuration $Config }
    catch { Add-Blocker $_.Exception.Message }
}

$states = $null
if ($Blockers.Count -eq 0) {
    try { $states = Assert-BoundProjectStates -AuditReport $AuditReport -Configuration $Config -SelectedProject $Project }
    catch { Add-Blocker $_.Exception.Message }
}

$selectedState = if ($null -ne $states) { $states[$Project] } else { $null }
$remoteHead = $null
$expectedUrl = if ($null -ne $selectedState) { [string]$selectedState.config.publish.expectedPushUrl } else { '' }
$branch = if ($null -ne $selectedState) { [string]$selectedState.config.publish.branch } else { '' }
$commit = if ($null -ne $selectedState) { [string]$selectedState.commit } else { '' }
if ($Blockers.Count -eq 0) {
    try {
        $refCheck = Invoke-UniversaarlGitRead -Repository $selectedState.path -Arguments @('check-ref-format', '--branch', $branch)
        if ($refCheck.exitCode -ne 0) { throw 'Der Zielzweig ist kein gueltiger Git-Zweigname.' }
        $remote = Invoke-CleanRemoteQuery -Url $expectedUrl -Branch $branch
        if ($remote.exitCode -ne 0) { throw 'Der Zustand des entfernten Zielzweigs konnte nicht sicher gelesen werden.' }
        if (-not [string]::IsNullOrWhiteSpace($remote.output)) {
            $remoteHead = ($remote.output -split '\s+')[0]
            Assert-FullCommitSha -Commit $remoteHead
            if ($remoteHead -eq $commit) { Write-Host 'Der gepruefte Commit ist bereits auf dem freigegebenen Zielzweig veroeffentlicht.'; exit 0 }
            $ancestor = Invoke-UniversaarlGitRead -Repository $selectedState.path -Arguments @('merge-base', '--is-ancestor', $remoteHead, $commit)
            if ($ancestor.exitCode -ne 0) { throw 'Der entfernte HEAD ist kein bekannter Vorfahr des geprueften Commits.' }
        }
        $revision = if ($null -ne $remoteHead) { "$remoteHead..$commit" } else { $commit }
        $history = Invoke-UniversaarlGitRead -Repository $selectedState.path -Arguments @('rev-list', '--reverse', $revision)
        if ($history.exitCode -ne 0 -or [string]::IsNullOrWhiteSpace($history.output)) { throw 'Die zu veroeffentlichende Commit-Historie kann nicht vollstaendig bestimmt werden.' }
        foreach ($historyCommit in @($history.output -split "`n" | Where-Object { $_ })) {
            Assert-FullCommitSha -Commit $historyCommit
            Assert-UniversaarlCommitRuntimeSafe -Repository $selectedState.path -Commit $historyCommit -AllowedVersionedMedia @($selectedState.config.allowedVersionedMedia)
            $historyEnvironmentExample = Test-UniversaarlEnvironmentExample -Repository $selectedState.path -Commit $historyCommit
            if ($historyEnvironmentExample.present -and $historyEnvironmentExample.safe -ne $true) { throw "Unsichere versionierte `.env.example` in der zu veroeffentlichenden Historie bei Commit $historyCommit." }
        }
    }
    catch { Add-Blocker $_.Exception.Message }
}

if ($Blockers.Count -gt 0) {
    Write-Host ''
    Write-Host 'VEROEFFENTLICHUNG BLOCKIERT:'
    foreach ($blocker in $Blockers) { Write-Host "- $blocker" }
    exit 1
}

if (-not $Execute) {
    Write-Host ''
    Write-Host "VEROEFFENTLICHUNGSBEREIT: $Project / $branch / $commit"
    Write-Host 'Es wurde nichts uebertragen. Fuer die echte Veroeffentlichung denselben Aufruf mit -Execute starten.'
    exit 0
}

try {
    $states = Assert-BoundProjectStates -AuditReport $AuditReport -Configuration $Config -SelectedProject $Project
    $verificationState = Assert-UniversaarlBoundVerificationSourceState -AuditReport $AuditReport -GoalReport $GoalReport -Configuration $Config
    $selectedState = $states[$Project]
    $expectedUrl = Test-ConfiguredRemote -Repository $selectedState.path -Entry $selectedState.config
    if ([string]$selectedState.commit -ne $commit) { throw 'Die ausgewaehlte Commit-SHA hat sich vor dem Push veraendert.' }
    $refSpec = Get-UniversaarlExactPushRefSpec -Commit $commit -Branch $branch
}
catch {
    Write-Host "VEROEFFENTLICHUNG BLOCKIERT: $($_.Exception.Message)"
    exit 1
}

$pushRoot = New-PublisherTemporaryRoot
$pushRootLock = $null
$pushRepositoryLock = $null
$hooksLock = $null
try {
    $pushRootLock = Open-UniversaarlLockedDirectoryChain -Directory $pushRoot
    $pushRepository = Join-Path $pushRoot 'push-copy'
    New-UniversaarlCommitSnapshot -SourceRepository $selectedState.path -Commit $commit -Destination $pushRepository -SandboxRoot $pushRoot -IncludeHistory -AllowedVersionedMedia @($selectedState.config.allowedVersionedMedia) | Out-Null
    $pushRepositoryLock = Open-UniversaarlLockedDirectoryChain -Directory $pushRepository
    $gitHome = Join-Path $pushRoot 'git-home'
    $hooksPath = Join-Path $pushRoot 'publisher-hooks'
    $null = Initialize-UniversaarlSafeDirectory -TrustedRoot $pushRoot -Directory $hooksPath
    $hooksLock = Open-UniversaarlLockedDirectoryChain -Directory $hooksPath
    if (@(Get-ChildItem -LiteralPath $hooksPath -Force -ErrorAction Stop).Count -ne 0) { throw 'Kontrollierter Publisher-Hookpfad ist nicht leer.' }
    $hookConfig = Invoke-UniversaarlIsolatedGit -GitHome $gitHome -Repository $pushRepository -UseExplicitRepositoryPaths -Arguments @('config', 'core.hooksPath', $hooksPath)
    if ($hookConfig.exitCode -ne 0) { throw 'Kontrollierter leerer Publisher-Hookpfad konnte nicht an die frische Push-Kopie gebunden werden.' }
    $credentialManager = Invoke-UniversaarlIsolatedGit -GitHome $gitHome -Arguments @('credential-manager', '--version')
    if ($credentialManager.exitCode -ne 0) { throw 'Der fest freigegebene Git Credential Manager ist fuer die authentifizierte Uebertragung nicht verfuegbar.' }
    $credentialConfig = Invoke-UniversaarlIsolatedGit -GitHome $gitHome -Repository $pushRepository -UseExplicitRepositoryPaths -Arguments @('config', 'credential.helper', 'manager')
    if ($credentialConfig.exitCode -ne 0) { throw 'Git Credential Manager konnte nicht in der bereinigten Push-Kopie aktiviert werden.' }
    Assert-UniversaarlCleanPushRepositoryConfiguration -Repository $pushRepository -GitHome $gitHome -ExpectedHooksPath $hooksPath -TrustedSandboxRoot $pushRoot -RequireCredentialManager
    if (@(Get-ChildItem -LiteralPath $hooksPath -Force -ErrorAction Stop).Count -ne 0) { throw 'Kontrollierter Publisher-Hookpfad wurde vor der Uebertragung veraendert.' }
    $null = Assert-UniversaarlBoundVerificationSourceState -AuditReport $AuditReport -GoalReport $GoalReport -Configuration $Config
    $null = Assert-BoundProjectStates -AuditReport $AuditReport -Configuration $Config -SelectedProject $Project
    $push = Invoke-UniversaarlIsolatedGit -GitHome $gitHome -Repository $pushRepository -UseExplicitRepositoryPaths -Arguments @('push', '--porcelain', $expectedUrl, $refSpec)
    if ($push.exitCode -ne 0) {
        $pushDetail = ([string]$push.output -replace '[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]', '').Trim()
        if ($pushDetail.Length -gt 2000) { $pushDetail = $pushDetail.Substring(0, 2000) + ' ...' }
        if ([string]::IsNullOrWhiteSpace($pushDetail)) { $pushDetail = 'Git lieferte keine Diagnoseausgabe.' }
        throw "Die Git-Uebertragung ist mit Rueckgabecode $($push.exitCode) fehlgeschlagen: $pushDetail"
    }
    $null = Assert-BoundProjectStates -AuditReport $AuditReport -Configuration $Config -SelectedProject $Project
    $verify = Invoke-UniversaarlIsolatedGit -GitHome $gitHome -Repository $pushRepository -UseExplicitRepositoryPaths -Arguments @('ls-remote', '--heads', $expectedUrl, "refs/heads/$branch")
    $published = if ($verify.output) { ($verify.output -split '\s+')[0] } else { '' }
    if ($verify.exitCode -ne 0 -or $published -ne $commit) { throw 'Die Uebertragung wurde ausgefuehrt, aber die exakte Commit-SHA konnte nicht bestaetigt werden.' }
}
finally {
    Close-UniversaarlDirectoryLock -Lock $hooksLock
    Close-UniversaarlDirectoryLock -Lock $pushRepositoryLock
    Close-UniversaarlDirectoryLock -Lock $pushRootLock
    Remove-PublisherTemporaryRoot -Root $pushRoot
}
Write-Host "VEROEFFENTLICHUNG ERFOLGREICH: $Project / $branch / $commit"
exit 0
