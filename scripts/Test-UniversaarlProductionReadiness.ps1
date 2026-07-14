[CmdletBinding()]
param([switch]$Json,[switch]$AllowPending,[string]$RunId)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$env:GIT_OPTIONAL_LOCKS = '0'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'Universaarl-Control.Common.ps1')
. (Join-Path $PSScriptRoot 'Universaarl-Readiness.Validator.ps1')
if([string]::IsNullOrWhiteSpace($RunId)){$RunId=New-UniversaarlRunId -Prefix 'readiness'}
Assert-UniversaarlRunId -RunId $RunId
$configuration = Get-Content -LiteralPath (Join-Path $root 'monitor.config.json') -Raw | ConvertFrom-Json
Assert-UniversaarlMonitorConfiguration -Configuration $configuration
$controlFingerprintBefore = Get-UniversaarlRepositoryFingerprint -Repository $root
if ($controlFingerprintBefore.dirty) { throw 'Das Kontrollzentrum muss fuer eine commitgebundene Produktionsreifepruefung sauber sein.' }
$controlCommit = [string]$controlFingerprintBefore.head
$contractBlob = Read-UniversaarlCommitText -Repository $root -Commit $controlCommit -Path 'production-readiness.contract.json' -MaximumBytes 262144 -Required
$contract = $contractBlob.content | ConvertFrom-Json
$null = Assert-UniversaarlReadinessContract -Contract $contract
$onboardingGateBlob = Read-UniversaarlCommitText -Repository $root -Commit $controlCommit -Path ([string]$contract.customerOnboardingGatePath) -MaximumBytes 1048576 -Required
$onboardingGate = $onboardingGateBlob.content | ConvertFrom-Json
$null = Assert-UniversaarlCustomerOnboardingGate -Gate $onboardingGate -Contract $contract
$repositories = @{
    'self' = $root
    'verificationSources.bcprojectos' = Get-UniversaarlConfiguredPath -Project $configuration.verificationSources.bcprojectos
    'projects.blueprint' = Get-UniversaarlConfiguredPath -Project (@($configuration.projects | Where-Object id -eq 'blueprint')[0])
    'projects.project-twin' = Get-UniversaarlConfiguredPath -Project (@($configuration.projects | Where-Object id -eq 'project-twin')[0])
}
$initialFingerprints = @{};$dirtySelectors=@{};$preflightFindings=[Collections.Generic.List[object]]::new()
foreach ($selector in $repositories.Keys) {
    $fingerprint = Get-UniversaarlRepositoryFingerprint -Repository ([string]$repositories[$selector])
    if ($fingerprint.dirty) {
        if(-not $AllowPending){throw "Repository '$selector' ist nicht sauber; Produktionsreife wird nicht aus einem Mischstand bewertet."}
        $dirtySelectors[$selector]=$true
        $preflightFindings.Add([pscustomobject]@{projectId=$selector;code='DIRTY_WORKTREE';message='Der lokale Arbeitsbaum ist in Bearbeitung. HEAD kann diagnostisch gelesen, aber nicht freigegeben werden.'})
    }
    $initialFingerprints[$selector] = $fingerprint
}
$components = [Collections.Generic.List[object]]::new(); $findings = [Collections.Generic.List[object]]::new()
foreach($finding in $preflightFindings){$findings.Add($finding)}
foreach ($component in @($contract.components)) {
    $selector=[string]$component.repositorySelector; $repository=[string]$repositories[$selector]; $commit=[string]$initialFingerprints[$selector].head
    try {
        $evidenceBlob = Read-UniversaarlCommitText -Repository $repository -Commit $commit -Path ([string]$component.evidencePath) -MaximumBytes 262144 -Required
        $evidence = $evidenceBlob.content | ConvertFrom-Json
        $result = Assert-UniversaarlComponentProductionReadiness -Evidence $evidence -Component $component -Contract $contract -Repository $repository -Commit $commit
        if($dirtySelectors.ContainsKey($selector)){$result.readyForCustomerWork=$false}
        $components.Add($result)
        if (-not $result.readyForCustomerWork) { $findings.Add([pscustomobject]@{ projectId=$result.projectId; code='NOT_READY_FOR_CUSTOMER_WORK'; message='Plattform- oder Onboarding-Reife ist noch nicht bestanden.' }) }
        if (-not $result.distributionReady) { $findings.Add([pscustomobject]@{ projectId=$result.projectId; code='DISTRIBUTION_NOT_APPROVED'; message='Externe Distribution besitzt noch keine ausdrueckliche Lizenzfreigabe.' }) }
    } catch {
        $message=$_.Exception.Message
        $components.Add([pscustomobject]@{
            projectId=[string]$component.projectId; commit=$commit
            platformReady=[pscustomobject]@{ status='failed'; evidenceMode='none'; evidenceCount=0; blockers=@($message); evidenceKinds=@() }
            onboardingReady=[pscustomobject]@{ status='failed'; evidenceMode='none'; evidenceCount=0; blockers=@($message); evidenceKinds=@() }
            customerGoLiveReady=[pscustomobject]@{ status='pending'; evidenceMode='none'; evidenceCount=0; blockers=@('Readiness-Evidence ist nicht validierbar.'); evidenceKinds=@() }
            readyForCustomerWork=$false; distributionStatus='blocked'; distributionReady=$false; deploymentBoundary=[string]$component.deploymentBoundary
        })
        $findings.Add([pscustomobject]@{ projectId=[string]$component.projectId; code='INVALID_OR_MISSING_READINESS_EVIDENCE'; message=$message })
    }
}
$repositoriesStable=$true
foreach ($selector in $repositories.Keys) {
    $after = Get-UniversaarlRepositoryFingerprint -Repository ([string]$repositories[$selector])
    if (-not (Test-UniversaarlFingerprintEqual -Expected $initialFingerprints[$selector] -Actual $after)) {
        if(-not $AllowPending){throw "Repository '$selector' hat sich waehrend der lesenden Produktionsreifepruefung veraendert."}
        $repositoriesStable=$false
        $findings.Add([pscustomobject]@{projectId=$selector;code='REPOSITORY_CHANGED_DURING_READ';message='Das Repository hat sich waehrend des Diagnose-Laufs veraendert; der Lauf ist keine Freigabeevidence.'})
        $affectedProjectId=[string]@($contract.components|Where-Object repositorySelector -eq $selector)[0].projectId
        foreach($componentResult in @($components|Where-Object projectId -eq $affectedProjectId)){$componentResult.readyForCustomerWork=$false}
    }
}
$portfolioReady=@($components | Where-Object { -not $_.readyForCustomerWork }).Count -eq 0
$distributionReady=@($components | Where-Object { -not $_.distributionReady }).Count -eq 0
$blueprintResult=@($components | Where-Object projectId -eq 'blueprint')[0]
$customerGoLiveReady=$blueprintResult.customerGoLiveReady.status -eq 'passed'
$passedWorkLevels=0
foreach($componentResult in $components){if($componentResult.platformReady.status -eq 'passed'){$passedWorkLevels++};if($componentResult.onboardingReady.status -eq 'passed'){$passedWorkLevels++}}
$evidenceCoverage=[int][Math]::Floor(($passedWorkLevels/8)*100)
$inputShas=[ordered]@{}
foreach($componentResult in $components){$inputShas[[string]$componentResult.projectId]=[string]$componentResult.commit}
$report=[pscustomobject]@{
    schemaVersion=1; kind='universaarl-production-readiness-report'; runId=$RunId; completed=$true; generatedAt=(Get-Date).ToUniversalTime().ToString('o'); controlCommit=$controlCommit; evidenceCoverage=$evidenceCoverage; inputShas=[pscustomobject]$inputShas
    portfolioWorkStatus=if($portfolioReady){'PORTFOLIO_READY_FOR_CUSTOMER_WORK'}else{'PORTFOLIO_NOT_READY_FOR_CUSTOMER_WORK'}
    distributionStatus=if($distributionReady){'DISTRIBUTION_APPROVED'}else{'DISTRIBUTION_NOT_FULLY_APPROVED'}
    customerGoLiveStatus=if($customerGoLiveReady){'CUSTOMER_GO_LIVE_READY'}else{'PENDING_REAL_CUSTOMER_EVIDENCE'}
    components=@($components); findings=@($findings)
    safety=[pscustomobject]@{ commitBoundReads=$true; gitOptionalLocksDisabled=$true; allRepositoriesClean=($dirtySelectors.Count -eq 0); repositoriesStableDuringRead=$repositoriesStable; realEnvironmentFilesRead=$false; targetWritesPerformed=$false }
}
$reportRoot=[IO.Path]::GetFullPath((Join-Path $root ([string]$configuration.reportDirectory)))
if(-not (Test-UniversaarlPathWithinRoot -Root $root -Path $reportRoot)){throw 'Readiness-Berichtverzeichnis liegt ausserhalb des Kontrollzentrums.'}
$runRoot=Join-Path $reportRoot 'readiness-runs';$directoryLock=Open-UniversaarlLockedDirectoryChain -Directory $runRoot -Create;Close-UniversaarlDirectoryLock -Lock $directoryLock
$jsonText=$report|ConvertTo-Json -Depth 12
$markdown=[Collections.Generic.List[string]]::new();$markdown.Add('# Universaarl Produktionsreife');$markdown.Add('');$markdown.Add("- Lauf: ``$RunId``");$markdown.Add("- Zeitpunkt (UTC): ``$($report.generatedAt)``");$markdown.Add("- Portfoliostatus: **$($report.portfolioWorkStatus)**");$markdown.Add("- Kunden-Go-live: **$($report.customerGoLiveStatus)**");$markdown.Add("- Distribution: **$($report.distributionStatus)**");$markdown.Add("- Nachweisabdeckung Plattform/Onboarding: **$evidenceCoverage %**")
foreach($componentResult in $components){$markdown.Add('');$markdown.Add("## $($componentResult.projectId)");$markdown.Add('');$markdown.Add("- Commit: ``$($componentResult.commit)``");$markdown.Add("- Plattform: **$($componentResult.platformReady.status)**");$markdown.Add("- Onboarding: **$($componentResult.onboardingReady.status)**");$markdown.Add("- Kunden-Go-live: **$($componentResult.customerGoLiveReady.status)**");$markdown.Add("- Deploymentgrenze: ``$($componentResult.deploymentBoundary)``")}
if($findings.Count -gt 0){$markdown.Add('');$markdown.Add('## Befunde');$markdown.Add('');foreach($finding in $findings){$markdown.Add("- **$($finding.projectId) / $($finding.code):** $($finding.message)")}}
$markdownText=$markdown -join "`r`n"
$null=Write-UniversaarlNewUtf8File -TrustedRoot $root -Path (Join-Path $runRoot "$RunId.json") -Text $jsonText
$null=Write-UniversaarlNewUtf8File -TrustedRoot $root -Path (Join-Path $runRoot "$RunId.md") -Text $markdownText
$null=Write-UniversaarlAtomicUtf8File -TrustedRoot $root -Path (Join-Path $reportRoot 'readiness-latest.json') -Text $jsonText
$null=Write-UniversaarlAtomicUtf8File -TrustedRoot $root -Path (Join-Path $reportRoot 'readiness-latest.md') -Text $markdownText
if($Json){$report|ConvertTo-Json -Depth 12}else{
    Write-Output $report.portfolioWorkStatus; Write-Output $report.distributionStatus; Write-Output $report.customerGoLiveStatus
    foreach($finding in $report.findings){Write-Output "[$($finding.projectId)/$($finding.code)] $($finding.message)"}
}
if(-not $portfolioReady -and -not $AllowPending){exit 1}; exit 0
