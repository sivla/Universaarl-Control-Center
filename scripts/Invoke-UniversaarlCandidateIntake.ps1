[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SpectraCommit,
    [Parameter(Mandatory)][string]$BlueprintCommit,
    [Parameter(Mandatory)][string]$TwinCommit,
    [string]$SpectraVersion = '0.1.0-alpha.1',
    [switch]$RunValidations,
    [string]$RunId,
    [string]$OutputRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ControlRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
. (Join-Path $PSScriptRoot 'Universaarl-Control.Common.ps1')
foreach ($sha in @($SpectraCommit,$BlueprintCommit,$TwinCommit)) { Assert-FullCommitSha $sha }
if ([string]::IsNullOrWhiteSpace($RunId)) { $RunId = New-UniversaarlRunId -Prefix 'intake' }
Assert-UniversaarlRunId $RunId
if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = Join-Path $ControlRoot 'reports\intake' }
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
if (-not $OutputRoot.StartsWith($ControlRoot + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Intake-Ausgabe muss innerhalb des Kontrollzentrums liegen.' }
$null = Initialize-UniversaarlSafeDirectory -TrustedRoot $ControlRoot -Directory $OutputRoot

$config = Get-Content -LiteralPath (Join-Path $ControlRoot 'monitor.config.json') -Raw | ConvertFrom-Json
Assert-UniversaarlMonitorConfiguration $config
$blueprintConfig = @($config.projects | Where-Object id -eq 'blueprint')[0]
$twinConfig = @($config.projects | Where-Object id -eq 'project-twin')[0]
$spectraConfig = $config.verificationSources.bcprojectos
$blueprintPath = Get-UniversaarlConfiguredPath $blueprintConfig
$twinPath = Get-UniversaarlConfiguredPath $twinConfig
$spectraPath = Get-UniversaarlConfiguredPath $spectraConfig

$expected = [ordered]@{ spectra=$SpectraCommit; blueprint=$BlueprintCommit; 'project-twin'=$TwinCommit }
$paths = [ordered]@{ spectra=$spectraPath; blueprint=$blueprintPath; 'project-twin'=$twinPath }
$fingerprints = [ordered]@{}
foreach ($id in $paths.Keys) {
    $fingerprint = Get-UniversaarlRepositoryFingerprint -Repository $paths[$id]
    if ($fingerprint.head -cne $expected[$id]) { throw "INTAKE_COMMIT_MISMATCH: $id" }
    if ($fingerprint.dirty) { throw "INTAKE_WORKTREE_DIRTY: $id" }
    $fingerprints[$id] = $fingerprint
}

$spectraProof = Test-UniversaarlSpectraCandidate -Repository $spectraPath -Commit $SpectraCommit -Version $SpectraVersion
$auditRunId = "$RunId-audit"
$auditRoot = Join-Path $OutputRoot "$RunId-audit"
$auditArguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'Invoke-UniversaarlAudit.ps1'),'-RunId',$auditRunId,'-ReportRoot',$auditRoot)
if ($RunValidations) { $auditArguments += '-RunValidations' }
& powershell @auditArguments
$auditExitCode = $LASTEXITCODE
if (-not (Test-UniversaarlBoundReportExitCode $auditExitCode)) { throw 'INTAKE_AUDIT_INCOMPLETE' }
$auditPath = Join-Path $auditRoot "runs\$auditRunId.json"
$audit = Read-UniversaarlBoundReport -Path $auditPath -RunId $auditRunId -Kind audit -TrustedRoot $auditRoot
if ($audit.verificationInputs.bcprojectos.sourceCommit -cne $SpectraCommit -or $audit.inputShas.blueprint -cne $BlueprintCommit -or $audit.inputShas.'project-twin' -cne $TwinCommit) { throw 'INTAKE_AUDIT_SHA_MISMATCH' }

$projectDecisions = [Collections.Generic.List[object]]::new()
foreach ($id in @('blueprint','project-twin')) {
    $project = @($audit.projects | Where-Object id -eq $id)[0]
    $ready = $RunValidations -and $project.validation -ceq 'passed' -and $project.germanValidation -ceq 'passed' -and $project.targetUnchanged -eq $true -and $project.reviewHeadEmpty -eq $true -and $project.reviewWorkingEmpty -eq $true
    $projectDecisions.Add([pscustomobject]@{ projectId=$id; commit=$expected[$id]; mergeDecision=if($ready){'READY_FOR_SEPARATE_APPROVAL'}else{'BLOCKED'}; reason=if($ready){'Commitgebundene Technik-, Deutsch-, REVIEW- und Unveraendertheitspruefung bestanden.'}elseif(-not $RunValidations){'Technische Validierungen wurden nicht ausgefuehrt.'}else{'Mindestens ein Projektgate ist nicht bestanden.'} })
}
$relationships = @($audit.relationships)
$releaseReady = @($relationships | Where-Object { $_.status -cne 'passed' -or $_.fullValidationPassed -ne $true }).Count -eq 0
$decision = [pscustomobject]@{
    schemaVersion=1; kind='candidate-intake'; runId=$RunId; completed=$true; generatedAt=(Get-Date).ToUniversalTime().ToString('o')
    inputs=[pscustomobject]@{ spectra=$SpectraCommit; blueprint=$BlueprintCommit; projectTwin=$TwinCommit }
    spectra=[pscustomobject]@{ commit=$SpectraCommit; version=$SpectraVersion; payloadBundleDigest=$spectraProof.payloadBundleDigest; mergeDecision='READY_FOR_SEPARATE_APPROVAL'; releaseDecision='BLOCKED_PENDING_MERGE_TAG_AND_FINAL_MANIFEST' }
    projects=@($projectDecisions)
    relationships=@($relationships | ForEach-Object { [pscustomobject]@{ id=$_.id; status=$_.status; fullValidationPassed=$_.fullValidationPassed } })
    centralDecision=if($releaseReady){'READY_FOR_SEPARATE_RELEASE_APPROVAL'}else{'RELEASE_BLOCKED'}
    targetRepositoriesChanged=$false
}
$jsonPath = Join-Path $OutputRoot "$RunId.json"
$markdownPath = Join-Path $OutputRoot "$RunId.md"
$null = Write-UniversaarlNewUtf8File -TrustedRoot $ControlRoot -Path $jsonPath -Text ($decision | ConvertTo-Json -Depth 10)
$lines = @('# Universaarl Kandidatenannahme','',"- Lauf: ``$RunId``","- Spectra: ``$SpectraCommit`` / **$($decision.spectra.mergeDecision)**","- BC Basic: ``$BlueprintCommit`` / **$($decision.projects[0].mergeDecision)**","- Project Twin: ``$TwinCommit`` / **$($decision.projects[1].mergeDecision)**","- Zentrale Releaseentscheidung: **$($decision.centralDecision)**",'', '> Merge, Tag und Release benoetigen weiterhin eine separate Freigabe.')
$null = Write-UniversaarlNewUtf8File -TrustedRoot $ControlRoot -Path $markdownPath -Text ($lines -join "`r`n")
$decision | ConvertTo-Json -Depth 10
if ($decision.centralDecision -ceq 'RELEASE_BLOCKED') { exit 1 }
exit 0
