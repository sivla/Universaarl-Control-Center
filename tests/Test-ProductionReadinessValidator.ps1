[CmdletBinding()]
param()
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest; $env:GIT_OPTIONAL_LOCKS='0'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $root 'scripts/Universaarl-Control.Common.ps1')
. (Join-Path $root 'scripts/Universaarl-Readiness.Validator.ps1')
$contract=Get-Content -LiteralPath (Join-Path $root 'production-readiness.contract.json') -Raw|ConvertFrom-Json
$null=Assert-UniversaarlReadinessContract -Contract $contract
$gate=Get-Content -LiteralPath (Join-Path $root $contract.customerOnboardingGatePath) -Raw|ConvertFrom-Json
$null=Assert-UniversaarlCustomerOnboardingGate -Gate $gate -Contract $contract
function Assert-Throws{param([scriptblock]$Action,[string]$Label)try{&$Action;throw "Negativfall '$Label' wurde nicht abgelehnt."}catch{if($_.Exception.Message -eq "Negativfall '$Label' wurde nicht abgelehnt."){throw}}}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('universaarl-readiness-test-'+[Guid]::NewGuid().ToString('N'))
try{
    New-Item -ItemType Directory -Path $temp|Out-Null
    & git -C $temp init -q; & git -C $temp config user.email 'fixture@example.invalid'; & git -C $temp config user.name 'Readiness Fixture'
    New-Item -ItemType Directory -Path (Join-Path $temp 'proof')|Out-Null
    Set-Content -LiteralPath (Join-Path $temp 'proof/test.md') -Value '# Testnachweis' -Encoding utf8
    Set-Content -LiteralPath (Join-Path $temp 'proof/onboarding.md') -Value '# Onboardingnachweis' -Encoding utf8
    & git -C $temp add -- proof/test.md proof/onboarding.md; & git -C $temp commit -q -m 'fixture'; $commit=(& git -C $temp rev-parse HEAD).Trim()
    $component=@($contract.components|Where-Object projectId -eq 'spectra')[0]
    $positive=[pscustomobject]@{
        schemaVersion=1;kind='universaarl-component-production-readiness';projectId='spectra'
        assessments=[pscustomobject]@{
            platformReady=[pscustomobject]@{status='passed';evidenceMode='technical';evidence=@([pscustomobject]@{kind='test-report';path='proof/test.md'});blockers=@()}
            onboardingReady=[pscustomobject]@{status='passed';evidenceMode='technical';evidence=@([pscustomobject]@{kind='onboarding-runbook';path='proof/onboarding.md'});blockers=@()}
            customerGoLiveReady=[pscustomobject]@{status='not-applicable';evidenceMode='none';evidence=@();blockers=@()}
        }
        distribution=[pscustomobject]@{status='internal-only';licenseDecision='pending';evidence=@()};deploymentBoundary='release-bound-product-tooling'
    }
    $result=Assert-UniversaarlComponentProductionReadiness -Evidence $positive -Component $component -Contract $contract -Repository $temp -Commit $commit
    if(-not $result.readyForCustomerWork -or $result.distributionReady){throw 'Positivfall trennt Arbeits- und Distributionsreife nicht korrekt.'}
    $invalidLive=$positive|ConvertTo-Json -Depth 12|ConvertFrom-Json; $invalidLive.assessments.customerGoLiveReady.status='passed';$invalidLive.assessments.customerGoLiveReady.evidenceMode='simulated';$invalidLive.assessments.customerGoLiveReady.evidence=@([pscustomobject]@{kind='real-tenant';path='proof/test.md'})
    Assert-Throws { $null=Assert-UniversaarlComponentProductionReadiness -Evidence $invalidLive -Component $component -Contract $contract -Repository $temp -Commit $commit } 'Spectra erfindet Kunden-Go-live'
    $missing=$positive|ConvertTo-Json -Depth 12|ConvertFrom-Json;$missing.assessments.platformReady.evidence[0].path='proof/fehlt.md'
    Assert-Throws { $null=Assert-UniversaarlComponentProductionReadiness -Evidence $missing -Component $component -Contract $contract -Repository $temp -Commit $commit } 'fehlender Commitnachweis'
    $self=$positive|ConvertTo-Json -Depth 12|ConvertFrom-Json;$self.assessments.platformReady.evidence[0].path='release/production-readiness.json'
    Assert-Throws { $null=Assert-UniversaarlComponentProductionReadiness -Evidence $self -Component $component -Contract $contract -Repository $temp -Commit $commit } 'Readiness-Selbstreferenz'
    $blueprintComponent=@($contract.components|Where-Object projectId -eq 'blueprint')[0];$fake=$positive|ConvertTo-Json -Depth 12|ConvertFrom-Json
    $fake.projectId='blueprint';$fake.deploymentBoundary='customer-source-of-truth';$fake.assessments.customerGoLiveReady.status='passed';$fake.assessments.customerGoLiveReady.evidenceMode='real';$fake.assessments.customerGoLiveReady.evidence=@([pscustomobject]@{kind='real-tenant';path='proof/test.md'})
    Assert-Throws { $null=Assert-UniversaarlComponentProductionReadiness -Evidence $fake -Component $blueprintComponent -Contract $contract -Repository $temp -Commit $commit } 'unvollstaendiger realer Go-live'
    $invalidGate=$gate|ConvertTo-Json -Depth 12|ConvertFrom-Json;$invalidGate.billing.budgetCeilingExclusive=10001
    Assert-Throws { $null=Assert-UniversaarlCustomerOnboardingGate -Gate $invalidGate -Contract $contract } 'Budget oberhalb Zielkorridor'
}finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}}
Write-Output 'Produktionsreife-Validator bestanden: Arbeits-, Distributions- und reale Kunden-Go-live-Reife sind getrennt und fail-closed.'
