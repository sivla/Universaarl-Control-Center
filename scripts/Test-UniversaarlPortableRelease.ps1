[CmdletBinding()]
param(
    [string]$ManifestPath,
    [switch]$AnonymousGitSelfTest,
    [switch]$SpectraDigestSelfTest,
    [switch]$ControlAnchorSelfTest,
    [switch]$ArchiveBindingSelfTest,
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:GIT_OPTIONAL_LOCKS = '0'
$repositoryRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
. (Join-Path $PSScriptRoot 'Universaarl-Control.Common.ps1')
$findings = [Collections.Generic.List[object]]::new()
$cleanupRoots = [Collections.Generic.List[string]]::new()
$requiredCommands=[ordered]@{'fresh-clone'='git clone --filter=blob:none <portfolio-components>';install='spectra install --locked';start='twin start --snapshot <snapshot-digest>'; 'no-git-runtime'='twin verify --no-git-runtime';'pilot-visible'='twin verify --project bc-basic';'filesystem-http-parity'='twin verify --transport-parity';onboarding='spectra project onboard --isolated';isolation='twin verify --project-isolation'}
function Add-Finding([string]$Code, [string]$Message) { $findings.Add([pscustomobject]@{ code = $Code; message = $Message }) }
function Test-FullSha([object]$Value) { $null -ne $Value -and [string]$Value -match '^[0-9a-f]{40}$' }
function Test-Digest([object]$Value) { $null -ne $Value -and [string]$Value -match '^[0-9a-f]{64}$' }
function Test-RelativeAssetPath([object]$Value) { $null -ne $Value -and [string]$Value -match '^[A-Za-z0-9._/-]+$' -and [string]$Value -notmatch '(^|/)\.\.?(/|$)' -and -not [IO.Path]::IsPathRooted([string]$Value) }
function Get-FileDigest([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Get-TextDigest([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Get-ProcessEnvironmentNames { @([Environment]::GetEnvironmentVariables('Process').Keys | ForEach-Object { [string]$_ }) }
function Test-AnonymousGitInjectionName([string]$Name) {
    $Name -match '^(?i:GIT_.+|GCM_.+|GH_TOKEN|GITHUB_TOKEN|SSH_(?:ASKPASS|AUTH_SOCK|AGENT_PID)|HTTP_PROXY|HTTPS_PROXY|ALL_PROXY|NO_PROXY)$'
}
function Invoke-AnonymousGit([string]$WorkingDirectory, [string[]]$Arguments, [string]$IsolatedHome) {
    $fixed = @('HOME','USERPROFILE','XDG_CONFIG_HOME','GIT_CONFIG_GLOBAL','GIT_CONFIG_SYSTEM','GIT_CONFIG_NOSYSTEM','GIT_TERMINAL_PROMPT','GCM_INTERACTIVE')
    $names = @($fixed + @(Get-ProcessEnvironmentNames | Where-Object { Test-AnonymousGitInjectionName $_ }) | Sort-Object -Unique)
    $saved = @{}
    foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
    try {
        foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $null, 'Process') }
        [Environment]::SetEnvironmentVariable('HOME', $IsolatedHome, 'Process')
        [Environment]::SetEnvironmentVariable('USERPROFILE', $IsolatedHome, 'Process')
        [Environment]::SetEnvironmentVariable('XDG_CONFIG_HOME', (Join-Path $IsolatedHome 'config'), 'Process')
        [Environment]::SetEnvironmentVariable('GIT_CONFIG_GLOBAL', (Join-Path $IsolatedHome 'empty.gitconfig'), 'Process')
        [Environment]::SetEnvironmentVariable('GIT_CONFIG_SYSTEM', (Join-Path $IsolatedHome 'empty-system.gitconfig'), 'Process')
        [Environment]::SetEnvironmentVariable('GIT_CONFIG_NOSYSTEM', '1', 'Process')
        [Environment]::SetEnvironmentVariable('GIT_CONFIG_COUNT', '0', 'Process')
        [Environment]::SetEnvironmentVariable('GIT_OPTIONAL_LOCKS', '0', 'Process')
        [Environment]::SetEnvironmentVariable('GIT_TERMINAL_PROMPT', '0', 'Process')
        [Environment]::SetEnvironmentVariable('GCM_INTERACTIVE', 'Never', 'Process')
        $output = @(& git -c credential.helper= -c core.askPass= -C $WorkingDirectory @Arguments 2>&1)
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    }
    finally { foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') } }
}

if ($AnonymousGitSelfTest) {
    $probeRoot = Join-Path ([IO.Path]::GetTempPath()) ('universaarl-anonymous-git-' + [Guid]::NewGuid().ToString('N'))
    $before = @{}
    foreach ($name in @(Get-ProcessEnvironmentNames|Where-Object{Test-AnonymousGitInjectionName $_})) { $before[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
    try {
        [IO.Directory]::CreateDirectory($probeRoot) | Out-Null
        $probe = Invoke-AnonymousGit -WorkingDirectory $repositoryRoot -Arguments @('config','--get','review.injected') -IsolatedHome $probeRoot
        if ($probe.ExitCode -eq 0 -or -not [string]::IsNullOrWhiteSpace(($probe.Output -join ''))) { throw 'Git-Konfigurationsinjektion erreichte den anonymen Prozess.' }
        foreach ($name in $before.Keys) { if ([Environment]::GetEnvironmentVariable($name, 'Process') -cne $before[$name]) { throw "Umgebungsvariable '$name' wurde nicht wiederhergestellt." } }
        Write-Output 'ANONYMOUS_GIT_SANITIZATION_PASSED'
        exit 0
    }
    finally { if (Test-Path -LiteralPath $probeRoot) { Remove-Item -LiteralPath $probeRoot -Recurse -Force -ErrorAction SilentlyContinue } }
}

function Test-ControlAnchor {
    param([Parameter(Mandatory)][string]$Repository,[Parameter(Mandatory)][string]$ExpectedCommit,[Parameter(Mandatory)][string]$ValidatorPath,[Parameter(Mandatory)][string]$TemplatePath)
    $head=Invoke-UniversaarlGitRead -Repository $Repository -Arguments @('rev-parse','HEAD')
    $status=Invoke-UniversaarlGitRead -Repository $Repository -Arguments @('status','--porcelain=v1','--untracked-files=all') -PreserveWhitespace
    if($head.exitCode -ne 0 -or [string]$head.output -cne $ExpectedCommit -or $status.exitCode -ne 0 -or -not[string]::IsNullOrWhiteSpace([string]$status.output)){return $false}
    foreach($relative in @($ValidatorPath,$TemplatePath)){
        try{
            $entry=Get-UniversaarlBlobEntry -Repository $Repository -Commit $ExpectedCommit -Path $relative -Required
            if($entry.mode -cne '100644'){return $false}
            $blob=Get-UniversaarlGitBlobBytes -Repository $Repository -Object $entry.object
            $working=[IO.File]::ReadAllBytes((Join-Path $Repository ($relative-replace'/',[IO.Path]::DirectorySeparatorChar)))
            if((Get-UniversaarlBytesSha256 $blob)-cne(Get-UniversaarlBytesSha256 $working)){return $false}
        }catch{return $false}
    }
    $true
}
function Expand-VerifiedEvidenceArchive {
    param([Parameter(Mandatory)][string]$ArchivePath,[Parameter(Mandatory)][string]$DestinationRoot,[Parameter(Mandatory)][string]$LocalAssetRoot,[Parameter(Mandatory)][string]$EvidenceRelative,[Parameter(Mandatory)][string]$EvidenceDigest,[Parameter(Mandatory)]$Document)
    if((Get-Item -LiteralPath $ArchivePath).Length-gt 20971520){throw 'Attestierungsarchiv ist zu gross.'}
    $expected=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($pair in @([pscustomobject]@{path=$EvidenceRelative;digest=$EvidenceDigest})+@($Document.records|ForEach-Object{[pscustomobject]@{path=[string]$_.artifact;digest=[string]$_.artifactSha256}})){
        if(-not(Test-RelativeAssetPath $pair.path)-or-not(Test-Digest $pair.digest)-or$expected.ContainsKey([string]$pair.path)){throw 'Evidence-Archivvertrag enthaelt ungueltige oder doppelte Member.'}
        $local=[IO.Path]::GetFullPath((Join-Path $LocalAssetRoot ([string]$pair.path-replace'/',[IO.Path]::DirectorySeparatorChar)))
        if(-not(Test-UniversaarlPathWithinRoot -Root $LocalAssetRoot -Path $local)-or-not(Test-Path -LiteralPath $local -PathType Leaf)-or(Get-FileDigest $local)-cne[string]$pair.digest){throw "Lokale Evidence '$($pair.path)' stimmt nicht mit ihrem gebundenen Digest ueberein."}
        $expected.Add([string]$pair.path,[string]$pair.digest)
    }
    if($expected.Count-ne 9){throw 'Evidence-Archiv muss exakt die Plattform-Evidence und acht Record-Artefakte binden.'}
    [IO.Directory]::CreateDirectory($DestinationRoot)|Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase);$total=[int64]0
    $archive=[IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try{
        foreach($entry in $archive.Entries){
            $name=([string]$entry.FullName).Replace('\','/');$isDirectory=$name.EndsWith('/')
            if([string]::IsNullOrWhiteSpace($name)-or-not(Test-RelativeAssetPath $name.TrimEnd('/'))-or-not$seen.Add($name.TrimEnd('/'))){throw 'ZIP enthaelt leere, absolute, traversierende oder doppelte Member.'}
            $unixType=($entry.ExternalAttributes-shr 16)-band 0xF000
            if(($entry.ExternalAttributes-band 0x400)-ne 0-or$unixType-eq 0xA000-or(-not$isDirectory-and$unixType-ne 0-and$unixType-ne 0x8000)){throw 'ZIP enthaelt Symlink, Reparse-Punkt oder unzulaessigen Spezialdateityp.'}
            if($isDirectory){continue}
            if(-not$expected.ContainsKey($name)){throw "Unerwartetes ZIP-Member '$name'."}
            if($entry.Length-gt 1048576){throw "ZIP-Member '$name' ist zu gross."};$total+=$entry.Length;if($total-gt 10485760){throw 'Entpackte Evidence ist zu gross.'}
            $target=[IO.Path]::GetFullPath((Join-Path $DestinationRoot ($name-replace'/',[IO.Path]::DirectorySeparatorChar)))
            if(-not(Test-UniversaarlPathWithinRoot -Root $DestinationRoot -Path $target)){throw 'ZIP-Member verlaesst das temporaere Ziel.'}
            [IO.Directory]::CreateDirectory((Split-Path -Parent $target))|Out-Null;$input=$entry.Open();$output=[IO.File]::Open($target,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            try{$input.CopyTo($output)}finally{$output.Dispose();$input.Dispose()}
            if((Get-FileDigest $target)-cne$expected[$name]){throw "ZIP-Member '$name' stimmt nicht mit dem Evidence-Digest ueberein."}
        }
    }finally{$archive.Dispose()}
    foreach($name in $expected.Keys){if(-not$seen.Contains($name)){throw "ZIP-Member '$name' fehlt."}}
    [pscustomobject]@{root=$DestinationRoot;evidencePath=(Join-Path $DestinationRoot ($EvidenceRelative-replace'/',[IO.Path]::DirectorySeparatorChar))}
}
function Test-GitHubActionsProvenance {
    param([Parameter(Mandatory)]$Provenance,[Parameter(Mandatory)]$Attestation,[Parameter(Mandatory)][string]$Platform,[Parameter(Mandatory)][string]$LocalAssetRoot,[Parameter(Mandatory)][string]$EvidenceRelative,[Parameter(Mandatory)][string]$EvidenceDigest,[Parameter(Mandatory)]$Document,[Parameter(Mandatory)][string]$SnapshotDigest,[Parameter(Mandatory)][string]$ComponentDigest)
    $saved=@{};$names=@(Get-ProcessEnvironmentNames|Where-Object{$_-match'^(?i:GH_.+|GITHUB_.+|HTTP_PROXY|HTTPS_PROXY|ALL_PROXY|NO_PROXY)$'})
    foreach($name in $names){$saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
    $tempRoot=$null
    try{
        foreach($name in $names){[Environment]::SetEnvironmentVariable($name,$null,'Process')}
        $headers=@{'User-Agent'='Universaarl-Control-Center';Accept='application/vnd.github+json'}
        $api="https://api.github.com/repos/sivla/Universaarl-Control-Center/actions/runs/$($Provenance.runId)"
        $run=Invoke-RestMethod -Uri $api -Headers $headers -Method Get -TimeoutSec 30
        if([string]$run.html_url-cne[string]$Provenance.runUrl -or [string]$run.repository.full_name-cne'sivla/Universaarl-Control-Center' -or [string]$run.head_sha-cne[string]$Provenance.commit -or [string]$run.conclusion-cne'success' -or [string]$run.path-cne[string]$Provenance.workflow){return $false}
        $jobs=Invoke-RestMethod -Uri ([string]$run.jobs_url) -Headers $headers -Method Get -TimeoutSec 30;$label=if($Platform-eq'windows'){'windows'}else{'macos'}
        if(@($jobs.jobs|Where-Object{[string]$_.conclusion-ceq'success'-and(@($_.labels|Where-Object{[string]$_-ceq[string]$Provenance.runnerImage}).Count-gt 0)-and(@($_.labels|Where-Object{[string]$_-match"^$label"}).Count-gt 0)}).Count-lt 1){return $false}
        $artifacts=Invoke-RestMethod -Uri ([string]$run.artifacts_url) -Headers $headers -Method Get -TimeoutSec 30;$artifact=@($artifacts.artifacts|Where-Object{[string]$_.name-ceq[string]$Attestation.artifactName-and-not$_.expired})
        if($artifact.Count-ne 1 -or [string]$artifact[0].archive_download_url-cne[string]$Attestation.artifactUrl -or [string]$artifact[0].digest-cne("sha256:"+[string]$Attestation.artifactSha256)){return $false}
        $tempRoot=Join-Path ([IO.Path]::GetTempPath()) ('universaarl-actions-artifact-'+[Guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($tempRoot)|Out-Null;$download=Join-Path $tempRoot 'attestation.zip'
        Invoke-WebRequest -Uri ([string]$Attestation.artifactUrl) -Headers $headers -OutFile $download -TimeoutSec 60 -UseBasicParsing
        if((Get-FileDigest $download)-cne[string]$Attestation.artifactSha256){return $false}
        $expanded=Expand-VerifiedEvidenceArchive -ArchivePath $download -DestinationRoot (Join-Path $tempRoot 'verified') -LocalAssetRoot $LocalAssetRoot -EvidenceRelative $EvidenceRelative -EvidenceDigest $EvidenceDigest -Document $Document
        $verifiedDocument=Get-Content -LiteralPath $expanded.evidencePath -Raw|ConvertFrom-Json
        foreach($recordId in $requiredCommands.Keys){$matches=@($verifiedDocument.records|Where-Object{[string]$_.id-ceq$recordId});if($matches.Count-ne 1){return $false};Test-EvidenceRecord $matches[0] $recordId $expanded.root $Platform $SnapshotDigest $ComponentDigest}
        $true
    }catch{$false}finally{if($null-ne$tempRoot-and(Test-Path -LiteralPath $tempRoot)){Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue};foreach($name in $names){[Environment]::SetEnvironmentVariable($name,$saved[$name],'Process')}}
}

if($ControlAnchorSelfTest){
    $probeRoot=Join-Path ([IO.Path]::GetTempPath()) ('universaarl-control-anchor-'+[Guid]::NewGuid().ToString('N'))
    try{
        [IO.Directory]::CreateDirectory((Join-Path $probeRoot 'scripts'))|Out-Null;[IO.Directory]::CreateDirectory((Join-Path $probeRoot 'release'))|Out-Null
        [IO.File]::WriteAllText((Join-Path $probeRoot 'scripts/validator.ps1'),'validator',[Text.UTF8Encoding]::new($false));[IO.File]::WriteAllText((Join-Path $probeRoot 'release/template.json'),'{}',[Text.UTF8Encoding]::new($false))
        & git -C $probeRoot init --quiet; & git -C $probeRoot config user.name fixture; & git -C $probeRoot config user.email fixture@example.invalid; & git -C $probeRoot add .; & git -C $probeRoot commit --quiet -m anchor
        $commit=(& git -C $probeRoot rev-parse HEAD).Trim();if(-not(Test-ControlAnchor $probeRoot $commit 'scripts/validator.ps1' 'release/template.json')){throw 'Sauberer Kontrollanker wurde abgelehnt.'}
        [IO.File]::AppendAllText((Join-Path $probeRoot 'scripts/validator.ps1'),'modified');if(Test-ControlAnchor $probeRoot $commit 'scripts/validator.ps1' 'release/template.json'){throw 'Modifizierter Validator wurde akzeptiert.'}
        & git -C $probeRoot checkout --quiet -- scripts/validator.ps1; & git -C $probeRoot rm --cached --quiet release/template.json
        if(Test-ControlAnchor $probeRoot $commit 'scripts/validator.ps1' 'release/template.json'){throw 'Ungetracktes Template wurde akzeptiert.'}
        Write-Output 'CONTROL_ANCHOR_SELF_TEST_PASSED';exit 0
    }finally{if(Test-Path -LiteralPath $probeRoot){Remove-Item -LiteralPath $probeRoot -Recurse -Force}}
}
function Test-EvidenceRecord {
    param([Parameter(Mandatory)]$Record,[Parameter(Mandatory)][string]$ExpectedId,[Parameter(Mandatory)][string]$AssetRoot,[Parameter(Mandatory)][string]$Platform,[Parameter(Mandatory)][string]$SnapshotDigest,[Parameter(Mandatory)][string]$ComponentDigest,[switch]$MetadataOnly)
    $expectedCommand=[string]$requiredCommands[$ExpectedId]
    if ($null -eq $Record -or [string]$Record.id -cne $ExpectedId -or [string]$Record.command -cne $expectedCommand -or $Record.exitCode -isnot [int] -or $Record.exitCode -ne 0 -or -not (Test-RelativeAssetPath $Record.artifact) -or -not (Test-Digest $Record.artifactSha256) -or [string]$Record.startedAt -notmatch '^\d{4}-\d{2}-\d{2}T' -or [string]$Record.completedAt -notmatch '^\d{4}-\d{2}-\d{2}T') {
        Add-Finding 'PORTABLE_EVIDENCE_RECORD_INVALID' "Ausfuehrungsrecord '$ExpectedId' fuer $Platform ist unvollstaendig oder nicht erfolgreich."
        return
    }
    if($MetadataOnly){return}
    $artifactPath = [IO.Path]::GetFullPath((Join-Path $AssetRoot ([string]$Record.artifact -replace '/', [IO.Path]::DirectorySeparatorChar)))
    if (-not (Test-UniversaarlPathWithinRoot -Root $AssetRoot -Path $artifactPath) -or -not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) { Add-Finding 'PORTABLE_EVIDENCE_ARTIFACT_MISSING' "Artefakt fuer '$ExpectedId' auf $Platform fehlt."; return }
    if ((Get-FileDigest $artifactPath) -cne [string]$Record.artifactSha256) { Add-Finding 'PORTABLE_EVIDENCE_ARTIFACT_DIGEST' "Artefaktdigest fuer '$ExpectedId' auf $Platform stimmt nicht." }
    try{$artifact=Get-Content -LiteralPath $artifactPath -Raw|ConvertFrom-Json}catch{Add-Finding 'PORTABLE_EVIDENCE_ARTIFACT_SCHEMA' "Artefakt fuer '$ExpectedId' auf $Platform ist kein JSON.";return}
    if($artifact.schemaVersion -isnot[int] -or $artifact.schemaVersion -ne 1 -or [string]$artifact.recordId -cne $ExpectedId -or [string]$artifact.platform -cne $Platform -or [string]$artifact.status -cne 'passed' -or [string]$artifact.snapshotDigest -cne $SnapshotDigest -or [string]$artifact.componentDigest -cne $ComponentDigest -or [string]$artifact.commandSha256 -cne (Get-TextDigest $expectedCommand) -or -not(Test-Digest $artifact.outputDigest) -or @($artifact.checks).Count -lt 1 -or @($artifact.checks|Where-Object{$_-isnot[string]-or[string]::IsNullOrWhiteSpace([string]$_)}).Count -gt 0){Add-Finding 'PORTABLE_EVIDENCE_ARTIFACT_SCHEMA' "Artefakt fuer '$ExpectedId' auf $Platform bindet Command, Snapshot oder Ergebnis nicht exakt."}
}
if($ArchiveBindingSelfTest){
    $probe=Join-Path ([IO.Path]::GetTempPath()) ('universaarl-archive-binding-'+[Guid]::NewGuid().ToString('N'))
    try{
        $local=Join-Path $probe 'local';$source=Join-Path $probe 'source';[IO.Directory]::CreateDirectory((Join-Path $local 'evidence'))|Out-Null;[IO.Directory]::CreateDirectory((Join-Path $source 'evidence'))|Out-Null;[IO.Directory]::CreateDirectory((Join-Path $local 'artifacts'))|Out-Null;[IO.Directory]::CreateDirectory((Join-Path $source 'artifacts'))|Out-Null
        $records=[Collections.Generic.List[object]]::new();foreach($id in $requiredCommands.Keys){$relative="artifacts/$id.json";$localPath=Join-Path $local $relative;$sourcePath=Join-Path $source $relative;[IO.File]::WriteAllText($localPath,"{`"id`":`"$id`"}",[Text.UTF8Encoding]::new($false));Copy-Item -LiteralPath $localPath -Destination $sourcePath;$records.Add([pscustomobject]@{id=$id;artifact=$relative;artifactSha256=Get-FileDigest $localPath})}
        $document=[pscustomobject]@{records=@($records)};$evidenceRelative='evidence/windows.json';$localEvidence=Join-Path $local $evidenceRelative;$sourceEvidence=Join-Path $source $evidenceRelative;[IO.File]::WriteAllText($localEvidence,(($document|ConvertTo-Json -Depth 5)+'`n'),[Text.UTF8Encoding]::new($false));Copy-Item -LiteralPath $localEvidence -Destination $sourceEvidence;$evidenceDigest=Get-FileDigest $localEvidence
        Add-Type -AssemblyName System.IO.Compression.FileSystem;$zip=Join-Path $probe 'valid.zip';[IO.Compression.ZipFile]::CreateFromDirectory($source,$zip)
        $expanded=Expand-VerifiedEvidenceArchive $zip (Join-Path $probe 'expanded-good') $local $evidenceRelative $evidenceDigest $document;if(-not(Test-Path -LiteralPath $expanded.evidencePath)){throw 'Gueltiges Evidence-Archiv wurde nicht gebunden.'}
        [IO.File]::AppendAllText($localEvidence,'fabricated');$fabricatedBlocked=$false;try{Expand-VerifiedEvidenceArchive $zip (Join-Path $probe 'expanded-fabricated') $local $evidenceRelative $evidenceDigest $document|Out-Null}catch{$fabricatedBlocked=$true};if(-not$fabricatedBlocked){throw 'Fabrizierte lokale Evidence wurde mit realer Archivmetadatenbindung akzeptiert.'};Copy-Item -LiteralPath $sourceEvidence -Destination $localEvidence -Force
        $missingSource=Join-Path $probe 'missing-source';Copy-Item -LiteralPath $source -Destination $missingSource -Recurse;Remove-Item -LiteralPath (Join-Path $missingSource 'artifacts/isolation.json') -Force;$missingZip=Join-Path $probe 'missing.zip';[IO.Compression.ZipFile]::CreateFromDirectory($missingSource,$missingZip);$missingBlocked=$false;try{Expand-VerifiedEvidenceArchive $missingZip (Join-Path $probe 'expanded-missing') $local $evidenceRelative $evidenceDigest $document|Out-Null}catch{$missingBlocked=$true};if(-not$missingBlocked){throw 'Fehlendes ZIP-Member wurde akzeptiert.'}
        $traversalZip=Join-Path $probe 'traversal.zip';$stream=[IO.File]::Open($traversalZip,[IO.FileMode]::CreateNew);$archive=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$false);try{$entry=$archive.CreateEntry('../escape.json');$writer=[IO.StreamWriter]::new($entry.Open());try{$writer.Write('{}')}finally{$writer.Dispose()}}finally{$archive.Dispose();$stream.Dispose()};$traversalBlocked=$false;try{Expand-VerifiedEvidenceArchive $traversalZip (Join-Path $probe 'expanded-traversal') $local $evidenceRelative $evidenceDigest $document|Out-Null}catch{$traversalBlocked=$true};if(-not$traversalBlocked){throw 'Traversierendes ZIP-Member wurde akzeptiert.'}
        Write-Output 'ARCHIVE_EVIDENCE_BINDING_PASSED';exit 0
    }finally{if(Test-Path -LiteralPath $probe){Remove-Item -LiteralPath $probe -Recurse -Force -ErrorAction SilentlyContinue}}
}
function Test-SpectraReleaseManifest {
    param([Parameter(Mandatory)][string]$Checkout,[Parameter(Mandatory)][string]$Commit,[Parameter(Mandatory)][string]$ManifestPath,[Parameter(Mandatory)]$Binding)
    $Path=Join-Path $Checkout ($ManifestPath-replace'/',[IO.Path]::DirectorySeparatorChar)
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){Add-Finding 'PORTABLE_SPECTRA_MANIFEST_MISSING' 'Spectra-Releasemanifest fehlt.';return}
    if((Get-FileDigest $Path)-cne[string]$Binding.manifestFileSha256){Add-Finding 'PORTABLE_SPECTRA_MANIFEST_FILE_DIGEST' 'SHA-256 der Spectra-Manifestdatei stimmt nicht.';return}
    try{
        $release=Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json
        if($release.schema_version -isnot[int] -or [string]$release.product_id -cne 'spectra' -or [string]$release.expected_tag -cne [string]$Binding.tag -or [string]$release.payload.digest_algorithm -cne 'SHA-256' -or -not(Test-Digest $release.payload.bundle_digest) -or $release.payload.file_count -isnot[int] -or $release.payload.file_count -lt 1){Add-Finding 'PORTABLE_SPECTRA_AGGREGATE_DIGEST' 'Deklarierter Spectra-Aggregatdigest entspricht nicht dem Releasemanifest-Schema.';return}
        $seen=@{};$records=[Collections.Generic.List[object]]::new()
        foreach($file in @($release.payload.files)){
            $relative=Assert-UniversaarlContractPath ([string]$file.path);if($seen.ContainsKey($relative)){throw 'Doppelter Payloadpfad.'};$seen[$relative]=$true
            $entry=Get-UniversaarlBlobEntry -Repository $Checkout -Commit $Commit -Path $relative -Required;$bytes=Get-UniversaarlGitBlobBytes -Repository $Checkout -Object $entry.object;$digest=Get-UniversaarlBytesSha256 $bytes
            if($entry.mode -cne '100644' -or $entry.size -ne[int64]$file.size_bytes -or $digest -cne[string]$file.sha256 -or ($null-ne$file.PSObject.Properties['mode'] -and [string]$file.mode -cne '100644')){throw "Payload '$relative' stimmt nicht mit dem Releasecommit ueberein."}
            $records.Add([pscustomobject]@{path=$relative;line="$digest  $relative"})
        }
        if($records.Count-ne[int]$release.payload.file_count){throw 'Payload-Dateianzahl stimmt nicht.'}
        $sorted=@($records);[Array]::Sort($sorted,[Comparison[object]]{param($left,$right)[StringComparer]::Ordinal.Compare([string]$left.path,[string]$right.path)})
        $checksumsText=((@($sorted|ForEach-Object line))-join"`n")+"`n";$aggregate=Get-UniversaarlBytesSha256 ([Text.UTF8Encoding]::new($false).GetBytes($checksumsText))
        if($aggregate-cne[string]$release.payload.bundle_digest -or $aggregate-cne[string]$Binding.aggregatePayloadDigest){Add-Finding 'PORTABLE_SPECTRA_AGGREGATE_DIGEST' 'Neu berechneter Spectra-Aggregatdigest stimmt nicht.'}
        $checksumPath=(([IO.Path]::GetDirectoryName($ManifestPath)-replace'\\','/')+'/'+[string]$release.payload.checksums_file).TrimStart('/')
        $stored=Read-UniversaarlCommitText -Repository $Checkout -Commit $Commit -Path $checksumPath -MaximumBytes 1048576 -Required
        if([string]$stored.content-cne$checksumsText.TrimEnd("`n")){Add-Finding 'PORTABLE_SPECTRA_CHECKSUM_BUNDLE' 'Versioniertes Spectra-Checksumbundle stimmt nicht mit den Payloadblobs ueberein.'}
    }catch{Add-Finding 'PORTABLE_SPECTRA_MANIFEST_INVALID' 'Spectra-Releasemanifest ist nicht schemafaehig lesbar.'}
}
if($SpectraDigestSelfTest){
    $probe=Join-Path ([IO.Path]::GetTempPath()) ('universaarl-spectra-manifest-'+[Guid]::NewGuid().ToString('N'))
    try{
        [IO.Directory]::CreateDirectory((Join-Path $probe 'release/versions/1.2.3-alpha.1'))|Out-Null;[IO.File]::WriteAllText((Join-Path $probe 'payload.txt'),"alpha`n",[Text.UTF8Encoding]::new($false));$payloadDigest=Get-FileDigest (Join-Path $probe 'payload.txt');$line="$payloadDigest  payload.txt`n";$aggregate=Get-TextDigest $line
        [IO.File]::WriteAllText((Join-Path $probe 'release/versions/1.2.3-alpha.1/checksums.sha256'),$line,[Text.UTF8Encoding]::new($false));$release=[ordered]@{schema_version=4;product_id='spectra';expected_tag='spectra-v1.2.3-alpha.1';payload=[ordered]@{digest_algorithm='SHA-256';bundle_digest=$aggregate;file_count=1;checksums_file='checksums.sha256';files=@([ordered]@{path='payload.txt';sha256=$payloadDigest;size_bytes=6;mode='100644'})}};$manifestFile=Join-Path $probe 'release/versions/1.2.3-alpha.1/release-manifest.json';[IO.File]::WriteAllText($manifestFile,(($release|ConvertTo-Json -Depth 8)+"`n"),[Text.UTF8Encoding]::new($false))
        & git -C $probe init --quiet;& git -C $probe config user.name fixture;& git -C $probe config user.email fixture@example.invalid;& git -C $probe config core.autocrlf false;& git -C $probe add .;& git -C $probe commit --quiet -m release;$commit=(& git -C $probe rev-parse HEAD).Trim()
        $binding=[pscustomobject]@{manifestFileSha256=Get-FileDigest $manifestFile;tag='spectra-v1.2.3-alpha.1';aggregatePayloadDigest=('b'*64)}
        Test-SpectraReleaseManifest -Checkout $probe -Commit $commit -ManifestPath 'release/versions/1.2.3-alpha.1/release-manifest.json' -Binding $binding
        if($findings.Count -ne 1 -or [string]$findings[0].code -cne 'PORTABLE_SPECTRA_AGGREGATE_DIGEST'){throw 'Manifestdatei-SHA und Aggregatdigest wurden nicht getrennt validiert.'}
        Write-Output 'SPECTRA_DIGEST_SEPARATION_PASSED';exit 0
    }finally{if(Test-Path -LiteralPath $probe){Remove-Item -LiteralPath $probe -Recurse -Force}}
}
if ([string]::IsNullOrWhiteSpace($ManifestPath)) { throw 'Ein externes finales Portfolio-Manifest ist erforderlich.' }

$manifest = $null
$manifestRoot = $null
$verifiedComponents = [ordered]@{}
try {
    $fullManifestPath = [IO.Path]::GetFullPath($ManifestPath)
    if (Test-UniversaarlPathWithinRoot -Root $repositoryRoot -Path $fullManifestPath -AllowRoot) { Add-Finding 'PORTABLE_MANIFEST_SELF_REFERENCE' 'Das finale Portfolio-Manifest muss als externes Release-Asset oder generierter Bericht ausserhalb des gebundenen Kontrollcommits liegen.' }
    if ((Split-Path -Leaf $fullManifestPath) -like '*.template.json') { Add-Finding 'PORTABLE_TEMPLATE_MISUSE' 'Eine versionierte Vorlage ist kein finales Portfolio-Manifest.' }
    if (-not (Test-Path -LiteralPath $fullManifestPath -PathType Leaf)) { Add-Finding 'PORTABLE_MANIFEST_MISSING' "Portabilitaetsmanifest fehlt: $fullManifestPath" }
    else {
        $manifestRoot = Split-Path -Parent $fullManifestPath
        $raw = [IO.File]::ReadAllText($fullManifestPath)
        if ($raw -match '(?i)(file://|[A-Z]:\\|/Users/|/home/)') { Add-Finding 'PORTABLE_ABSOLUTE_PATH' 'Das Manifest enthaelt einen lokalen absoluten Pfad.' }
        try { $manifest = $raw | ConvertFrom-Json } catch { Add-Finding 'PORTABLE_MANIFEST_INVALID' $_.Exception.Message }
    }

    $expected = [ordered]@{ spectra='https://github.com/sivla/BCProjectOS.git'; blueprint='https://github.com/sivla/Universaarl-BC-Basic.git'; 'project-twin'='https://github.com/sivla/Universaarl-Project-Twin.git'; 'control-center'='https://github.com/sivla/Universaarl-Control-Center.git' }
    $componentLines = [Collections.Generic.List[string]]::new()
    $components = @()
    $calculatedComponentDigest = $null
    if ($null -ne $manifest) {
        if ($manifest.schemaVersion -isnot [int] -or $manifest.schemaVersion -ne 3 -or [string]$manifest.kind -cne 'portfolio-portability-final-evidence') { Add-Finding 'PORTABLE_SCHEMA_INVALID' 'Finales Manifest muss exakt Schema 3 und den finalen Evidence-Typ verwenden.' }
        if ([string]$manifest.status -cne 'READY') { Add-Finding 'PORTABLE_STATUS_NOT_READY' 'Finales Manifest ist nicht READY.' }
        if ($manifest.controlContract -isnot [pscustomobject] -or -not (Test-FullSha $manifest.controlContract.validatorCommit) -or [string]$manifest.controlContract.templatePath -cne 'release/portfolio-portability-manifest.template.json' -or $manifest.controlContract.templateSchemaVersion -ne 3) { Add-Finding 'PORTABLE_TWO_STAGE_BINDING_INVALID' 'Externe Evidence bindet Validatorcommit und versionierte Vorlage nicht exakt.' }
        else {
            if(-not(Test-ControlAnchor -Repository $repositoryRoot -ExpectedCommit ([string]$manifest.controlContract.validatorCommit) -ValidatorPath 'scripts/Test-UniversaarlPortableRelease.ps1' -TemplatePath 'release/portfolio-portability-manifest.template.json')){Add-Finding 'PORTABLE_VALIDATOR_TRUST_ANCHOR' 'Kontrollarbeitsbaum ist unsauber oder Validator-/Templatebytes entsprechen nicht exakt dem gebundenen HEAD.'}
        }
        $components = @($manifest.components)
        if ($components.Count -ne 4) { Add-Finding 'PORTABLE_COMPONENT_COUNT' 'Exakt vier Komponenten sind erforderlich.' }
        foreach ($id in $expected.Keys) {
            $matches = @($components | Where-Object { [string]$_.id -ceq $id })
            if ($matches.Count -ne 1) { Add-Finding 'PORTABLE_COMPONENT_ID' "Komponente $id fehlt oder ist doppelt."; continue }
            $component = $matches[0]
            if ([string]$component.repository -cne [string]$expected[$id] -or $component.public -ne $true -or [string]$component.ref -notmatch '^refs/(heads|tags)/[^\s]+$' -or -not (Test-FullSha $component.commit) -or -not (Test-FullSha $component.tree)) { Add-Finding 'PORTABLE_COMPONENT_INVALID' "Komponente $id ist nicht vollstaendig und unveraenderlich gebunden." }
            $componentLines.Add("$id|$($component.repository)|$($component.ref)|$($component.commit)|$($component.tree)")
            if ((Test-FullSha $component.commit) -and (Test-FullSha $component.tree) -and [string]$component.repository -ceq [string]$expected[$id]) {
                $verificationRoot = Join-Path ([IO.Path]::GetTempPath()) ('universaarl-public-verify-' + [Guid]::NewGuid().ToString('N')); $cleanupRoots.Add($verificationRoot)
                $gitHome = Join-Path $verificationRoot 'home'; $clone = Join-Path $verificationRoot 'repo'; [IO.Directory]::CreateDirectory($gitHome)|Out-Null; [IO.Directory]::CreateDirectory($clone)|Out-Null
                $init=Invoke-AnonymousGit $clone @('init','--quiet') $gitHome; $remote=Invoke-AnonymousGit $clone @('remote','add','origin',[string]$component.repository) $gitHome
                $fetchRef=if([string]$component.ref -like 'refs/tags/*'){"$($component.ref):$($component.ref)"}else{"$($component.ref):refs/remotes/origin/portable-verify"}; $fetch=Invoke-AnonymousGit $clone @('fetch','--quiet','--depth=1','origin',$fetchRef) $gitHome
                if($init.ExitCode -ne 0 -or $remote.ExitCode -ne 0 -or $fetch.ExitCode -ne 0){Add-Finding 'PORTABLE_ANONYMOUS_CLONE_FAILED' "Repository fuer $id ist anonym nicht frisch abrufbar."}
                else {
                    $commitResult=Invoke-AnonymousGit $clone @('rev-parse','FETCH_HEAD^{}') $gitHome; $remoteCommit=(($commitResult.Output|Select-Object -Last 1)-as[string]).Trim()
                    $treeResult=Invoke-AnonymousGit $clone @('rev-parse',"$($component.commit)^{tree}") $gitHome; $remoteTree=(($treeResult.Output|Select-Object -Last 1)-as[string]).Trim()
                    if($remoteCommit -cne [string]$component.commit){Add-Finding 'PORTABLE_REMOTE_COMMIT_MISMATCH' "Remotecommit fuer $id stimmt nicht."}; if($remoteTree -cne [string]$component.tree){Add-Finding 'PORTABLE_REMOTE_TREE_MISMATCH' "Remotetree fuer $id stimmt nicht."}
                    $checkout=Invoke-AnonymousGit $clone @('checkout','--quiet','--detach',[string]$component.commit) $gitHome; if($checkout.ExitCode -ne 0){Add-Finding 'PORTABLE_REMOTE_CHECKOUT_FAILED' "Commit fuer $id ist nicht auscheckbar."}
                    if($id -eq 'spectra'){ $tag=Invoke-AnonymousGit $clone @('cat-file','-t',[string]$component.ref) $gitHome; if((($tag.Output|Select-Object -Last 1)-as[string]).Trim() -cne 'tag'){Add-Finding 'PORTABLE_SPECTRA_TAG_NOT_ANNOTATED' 'Spectra-Tag ist nicht annotiert.'} }
                    $verifiedComponents[$id]=[pscustomobject]@{clone=$clone;commit=$remoteCommit;tree=$remoteTree}
                }
            }
        }
        $calculatedComponentDigest=Get-TextDigest (($componentLines|Sort-Object)-join "`n"); if(-not(Test-Digest $manifest.componentDigest)-or[string]$manifest.componentDigest -cne $calculatedComponentDigest){Add-Finding 'PORTABLE_COMPONENT_DIGEST_MISMATCH' 'Komponentendigest stimmt nicht.'}
        $controlComponent=@($components|Where-Object{[string]$_.id -ceq 'control-center'});if($controlComponent.Count -ne 1 -or [string]$controlComponent[0].commit -cne [string]$manifest.controlContract.validatorCommit){Add-Finding 'PORTABLE_CONTROL_COMPONENT_MISMATCH' 'Kontrollkomponente und Validatorcommit sind nicht identisch gebunden.'}
        $binding=$manifest.spectraBinding
        if($binding -isnot [pscustomobject] -or [string]$binding.tag -notmatch '^spectra-v\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$' -or -not(Test-RelativeAssetPath $binding.manifestPath) -or -not(Test-Digest $binding.manifestFileSha256) -or -not(Test-Digest $binding.aggregatePayloadDigest) -or [string]$binding.aggregateDigestAlgorithm -cne 'SHA-256'){Add-Finding 'PORTABLE_SPECTRA_BINDING_INVALID' 'Spectra-Manifestdatei und Aggregatdigest sind nicht getrennt und vollstaendig gebunden.'}
        elseif($verifiedComponents.Contains('spectra')){
            Test-SpectraReleaseManifest -Checkout $verifiedComponents['spectra'].clone -Commit $verifiedComponents['spectra'].commit -ManifestPath ([string]$binding.manifestPath) -Binding $binding
        }
        $requiredRecords=@('fresh-clone','install','start','no-git-runtime','pilot-visible','filesystem-http-parity','onboarding','isolation')
        $snapshotDigests=@{}
        foreach($platform in @('windows','macos')){
            $pointer=$manifest.platformEvidence.$platform
            if($pointer -isnot[pscustomobject] -or [string]$pointer.status -cne 'passed' -or -not(Test-RelativeAssetPath $pointer.evidenceFile) -or -not(Test-Digest $pointer.sha256)){Add-Finding 'PORTABLE_PLATFORM_PENDING' "Plattformnachweis fuer $platform bleibt PENDING.";continue}
            $evidencePath=[IO.Path]::GetFullPath((Join-Path $manifestRoot ([string]$pointer.evidenceFile -replace '/', [IO.Path]::DirectorySeparatorChar)))
            if(-not(Test-UniversaarlPathWithinRoot -Root $manifestRoot -Path $evidencePath)-or-not(Test-Path -LiteralPath $evidencePath -PathType Leaf)){Add-Finding 'PORTABLE_EVIDENCE_MISSING' "Evidence fuer $platform fehlt.";continue}
            if((Get-FileDigest $evidencePath)-cne[string]$pointer.sha256){Add-Finding 'PORTABLE_EVIDENCE_DIGEST_MISMATCH' "Evidence-Digest fuer $platform stimmt nicht.";continue}
            try{$document=Get-Content -LiteralPath $evidencePath -Raw|ConvertFrom-Json}catch{Add-Finding 'PORTABLE_EVIDENCE_INVALID' "Evidence fuer $platform ist ungueltig.";continue}
            $provenance=$document.provenance
            $attestation=$pointer.attestation
            $provenanceStructured=$document.schemaVersion-is[int]-and$document.schemaVersion-eq 1-and[string]$document.kind-ceq'platform-portability-evidence'-and[string]$document.platform-ceq$platform-and[string]$document.status-ceq'passed'-and[string]$document.componentDigest-ceq$calculatedComponentDigest-and(Test-Digest $document.snapshotDigest)-and$provenance-is[pscustomobject]-and[string]$provenance.kind-ceq'github-actions'-and[string]$provenance.runId-match'^\d+$'-and[string]$provenance.runUrl-match'^https://github\.com/sivla/Universaarl-Control-Center/actions/runs/\d+$'-and[string]$provenance.repository-ceq'https://github.com/sivla/Universaarl-Control-Center'-and[string]$provenance.workflow-match'^\.github/workflows/[^/]+\.ya?ml$'-and[string]$provenance.commit-ceq[string]$manifest.controlContract.validatorCommit-and[string]$provenance.osName-ceq$platform-and-not[string]::IsNullOrWhiteSpace([string]$provenance.osVersion)-and[string]$provenance.runnerImage-match("^"+$platform)-and[string]$provenance.startedAt-match'^\d{4}-\d{2}-\d{2}T'-and[string]$provenance.completedAt-match'^\d{4}-\d{2}-\d{2}T'-and$attestation-is[pscustomobject]-and(Test-RelativeAssetPath $attestation.artifactName)-and[string]$attestation.artifactUrl-match'^https://api\.github\.com/repos/sivla/Universaarl-Control-Center/actions/artifacts/\d+/zip$'-and(Test-Digest $attestation.artifactSha256)
            if(-not$provenanceStructured-or-not(Test-GitHubActionsProvenance -Provenance $provenance -Attestation $attestation -Platform $platform -LocalAssetRoot $manifestRoot -EvidenceRelative ([string]$pointer.evidenceFile) -EvidenceDigest ([string]$pointer.sha256) -Document $document -SnapshotDigest ([string]$document.snapshotDigest) -ComponentDigest $calculatedComponentDigest)){Add-Finding 'PORTABLE_EVIDENCE_PROVENANCE_PENDING' "GitHub-Run, Runner und heruntergeladenes Attestierungsarchiv samt Evidence-Membern fuer $platform sind nicht anonym verifizierbar und bleiben PENDING."}
            $snapshotDigests[$platform]=[string]$document.snapshotDigest
            $records=@($document.records); if($records.Count -ne $requiredRecords.Count){Add-Finding 'PORTABLE_EVIDENCE_RECORD_COUNT' "Evidence fuer $platform besitzt nicht exakt alle Ausfuehrungsrecords."}
            foreach($recordId in $requiredRecords){$matches=@($records|Where-Object{[string]$_.id -ceq $recordId});if($matches.Count -ne 1){Add-Finding 'PORTABLE_EVIDENCE_RECORD_MISSING' "Record '$recordId' fuer $platform fehlt oder ist doppelt."}else{Test-EvidenceRecord $matches[0] $recordId $manifestRoot $platform ([string]$document.snapshotDigest) $calculatedComponentDigest -MetadataOnly}}
            $bound=@($document.components);foreach($component in $components){if(@($bound|Where-Object{[string]$_.id -ceq [string]$component.id -and [string]$_.commit -ceq [string]$component.commit -and [string]$_.tree -ceq [string]$component.tree}).Count -ne 1){Add-Finding 'PORTABLE_EVIDENCE_COMPONENT_MISMATCH' "Evidence fuer $platform bindet $($component.id) nicht exakt."}}
        }
        if(-not(Test-Digest $manifest.snapshotDigest)-or -not $snapshotDigests.ContainsKey('windows') -or -not $snapshotDigests.ContainsKey('macos') -or $snapshotDigests.windows -cne [string]$manifest.snapshotDigest -or $snapshotDigests.macos -cne [string]$manifest.snapshotDigest){Add-Finding 'PORTABLE_SNAPSHOT_DIGEST_MISMATCH' 'Windows und macOS binden nicht denselben unveraenderlichen Snapshotdigest.'}
    }
}
catch { Add-Finding 'PORTABLE_VALIDATION_FAILED' $_.Exception.Message }
finally { foreach($root in $cleanupRoots){if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue}} }

$status=if($findings.Count -eq 0){'PORTABLE_RELEASE_READY'}else{'BLOCKED'}
$result=[pscustomobject]@{schemaVersion=3;status=$status;manifest=[IO.Path]::GetFullPath($ManifestPath);findings=@($findings)}
if($Json){$result|ConvertTo-Json -Depth 8 -Compress}elseif($status -eq 'PORTABLE_RELEASE_READY'){Write-Output 'PORTABLE_RELEASE_READY'}else{Write-Output 'BLOCKED: Der Portfolio-Stand ist nicht portabel abgenommen.';foreach($finding in $findings){Write-Output "- [$($finding.code)] $($finding.message)"}}
if($findings.Count -gt 0){exit 1}
