Set-StrictMode -Version Latest

function Assert-UniversaarlReadinessExactProperties {
    param([Parameter(Mandatory)]$Value, [Parameter(Mandatory)][string[]]$Names, [Parameter(Mandatory)][string]$Label)
    $actual = @($Value.PSObject.Properties | ForEach-Object { [string]$_.Name })
    if ($actual.Count -ne $Names.Count -or @($actual | Where-Object { $_ -notin $Names }).Count -gt 0 -or @($Names | Where-Object { $_ -notin $actual }).Count -gt 0) {
        throw "$Label besitzt fehlende oder unbekannte Felder."
    }
}

function Assert-UniversaarlReadinessContract {
    param([Parameter(Mandatory)]$Contract)
    Assert-UniversaarlReadinessExactProperties -Value $Contract -Names @('schemaVersion','kind','customerOnboardingGatePath','readinessLevels','evidenceKinds','requiredRealCustomerEvidenceKinds','components') -Label 'Produktionsreifevertrag'
    if ($Contract.schemaVersion -isnot [int] -or $Contract.schemaVersion -ne 1 -or $Contract.kind -cne 'universaarl-production-readiness-contract') { throw 'Produktionsreifevertrag besitzt keine bekannte Identitaet.' }
    $onboardingGatePath = Assert-SafeRepositoryRelativePath -Path ([string]$Contract.customerOnboardingGatePath)
    if ($onboardingGatePath -cne 'release/real-customer-onboarding-gate-v1.json') { throw 'Der reale Kunden-Onboarding-Gatevertrag besitzt keinen kanonischen Pfad.' }
    $levels = @($Contract.readinessLevels); $expectedLevels = @('platformReady','onboardingReady','customerGoLiveReady')
    if ($levels.Count -ne 3 -or @($levels | Sort-Object -Unique).Count -ne 3 -or @($expectedLevels | Where-Object { $_ -notin $levels }).Count -gt 0) { throw 'Produktionsreifevertrag muss exakt Plattform-, Onboarding- und Kunden-Go-live-Reife trennen.' }
    Assert-UniversaarlReadinessExactProperties -Value $Contract.evidenceKinds -Names $expectedLevels -Label 'Evidence-Katalog'
    foreach ($level in $expectedLevels) {
        $kinds = @($Contract.evidenceKinds.$level)
        if ($kinds.Count -lt 1 -or @($kinds | Sort-Object -Unique).Count -ne $kinds.Count -or @($kinds | Where-Object { $_ -isnot [string] -or $_ -notmatch '^[a-z][a-z0-9-]+$' }).Count -gt 0) { throw "Evidence-Katalog fuer '$level' ist leer, doppelt oder ungueltig." }
    }
    $requiredReal = @($Contract.requiredRealCustomerEvidenceKinds)
    if ($requiredReal.Count -ne 8 -or @($requiredReal | Sort-Object -Unique).Count -ne 8 -or @($requiredReal | Where-Object { $_ -notin @($Contract.evidenceKinds.customerGoLiveReady) }).Count -gt 0) { throw 'Pflichtnachweise fuer einen realen Kunden-Go-live sind unvollstaendig oder widerspruechlich.' }
    $components = @($Contract.components); $expectedProjects = @('spectra','blueprint','project-twin','control-center')
    if ($components.Count -ne 4 -or @($components.projectId | Sort-Object -Unique).Count -ne 4 -or @($expectedProjects | Where-Object { $_ -notin @($components.projectId) }).Count -gt 0) { throw 'Produktionsreifevertrag muss exakt die vier Universaarl-Komponenten enthalten.' }
    foreach ($component in $components) {
        Assert-UniversaarlReadinessExactProperties -Value $component -Names @('projectId','repositorySelector','evidencePath','customerGoLivePolicy','deploymentBoundary') -Label "Komponente '$($component.projectId)'"
        if ($component.repositorySelector -notin @('verificationSources.bcprojectos','projects.blueprint','projects.project-twin','self')) { throw "Komponente '$($component.projectId)' besitzt keine erlaubte Repositoryauswahl." }
        $safePath = Assert-SafeRepositoryRelativePath -Path ([string]$component.evidencePath)
        if ($safePath -match '(^|/)\.env[^/]*$' -or $safePath -match '\.(pem|pfx|p12|key)$') { throw 'Produktionsreife-Evidence darf keinen sensiblen Pfad verwenden.' }
        if ($component.customerGoLivePolicy -notin @('not-applicable','real-evidence-only','source-dependent')) { throw "Komponente '$($component.projectId)' besitzt keine erlaubte Kunden-Go-live-Policy." }
        if ([string]::IsNullOrWhiteSpace([string]$component.deploymentBoundary)) { throw 'Deploymentgrenze fehlt.' }
    }
    $expectedComponentBindings=@{
        'spectra'=@('verificationSources.bcprojectos','release/production-readiness.json','not-applicable','release-bound-product-tooling')
        'blueprint'=@('projects.blueprint','governance/production-readiness.json','real-evidence-only','customer-source-of-truth')
        'project-twin'=@('projects.project-twin','operations/production-readiness.json','source-dependent','local-loopback-single-operator')
        'control-center'=@('self','release/control-center-production-readiness.json','not-applicable','independent-read-only-verifier')
    }
    foreach($component in $components){$expected=$expectedComponentBindings[[string]$component.projectId];if($component.repositorySelector -cne $expected[0] -or $component.evidencePath -cne $expected[1] -or $component.customerGoLivePolicy -cne $expected[2] -or $component.deploymentBoundary -cne $expected[3]){throw "Komponentenbindung fuer '$($component.projectId)' weicht vom kanonischen Vertrag ab."}}
    if (@($components | Where-Object projectId -eq 'blueprint')[0].customerGoLivePolicy -cne 'real-evidence-only') { throw 'Nur die Kundeninstanz darf einen realen Kunden-Go-live nachweisen.' }
    $true
}

function Assert-UniversaarlCustomerOnboardingGate {
    param([Parameter(Mandatory)]$Gate,[Parameter(Mandatory)]$Contract)
    Assert-UniversaarlReadinessExactProperties -Value $Gate -Names @('schemaVersion','kind','projectType','billing','phases','gates','officialSources') -Label 'Kunden-Onboarding-Gate'
    if ($Gate.schemaVersion -isnot [int] -or $Gate.schemaVersion -ne 1 -or $Gate.kind -cne 'universaarl-real-customer-onboarding-gate' -or $Gate.projectType -cne 'business-central-basic') { throw 'Kunden-Onboarding-Gate besitzt keine bekannte Identitaet.' }
    Assert-UniversaarlReadinessExactProperties -Value $Gate.billing -Names @('currency','budgetCeilingExclusive','billingModel','worklogLevel','frequency','changeControlRequired') -Label 'Abrechnungsvertrag'
    if ($Gate.billing.currency -cne 'EUR' -or $Gate.billing.budgetCeilingExclusive -isnot [int] -or $Gate.billing.budgetCeilingExclusive -ne 10000 -or $Gate.billing.billingModel -cne 'time-and-materials' -or $Gate.billing.worklogLevel -cne 'task' -or $Gate.billing.frequency -cne 'weekly' -or $Gate.billing.changeControlRequired -isnot [bool] -or -not $Gate.billing.changeControlRequired) { throw 'Abrechnungsvertrag muss unter 10.000 EUR, aufgabenbasiert, wochenweise und change-kontrolliert sein.' }
    $phases=@($Gate.phases);$expectedPhases=@('preparation','implementation-week','hypercare-close')
    if($phases.Count -ne 3 -or @($phases.id|Sort-Object -Unique).Count -ne 3 -or @($expectedPhases|Where-Object{$_ -notin @($phases.id)}).Count -gt 0){throw 'Kunden-Onboarding muss exakt drei Phasen besitzen.'}
    foreach($phase in $phases){Assert-UniversaarlReadinessExactProperties -Value $phase -Names @('id','name','duration') -Label "Phase '$($phase.id)'";if([string]::IsNullOrWhiteSpace([string]$phase.name)-or[string]::IsNullOrWhiteSpace([string]$phase.duration)){throw 'Phase besitzt keinen Namen oder keine Dauerannahme.'}}
    $gates=@($Gate.gates)
    if($gates.Count -lt 20 -or @($gates.id|Sort-Object -Unique).Count -ne $gates.Count){throw 'Kunden-Onboarding-Gates sind unvollstaendig oder doppelt.'}
    $realKinds=[Collections.Generic.List[string]]::new()
    foreach($entry in $gates){
        Assert-UniversaarlReadinessExactProperties -Value $entry -Names @('id','phase','readinessLevel','requiredEvidenceMode','ownerRole','ticketRequired','meetingTranscriptRequired','evidenceKind') -Label "Onboarding-Gate '$($entry.id)'"
        if($entry.id -notmatch '^[a-z][a-z0-9-]+$' -or $entry.phase -notin $expectedPhases -or $entry.readinessLevel -notin @('onboardingReady','customerGoLiveReady') -or $entry.ownerRole -notmatch '^[a-z][a-z0-9-]+$' -or $entry.ticketRequired -isnot [bool] -or -not $entry.ticketRequired -or $entry.meetingTranscriptRequired -isnot [bool]){throw "Onboarding-Gate '$($entry.id)' besitzt ungueltige Pflichtfelder."}
        if($entry.readinessLevel -eq 'onboardingReady'){
            if($entry.requiredEvidenceMode -cne 'template-or-simulated' -or $entry.evidenceKind -notin @($Contract.evidenceKinds.onboardingReady)){throw "Onboarding-Gate '$($entry.id)' besitzt keine erlaubte vorbereitende Evidence."}
        }else{
            if($entry.requiredEvidenceMode -cne 'real' -or $entry.evidenceKind -notin @($Contract.requiredRealCustomerEvidenceKinds)){throw "Kunden-Go-live-Gate '$($entry.id)' ist nicht strikt real gebunden."}
            $realKinds.Add([string]$entry.evidenceKind)
        }
    }
    foreach($phaseId in $expectedPhases){if(@($gates|Where-Object phase -eq $phaseId).Count -lt 1){throw "Phase '$phaseId' besitzt kein Gate."}}
    if(@($realKinds|Sort-Object -Unique).Count -ne @($Contract.requiredRealCustomerEvidenceKinds).Count -or @($Contract.requiredRealCustomerEvidenceKinds|Where-Object{$_ -notin @($realKinds)}).Count -gt 0){throw 'Reale Kunden-Go-live-Gates decken nicht exakt alle Pflichtnachweise ab.'}
    $sources=@($Gate.officialSources)
    if($sources.Count -lt 8){throw 'Kunden-Onboarding-Gate besitzt zu wenige offizielle Primaerquellen.'}
    foreach($source in $sources){
        Assert-UniversaarlReadinessExactProperties -Value $source -Names @('title','url','accessedAt','useCase','conclusion') -Label 'Offizielle Quelle'
        if($source.url -notmatch '^https://learn\.microsoft\.com/' -or $source.accessedAt -notmatch '^20[0-9]{2}-[0-9]{2}-[0-9]{2}$' -or [string]::IsNullOrWhiteSpace([string]$source.title) -or [string]::IsNullOrWhiteSpace([string]$source.useCase) -or [string]::IsNullOrWhiteSpace([string]$source.conclusion)){throw 'Offizielle Quelle ist unvollstaendig oder nicht als Microsoft-Primaerquelle gebunden.'}
    }
    $true
}

function Assert-UniversaarlReadinessEvidencePath {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$EvidencePath)
    $safePath = Assert-SafeRepositoryRelativePath -Path $Path
    if ($safePath -ceq $EvidencePath) { throw 'Ein Readiness-Nachweis darf nicht nur auf sich selbst verweisen.' }
    if ($safePath -match '(^|/)\.env[^/]*$' -or $safePath -match '\.(pem|pfx|p12|key)$' -or $safePath -match '(^|/)(node_modules|\.runtime)(/|$)') { throw "Evidence-Pfad '$safePath' ist fuer den Kontrollbericht nicht zulaessig." }
    $safePath
}

function Assert-UniversaarlComponentProductionReadiness {
    param([Parameter(Mandatory)]$Evidence,[Parameter(Mandatory)]$Component,[Parameter(Mandatory)]$Contract,[Parameter(Mandatory)][string]$Repository,[Parameter(Mandatory)][string]$Commit)
    Assert-FullCommitSha -Commit $Commit
    Assert-UniversaarlReadinessExactProperties -Value $Evidence -Names @('schemaVersion','kind','projectId','assessments','distribution','deploymentBoundary') -Label "Readiness-Evidence '$($Component.projectId)'"
    if ($Evidence.schemaVersion -isnot [int] -or $Evidence.schemaVersion -ne 1 -or $Evidence.kind -cne 'universaarl-component-production-readiness' -or $Evidence.projectId -cne [string]$Component.projectId) { throw "Readiness-Evidence fuer '$($Component.projectId)' besitzt eine falsche Identitaet." }
    if ($Evidence.deploymentBoundary -cne [string]$Component.deploymentBoundary) { throw "Deploymentgrenze fuer '$($Component.projectId)' widerspricht dem Kontrollvertrag." }
    Assert-UniversaarlReadinessExactProperties -Value $Evidence.assessments -Names @($Contract.readinessLevels) -Label 'Readiness-Bewertungen'
    $assessmentResults = [ordered]@{}
    foreach ($level in @($Contract.readinessLevels)) {
        $assessment = $Evidence.assessments.$level
        Assert-UniversaarlReadinessExactProperties -Value $assessment -Names @('status','evidenceMode','evidence','blockers') -Label "Bewertung '$level'"
        $allowedStatuses = if ($level -eq 'customerGoLiveReady') { @('passed','pending','failed','not-applicable','source-dependent') } else { @('passed','pending','failed') }
        if ($assessment.status -notin $allowedStatuses) { throw "Bewertung '$level' besitzt einen unbekannten Status." }
        if ($assessment.evidenceMode -notin @('technical','simulated','none','real','source')) { throw "Bewertung '$level' besitzt einen unbekannten Evidence-Modus." }
        $blockers = @($assessment.blockers)
        if (@($blockers | Where-Object { $_ -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) { throw "Bewertung '$level' besitzt einen ungueltigen Blocker." }
        $records = @($assessment.evidence); $seenPaths = @{}; $seenKinds = [Collections.Generic.List[string]]::new()
        foreach ($record in $records) {
            Assert-UniversaarlReadinessExactProperties -Value $record -Names @('kind','path') -Label "Evidence-Record '$level'"
            if ($record.kind -notin @($Contract.evidenceKinds.$level)) { throw "Evidence-Art '$($record.kind)' ist fuer '$level' nicht erlaubt." }
            $safePath = Assert-UniversaarlReadinessEvidencePath -Path ([string]$record.path) -EvidencePath ([string]$Component.evidencePath)
            if ($seenPaths.ContainsKey($safePath)) { throw "Evidence-Pfad '$safePath' ist doppelt." }; $seenPaths[$safePath] = $true; $seenKinds.Add([string]$record.kind)
            $null = Read-UniversaarlCommitText -Repository $Repository -Commit $Commit -Path $safePath -MaximumBytes 1048576 -Required
        }
        if ($assessment.status -eq 'passed' -and ($records.Count -lt 1 -or $blockers.Count -ne 0)) { throw "Bestandene Bewertung '$level' benoetigt Evidence und darf keine Blocker besitzen." }
        if ($assessment.status -in @('pending','failed') -and $blockers.Count -lt 1) { throw "Offene oder fehlgeschlagene Bewertung '$level' muss mindestens einen konkreten Blocker nennen." }
        $assessmentResults[$level] = [pscustomobject]@{ status=[string]$assessment.status; evidenceMode=[string]$assessment.evidenceMode; evidenceCount=$records.Count; blockers=$blockers; evidenceKinds=@($seenKinds) }
    }
    $customer = $Evidence.assessments.customerGoLiveReady
    switch ([string]$Component.customerGoLivePolicy) {
        'not-applicable' { if ($customer.status -cne 'not-applicable' -or $customer.evidenceMode -cne 'none' -or @($customer.evidence).Count -ne 0 -or @($customer.blockers).Count -ne 0) { throw "'$($Component.projectId)' darf keinen eigenen Kunden-Go-live behaupten." } }
        'source-dependent' { if ($customer.status -cne 'source-dependent' -or $customer.evidenceMode -cne 'source' -or @($customer.evidence).Count -ne 0 -or @($customer.blockers).Count -ne 0) { throw 'Project Twin muss den Kunden-Go-live ausschliesslich als quellabhaengig behandeln.' } }
        'real-evidence-only' {
            if ($customer.status -eq 'passed') {
                if ($customer.evidenceMode -cne 'real') { throw 'Kunden-Go-live darf nur mit realer Evidence bestanden sein.' }
                $actualKinds = @($assessmentResults.customerGoLiveReady.evidenceKinds); $missingKinds = @($Contract.requiredRealCustomerEvidenceKinds | Where-Object { $_ -notin $actualKinds })
                if ($missingKinds.Count -gt 0) { throw "Realer Kunden-Go-live vermisst Pflichtnachweise: $($missingKinds -join ', ')." }
            } elseif ($customer.evidenceMode -eq 'real' -and $customer.status -ne 'failed') { throw 'Unvollstaendige reale Go-live-Evidence darf nicht als neutraler Pending-Status erscheinen.' }
        }
    }
    Assert-UniversaarlReadinessExactProperties -Value $Evidence.distribution -Names @('status','licenseDecision','evidence') -Label 'Distributionsbewertung'
    if ($Evidence.distribution.status -notin @('internal-only','approved','blocked') -or $Evidence.distribution.licenseDecision -notin @('pending','approved','not-required')) { throw 'Distributions- oder Lizenzstatus ist unbekannt.' }
    $distributionEvidence = @($Evidence.distribution.evidence)
    foreach ($record in $distributionEvidence) {
        Assert-UniversaarlReadinessExactProperties -Value $record -Names @('kind','path') -Label 'Distributions-Evidence'
        if ($record.kind -cne 'license-decision') { throw 'Distributions-Evidence besitzt eine unbekannte Art.' }
        $safePath = Assert-UniversaarlReadinessEvidencePath -Path ([string]$record.path) -EvidencePath ([string]$Component.evidencePath)
        $null = Read-UniversaarlCommitText -Repository $Repository -Commit $Commit -Path $safePath -MaximumBytes 1048576 -Required
    }
    if ($Evidence.distribution.status -eq 'approved' -and ($Evidence.distribution.licenseDecision -notin @('approved','not-required') -or $distributionEvidence.Count -lt 1)) { throw 'Externe Distribution benoetigt eine ausdrueckliche Lizenzentscheidung mit Evidence.' }
    [pscustomobject]@{
        projectId=[string]$Component.projectId; commit=$Commit; platformReady=$assessmentResults.platformReady; onboardingReady=$assessmentResults.onboardingReady; customerGoLiveReady=$assessmentResults.customerGoLiveReady
        readyForCustomerWork=($assessmentResults.platformReady.status -eq 'passed' -and $assessmentResults.onboardingReady.status -eq 'passed')
        distributionStatus=[string]$Evidence.distribution.status; distributionReady=($Evidence.distribution.status -eq 'approved'); deploymentBoundary=[string]$Evidence.deploymentBoundary
    }
}
