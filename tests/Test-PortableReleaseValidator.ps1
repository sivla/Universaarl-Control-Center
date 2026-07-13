[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$validator = Join-Path $root 'scripts/Test-UniversaarlPortableRelease.ps1'
$template = Join-Path $root 'release/portfolio-portability-manifest.template.json'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('universaarl-portable-validator-' + [Guid]::NewGuid().ToString('N'))
$powerShell = (Get-Process -Id $PID).Path
function Assert-True([bool]$Condition,[string]$Message){if(-not$Condition){throw "TEST FEHLGESCHLAGEN: $Message"}}
function Get-Digest([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Get-TextDigest([string]$Text){$sha=[Security.Cryptography.SHA256]::Create();try{([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}}
function Write-Json([string]$Path,[object]$Value){$parent=Split-Path -Parent $Path;[IO.Directory]::CreateDirectory($parent)|Out-Null;[IO.File]::WriteAllText($Path,(($Value|ConvertTo-Json -Depth 20)+"`n"),[Text.UTF8Encoding]::new($false))}
function Invoke-Validation([string]$Path){$output=@(& $powerShell -NoProfile -ExecutionPolicy Bypass -File $validator -ManifestPath $Path -Json 2>&1);$exit=$LASTEXITCODE;$document=($output-join"`n")|ConvertFrom-Json;[pscustomobject]@{exit=$exit;document=$document;raw=($output-join"`n")}}
function New-Records([string]$Platform,[switch]$MissingExecution){
    $records=[Collections.Generic.List[object]]::new()
    $commands=[ordered]@{'fresh-clone'='git clone --filter=blob:none <portfolio-components>';install='spectra install --locked';start='twin start --snapshot <snapshot-digest>'; 'no-git-runtime'='twin verify --no-git-runtime';'pilot-visible'='twin verify --project bc-basic';'filesystem-http-parity'='twin verify --transport-parity';onboarding='spectra project onboard --isolated';isolation='twin verify --project-isolation'}
    foreach($id in @('fresh-clone','install','start','no-git-runtime','pilot-visible','filesystem-http-parity','onboarding','isolation')){
        $relative="artifacts/$Platform-$id.json";$path=Join-Path $testRoot ($relative-replace'/',[IO.Path]::DirectorySeparatorChar);$command=[string]$commands[$id];$artifact=[ordered]@{schemaVersion=1;recordId=$id;platform=$Platform;status='passed';snapshotDigest=$script:CurrentFixtureSnapshot;componentDigest=Get-TextDigest '';commandSha256=Get-TextDigest $command;outputDigest=('9'*64);checks=@('fixture-check')};Write-Json $path $artifact
        $record=[ordered]@{id=$id;command=$command;exitCode=0;artifact=$relative;artifactSha256=Get-Digest $path;startedAt='2026-07-13T10:00:00Z';completedAt='2026-07-13T10:01:00Z'}
        if($MissingExecution -and $id -eq 'install'){$record.command='';$record.Remove('artifactSha256')}
        $records.Add($record)
    }
    @($records)
}
function New-Evidence([string]$Platform,[string]$SnapshotDigest,[ValidateSet('records','booleans','missing')][string]$Mode='records'){
    $script:CurrentFixtureSnapshot=$SnapshotDigest
    $value=[ordered]@{schemaVersion=1;kind='platform-portability-evidence';platform=$Platform;status='passed';componentDigest=Get-TextDigest '';snapshotDigest=$SnapshotDigest;provenance=[ordered]@{kind='fixture-local';runId='fixture';runUrl='https://example.invalid';repository='https://github.com/sivla/Universaarl-Control-Center';workflow='portable';commit=('b'*40);osName=$Platform;osVersion='test';runnerImage="$Platform-test";startedAt='2026-07-13T10:00:00Z';completedAt='2026-07-13T10:10:00Z'};components=@()}
    if($Mode-eq'booleans'){$value.records=@();$value.freshClone=$true;$value.install=$true;$value.start=$true;$value.noGitRuntime=$true;$value.pilotSnapshotVisible=$true;$value.filesystemHttpParity=$true;$value.isolatedProjectOnboarding=$true}else{$value.records=New-Records $Platform -MissingExecution:($Mode-eq'missing')}
    [pscustomobject]$value
}
function New-Manifest([string]$WindowsDigest,[string]$MacDigest,[string]$WindowsMode='records',[string]$MacMode='records'){
    $windowsPath=Join-Path $testRoot 'evidence/windows.json';$macPath=Join-Path $testRoot 'evidence/macos.json'
    Write-Json $windowsPath (New-Evidence 'windows' $WindowsDigest $WindowsMode);Write-Json $macPath (New-Evidence 'macos' $MacDigest $MacMode)
    $attestation=[ordered]@{artifactName='portable-evidence';artifactUrl='https://api.github.com/repos/sivla/Universaarl-Control-Center/actions/artifacts/1/zip';artifactSha256=('a'*64)}
    [pscustomobject][ordered]@{schemaVersion=3;kind='portfolio-portability-final-evidence';status='READY';controlContract=[ordered]@{validatorCommit=('b'*40);templatePath='release/portfolio-portability-manifest.template.json';templateSchemaVersion=3};componentDigest=Get-TextDigest '';snapshotDigest=$WindowsDigest;components=@();spectraBinding=[ordered]@{tag='spectra-v1.1.0-alpha.1';manifestPath='release/versions/1.1.0-alpha.1/release-manifest.json';manifestFileSha256=('c'*64);aggregateDigestAlgorithm='SHA-256';aggregatePayloadDigest=('d'*64)};platformEvidence=[ordered]@{windows=[ordered]@{status='passed';evidenceFile='evidence/windows.json';sha256=Get-Digest $windowsPath;attestation=$attestation};macos=[ordered]@{status='passed';evidenceFile='evidence/macos.json';sha256=Get-Digest $macPath;attestation=$attestation}}}
}

try{
    [IO.Directory]::CreateDirectory($testRoot)|Out-Null
    Assert-True (Test-Path -LiteralPath $template -PathType Leaf) 'Versionierte Portabilitaetsvorlage fehlt.'
    $templateResult=Invoke-Validation $template
    Assert-True ($templateResult.exit-ne 0 -and @($templateResult.document.findings.code)-contains'PORTABLE_MANIFEST_SELF_REFERENCE' -and @($templateResult.document.findings.code)-contains'PORTABLE_TEMPLATE_MISUSE') 'Template oder selbstreferenzielles Manifest wurde nicht abgelehnt.'

    $injectedRepo=Join-Path $testRoot 'injected-repository';[IO.Directory]::CreateDirectory($injectedRepo)|Out-Null;& git -C $injectedRepo init --quiet;& git -C $injectedRepo config review.injected from-git-dir
    $saved=@{};foreach($name in @('GIT_CONFIG_COUNT','GIT_CONFIG_KEY_0','GIT_CONFIG_VALUE_0','GIT_CONFIG_PARAMETERS','GIT_ASKPASS','GIT_SSH_COMMAND','GIT_DIR','GIT_WORK_TREE','GIT_COMMON_DIR','GIT_OBJECT_DIRECTORY','GIT_ALTERNATE_OBJECT_DIRECTORIES','SSH_AUTH_SOCK','GH_TOKEN')){$saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
    try{
        [Environment]::SetEnvironmentVariable('GIT_CONFIG_COUNT','1','Process');[Environment]::SetEnvironmentVariable('GIT_CONFIG_KEY_0','review.injected','Process');[Environment]::SetEnvironmentVariable('GIT_CONFIG_VALUE_0','yes','Process');[Environment]::SetEnvironmentVariable('GIT_CONFIG_PARAMETERS',"'review.injected=also'",'Process');[Environment]::SetEnvironmentVariable('GIT_ASKPASS','invalid-askpass','Process');[Environment]::SetEnvironmentVariable('GIT_SSH_COMMAND','invalid-ssh','Process');[Environment]::SetEnvironmentVariable('GIT_DIR',(Join-Path $injectedRepo '.git'),'Process');[Environment]::SetEnvironmentVariable('GIT_WORK_TREE',$injectedRepo,'Process');[Environment]::SetEnvironmentVariable('GIT_COMMON_DIR',(Join-Path $injectedRepo '.git'),'Process');[Environment]::SetEnvironmentVariable('GIT_OBJECT_DIRECTORY',(Join-Path $injectedRepo '.git/objects'),'Process');[Environment]::SetEnvironmentVariable('GIT_ALTERNATE_OBJECT_DIRECTORIES',(Join-Path $injectedRepo '.git/objects'),'Process');[Environment]::SetEnvironmentVariable('SSH_AUTH_SOCK','invalid-agent','Process');[Environment]::SetEnvironmentVariable('GH_TOKEN','invalid-token','Process')
        $probe=@(& $powerShell -NoProfile -ExecutionPolicy Bypass -File $validator -AnonymousGitSelfTest 2>&1)
        Assert-True ($LASTEXITCODE-eq 0 -and ($probe-join"`n").Trim()-ceq'ANONYMOUS_GIT_SANITIZATION_PASSED') 'Git-Konfigurations-/Auth-Injektion wurde nicht verhaltensgeprueft abgewehrt.'
    }finally{foreach($name in $saved.Keys){[Environment]::SetEnvironmentVariable($name,$saved[$name],'Process')}}
    $digestProbe=@(& $powerShell -NoProfile -ExecutionPolicy Bypass -File $validator -SpectraDigestSelfTest 2>&1)
    Assert-True ($LASTEXITCODE-eq 0 -and ($digestProbe-join"`n").Trim()-ceq'SPECTRA_DIGEST_SEPARATION_PASSED') 'Manifestdatei-SHA und deklarierter Spectra-Aggregatdigest wurden nicht getrennt geprueft.'
    $anchorProbe=@(& $powerShell -NoProfile -ExecutionPolicy Bypass -File $validator -ControlAnchorSelfTest 2>&1)
    Assert-True ($LASTEXITCODE-eq 0 -and ($anchorProbe-join"`n").Trim()-ceq'CONTROL_ANCHOR_SELF_TEST_PASSED') 'Modifizierter/ungetrackter Validator oder Template wurde nicht durch den Trust Anchor blockiert.'
    $archiveProbe=@(& $powerShell -NoProfile -ExecutionPolicy Bypass -File $validator -ArchiveBindingSelfTest 2>&1)
    Assert-True ($LASTEXITCODE-eq 0 -and ($archiveProbe-join"`n").Trim()-ceq'ARCHIVE_EVIDENCE_BINDING_PASSED') 'Attestierungsarchiv wurde nicht gegen lokale Evidence, fehlende oder traversierende Member verhaltensgeprueft.'

    $manifestPath=Join-Path $testRoot 'portfolio-final.json';$snapshot='e'*64
    Write-Json $manifestPath (New-Manifest $snapshot $snapshot 'booleans' 'records');$booleanResult=Invoke-Validation $manifestPath
    Assert-True ($booleanResult.exit-ne 0 -and @($booleanResult.document.findings.code)-contains'PORTABLE_EVIDENCE_RECORD_COUNT' -and @($booleanResult.document.findings.code)-contains'PORTABLE_EVIDENCE_RECORD_MISSING') 'Freie Boolean-Evidence wurde akzeptiert.'
    Write-Json $manifestPath (New-Manifest $snapshot $snapshot 'missing' 'records');$missingResult=Invoke-Validation $manifestPath
    Assert-True ($missingResult.exit-ne 0 -and @($missingResult.document.findings.code)-contains'PORTABLE_EVIDENCE_RECORD_INVALID') 'Fehlende Command-/Artefaktfelder wurden akzeptiert.'
    Write-Json $manifestPath (New-Manifest $snapshot ('f'*64) 'records' 'records');$mismatchResult=Invoke-Validation $manifestPath
    Assert-True ($mismatchResult.exit-ne 0 -and @($mismatchResult.document.findings.code)-contains'PORTABLE_SNAPSHOT_DIGEST_MISMATCH') 'Unterschiedliche Windows-/macOS-Snapshotdigests wurden akzeptiert.'
    $unsupported=New-Manifest $snapshot $snapshot 'records' 'records';$macEvidencePath=Join-Path $testRoot 'evidence/macos.json';$macEvidence=Get-Content -LiteralPath $macEvidencePath -Raw|ConvertFrom-Json;$macEvidence.provenance.kind='work-mac';Write-Json $macEvidencePath $macEvidence;$unsupported.platformEvidence.macos.sha256=Get-Digest $macEvidencePath;Write-Json $manifestPath $unsupported;$unsupportedResult=Invoke-Validation $manifestPath
    Assert-True ($unsupportedResult.exit-ne 0 -and @($unsupportedResult.document.findings.code)-contains'PORTABLE_EVIDENCE_PROVENANCE_PENDING') 'Nicht verifizierbare lokale Attestation wurde nicht als PENDING blockiert.'

    $cleanupBefore=@(Get-ChildItem -LiteralPath ([IO.Path]::GetTempPath()) -Directory -Filter 'universaarl-public-verify-*' -ErrorAction SilentlyContinue|ForEach-Object FullName)
    $spectraLine='spectra|https://github.com/sivla/BCProjectOS.git|refs/tags/spectra-v1.1.0-alpha.1|1dc0fd14c256dfc926eae48b1e1f664339ebb9e4|6b17c699bf9dbe264bb276e6b142d9befe746f75'
    $malformed=[ordered]@{schemaVersion=3;kind='portfolio-portability-final-evidence';status='READY';controlContract=[ordered]@{validatorCommit=('b'*40);templatePath='release/portfolio-portability-manifest.template.json';templateSchemaVersion=3};componentDigest=Get-TextDigest $spectraLine;snapshotDigest=$snapshot;components=@([ordered]@{id='spectra';repository='https://github.com/sivla/BCProjectOS.git';public=$true;ref='refs/tags/spectra-v1.1.0-alpha.1';commit='1dc0fd14c256dfc926eae48b1e1f664339ebb9e4';tree='6b17c699bf9dbe264bb276e6b142d9befe746f75'});spectraBinding=[ordered]@{tag='spectra-v1.1.0-alpha.1';manifestPath='release/versions/1.1.0-alpha.1/release-manifest.json';manifestFileSha256='f90e0dfb03298067c89732c7f0996fa0a65dcd1ee0a2cc169bc97fbfcabb8160';aggregateDigestAlgorithm='SHA-256';aggregatePayloadDigest=('d'*64)}}
    Write-Json $manifestPath $malformed;$cleanupResult=Invoke-Validation $manifestPath
    $cleanupAfter=@(Get-ChildItem -LiteralPath ([IO.Path]::GetTempPath()) -Directory -Filter 'universaarl-public-verify-*' -ErrorAction SilentlyContinue|ForEach-Object FullName)
    Assert-True ($cleanupResult.exit-ne 0 -and @($cleanupAfter|Where-Object{$_ -notin $cleanupBefore}).Count-eq 0) "Temporaerer Clone blieb nach anonymer Fetch-/StrictMode-Ausnahme liegen: $($cleanupResult.raw)"

    $source=Get-Content -LiteralPath $validator -Raw
    Assert-True ($source -match 'elseif\(\$status -eq ''PORTABLE_RELEASE_READY''\)\{Write-Output ''PORTABLE_RELEASE_READY''\}' -and $source -notmatch "Write-Host 'PORTABLE_RELEASE_READY'") 'Ready-Pfad garantiert nicht exakt die maschinenlesbare Ausgabe.'
    Write-Output 'Portable-Release-Validator-Fixtures bestanden: Config-Injektion, Evidencefelder, Snapshotdigest, Boolean-Atteste, Template/Selbstreferenz und Ready-Ausgabe.'
}finally{if(Test-Path -LiteralPath $testRoot){Remove-Item -LiteralPath $testRoot -Recurse -Force}}
