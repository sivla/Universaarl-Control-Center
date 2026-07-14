Set-StrictMode -Version Latest

function Get-UniversaarlGitBlobBytes {
    param([Parameter(Mandatory)][string]$Repository, [Parameter(Mandatory)][string]$Object)
    if ($Object -notmatch '^[0-9a-f]{40,64}$') { throw 'Eine gueltige Git-Blob-ID ist erforderlich.' }
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = 'git'
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $escapedRepository = $Repository.Replace('"','\"')
    $start.Arguments = "-C `"$escapedRepository`" cat-file blob $Object"
    foreach ($name in @($start.Environment.Keys)) {
        if ($name.StartsWith('GIT_', [StringComparison]::OrdinalIgnoreCase) -or $name.StartsWith('GCM_', [StringComparison]::OrdinalIgnoreCase) -or $name -in @('SSH_ASKPASS','SSH_ASKPASS_REQUIRE')) { $null = $start.Environment.Remove($name) }
    }
    $start.Environment['GIT_OPTIONAL_LOCKS'] = '0'; $start.Environment['GIT_TERMINAL_PROMPT'] = '0'
    $process = [Diagnostics.Process]::new(); $process.StartInfo = $start
    $memory = [IO.MemoryStream]::new()
    try {
        if (-not $process.Start()) { throw 'Git-Blobprozess konnte nicht gestartet werden.' }
        $process.StandardOutput.BaseStream.CopyTo($memory)
        $errorText = $process.StandardError.ReadToEnd(); $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw "Git-Blob kann nicht gelesen werden: $errorText" }
        $memory.ToArray()
    }
    finally { $memory.Dispose(); $process.Dispose() }
}

function Get-UniversaarlBytesSha256 {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($algorithm.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $algorithm.Dispose() }
}

function Assert-UniversaarlExactProperties {
    param([Parameter(Mandatory)]$Value, [Parameter(Mandatory)][string[]]$Names, [Parameter(Mandatory)][string]$Label)
    $actual = @($Value.PSObject.Properties | ForEach-Object { [string]$_.Name })
    if ($actual.Count -ne $Names.Count -or @($actual | Where-Object { $_ -notin $Names }).Count -gt 0 -or @($Names | Where-Object { $_ -notin $actual }).Count -gt 0) {
        throw "$Label besitzt fehlende oder unbekannte Felder."
    }
}

function Assert-UniversaarlContractPath {
    param([Parameter(Mandatory)][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path.Contains('\') -or $Path.StartsWith('/') -or $Path.EndsWith('/') -or
        $Path -match '^[A-Za-z]:' -or $Path -match '^[A-Za-z][A-Za-z0-9+.-]*:' -or $Path -match '[\x00-\x1f\x7f]') { throw 'Vertragspfad ist unsicher.' }
    foreach ($segment in $Path.Split('/')) { if ([string]::IsNullOrEmpty($segment) -or $segment -in @('.','..')) { throw 'Vertragspfad enthaelt ein unzulaessiges Segment.' } }
    $Path
}

function Test-UniversaarlGitAncestor {
    param([string]$Repository, [string]$Ancestor, [string]$Descendant)
    Assert-FullCommitSha $Ancestor; Assert-FullCommitSha $Descendant
    (Invoke-UniversaarlGitRead -Repository $Repository -Arguments @('merge-base','--is-ancestor',$Ancestor,$Descendant)).exitCode -eq 0
}

function Resolve-UniversaarlAnnotatedTag {
    param([string]$Repository, [string]$Tag)
    if ($Tag -notmatch '^spectra-v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$') { throw 'Spectra-Tag ist ungueltig.' }
    $type = Invoke-UniversaarlGitRead -Repository $Repository -Arguments @('cat-file','-t',"refs/tags/$Tag")
    if ($type.exitCode -ne 0 -or $type.output -cne 'tag') { throw 'Spectra-Tag fehlt oder ist nicht annotiert.' }
    $resolved = Invoke-UniversaarlGitRead -Repository $Repository -Arguments @('rev-parse',"refs/tags/$Tag`^{commit}")
    if ($resolved.exitCode -ne 0 -or $resolved.output -notmatch '^[0-9a-f]{40}$') { throw 'Spectra-Tag-Commit kann nicht aufgeloest werden.' }
    [string]$resolved.output
}

function Test-UniversaarlSpectraReleaseBinding {
    param([Parameter(Mandatory)][string]$Repository, [Parameter(Mandatory)]$Binding)
    $version = [string]$Binding.releaseVersion; $tag = [string]$Binding.releaseTag
    if ($Binding.bindingStatus -cne 'BOUND' -or $Binding.productId -cne 'spectra' -or $Binding.technicalRepositoryName -cne 'BCProjectOS' -or $Binding.repositoryUrl -cne 'https://github.com/sivla/BCProjectOS.git') { throw 'Spectra-Bindungsidentitaet ist ungueltig.' }
    if ($tag -cne "spectra-v$version") { throw 'Spectra-Version und Tag widersprechen sich.' }
    $tagCommit = Resolve-UniversaarlAnnotatedTag -Repository $Repository -Tag $tag
    if ($tagCommit -cne [string]$Binding.tagCommit) { throw 'Spectra-Tag-Commit widerspricht der Bindung.' }
    Assert-FullCommitSha ([string]$Binding.manifestSourceCommit)
    if (-not (Test-UniversaarlGitAncestor -Repository $Repository -Ancestor ([string]$Binding.manifestSourceCommit) -Descendant $tagCommit)) { throw 'Manifest-Source-Commit ist kein Vorfahr des Tag-Commits.' }
    $manifestBlob = Read-UniversaarlCommitText -Repository $Repository -Commit $tagCommit -Path ([string]$Binding.manifestPath) -MaximumBytes 1048576 -Required
    $manifest = $manifestBlob.content | ConvertFrom-Json
    $manifestSchema = [int]$manifest.schema_version
    if ($manifestSchema -notin @(1,2,3,4)) { throw 'Spectra-Releasemanifest verwendet eine nicht unterstuetzte Schemaversion.' }
    $manifestProperties = @('schema_version','product_id','release_version','release_kind','manifest_state','release_date','expected_tag','source_commit')
    if ($manifestSchema -ge 2) { $manifestProperties += 'source_tree' }
    $manifestProperties += @('consumer_mode','installable_blueprint','blueprint_version','payload','binding_requirements','excluded_from_payload','known_limits')
    Assert-UniversaarlExactProperties $manifest $manifestProperties 'Spectra-Releasemanifest'
    if ($manifest.product_id -cne 'spectra' -or $manifest.release_version -cne $version -or $manifest.expected_tag -cne $tag -or $manifest.source_commit -cne [string]$Binding.manifestSourceCommit -or $manifest.release_kind -cne 'installable_blueprint' -or $manifest.manifest_state -cne 'final' -or $manifest.consumer_mode -cne 'INSTALLABLE_BLUEPRINT' -or $manifest.installable_blueprint -ne $true -or $manifest.blueprint_version -cne $version) { throw 'Spectra-Releasemanifest ist nicht final installierbar oder widerspruechlich.' }
    if ($manifestSchema -ge 2) {
        $sourceTree = Invoke-UniversaarlGitRead -Repository $Repository -Arguments @('rev-parse', "$($Binding.manifestSourceCommit)^{tree}")
        if ($sourceTree.exitCode -ne 0 -or $manifest.source_tree -cne [string]$sourceTree.output) { throw 'Spectra-Source-Tree widerspricht dem Manifest-Source-Commit.' }
    }
    if ($Binding.consumerMode -cne 'INSTALLABLE_BLUEPRINT' -or $Binding.installableBlueprint -ne $true -or $Binding.digestAlgorithm -cne 'SHA-256') { throw 'Spectra-Consumerbindung ist nicht installierbar.' }
    $records = [Collections.Generic.List[object]]::new(); $seen = @{}
    foreach ($file in @($manifest.payload.files)) {
        $path = Assert-UniversaarlContractPath ([string]$file.path)
        if ($seen.ContainsKey($path)) { throw 'Spectra-Payloadpfad ist doppelt.' }; $seen[$path] = $true
        $entry = Get-UniversaarlBlobEntry -Repository $Repository -Commit $tagCommit -Path $path -Required
        $bytes = Get-UniversaarlGitBlobBytes -Repository $Repository -Object $entry.object
        $digest = Get-UniversaarlBytesSha256 $bytes
        if ($entry.size -ne [int64]$file.size_bytes -or $digest -cne [string]$file.sha256) { throw "Spectra-Payload '$path' stimmt nicht mit dem Manifest ueberein (Blob: $($entry.size)/$digest; Manifest: $($file.size_bytes)/$($file.sha256))." }
        if ($manifestSchema -ge 4) {
            if ($file.mode -notmatch '^100(644|755)$' -or $entry.mode -cne [string]$file.mode) { throw "Spectra-Payload '$path' besitzt keinen passenden gebundenen Git-Modus." }
            $records.Add([pscustomobject]@{ path=$path; line="$digest  $($file.mode)  $path" })
        }
        else { $records.Add([pscustomobject]@{ path=$path; line="$digest  $path" }) }
        $sourceEntry = Get-UniversaarlBlobEntry -Repository $Repository -Commit ([string]$Binding.manifestSourceCommit) -Path $path -Required
        if ($sourceEntry.object -cne $entry.object -or $sourceEntry.mode -cne $entry.mode) { throw "Spectra-Payload '$path' wurde nach dem Source-Commit veraendert." }
    }
    if ($records.Count -ne [int]$manifest.payload.file_count) { throw 'Spectra-Payloadanzahl ist ungueltig.' }
    $sorted = @($records); [Array]::Sort($sorted, [Comparison[object]]{ param($left,$right) [StringComparer]::Ordinal.Compare([string]$left.path,[string]$right.path) })
    $checksumBytes = [Text.UTF8Encoding]::new($false).GetBytes(((@($sorted | ForEach-Object line)) -join "`n") + "`n")
    $bundle = Get-UniversaarlBytesSha256 $checksumBytes
    if ($bundle -cne [string]$manifest.payload.bundle_digest -or $bundle -cne [string]$Binding.payloadBundleDigest) { throw 'Spectra-Payload-Bundledigest stimmt nicht ueberein.' }
    [pscustomobject]@{ status='passed'; fullValidationPassed=$true; tagCommit=$tagCommit; manifestSourceCommit=[string]$Binding.manifestSourceCommit; payloadBundleDigest=$bundle }
}

function Test-UniversaarlSpectraCandidate {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$Commit,
        [Parameter(Mandatory)][string]$Version
    )
    Assert-FullCommitSha $Commit
    if ($Version -notmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$') { throw 'Spectra-Candidate-Version ist ungueltig.' }
    $manifestPath = "release/versions/$Version/release-manifest.json"
    $manifest = (Read-UniversaarlCommitText -Repository $Repository -Commit $Commit -Path $manifestPath -MaximumBytes 1048576 -Required).content | ConvertFrom-Json
    Assert-UniversaarlExactProperties $manifest @('schema_version','product_id','release_version','release_kind','manifest_state','release_date','expected_tag','source_commit','consumer_mode','installable_blueprint','blueprint_version','payload','binding_requirements','excluded_from_payload','known_limits') 'Spectra-Candidate-Manifest'
    if ($manifest.schema_version -ne 1 -or $manifest.product_id -cne 'spectra' -or $manifest.release_version -cne $Version -or
        $manifest.release_kind -cne 'installable_blueprint' -or $manifest.manifest_state -cne 'candidate' -or
        $manifest.expected_tag -cne "spectra-v$Version" -or $null -ne $manifest.source_commit -or
        $manifest.consumer_mode -cne 'INSTALLABLE_BLUEPRINT' -or $manifest.installable_blueprint -ne $true -or
        $manifest.blueprint_version -cne $Version -or $manifest.payload.digest_algorithm -cne 'SHA-256') {
        throw 'Spectra-Candidate ist nicht konsistent installierbar oder behauptet bereits eine Releasebindung.'
    }
    $records = [Collections.Generic.List[object]]::new()
    $seen = @{}
    foreach ($file in @($manifest.payload.files)) {
        $path = Assert-UniversaarlContractPath ([string]$file.path)
        if ($seen.ContainsKey($path)) { throw 'Spectra-Candidate-Payloadpfad ist doppelt.' }
        $seen[$path] = $true
        $entry = Get-UniversaarlBlobEntry -Repository $Repository -Commit $Commit -Path $path -Required
        $bytes = Get-UniversaarlGitBlobBytes -Repository $Repository -Object $entry.object
        $digest = Get-UniversaarlBytesSha256 $bytes
        if ($entry.size -ne [int64]$file.size_bytes -or $digest -cne [string]$file.sha256) { throw "Spectra-Candidate-Payload '$path' stimmt nicht mit dem Commit ueberein." }
        $records.Add([pscustomobject]@{ path=$path; line="$digest  $path" })
    }
    if ($records.Count -ne [int]$manifest.payload.file_count) { throw 'Spectra-Candidate-Payloadanzahl ist ungueltig.' }
    $sorted = @($records); [Array]::Sort($sorted, [Comparison[object]]{ param($left,$right) [StringComparer]::Ordinal.Compare([string]$left.path,[string]$right.path) })
    $checksumsText = ((@($sorted | ForEach-Object line)) -join "`n") + "`n"
    $bundle = Get-UniversaarlBytesSha256 ([Text.UTF8Encoding]::new($false).GetBytes($checksumsText))
    if ($bundle -cne [string]$manifest.payload.bundle_digest) { throw 'Spectra-Candidate-Bundledigest stimmt nicht ueberein.' }
    $checksumsPath = "release/versions/$Version/$($manifest.payload.checksums_file)"
    $storedChecksums = Read-UniversaarlCommitText -Repository $Repository -Commit $Commit -Path $checksumsPath -MaximumBytes 1048576 -Required
    if ([string]$storedChecksums.content -cne $checksumsText.TrimEnd("`n")) { throw 'Spectra-Candidate-Checksums stimmen nicht exakt mit den Git-Blobs ueberein.' }
    [pscustomobject]@{ status='passed'; fullValidationPassed=$true; commit=$Commit; version=$Version; expectedTag="spectra-v$Version"; payloadBundleDigest=$bundle; fileCount=$records.Count }
}

function Test-UniversaarlBranchIndex {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$Commit,
        [Parameter(Mandatory)][string]$ExpectedBranch
    )
    Assert-FullCommitSha $Commit
    if ($ExpectedBranch -cne 'codex/universaarl-projekt') { throw 'Der erlaubte BC-Basic-Branch ist ungueltig.' }

    $indexPath = 'exports/project-data/v1/index.yaml'
    $indexEntry = Get-UniversaarlBlobEntry -Repository $Repository -Commit $Commit -Path $indexPath -Required
    if ($indexEntry.mode -cne '100644') { throw 'Der Branch-Index ist kein regulaerer Git-Blob im Modus 100644.' }
    $indexText = (Read-UniversaarlCommitText -Repository $Repository -Commit $Commit -Path $indexPath -MaximumBytes 1048576 -Required).content

    $requiredScalars = [ordered]@{
        schemaVersion = '1'
        contractId = 'UABC-PROJECT-DATA-V1'
        projectId = 'UABC-BC-BASIC-001'
        routeKey = 'bc-basic'
        readOnly = 'true'
        contractRole = 'repository-relative-data-allowlist'
        pathSemantics = 'repository-relative'
        allowedBranch = $ExpectedBranch
        validationStatus = 'branch-commit-validierung-erforderlich'
    }
    foreach ($name in $requiredScalars.Keys) {
        $match = [regex]::Match($indexText, "(?m)^$([regex]::Escape($name)):\s*(?<value>[^#\r\n]+?)\s*$")
        if (-not $match.Success -or $match.Groups['value'].Value -cne [string]$requiredScalars[$name]) {
            throw "Branch-Indexfeld '$name' fehlt oder ist ungueltig."
        }
    }

    $artifactMatches = @([regex]::Matches($indexText, "(?m)^\s*-\s*\{\s*id:\s*(?<id>[^,}\s]+).*?path:\s*(?<path>[^,}\s]+).*?required:\s*(?<required>true|false)\s*\}\s*$"))
    if ($artifactMatches.Count -eq 0) { throw 'Der Branch-Index enthaelt keine Artefakt-Allowlist.' }
    $ids = @{}; $paths = @{}; $records = [Collections.Generic.List[object]]::new()
    foreach ($match in $artifactMatches) {
        $id = [string]$match.Groups['id'].Value
        $path = Assert-UniversaarlContractPath ([string]$match.Groups['path'].Value)
        if ($id -notmatch '^UABC-[A-Z0-9]+(?:-[A-Z0-9]+)*$') { throw "Branch-Index-ID '$id' ist ungueltig." }
        if ($ids.ContainsKey($id)) { throw "Branch-Index-ID '$id' ist doppelt." }; $ids[$id] = $true
        if ($paths.ContainsKey($path)) { throw "Branch-Indexpfad '$path' ist doppelt." }; $paths[$path] = $true
        if ($match.Groups['required'].Value -cne 'true') { throw "Branch-Indexpfad '$path' ist nicht verbindlich erforderlich." }
        $entry = Get-UniversaarlBlobEntry -Repository $Repository -Commit $Commit -Path $path -Required
        if ($entry.mode -cne '100644') { throw "Branch-Indexpfad '$path' ist kein regulaerer Git-Blob im Modus 100644." }
        $bytes = Get-UniversaarlGitBlobBytes -Repository $Repository -Object $entry.object
        $digest = Get-UniversaarlBytesSha256 $bytes
        $records.Add([pscustomobject]@{ path=$path; line="$path`0$($entry.mode)`0$($entry.size)`0$digest`n" })
    }
    foreach ($requiredPath in @('evidence/simulation/phase-2-p2p-o2c.yaml','evidence/simulation/phase-3-cash-inventory-close.yaml')) {
        if (-not $paths.ContainsKey($requiredPath)) { throw "Aktuelle Simulationsevidence '$requiredPath' fehlt in der Allowlist." }
    }
    $ordered = @($records); [Array]::Sort($ordered, [Comparison[object]]{ param($left,$right) [StringComparer]::Ordinal.Compare([string]$left.path,[string]$right.path) })
    $bundleText = (@($ordered | ForEach-Object line) -join '')
    $bundle = Get-UniversaarlBytesSha256 ([Text.UTF8Encoding]::new($false).GetBytes($bundleText))
    [pscustomobject]@{
        status='passed'; fullValidationPassed=$true; providerCommit=$Commit; branch=$ExpectedBranch
        indexPath=$indexPath; indexBlob=$indexEntry.object; artifactCount=$records.Count
        payloadBundleDigest="sha256:$bundle"; access='nur-lesend'; legacySnapshotRequired=$false
    }
}

function Test-UniversaarlPortableSnapshotRelease {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$Commit,
        [Parameter(Mandatory)][string]$SpectraRepository
    )
    Assert-FullCommitSha $Commit
    $pointerPath = 'exports/project-data/v1/snapshots/current.json'
    $pointerEntry = Get-UniversaarlBlobEntry -Repository $Repository -Commit $Commit -Path $pointerPath -Required
    if ($pointerEntry.mode -cne '100644') { throw 'Der Snapshotzeiger ist kein regulaerer Git-Blob im Modus 100644.' }
    $pointerBlob = Read-UniversaarlCommitText -Repository $Repository -Commit $Commit -Path $pointerPath -MaximumBytes 65536 -Required
    $pointer = $pointerBlob.content | ConvertFrom-Json
    Assert-UniversaarlExactProperties $pointer @('schemaVersion','pointerContract','customerId','projectId','currentReleaseId','manifestPath','manifestSha256','bindingStatus','consumerEligible','publishEligible','updatedAt') 'Snapshotzeiger'
    if ($pointer.schemaVersion -ne 1 -or $pointer.pointerContract -cne 'uabc-portable-snapshot-current-v1' -or
        $pointer.customerId -cne 'UABC-CUSTOMER-001' -or $pointer.projectId -cne 'UABC-BC-BASIC-001' -or
        $pointer.currentReleaseId -notmatch '^UABC-PORTABLE-PILOT-[0-9]{4}$' -or
        $pointer.bindingStatus -cne 'BOUND_BCPROJECTOS_RELEASE' -or $pointer.consumerEligible -ne $true -or $pointer.publishEligible -ne $true -or
        $pointer.manifestSha256 -notmatch '^[0-9a-f]{64}$') { throw 'Snapshotzeiger besitzt keine freigegebene portable Identitaet.' }

    $manifestPath = Assert-UniversaarlContractPath ([string]$pointer.manifestPath)
    $releaseRoot = "exports/project-data/v1/snapshots/releases/$($pointer.currentReleaseId)"
    if ($manifestPath -cne "$releaseRoot/manifest.json") { throw 'Snapshotzeiger verweist nicht auf das unveraenderliche Manifest seines Releases.' }
    $manifestEntry = Get-UniversaarlBlobEntry -Repository $Repository -Commit $Commit -Path $manifestPath -Required
    if ($manifestEntry.mode -cne '100644') { throw 'Das portable Snapshotmanifest ist kein regulaerer Git-Blob im Modus 100644.' }
    $manifestBytes = Get-UniversaarlGitBlobBytes -Repository $Repository -Object $manifestEntry.object
    $manifestDigest = Get-UniversaarlBytesSha256 $manifestBytes
    if ($manifestDigest -cne [string]$pointer.manifestSha256) { throw 'Manifestdigest des Snapshotzeigers stimmt nicht mit dem Commitblob ueberein.' }
    $manifest = [Text.UTF8Encoding]::new($false, $true).GetString($manifestBytes) | ConvertFrom-Json
    Assert-UniversaarlExactProperties $manifest @('schemaVersion','manifestContract','releaseId','immutable','producer','consumer','releaseBinding','pathSemantics','byteContract','sourceInventoryDigest','projectData','files','validationStatus') 'Portables Snapshotmanifest'
    if ($manifest.schemaVersion -ne 1 -or $manifest.manifestContract -cne 'uabc-portable-snapshot-release-v1' -or
        $manifest.releaseId -cne $pointer.currentReleaseId -or $manifest.immutable -ne $true -or
        $manifest.pathSemantics -cne 'repository-relative' -or $manifest.byteContract -cne 'identical-canonical-bytes' -or
        $manifest.validationStatus -cne 'validated-release' -or $manifest.sourceInventoryDigest -notmatch '^[0-9a-f]{64}$') {
        throw 'Portables Snapshotmanifest besitzt keine unveraenderliche freigegebene Identitaet.'
    }
    Assert-UniversaarlExactProperties $manifest.producer @('customerId','projectIds','commitShaProvenance') 'Snapshotproduzent'
    if ($manifest.producer.customerId -cne $pointer.customerId -or @($manifest.producer.projectIds).Count -ne 1 -or
        [string]$manifest.producer.projectIds[0] -cne $pointer.projectId) { throw 'Snapshotproduzent widerspricht dem Zeiger.' }

    Assert-UniversaarlExactProperties $manifest.consumer @('consumerId','repositoryUrl','branch','access','authorizationScope') 'Snapshotverbraucher'
    if ($manifest.consumer.consumerId -cne 'project-twin' -or
        $manifest.consumer.repositoryUrl -cne 'https://github.com/sivla/Universaarl-Project-Twin.git' -or
        $manifest.consumer.branch -cne 'codex/universaarl-projekt-twin' -or
        $manifest.consumer.access -cne 'nur-lesend' -or
        $manifest.consumer.authorizationScope -cne 'ausschliesslich-validierte-snapshots-lesen') {
        throw 'Snapshotverbraucher ist nicht der kanonische strikt nur-lesende Project Twin.'
    }

    Assert-UniversaarlExactProperties $manifest.releaseBinding @('bindingStatus','pendingReason','consumerEligible','publishEligible','requiredEvidence','spectraReleaseBinding') 'Snapshot-Releasebindung'
    if ($manifest.releaseBinding.bindingStatus -cne $pointer.bindingStatus -or $null -ne $manifest.releaseBinding.pendingReason -or
        $manifest.releaseBinding.consumerEligible -ne $true -or $manifest.releaseBinding.publishEligible -ne $true) { throw 'Snapshot-Releasebindung ist nicht vollstaendig freigegeben.' }
    $requiredEvidence = @($manifest.releaseBinding.requiredEvidence)
    foreach ($name in @('annotatedTag','peeledCommit','finalManifest','productDigest','platformMatrix')) {
        if ($requiredEvidence -cnotcontains $name) { throw "Snapshot-Releasebindung fordert '$name' nicht an." }
    }
    $spectra = $manifest.releaseBinding.spectraReleaseBinding
    Assert-UniversaarlExactProperties $spectra @('evidencePath','productId','technicalRepositoryName','repositoryUrl','releaseVersion','releaseTag','annotatedTagObject','peeledCommit','manifestPath','manifestSourceCommit','sourceTree','consumerMode','installableBlueprint','digestAlgorithm','payloadBundleDigest','platformEvidenceStatus','platformEvidenceRun') 'Snapshot-Spectra-Bindung'
    foreach ($sha in @([string]$spectra.annotatedTagObject,[string]$spectra.peeledCommit,[string]$spectra.manifestSourceCommit,[string]$spectra.sourceTree)) {
        if ($sha -notmatch '^[0-9a-f]{40}$') { throw 'Snapshot-Spectra-Bindung enthaelt keine vollstaendigen Git-SHAs.' }
    }
    if ($spectra.platformEvidenceStatus -cne 'passed' -or $spectra.platformEvidenceRun -notmatch '^https://github\.com/sivla/BCProjectOS/actions/runs/[0-9]+$') {
        throw 'Snapshot-Spectra-Bindung besitzt keinen bestandenen Plattformnachweis.'
    }
    $tagObject = Invoke-UniversaarlGitRead -Repository $SpectraRepository -Arguments @('rev-parse',"refs/tags/$($spectra.releaseTag)")
    if ($tagObject.exitCode -ne 0 -or $tagObject.output -cne [string]$spectra.annotatedTagObject) { throw 'Annotiertes Spectra-Tagobjekt widerspricht dem Snapshotmanifest.' }
    $bound = [pscustomobject]@{
        bindingStatus='BOUND'; productId=[string]$spectra.productId; technicalRepositoryName=[string]$spectra.technicalRepositoryName
        repositoryUrl=[string]$spectra.repositoryUrl; releaseVersion=[string]$spectra.releaseVersion; releaseTag=[string]$spectra.releaseTag
        tagCommit=[string]$spectra.peeledCommit; manifestPath=[string]$spectra.manifestPath; manifestSourceCommit=[string]$spectra.manifestSourceCommit
        consumerMode=[string]$spectra.consumerMode; installableBlueprint=[bool]$spectra.installableBlueprint; digestAlgorithm=[string]$spectra.digestAlgorithm
        payloadBundleDigest=[string]$spectra.payloadBundleDigest
    }
    $spectraProof = Test-UniversaarlSpectraReleaseBinding -Repository $SpectraRepository -Binding $bound

    Assert-UniversaarlExactProperties $manifest.projectData @('contractId','indexSourcePath','indexPath','sourceCommit','artifactCount') 'Snapshot-Projektdaten'
    if ($manifest.projectData.contractId -cne 'UABC-PROJECT-DATA-V1' -or $manifest.projectData.indexSourcePath -cne 'exports/project-data/v1/index.yaml' -or
        $manifest.projectData.indexPath -cne "$releaseRoot/data/exports/project-data/v1/index.yaml" -or [int]$manifest.projectData.artifactCount -le 0) {
        throw 'Snapshot-Projektdatenvertrag ist ungueltig.'
    }
    $sourceCommit = [string]$manifest.projectData.sourceCommit
    Assert-FullCommitSha $sourceCommit
    if ($sourceCommit -cne [string]$manifest.producer.commitShaProvenance -or -not (Test-UniversaarlGitAncestor -Repository $Repository -Ancestor $sourceCommit -Descendant $Commit)) {
        throw 'Snapshot-Source-Commit ist nicht konsistent oder kein Vorfahr des Releasecommits.'
    }

    $files = @($manifest.files)
    if ($files.Count -ne ([int]$manifest.projectData.artifactCount + 3)) { throw 'Snapshotmanifest enthaelt nicht exakt Projektindex, Projektquellen, Knowledge-Payload und Katalogfragment.' }
    $ids = @{}; $paths = @{}; $sourceRecords = @{}; $kindCounts = @{}
    foreach ($file in $files) {
        Assert-UniversaarlExactProperties $file @('kind','id','sourcePath','format','selector','path','sizeBytes','sha256','transports') 'Snapshotdatei'
        $id = [string]$file.id; $path = Assert-UniversaarlContractPath ([string]$file.path); $kind = [string]$file.kind
        if ($id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,118}[A-Za-z0-9]$' -or $ids.ContainsKey($id)) { throw "Snapshotdatei-ID '$id' ist ungueltig oder doppelt." }
        if ($paths.ContainsKey($path) -or -not $path.StartsWith("$releaseRoot/", [StringComparison]::Ordinal)) { throw "Snapshotdateipfad '$path' ist doppelt oder liegt ausserhalb des Releases." }
        $ids[$id]=$true; $paths[$path]=$true; $kindCounts[$kind]=1+$(if($kindCounts.ContainsKey($kind)){[int]$kindCounts[$kind]}else{0})
        if ([int64]$file.sizeBytes -lt 1 -or $file.sha256 -notmatch '^[0-9a-f]{64}$') { throw "Snapshotdatei '$path' besitzt ungueltige Groesse oder Digest." }
        $entry = Get-UniversaarlBlobEntry -Repository $Repository -Commit $Commit -Path $path -Required
        if ($entry.mode -cne '100644' -or $entry.size -ne [int64]$file.sizeBytes) { throw "Snapshotdatei '$path' ist kein passender regulaerer Commitblob." }
        $bytes = Get-UniversaarlGitBlobBytes -Repository $Repository -Object $entry.object
        if ((Get-UniversaarlBytesSha256 $bytes) -cne [string]$file.sha256) { throw "Snapshotdateidigest fuer '$path' stimmt nicht." }
        $transports=@($file.transports); if($transports.Count-ne 2){throw "Snapshotdatei '$path' besitzt nicht exakt zwei Transporte."}
        $transportTypes=@{}
        foreach($transport in $transports){
            Assert-UniversaarlExactProperties $transport @('type','relativePath','sha256') 'Snapshottransport'
            if($transport.type -notin @('filesystem','https') -or $transportTypes.ContainsKey([string]$transport.type) -or
                $transport.relativePath -cne $path -or $transport.sha256 -cne [string]$file.sha256){throw "Snapshottransport fuer '$path' ist ungueltig."}
            $transportTypes[[string]$transport.type]=$true
        }
        if ($kind -in @('project-index','project-source')) {
            $sourcePath = Assert-UniversaarlContractPath ([string]$file.sourcePath)
            if ($path -cne "$releaseRoot/data/$sourcePath") { throw "Snapshotquellabbildung fuer '$sourcePath' ist ungueltig." }
            $sourceEntry = Get-UniversaarlBlobEntry -Repository $Repository -Commit $sourceCommit -Path $sourcePath -Required
            if ($sourceEntry.mode -cne '100644' -or $sourceEntry.object -cne $entry.object) { throw "Snapshotquellbytes fuer '$sourcePath' sind nicht identisch mit dem Source-Commit." }
            if ($kind -ceq 'project-source') { $sourceRecords[$id]=[pscustomobject]@{ path=$sourcePath; format=[string]$file.format; selector=$file.selector } }
        }
        elseif ($null -ne $file.sourcePath) { throw "Snapshotdatei '$path' darf keinen Quellpfad besitzen." }
    }
    if ($kindCounts['project-index'] -ne 1 -or $kindCounts['project-source'] -ne [int]$manifest.projectData.artifactCount -or
        $kindCounts['knowledge-payload'] -ne 1 -or $kindCounts['catalog-fragment'] -ne 1) { throw 'Snapshotdateiarten oder Anzahlen sind ungueltig.' }

    $indexText = (Read-UniversaarlCommitText -Repository $Repository -Commit $sourceCommit -Path ([string]$manifest.projectData.indexSourcePath) -MaximumBytes 1048576 -Required).content
    $declared = @([regex]::Matches($indexText, '(?ms)^  - id:\s*(?<id>[^\r\n#]+?)\s*\r?\n(?<body>.*?)(?=^  - id:|\z)'))
    if ($declared.Count -ne [int]$manifest.projectData.artifactCount -or $sourceRecords.Count -ne $declared.Count) { throw 'Snapshot-Projektquellenmenge stimmt nicht mit der Index-Allowlist ueberein.' }
    foreach($match in $declared){
        $id=[string]$match.Groups['id'].Value; $body=[string]$match.Groups['body'].Value
        $pathMatch=[regex]::Match($body,'(?m)^    path:\s*(?<value>[^\r\n#]+?)\s*$'); $requiredMatch=[regex]::Match($body,'(?m)^    required:\s*(?<value>true|false)\s*$')
        $formatMatch=[regex]::Match($body,'(?m)^    format:\s*(?<value>[^\r\n#]+?)\s*$')
        if(-not $pathMatch.Success -or -not $requiredMatch.Success -or -not $formatMatch.Success){throw "Index-Allowlist-Eintrag '$id' ist unvollstaendig."}
        $path=[string]$pathMatch.Groups['value'].Value; $format=[string]$formatMatch.Groups['value'].Value
        if($requiredMatch.Groups['value'].Value -cne 'true' -or -not $sourceRecords.ContainsKey($id) -or
            $sourceRecords[$id].path -cne $path -or $sourceRecords[$id].format -cne $format){throw "Snapshot-Projektquelle '$id' widerspricht der Index-Allowlist."}
    }
    $treeEntries = @(Get-UniversaarlCommitTree -Repository $Repository -Commit $Commit | Where-Object { $_.path -ceq $manifestPath -or $_.path.StartsWith("$releaseRoot/", [StringComparison]::Ordinal) })
    if ($treeEntries.Count -ne ($files.Count + 1) -or @($treeEntries | Where-Object { $_.type -cne 'blob' -or $_.mode -cne '100644' }).Count -gt 0) {
        throw 'Snapshotrelease enthaelt zusaetzliche, fehlende oder nicht regulaere Dateien.'
    }
    $payloadRecord=@($files|Where-Object{$_.kind -ceq 'knowledge-payload'})[0]
    $fragmentRecord=@($files|Where-Object{$_.kind -ceq 'catalog-fragment'})[0]
    $payload=(Read-UniversaarlCommitText -Repository $Repository -Commit $Commit -Path ([string]$payloadRecord.path) -MaximumBytes 1048576 -Required).content|ConvertFrom-Json
    if($payload.schemaVersion-ne 1 -or $payload.releaseId-cne $pointer.currentReleaseId -or $payload.customerId-cne $pointer.customerId -or $payload.projectId-cne $pointer.projectId -or
        $payload.truthBoundary.liveExecutionClaimed-ne $false -or $payload.truthBoundary.externalSyncClaimed-ne $false -or $payload.truthBoundary.uncheckedKnowledgePromoted-ne $false){throw 'Knowledge-Payload verletzt Identitaet oder Wahrheitsgrenze.'}
    $fragment=(Read-UniversaarlCommitText -Repository $Repository -Commit $Commit -Path ([string]$fragmentRecord.path) -MaximumBytes 1048576 -Required).content|ConvertFrom-Json
    $projects=@($fragment.projects)
    if($fragment.schemaVersion-ne 1 -or $fragment.fragmentContract-cne 'uabc-customer-project-fragment-v1' -or $fragment.customerId-cne $pointer.customerId -or $fragment.fixtureOnly-ne $false -or
        $projects.Count-ne 1 -or $projects[0].projectId-cne $pointer.projectId -or $projects[0].snapshotReleaseId-cne $pointer.currentReleaseId -or
        $projects[0].consumerEligible-ne $true -or $projects[0].publishEligible-ne $true -or $fragment.payload.path-cne $payloadRecord.path -or
        $fragment.payload.sha256-cne $payloadRecord.sha256 -or [int64]$fragment.payload.sizeBytes-ne [int64]$payloadRecord.sizeBytes -or
        $fragment.projectData.sourceCommit-cne $sourceCommit -or [int]$fragment.projectData.artifactCount-ne [int]$manifest.projectData.artifactCount){throw 'Katalogfragment verletzt Identitaet, Isolation oder Payloadbindung.'}

    [pscustomobject]@{
        status='passed'; fullValidationPassed=$true; providerCommit=$Commit; sourceCommit=$sourceCommit; pointerPath=$pointerPath
        releaseId=[string]$pointer.currentReleaseId; manifestPath=$manifestPath; manifestSha256=$manifestDigest
        sourceInventoryDigest=[string]$manifest.sourceInventoryDigest; artifactCount=[int]$manifest.projectData.artifactCount; fileCount=$files.Count
        customerId=[string]$pointer.customerId; projectId=[string]$pointer.projectId; transports=@('filesystem','https')
        spectraBinding=$bound; spectraProof=$spectraProof; access='nur-lesend'
    }
}

function Test-UniversaarlSnapshotManifest {
    param([Parameter(Mandatory)][string]$Repository, [Parameter(Mandatory)][string]$MetadataCommit, [Parameter(Mandatory)]$ExpectedBinding)
    Assert-FullCommitSha $MetadataCommit
    $parents = @((Invoke-UniversaarlGitRead -Repository $Repository -Arguments @('rev-list','--parents','-n','1',$MetadataCommit)).output -split ' ')
    if ($parents.Count -ne 2) { throw 'Snapshot-Metadatencommit muss genau einen Parent besitzen.' }; $producerCommit = $parents[1]
    $manifestPath = 'exports/project-data/v1/snapshot-manifest.json'
    $changed = @(((Invoke-UniversaarlGitRead -Repository $Repository -Arguments @('diff-tree','--no-commit-id','--name-status','-r','-M',$producerCommit,$MetadataCommit) -PreserveWhitespace).output -split "`n") | Where-Object { $_ })
    if ($changed.Count -ne 1 -or $changed[0] -notmatch '^[AM]\texports/project-data/v1/snapshot-manifest\.json$') { throw 'Snapshot-A/B-Diff enthaelt andere Pfade, Renames oder Deletes.' }
    $manifest = (Read-UniversaarlCommitText -Repository $Repository -Commit $MetadataCommit -Path $manifestPath -Required).content | ConvertFrom-Json
    $top = @('schemaVersion','producerId','projectId','contractId','producerCommitSha','schemaPath','indexPath','consumer','spectraReleaseBinding','consumerBindingDigest','payloadDigestFormat','index','payloads','payloadBundleDigest','validationStatus')
    Assert-UniversaarlExactProperties $manifest $top 'Snapshotmanifest'
    if ($manifest.schemaVersion -ne 1 -or $manifest.producerId -cne 'blueprint' -or $manifest.projectId -cne 'UABC-BC-BASIC-001' -or $manifest.contractId -cne 'UABC-PROJECT-DATA-V1' -or $manifest.producerCommitSha -cne $producerCommit -or $manifest.validationStatus -cne 'validated' -or $manifest.payloadDigestFormat -cne 'uabc-snapshot-records-v1') { throw 'Snapshotmanifest-Identitaet oder Freigabestatus ist ungueltig.' }
    if ($manifest.schemaPath -cne 'governance/schemas/project-snapshot-manifest.schema.json' -or $manifest.indexPath -cne 'exports/project-data/v1/index.yaml' -or $manifest.index.path -cne $manifest.indexPath) { throw 'Snapshot-Schema- oder Indexreferenz ist ungueltig.' }
    $schema=(Read-UniversaarlCommitText -Repository $Repository -Commit $MetadataCommit -Path ([string]$manifest.schemaPath) -MaximumBytes 1048576 -Required).content|ConvertFrom-Json
    if($schema.'$schema' -cne 'https://json-schema.org/draft/2020-12/schema' -or $schema.'$id' -cne 'urn:universaarl:schema:project-snapshot-manifest:v1' -or $schema.type -cne 'object' -or $schema.additionalProperties -ne $false){throw 'Snapshotmanifestschema besitzt nicht die verbindliche Identitaet oder Striktheit.'}
    $schemaRequired=@($schema.required);if($schemaRequired.Count-ne $top.Count -or @($top|Where-Object{$_ -notin $schemaRequired}).Count-gt 0){throw 'Snapshotmanifestschema fordert nicht exakt die Vertragsfelder.'}
    Assert-UniversaarlExactProperties $manifest.consumer @('consumerId','repositoryUrl','branch','access') 'Snapshot-Consumer'
    Assert-UniversaarlExactProperties $manifest.spectraReleaseBinding @('bindingStatus','productId','technicalRepositoryName','repositoryUrl','releaseVersion','releaseTag','tagCommit','manifestPath','manifestSourceCommit','consumerMode','installableBlueprint','digestAlgorithm','payloadBundleDigest') 'Snapshot-Spectra-Bindung'
    foreach ($name in @('productId','releaseVersion','releaseTag','tagCommit','manifestSourceCommit','consumerMode','installableBlueprint','payloadBundleDigest')) { if ([string]$manifest.spectraReleaseBinding.$name -cne [string]$ExpectedBinding.$name) { throw "Snapshot-Spectra-Projektion '$name' widerspricht der Consumerbindung." } }
    if ($manifest.consumer.consumerId -cne 'project-twin' -or $manifest.consumer.access -cne 'nur-lesend') { throw 'Snapshot-Consumer ist nicht der nur-lesende Project Twin.' }
    $bindingEntry = Get-UniversaarlBlobEntry -Repository $Repository -Commit $producerCommit -Path 'governance/consumer-bindings.yaml' -Required
    $bindingDigest = Get-UniversaarlBytesSha256 (Get-UniversaarlGitBlobBytes -Repository $Repository -Object $bindingEntry.object)
    if ([string]$manifest.consumerBindingDigest -cne "sha256:$bindingDigest") { throw 'Consumer-Bindungsdigest stimmt nicht mit Commit A ueberein.' }
    foreach ($stablePath in @([string]$manifest.schemaPath,[string]$manifest.indexPath)) {
        $aEntry=Get-UniversaarlBlobEntry -Repository $Repository -Commit $producerCommit -Path $stablePath -Required
        $bEntry=Get-UniversaarlBlobEntry -Repository $Repository -Commit $MetadataCommit -Path $stablePath -Required
        if($aEntry.object -cne $bEntry.object -or $aEntry.mode -cne $bEntry.mode){throw "Snapshot-Vertragspfad '$stablePath' ist zwischen A und B nicht objektidentisch."}
    }
    $indexText=(Read-UniversaarlCommitText -Repository $Repository -Commit $producerCommit -Path ([string]$manifest.indexPath) -MaximumBytes 1048576 -Required).content
    $declared=@([regex]::Matches($indexText,'(?m)^\s*-\s*\{\s*id:\s*(?<id>[^,}\s]+).*?path:\s*(?<path>[^,}\s]+)(?:.*?selector:\s*''(?<selector>[^'']*)'')?.*?\}\s*$'))
    if($declared.Count-ne @($manifest.payloads).Count){throw 'Snapshotpayloadliste stimmt nicht exakt mit der Index-Allowlist ueberein.'}
    foreach($payload in @($manifest.payloads)){$match=@($declared|Where-Object{$_.Groups['id'].Value-ceq[string]$payload.id -and $_.Groups['path'].Value-ceq[string]$payload.path});if($match.Count-ne 1){throw "Snapshotpayload '$($payload.id)' ist nicht eindeutig im Index positivgelistet."}}
    $records = [Collections.Generic.List[object]]::new(); $all = @([pscustomobject]@{ path=$manifest.index.path; gitMode=$manifest.index.gitMode; sizeBytes=$manifest.index.sizeBytes; sha256=$manifest.index.sha256 }) + @($manifest.payloads)
    $seen=@{}
    foreach ($record in $all) {
        $path=Assert-UniversaarlContractPath ([string]$record.path); if($seen.ContainsKey($path)){throw 'Snapshotpfad ist doppelt.'};$seen[$path]=$true
        if ($record.gitMode -cne '100644') { throw 'Snapshotblob besitzt nicht Modus 100644.' }
        $entry=Get-UniversaarlBlobEntry -Repository $Repository -Commit $MetadataCommit -Path $path -Required
        $source=Get-UniversaarlBlobEntry -Repository $Repository -Commit $producerCommit -Path $path -Required
        if($entry.object -cne $source.object -or $entry.mode -cne '100644'){throw "Snapshotblob '$path' ist zwischen A und B nicht objektidentisch."}
        $bytes=Get-UniversaarlGitBlobBytes -Repository $Repository -Object $entry.object; $sha=Get-UniversaarlBytesSha256 $bytes
        if($entry.size -ne [int64]$record.sizeBytes -or $sha -cne [string]$record.sha256){throw "Snapshotrecord '$path' stimmt nicht mit dem Blob ueberein."}
        $records.Add([pscustomobject]@{path=$path;bytes=[Text.UTF8Encoding]::new($false).GetBytes("$path`0$($entry.mode)`0$($entry.size)`0$sha`n")})
    }
    $ordered=@($records); [Array]::Sort($ordered, [Comparison[object]]{ param($left,$right) [StringComparer]::Ordinal.Compare([string]$left.path,[string]$right.path) })
    $stream=[IO.MemoryStream]::new(); try { foreach($record in $ordered){$stream.Write($record.bytes,0,$record.bytes.Length)}; $bundle=Get-UniversaarlBytesSha256 $stream.ToArray() } finally {$stream.Dispose()}
    if ([string]$manifest.payloadBundleDigest -cne "sha256:$bundle") { throw 'Snapshot-Payload-Bundledigest stimmt nicht ueberein.' }
    if ([string]$manifest.spectraReleaseBinding.payloadBundleDigest -ceq $bundle -or [string]$manifest.spectraReleaseBinding.payloadBundleDigest -ceq "sha256:$bundle") { throw 'Spectra- und Snapshotdigest wurden unzulaessig gleichgesetzt.' }
    [pscustomobject]@{status='passed';fullValidationPassed=$true;producerCommit=$producerCommit;metadataCommit=$MetadataCommit;payloadBundleDigest="sha256:$bundle"}
}

function Test-UniversaarlTwinContractBoundary {
    param([Parameter(Mandatory)][string]$Repository,[Parameter(Mandatory)][string]$Commit)
    Assert-FullCommitSha $Commit
    $tree=@(Get-UniversaarlCommitTree -Repository $Repository -Commit $Commit)
    foreach($entry in $tree){
        if($entry.type -ne 'blob' -or $entry.size -gt 1048576){continue}
        $path=[string]$entry.path
        if($path -notmatch '^(package(?:-lock)?\.json|src/|config/|server/|scripts/)'){continue}
        if($path -match '\.(png|jpg|jpeg|gif|webp|woff2?|zip|pdf)$'){continue}
        $text=(Read-UniversaarlCommitText -Repository $Repository -Commit $Commit -Path $path -MaximumBytes 1048576 -Required).content
        if($text -match '(?i)UNIVERSAARL_BCPROJECTOS_PATH|BCPROJECTOS_ROOT|BCPROJECTOS_SOURCE_REPO|git\s+(?:-C\s+\S+\s+)?(?:clone|fetch|show|cat-file)[^\r\n]*BCProjectOS'){
            throw "Project Twin besitzt in '$path' eine direkte BCProjectOS-Laufzeitkopplung."
        }
    }
    [pscustomobject]@{status='passed';fullValidationPassed=$true;consumerCommit=$Commit;directProductDependency=$false;access='nur-lesend'}
}
