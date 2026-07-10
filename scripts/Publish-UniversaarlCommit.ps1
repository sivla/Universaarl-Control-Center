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
$ConfigPath = Join-Path $MonitorRoot 'monitor.config.json'
$AuditPath = Join-Path $PSScriptRoot 'Invoke-UniversaarlAudit.ps1'
$ReportPath = Join-Path $MonitorRoot 'reports\latest.json'
$GoalReviewPath = Join-Path $PSScriptRoot 'Invoke-UniversaarlGoalReview.ps1'
$GoalReportPath = Join-Path $MonitorRoot 'reports\goals-latest.json'
$GermanSurfaceCheckPath = Join-Path $PSScriptRoot 'Test-UniversaarlGermanSurface.ps1'
$Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$ProjectConfig = @($Config.projects | Where-Object { $_.id -eq $Project })[0]

if ($null -eq $ProjectConfig) { throw "Unbekanntes Projekt '$Project'." }

function Get-TargetPath {
    param([Parameter(Mandatory)]$Entry)
    $override = [Environment]::GetEnvironmentVariable([string]$Entry.pathEnvironmentVariable)
    $candidate = if ([string]::IsNullOrWhiteSpace($override)) { [string]$Entry.defaultPath } else { $override }
    if (-not [IO.Path]::IsPathRooted($candidate)) { throw 'Der Zielpfad muss absolut sein.' }
    [IO.Path]::GetFullPath($candidate).TrimEnd([IO.Path]::DirectorySeparatorChar)
}

function Invoke-GitCapture {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string[]]$Arguments
    )
    $oldErrorActionPreference = $ErrorActionPreference
    $oldOptionalLocks = [Environment]::GetEnvironmentVariable('GIT_OPTIONAL_LOCKS')
    $ErrorActionPreference = 'SilentlyContinue'
    [Environment]::SetEnvironmentVariable('GIT_OPTIONAL_LOCKS', '0')
    try {
        $lines = @(& git -C $Repository @Arguments 2>$null)
        [pscustomobject]@{ exitCode = $LASTEXITCODE; output = ($lines -join "`n").Trim() }
    }
    finally {
        [Environment]::SetEnvironmentVariable('GIT_OPTIONAL_LOCKS', $oldOptionalLocks)
        $ErrorActionPreference = $oldErrorActionPreference
    }
}

Write-Host "Pruefe Veroeffentlichungsbedingungen fuer '$Project' ..."
$auditOutput = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $AuditPath -RunValidations 2>&1)
$auditExitCode = $LASTEXITCODE
$auditOutput | ForEach-Object { Write-Host $_ }

if (-not (Test-Path -LiteralPath $ReportPath -PathType Leaf)) {
    throw 'Die technische Gesamtpruefung hat keinen maschinenlesbaren Bericht erzeugt.'
}

$Report = Get-Content -LiteralPath $ReportPath -Raw | ConvertFrom-Json
$ProjectResult = @($Report.projects | Where-Object { $_.id -eq $Project })[0]
$Relationship = @($Report.relationships | Where-Object { $_.id -eq 'twin-reads-blueprint' })[0]
$TargetPath = Get-TargetPath -Entry $ProjectConfig
$Blockers = [Collections.Generic.List[string]]::new()

Write-Host "Pruefe strategische Zielausrichtung fuer '$Project' ..."
$goalOutput = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $GoalReviewPath 2>&1)
$goalExitCode = $LASTEXITCODE
$goalOutput | ForEach-Object { Write-Host $_ }

if ($goalExitCode -ne 0) {
    $Blockers.Add("Die strategische Zielpruefung endete mit Rueckgabecode $goalExitCode.")
}
elseif (-not (Test-Path -LiteralPath $GoalReportPath -PathType Leaf)) {
    $Blockers.Add('Die strategische Zielpruefung hat keinen maschinenlesbaren Bericht erzeugt.')
}
else {
    $GoalReport = Get-Content -LiteralPath $GoalReportPath -Raw | ConvertFrom-Json
    $ProjectGoalResult = @($GoalReport.projects | Where-Object { $_.id -eq $Project })[0]
    $RelationshipGoalResult = @($GoalReport.relationships | Where-Object { $_.id -eq 'twin-reads-blueprint' })[0]

    if ($null -eq $ProjectGoalResult) {
        $Blockers.Add('Projekt fehlt im strategischen Zielbericht.')
    }
    elseif ($ProjectGoalResult.status -eq 'ROT') {
        $Blockers.Add("Die strategische Projektziel-Pruefstufe ist ROT: $Project.")
        foreach ($finding in @($ProjectGoalResult.findings | Where-Object { $_.severity -eq 'high' })) {
            $Blockers.Add("$($finding.code): $($finding.message)")
        }
    }

    if ($null -eq $RelationshipGoalResult) {
        $Blockers.Add('Zusammenspiel fehlt im strategischen Zielbericht.')
    }
    elseif ($RelationshipGoalResult.status -eq 'ROT') {
        $Blockers.Add('Die strategische Twin-Blueprint-Zielpruefung ist ROT.')
        foreach ($finding in @($RelationshipGoalResult.findings | Where-Object { $_.severity -eq 'high' })) {
            $Blockers.Add("$($finding.code): $($finding.message)")
        }
    }
}

Write-Host 'Pruefe die vollstaendig deutsche Kontrolloberflaeche ...'
$languageOutput = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $GermanSurfaceCheckPath 2>&1)
$languageExitCode = $LASTEXITCODE
$languageOutput | ForEach-Object { Write-Host $_ }
if ($languageExitCode -ne 0) {
    $Blockers.Add("Die Deutsch-Pruefung endete mit Rueckgabecode $languageExitCode.")
}

if ($null -eq $ProjectResult) { $Blockers.Add('Projekt fehlt im aktuellen Pruefbericht.') }
if ($auditExitCode -ne 0 -and $null -eq $ProjectResult) { $Blockers.Add("Der technische Pruefprozess endete mit Rueckgabecode $auditExitCode.") }

if ($null -ne $ProjectResult) {
    if ($ProjectResult.status -ne 'GRUEN') { $Blockers.Add("Projektstatus ist $($ProjectResult.status), nicht GRUEN.") }
    if ($ProjectResult.validation -ne 'passed') { $Blockers.Add('Die abgeschottete technische Pruefung ist nicht bestanden.') }
    if ($ProjectResult.targetUnchanged -ne $true) { $Blockers.Add('Unveraendertheitsnachweis des Zielprojekts fehlt.') }
    if ($ProjectResult.dirty -eq $true) { $Blockers.Add('Arbeitsbaum ist nicht sauber.') }
    if ($ProjectResult.hasCommit -ne $true) { $Blockers.Add('Es existiert kein uebergabefaehiger Commit.') }
}

if ($null -eq $Relationship -or $Relationship.status -ne 'passed') {
    $relationStatus = if ($null -eq $Relationship) { 'fehlt' } elseif ($Relationship.status -eq 'failed') { 'fehlgeschlagen' } elseif ($Relationship.status -eq 'warning') { 'mit Warnungen' } else { 'nicht bestanden' }
    $Blockers.Add("Die Twin-Blueprint-Vertragspruefung ist $relationStatus.")
}

if ($null -eq $ProjectConfig.publish -or $ProjectConfig.publish.enabled -ne $true) {
    $reason = if ($null -ne $ProjectConfig.publish -and $ProjectConfig.publish.blockReason) {
        [string]$ProjectConfig.publish.blockReason
    }
    else { 'Die Veroeffentlichung ist nicht aktiviert.' }
    $Blockers.Add($reason)
}

$remote = if ($null -ne $ProjectConfig.publish) { [string]$ProjectConfig.publish.remote } else { '' }
$branch = if ($null -ne $ProjectConfig.publish) { [string]$ProjectConfig.publish.branch } else { '' }
$expectedPushUrl = if ($null -ne $ProjectConfig.publish) { [string]$ProjectConfig.publish.expectedPushUrl } else { '' }

if ([string]::IsNullOrWhiteSpace($remote)) { $Blockers.Add('Kein Git-Ziel fuer die Veroeffentlichung konfiguriert.') }
if ([string]::IsNullOrWhiteSpace($branch) -or $branch -notmatch '^[A-Za-z0-9._/-]+$' -or $branch -match '\.\.|@\{') {
    $Blockers.Add('Kein sicherer Zielbranch konfiguriert.')
}
if ([string]::IsNullOrWhiteSpace($expectedPushUrl)) { $Blockers.Add('Die exakte erwartete Push-URL ist nicht bestaetigt.') }

if (-not (Test-Path -LiteralPath $TargetPath -PathType Container)) {
    $Blockers.Add('Zielprojekt ist nicht erreichbar.')
}
else {
    $branchResult = Invoke-GitCapture -Repository $TargetPath -Arguments @('branch', '--show-current')
    $headResult = Invoke-GitCapture -Repository $TargetPath -Arguments @('rev-parse', '--short', 'HEAD')
    $fullHeadResult = Invoke-GitCapture -Repository $TargetPath -Arguments @('rev-parse', 'HEAD')
    $statusResult = Invoke-GitCapture -Repository $TargetPath -Arguments @('status', '--porcelain=v1', '--untracked-files=all')

    if ($branchResult.exitCode -ne 0 -or $branchResult.output -ne $branch) {
        $Blockers.Add("Aktueller Zweig '$($branchResult.output)' stimmt nicht mit '$branch' ueberein.")
    }
    if ($headResult.exitCode -ne 0) {
        $Blockers.Add('HEAD kann nicht gelesen werden.')
    }
    elseif ($null -ne $ProjectResult -and $headResult.output -ne [string]$ProjectResult.commit) {
        $Blockers.Add('HEAD hat sich seit dem technischen Pruefbericht veraendert.')
    }
    if ($statusResult.exitCode -ne 0 -or -not [string]::IsNullOrWhiteSpace($statusResult.output)) {
        $Blockers.Add('Arbeitsbaum ist nach der technischen Pruefung nicht sauber.')
    }

    $reviewFile = [string]$ProjectConfig.reviewFile
    if ([string]::IsNullOrWhiteSpace($reviewFile) -or [IO.Path]::IsPathRooted($reviewFile) -or $reviewFile -match '(^|[\\/])\.\.([\\/]|$)') {
        $Blockers.Add('Keine sichere Pruefdatei konfiguriert.')
    }
    else {
        $reviewPath = Join-Path $TargetPath $reviewFile
        if (-not (Test-Path -LiteralPath $reviewPath -PathType Leaf)) {
            $Blockers.Add("Pruefdatei '$reviewFile' fehlt in der Arbeitskopie.")
        }
        else {
            $reviewWorkingContent = Get-Content -LiteralPath $reviewPath -Raw
            if (-not [string]::IsNullOrWhiteSpace($reviewWorkingContent)) {
                $Blockers.Add("Pruefdatei '$reviewFile' ist in der Arbeitskopie nicht leer.")
            }
        }

        $reviewHeadResult = Invoke-GitCapture -Repository $TargetPath -Arguments @('show', "HEAD:$reviewFile")
        if ($reviewHeadResult.exitCode -ne 0) {
            $Blockers.Add("Pruefdatei '$reviewFile' fehlt im uebergebenen Commit.")
        }
        elseif (-not [string]::IsNullOrWhiteSpace($reviewHeadResult.output)) {
            $Blockers.Add("Pruefdatei '$reviewFile' ist im uebergebenen Commit nicht leer.")
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($remote)) {
        $urlResult = Invoke-GitCapture -Repository $TargetPath -Arguments @('remote', 'get-url', '--push', $remote)
        if ($urlResult.exitCode -ne 0) {
            $Blockers.Add("Das Git-Ziel '$remote' besitzt keine lesbare Veroeffentlichungsadresse.")
        }
        elseif (-not [string]::IsNullOrWhiteSpace($expectedPushUrl) -and $urlResult.output -ne $expectedPushUrl) {
            $Blockers.Add('Konfigurierte und tatsaechliche Push-URL stimmen nicht exakt ueberein.')
        }
    }

    $remoteHead = $null
    if ($Blockers.Count -eq 0) {
        $oldTerminalPrompt = [Environment]::GetEnvironmentVariable('GIT_TERMINAL_PROMPT')
        [Environment]::SetEnvironmentVariable('GIT_TERMINAL_PROMPT', '0')
        try {
            $remoteResult = Invoke-GitCapture -Repository $TargetPath -Arguments @('ls-remote', '--heads', $remote, "refs/heads/$branch")
        }
        finally {
            [Environment]::SetEnvironmentVariable('GIT_TERMINAL_PROMPT', $oldTerminalPrompt)
        }
        if ($remoteResult.exitCode -ne 0) {
            $Blockers.Add('Der Zustand des entfernten Zweigs konnte nicht sicher gelesen werden.')
        }
        elseif (-not [string]::IsNullOrWhiteSpace($remoteResult.output)) {
            $remoteHead = ($remoteResult.output -split '\s+')[0]
            if ($remoteHead -eq $fullHeadResult.output) {
                Write-Host 'Der gepruefte Commit ist bereits im entfernten Repository veroeffentlicht.'
                exit 0
            }
            $ancestor = Invoke-GitCapture -Repository $TargetPath -Arguments @('merge-base', '--is-ancestor', $remoteHead, 'HEAD')
            if ($ancestor.exitCode -ne 0) {
                $Blockers.Add('Der entfernte HEAD ist kein bekannter Vorfahr des lokalen HEAD; die Veroeffentlichung wird blockiert.')
            }
        }
    }
}

if ($Blockers.Count -gt 0) {
    Write-Host ''
    Write-Host 'VEROEFFENTLICHUNG BLOCKIERT:'
    foreach ($blocker in $Blockers) { Write-Host "- $blocker" }
    exit 1
}

if (-not $Execute) {
    Write-Host ''
    Write-Host "VEROEFFENTLICHUNGSBEREIT: $Project / $branch"
    Write-Host 'Es wurde nichts uebertragen. Fuer die echte Veroeffentlichung denselben Aufruf mit -Execute starten.'
    exit 0
}

$oldTerminalPrompt = [Environment]::GetEnvironmentVariable('GIT_TERMINAL_PROMPT')
$oldOptionalLocks = [Environment]::GetEnvironmentVariable('GIT_OPTIONAL_LOCKS')
[Environment]::SetEnvironmentVariable('GIT_TERMINAL_PROMPT', '0')
[Environment]::SetEnvironmentVariable('GIT_OPTIONAL_LOCKS', '0')
try {
    & git -C $TargetPath push --porcelain $remote "HEAD:refs/heads/$branch"
    $pushExitCode = $LASTEXITCODE
}
finally {
    [Environment]::SetEnvironmentVariable('GIT_TERMINAL_PROMPT', $oldTerminalPrompt)
    [Environment]::SetEnvironmentVariable('GIT_OPTIONAL_LOCKS', $oldOptionalLocks)
}

if ($pushExitCode -ne 0) { throw "Die Git-Uebertragung ist mit Rueckgabecode $pushExitCode fehlgeschlagen." }

$verifyResult = Invoke-GitCapture -Repository $TargetPath -Arguments @('ls-remote', '--heads', $remote, "refs/heads/$branch")
$publishedHead = if ($verifyResult.output) { ($verifyResult.output -split '\s+')[0] } else { '' }
if ($verifyResult.exitCode -ne 0 -or $publishedHead -ne $fullHeadResult.output) {
    throw 'Die Uebertragung wurde ausgefuehrt, aber der entfernte Stand konnte nicht bestaetigt werden.'
}

Write-Host "VEROEFFENTLICHUNG ERFOLGREICH: $Project / $branch / $($fullHeadResult.output)"
exit 0
