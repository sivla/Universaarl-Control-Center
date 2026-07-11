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
    Assert-UniversaarlExactProperties $manifest @('schema_version','product_id','release_version','release_kind','manifest_state','release_date','expected_tag','source_commit','consumer_mode','installable_blueprint','blueprint_version','payload','binding_requirements','excluded_from_payload','known_limits') 'Spectra-Releasemanifest'
    if ($manifest.schema_version -ne 1 -or $manifest.product_id -cne 'spectra' -or $manifest.release_version -cne $version -or $manifest.expected_tag -cne $tag -or $manifest.source_commit -cne [string]$Binding.manifestSourceCommit -or $manifest.release_kind -cne 'installable_blueprint' -or $manifest.manifest_state -cne 'final' -or $manifest.consumer_mode -cne 'INSTALLABLE_BLUEPRINT' -or $manifest.installable_blueprint -ne $true -or $manifest.blueprint_version -cne $version) { throw 'Spectra-Releasemanifest ist nicht final installierbar oder widerspruechlich.' }
    if ($Binding.consumerMode -cne 'INSTALLABLE_BLUEPRINT' -or $Binding.installableBlueprint -ne $true -or $Binding.digestAlgorithm -cne 'SHA-256') { throw 'Spectra-Consumerbindung ist nicht installierbar.' }
    $records = [Collections.Generic.List[object]]::new(); $seen = @{}
    foreach ($file in @($manifest.payload.files)) {
        $path = Assert-UniversaarlContractPath ([string]$file.path)
        if ($seen.ContainsKey($path)) { throw 'Spectra-Payloadpfad ist doppelt.' }; $seen[$path] = $true
        $entry = Get-UniversaarlBlobEntry -Repository $Repository -Commit $tagCommit -Path $path -Required
        $bytes = Get-UniversaarlGitBlobBytes -Repository $Repository -Object $entry.object
        $digest = Get-UniversaarlBytesSha256 $bytes
        if ($entry.size -ne [int64]$file.size_bytes -or $digest -cne [string]$file.sha256) { throw "Spectra-Payload '$path' stimmt nicht mit dem Manifest ueberein (Blob: $($entry.size)/$digest; Manifest: $($file.size_bytes)/$($file.sha256))." }
        $records.Add([pscustomobject]@{ path=$path; line="$digest  $path" })
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
