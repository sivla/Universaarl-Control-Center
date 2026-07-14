[CmdletBinding()]
param(
    [switch]$RunValidations,
    [switch]$FailOnWarning,
    [string]$RunId,
    [string]$ConfigPath,
    [string]$ReportRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$MonitorRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
. (Join-Path $PSScriptRoot 'Universaarl-Control.Common.ps1')
if ([string]::IsNullOrWhiteSpace($RunId)) { $RunId = New-UniversaarlRunId -Prefix 'audit' }
Assert-UniversaarlRunId -RunId $RunId
if ([string]::IsNullOrWhiteSpace($ConfigPath)) { $ConfigPath = Join-Path $MonitorRoot 'monitor.config.json' }
$Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
Assert-UniversaarlMonitorConfiguration -Configuration $Config
if ([string]::IsNullOrWhiteSpace($ReportRoot)) { $ReportRoot = Join-Path $MonitorRoot ([string]$Config.reportDirectory) }
$ReportRoot = [IO.Path]::GetFullPath($ReportRoot)
if (-not $ReportRoot.StartsWith($MonitorRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Berichtverzeichnis muss innerhalb des Kontrollzentrums liegen.' }
$ReportTrustedRoot = $MonitorRoot
$RunReportRoot = Join-Path $ReportRoot 'runs'
$LogRoot = Join-Path $ReportRoot 'logs'
$StartedAt = (Get-Date).ToUniversalTime()

function New-Finding {
    param(
        [Parameter(Mandatory)][ValidateSet('critical', 'high', 'medium', 'low', 'info')][string]$Severity,
        [Parameter(Mandatory)][string]$Code,
        [Parameter(Mandatory)][string]$Message
    )
    [pscustomobject]@{ severity = $Severity; code = $Code; message = $Message }
}

function Get-HeadCommit {
    param([Parameter(Mandatory)][string]$Repository)
    $head = Invoke-UniversaarlGitRead -Repository $Repository -Arguments @('rev-parse', '--verify', 'HEAD^{commit}')
    if ($head.exitCode -ne 0) { throw 'HEAD kann nicht als Commit aufgeloest werden.' }
    Assert-FullCommitSha -Commit $head.output
    $head.output
}

function Get-PathSet {
    param([object[]]$Tree)
    $set = @{}
    foreach ($entry in $Tree) { $set[[string]$entry.path] = $entry }
    $set
}

function Get-ActiveChangeNames {
    param([object[]]$Tree)
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in $Tree) {
        if ([string]$entry.path -match '^openspec/changes/([^/]+)/') {
            $name = $Matches[1]
            if ($name -notin @('archive', 'archived')) { $null = $names.Add($name) }
        }
    }
    @($names | Sort-Object)
}

function Get-ProjectObservation {
    param([Parameter(Mandatory)]$Project, [Parameter(Mandatory)][string]$TargetPath)
    $findings = [Collections.Generic.List[object]]::new()
    $result = [ordered]@{
        id = [string]$Project.id
        name = [string]$Project.name
        pathAlias = [string]$Project.pathAlias
        exists = $false
        gitRepository = $false
        hasCommit = $false
        branch = '(nicht verfuegbar)'
        commit = $null
        dirty = $null
        requiredScriptFound = $false
        germanScriptFound = $false
        lockfileFound = $false
        unpinnedDependencyCount = 0
        activeChangeCount = $null
        activeChangeName = $null
        reviewWorkingEmpty = $false
        reviewHeadEmpty = $false
        environmentExamplePresent = $false
        environmentExampleSafe = $null
        structuralScore = 0
        evidenceCoverage = 0
        validation = 'not-run'
        validationExitCode = $null
        germanValidation = 'not-run'
        germanValidationExitCode = $null
        fingerprintBefore = $null
        fingerprintAfter = $null
        targetUnchanged = $null
        snapshotEligible = $false
        findings = @()
    }

    if (-not (Test-Path -LiteralPath $TargetPath -PathType Container)) {
        $findings.Add((New-Finding critical 'PATH-001' 'Das konfigurierte Projekt ist nicht erreichbar.'))
        $result.findings = @($findings)
        return [pscustomobject]$result
    }
    $result.exists = $true

    try {
        $commit = Get-HeadCommit -Repository $TargetPath
        $result.commit = $commit
        $result.hasCommit = $true
        $tree = @(Get-UniversaarlCommitTree -Repository $TargetPath -Commit $commit)
        Assert-UniversaarlCommitRuntimeSafe -Repository $TargetPath -Commit $commit -AllowedVersionedMedia @($Project.allowedVersionedMedia)
        $result.snapshotEligible = $true
        $fingerprint = Get-UniversaarlRepositoryFingerprint -Repository $TargetPath
        $result.gitRepository = $true
        $result.branch = $fingerprint.branch
        $result.dirty = $fingerprint.dirty
        $result.fingerprintBefore = $fingerprint
        if ($fingerprint.dirty) { $findings.Add((New-Finding medium 'GIT-003' 'Der lokale Arbeitsbaum ist nicht sauber.')) }
    }
    catch {
        $findings.Add((New-Finding critical 'GIT-001' "Der commitgebundene Git-Ausgangsstand kann nicht sicher gelesen werden: $($_.Exception.Message)"))
        $result.findings = @($findings)
        return [pscustomobject]$result
    }

    $paths = Get-PathSet -Tree $tree
    try {
        $packageBlob = Read-UniversaarlCommitText -Repository $TargetPath -Commit $commit -Path 'package.json' -MaximumBytes 1048576 -Required
        $package = $packageBlob.content | ConvertFrom-Json
        $requiredScript = [string]$Project.requiredNpmScript
        $result.requiredScriptFound = $null -ne $package.scripts -and $package.scripts.PSObject.Properties.Name -contains $requiredScript
        if (-not $result.requiredScriptFound) { $findings.Add((New-Finding critical 'RUN-001' "Das erforderliche npm-Skript '$requiredScript' fehlt im Commit.")) }
        $germanScript = if ($null -ne $Project.germanCheck) { [string]$Project.germanCheck.npmScript } else { '' }
        $result.germanScriptFound = -not [string]::IsNullOrWhiteSpace($germanScript) -and $null -ne $package.scripts -and $package.scripts.PSObject.Properties.Name -contains $germanScript
        if (-not $result.germanScriptFound) { $findings.Add((New-Finding critical 'LANG-001' 'Der konfigurierte projektspezifische maschinenlesbare Deutsch-Pruefer fehlt im Commit.')) }
        $dependencyProperties = @()
        if ($package.PSObject.Properties.Name -contains 'dependencies' -and $null -ne $package.dependencies) { $dependencyProperties += $package.dependencies.PSObject.Properties }
        if ($package.PSObject.Properties.Name -contains 'devDependencies' -and $null -ne $package.devDependencies) { $dependencyProperties += $package.devDependencies.PSObject.Properties }
        $result.unpinnedDependencyCount = @($dependencyProperties | Where-Object { [string]$_.Value -in @('latest', '*') }).Count
        if ($result.unpinnedDependencyCount -gt 0) { $findings.Add((New-Finding low 'DEP-002' "$($result.unpinnedDependencyCount) Abhaengigkeit(en) verwenden einen nicht festgelegten Versionswert.")) }
    }
    catch { $findings.Add((New-Finding critical 'MANIFEST-001' "package.json kann nicht commitgebunden gelesen oder geparst werden: $($_.Exception.Message)")) }

    $result.lockfileFound = $paths.ContainsKey('package-lock.json')
    if (-not $result.lockfileFound) { $findings.Add((New-Finding high 'DEP-001' 'package-lock.json fehlt im Commit.')) }

    $activeChanges = @(Get-ActiveChangeNames -Tree $tree)
    $result.activeChangeCount = $activeChanges.Count
    if ($activeChanges.Count -eq 1) { $result.activeChangeName = $activeChanges[0] }
    if ($activeChanges.Count -gt [int]$Project.maxActiveChanges) { $findings.Add((New-Finding high 'WIP-001' "$($activeChanges.Count) aktive OpenSpec-Aenderungen ueberschreiten das erlaubte Maximum $($Project.maxActiveChanges).")) }
    foreach ($change in $activeChanges) {
        $taskPath = "openspec/changes/$change/tasks.md"
        if ($paths.ContainsKey($taskPath)) {
            try {
                $tasks = Read-UniversaarlCommitText -Repository $TargetPath -Commit $commit -Path $taskPath -MaximumBytes 262144 -Required
                if ($tasks.content -match '(?m)^\s*-\s*\[\s\]\s+') { $findings.Add((New-Finding high 'WIP-003' "Die aktive Aenderung '$change' enthaelt offene Aufgaben.")) }
            }
            catch { $findings.Add((New-Finding high 'WIP-004' "Aufgaben der aktiven Aenderung '$change' koennen nicht sicher gelesen werden.")) }
        }
        else { $findings.Add((New-Finding high 'WIP-004' "Aufgabendatei der aktiven Aenderung '$change' fehlt im Commit.")) }
    }

    $reviewFile = [string]$Project.reviewFile
    try {
        $reviewHead = Read-UniversaarlCommitText -Repository $TargetPath -Commit $commit -Path $reviewFile -MaximumBytes 65536 -Required
        $result.reviewHeadEmpty = [string]::IsNullOrWhiteSpace([string]$reviewHead.content)
        if (-not $result.reviewHeadEmpty) { $findings.Add((New-Finding high 'REVIEW-005' "Pruefdatei '$reviewFile' ist im Commit nicht leer.")) }
    }
    catch { $findings.Add((New-Finding high 'REVIEW-004' "Pruefdatei '$reviewFile' ist im Commit nicht als kleine regulaere Datei lesbar: $($_.Exception.Message)")) }
    if ($result.dirty -eq $false) {
        try {
            $reviewWorking = Read-UniversaarlWorkingText -Repository $TargetPath -Path $reviewFile -MaximumBytes 65536 -RequireCleanRepository
            $result.reviewWorkingEmpty = [string]::IsNullOrWhiteSpace($reviewWorking)
            if (-not $result.reviewWorkingEmpty) { $findings.Add((New-Finding high 'REVIEW-003' "Pruefdatei '$reviewFile' ist in der Arbeitskopie nicht leer.")) }
        }
        catch { $findings.Add((New-Finding high 'REVIEW-002' "Pruefdatei '$reviewFile' kann in der sauberen Arbeitskopie nicht sicher geprueft werden: $($_.Exception.Message)")) }
    }

    $environment = Test-UniversaarlEnvironmentExample -Repository $TargetPath -Commit $commit
    $result.environmentExamplePresent = $environment.present
    $result.environmentExampleSafe = $environment.safe
    foreach ($finding in @($environment.findings)) { $findings.Add((New-Finding $finding.severity $finding.code $finding.message)) }
    if ($environment.present -and $environment.safe -ne $true) { $result.snapshotEligible = $false }

    $score = 20
    if ($result.hasCommit) { $score += 20 }
    if ($result.dirty -eq $false) { $score += 15 }
    if ($result.requiredScriptFound) { $score += 10 }
    if ($result.germanScriptFound) { $score += 10 }
    if ($result.lockfileFound) { $score += 10 }
    if ($activeChanges.Count -le [int]$Project.maxActiveChanges) { $score += 5 }
    if ($result.reviewHeadEmpty -and $result.reviewWorkingEmpty) { $score += 10 }
    $result.structuralScore = [Math]::Min(100, $score)
    $result.evidenceCoverage = 80
    $result.findings = @($findings)
    [pscustomobject]$result
}

function Get-VerificationSourceObservation {
    param([Parameter(Mandatory)]$Source, [Parameter(Mandatory)][string]$TargetPath)
    $findings = [Collections.Generic.List[object]]::new()
    $result = [ordered]@{
        id = 'bcprojectos'
        technicalProjectName = [string]$Source.technicalProjectName
        productName = [string]$Source.expectedProduct.name
        productId = [string]$Source.expectedProduct.productId
        pathAlias = [string]$Source.pathAlias
        exists = $false
        gitRepository = $false
        sourceCommit = $null
        branch = '(nicht verfuegbar)'
        dirty = $null
        remoteUrl = $null
        fingerprintBefore = $null
        fingerprintAfter = $null
        targetUnchanged = $null
        status = 'failed'
        findings = @()
    }
    if (-not (Test-Path -LiteralPath $TargetPath -PathType Container)) {
        $findings.Add((New-Finding critical 'SPECTRA-SOURCE-001' 'Die konfigurierte technische Spectra-Evidence-Quelle BCProjectOS ist nicht erreichbar.'))
        $result.findings = @($findings)
        return [pscustomobject]$result
    }
    $result.exists = $true
    try {
        $result.sourceCommit = Get-HeadCommit -Repository $TargetPath
        $fingerprint = Get-UniversaarlRepositoryFingerprint -Repository $TargetPath
        $result.gitRepository = $true
        $result.branch = $fingerprint.branch
        $result.dirty = $fingerprint.dirty
        $result.fingerprintBefore = $fingerprint
        $result.remoteUrl = Get-UniversaarlRawFetchUrl -Repository $TargetPath -Remote ([string]$Source.remote)
        if ([string]$result.remoteUrl -cne [string]$Source.canonicalRemoteUrl) {
            $findings.Add((New-Finding critical 'SPECTRA-SOURCE-002' 'Die rohe BCProjectOS-Remote-URL stimmt nicht exakt mit der Spectra-Evidence-Positivliste ueberein.'))
        }
        if ($findings.Count -eq 0) { $result.status = 'observed' }
    }
    catch { $findings.Add((New-Finding critical 'SPECTRA-SOURCE-003' "Die technische Spectra-Evidence-Quelle kann nicht sicher gelesen werden: $($_.Exception.Message)")) }
    $result.findings = @($findings)
    [pscustomobject]$result
}

function Get-SpectraBindingObservation {
    param([Parameter(Mandatory)][string]$Repository, [Parameter(Mandatory)][string]$Commit, [Parameter(Mandatory)][string]$ProviderRepository)
    $findings = [Collections.Generic.List[object]]::new()
    try {
        $snapshotProof = Test-UniversaarlPortableSnapshotRelease -Repository $Repository -Commit $Commit -SpectraRepository $ProviderRepository
        $bound = $snapshotProof.spectraBinding
        $proof = $snapshotProof.spectraProof
        return [pscustomobject]@{ id='blueprint-binds-spectra'; contractType='versioned-product-release'; status='passed'; fullValidationPassed=$true; bindingStatus='BOUND'; productName='Spectra'; productId='spectra'; technicalProjectName='BCProjectOS'; repositoryUrl='https://github.com/sivla/BCProjectOS.git'; binding=$bound; proof=$proof; snapshotProof=$snapshotProof; findings=@() }
    }
    catch {
        $findings.Add((New-Finding critical 'SPECTRA-BINDING-INVALID' "Die releasegebundene Spectra- und Snapshotkette ist ungueltig: $($_.Exception.Message)"))
    }
    [pscustomobject]@{
        id = 'blueprint-binds-spectra'
        contractType = 'versioned-product-release'
        status = 'failed'
        fullValidationPassed = $false
        bindingStatus = 'invalid'
        productName = 'Spectra'
        productId = 'spectra'
        technicalProjectName = 'BCProjectOS'
        repositoryUrl = 'https://github.com/sivla/BCProjectOS.git'
        findings = @($findings)
    }
}

function Get-NpmRuntime {
    $node = Resolve-UniversaarlTool -Names @('node', 'node.exe') -Description 'Node.js'
    if (-not (Test-UniversaarlIsWindows)) {
        $npm = Resolve-UniversaarlTool -Names @('npm') -Description 'npm'
        return [pscustomobject]@{ executable = $npm; prefix = @() }
    }
    $npm = Resolve-UniversaarlTool -Names @('npm.cmd') -Description 'npm'
    $npmCli = Join-Path (Split-Path -Parent $npm) 'node_modules\npm\bin\npm-cli.js'
    if (-not (Test-Path -LiteralPath $npmCli -PathType Leaf)) { throw 'npm-cli.js wurde nicht gefunden.' }
    [pscustomobject]@{ executable = $node; prefix = @($npmCli) }
}

function Invoke-ProjectValidation {
    param(
        [Parameter(Mandatory)]$Project,
        [Parameter(Mandatory)][string]$Commit,
        [Parameter(Mandatory)][string]$SnapshotPath,
        [Parameter(Mandatory)][string]$SandboxRoot,
        [Parameter(Mandatory)]$Runner,
        [Parameter(Mandatory)][hashtable]$AdditionalEnvironment
    )
    $runtime = Get-NpmRuntime
    $installLog = Join-Path $LogRoot "$RunId-$($Project.id)-installation.log"
    $validationLog = Join-Path $LogRoot "$RunId-$($Project.id)-pruefung.log"
    $languageLog = Join-Path $LogRoot "$RunId-$($Project.id)-deutsch.log"
    $sensitiveRoots = @($SnapshotPath, $SandboxRoot)
    $install = Invoke-UniversaarlSanitizedProcess -Runner $Runner -FilePath $runtime.executable -Arguments (@($runtime.prefix) + @('ci', '--ignore-scripts', '--no-audit', '--no-fund')) -WorkingDirectory $SnapshotPath -SandboxRoot $SandboxRoot -LogPath $installLog -LogRoot $LogRoot -AdditionalEnvironment $AdditionalEnvironment -TimeoutSeconds ([int]$Config.validationTimeoutSeconds) -SensitiveRoots $sensitiveRoots
    if ($install.exitCode -ne 0) { return [pscustomobject]@{ validation = 'failed'; validationExitCode = $install.exitCode; german = 'not-run'; germanExitCode = $null; reason = '`npm ci` ist in der bereinigten Wegwerfkopie fehlgeschlagen.' } }
    $validation = Invoke-UniversaarlSanitizedProcess -Runner $Runner -FilePath $runtime.executable -Arguments (@($runtime.prefix) + @($Project.validationArguments)) -WorkingDirectory $SnapshotPath -SandboxRoot $SandboxRoot -LogPath $validationLog -LogRoot $LogRoot -AdditionalEnvironment $AdditionalEnvironment -TimeoutSeconds ([int]$Config.validationTimeoutSeconds) -SensitiveRoots $sensitiveRoots
    if ($validation.exitCode -ne 0) { return [pscustomobject]@{ validation = 'failed'; validationExitCode = $validation.exitCode; german = 'not-run'; germanExitCode = $null; reason = if ($validation.timedOut) { 'Zeitlimit der technischen Pruefung ueberschritten.' } else { 'Die technische Pruefung ist fehlgeschlagen.' } } }

    $languageEnvironment = @{} + $AdditionalEnvironment
    $languageEnvironment['UNIVERSAARL_EXPECTED_COMMIT'] = $Commit
    $languageEnvironment['UNIVERSAARL_PROJECT_ID'] = [string]$Project.id
    $germanScript = [string]$Project.germanCheck.npmScript
    $language = Invoke-UniversaarlSanitizedProcess -Runner $Runner -FilePath $runtime.executable -Arguments (@($runtime.prefix) + @('--silent', 'run', $germanScript)) -WorkingDirectory $SnapshotPath -SandboxRoot $SandboxRoot -LogPath $languageLog -LogRoot $LogRoot -AdditionalEnvironment $languageEnvironment -TimeoutSeconds ([int]$Config.validationTimeoutSeconds) -SensitiveRoots $sensitiveRoots
    if ($language.exitCode -ne 0 -or $language.outputTruncated) { return [pscustomobject]@{ validation = 'passed'; validationExitCode = 0; german = 'failed'; germanExitCode = $language.exitCode; reason = 'Der projektspezifische Deutsch-Pruefer ist fehlgeschlagen oder lieferte zu viel Ausgabe.' } }
    try {
        $valid = Test-UniversaarlGermanEvidencePayload -Json $language.output -ProjectId ([string]$Project.id) -Commit $Commit -SchemaVersion ([int]$Project.germanCheck.resultSchemaVersion)
        if (-not $valid) { throw 'Ungueltiger Deutsch-Nachweis.' }
    }
    catch { return [pscustomobject]@{ validation = 'passed'; validationExitCode = 0; german = 'failed'; germanExitCode = 3; reason = 'Der projektspezifische Deutsch-Pruefer lieferte keinen gueltigen commitgebundenen JSON-Nachweis.' } }
    [pscustomobject]@{ validation = 'passed'; validationExitCode = 0; german = 'passed'; germanExitCode = 0; reason = $null }
}

function Get-TrafficLight {
    param([Parameter(Mandatory)]$Result)
    $severities = @($Result.findings | ForEach-Object { $_.severity })
    if ($severities -contains 'critical' -or $Result.validation -eq 'failed' -or $Result.germanValidation -eq 'failed' -or -not $Result.hasCommit) { return 'ROT' }
    if ($Result.validation -ne 'passed' -or $Result.germanValidation -ne 'passed') { return 'GRAU' }
    if ($severities -contains 'high' -or $severities -contains 'medium' -or $Result.structuralScore -lt 85) { return 'GELB' }
    'GRUEN'
}

$null = Initialize-UniversaarlSafeDirectory -TrustedRoot $ReportTrustedRoot -Directory $ReportRoot
$null = Initialize-UniversaarlSafeDirectory -TrustedRoot $ReportRoot -Directory $RunReportRoot
$null = Initialize-UniversaarlSafeDirectory -TrustedRoot $ReportRoot -Directory $LogRoot
$runJsonPath = Join-Path $RunReportRoot "$RunId.json"
$runMarkdownPath = Join-Path $RunReportRoot "$RunId.md"
if ((Test-Path -LiteralPath $runJsonPath) -or (Test-Path -LiteralPath $runMarkdownPath)) { throw 'Die Laufkennung wurde bereits verwendet.' }

$projectPaths = @{}
$projectConfigs = @{}
$results = [Collections.Generic.List[object]]::new()
foreach ($project in $Config.projects) {
    $path = Get-UniversaarlConfiguredPath -Project $project
    $projectPaths[[string]$project.id] = $path
    $projectConfigs[[string]$project.id] = $project
    $results.Add((Get-ProjectObservation -Project $project -TargetPath $path))
}

$verificationSourceConfig = $Config.verificationSources.bcprojectos
$verificationSourcePath = Get-UniversaarlConfiguredPath -Project $verificationSourceConfig
$verificationInput = Get-VerificationSourceObservation -Source $verificationSourceConfig -TargetPath $verificationSourcePath

$inputShas = [ordered]@{ blueprint = $null; 'project-twin' = $null }
foreach ($result in $results) { if ($result.commit) { $inputShas[[string]$result.id] = [string]$result.commit } }
$spectraRelationship = if ($inputShas['blueprint']) {
    Get-SpectraBindingObservation -Repository $projectPaths['blueprint'] -Commit $inputShas['blueprint'] -ProviderRepository $verificationSourcePath
}
else {
    [pscustomobject]@{ id = 'blueprint-binds-spectra'; contractType = 'versioned-product-release'; status = 'failed'; fullValidationPassed = $false; bindingStatus = 'unknown'; productName = 'Spectra'; productId = 'spectra'; technicalProjectName = 'BCProjectOS'; repositoryUrl = 'https://github.com/sivla/BCProjectOS.git'; findings = @((New-Finding critical 'SPECTRA-BINDING-UNKNOWN' 'Die Spectra-Bindung kann ohne vollstaendige Blueprint-Commit-SHA nicht geprueft werden.')) }
}
$spectraRelationship | Add-Member -NotePropertyName sourceCommit -NotePropertyValue $verificationInput.sourceCommit
$spectraRelationship | Add-Member -NotePropertyName consumerCommit -NotePropertyValue $inputShas['blueprint']
$relationshipFindings = [Collections.Generic.List[object]]::new()
$crossStatus = 'failed'
$crossFullValidationPassed = $false
$crossStats = $null
$crossWarnings = @()
$legacySmokeStatus = 'not-run'
$runtimeBindingInspected = $false
$SandboxRoot = $null

if ($inputShas['blueprint']) {
    try {
        $pointerEntry = Get-UniversaarlBlobEntry -Repository $projectPaths['blueprint'] -Commit $inputShas['blueprint'] -Path 'exports/project-data/v1/snapshots/current.json'
        if ($null -eq $pointerEntry) {
            $relationshipFindings.Add((New-Finding critical 'CROSS-SNAPSHOT-POINTER-MISSING' 'Der commitgebundene BC-Basic-Snapshotzeiger fehlt; die validierte Consumerbeziehung bleibt blockiert.'))
        }
        elseif ($spectraRelationship.fullValidationPassed -eq $true -and $null -ne $spectraRelationship.snapshotProof) {
            $snapshotProof = $spectraRelationship.snapshotProof
            $twinBoundaryProof = Test-UniversaarlTwinContractBoundary -Repository $projectPaths['project-twin'] -Commit $inputShas['project-twin']
            $crossStatus = 'passed'
            $crossFullValidationPassed = $true
            $crossStats = [pscustomobject]@{ snapshot=$snapshotProof; twinBoundary=$twinBoundaryProof }
        }
        else {
            $relationshipFindings.Add((New-Finding critical 'CROSS-SNAPSHOT-UPSTREAM-BLOCKED' 'Der portable Snapshot kann ohne vollstaendig gebundene Spectra-Evidence nicht freigegeben werden.'))
        }
    }
    catch { $relationshipFindings.Add((New-Finding critical 'CROSS-SNAPSHOT-INVALID' "Der portable Snapshot kann nicht sicher validiert werden: $($_.Exception.Message)")) }
}
else {
    $relationshipFindings.Add((New-Finding critical 'CROSS-SNAPSHOT-UNKNOWN' 'Ohne vollstaendige Blueprint-Commit-SHA kann kein portabler Snapshotvertrag geprueft werden.'))
}

if ($RunValidations) {
    $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
    # Der Laufbezug bleibt in den Berichten. Der physische Windows-Temp-Pfad
    # bleibt bewusst kurz, damit tiefe, commitgebundene Testfixtures nicht an
    # der klassischen Pfadlaengengrenze scheitern.
    $SandboxRoot = Join-Path $tempBase "uabc-a-$([Guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $SandboxRoot -Force | Out-Null
    try {
        $runner = Initialize-UniversaarlProcessRunner -ControlRoot $MonitorRoot -SandboxRoot $SandboxRoot
        $snapshotPaths = @{}
        foreach ($project in $Config.projects) {
            $result = @($results | Where-Object { $_.id -eq [string]$project.id })[0]
            if (-not $result.snapshotEligible) { continue }
            $snapshot = Join-Path $SandboxRoot ([string]$project.id)
            try {
                New-UniversaarlCommitSnapshot -SourceRepository $projectPaths[[string]$project.id] -Commit $result.commit -Destination $snapshot -SandboxRoot $SandboxRoot -ExpectedBranch $result.branch -IncludeHistory:([string]$project.id -eq 'blueprint') -AllowedVersionedMedia @($project.allowedVersionedMedia) | Out-Null
                $snapshotPaths[[string]$project.id] = $snapshot
            }
            catch { $result.findings += New-Finding critical 'SAFE-001' "Commitgebundene Wegwerfkopie konnte nicht erstellt werden: $($_.Exception.Message)" }
        }

        foreach ($project in $Config.projects) {
            $result = @($results | Where-Object { $_.id -eq [string]$project.id })[0]
            if (-not $snapshotPaths.ContainsKey([string]$project.id)) { continue }
            $extraEnvironment = @{}
            if ([string]$project.id -eq 'project-twin' -and $snapshotPaths.ContainsKey('blueprint')) {
                $extraEnvironment['UABC_PORTABLE_PRODUCER_ROOT'] = $snapshotPaths['blueprint']
                $extraEnvironment['UABC_REQUIRE_PORTABLE_PRODUCER'] = '1'
            }
            try {
                $validation = Invoke-ProjectValidation -Project $project -Commit $result.commit -SnapshotPath $snapshotPaths[[string]$project.id] -SandboxRoot $SandboxRoot -Runner $runner -AdditionalEnvironment $extraEnvironment
                $result.validation = $validation.validation
                $result.validationExitCode = $validation.validationExitCode
                $result.germanValidation = $validation.german
                $result.germanValidationExitCode = $validation.germanExitCode
                $result.evidenceCoverage = 100
                if ($validation.validation -eq 'failed') { $result.findings += New-Finding critical 'RUN-002' $validation.reason }
                elseif ($validation.german -eq 'failed') { $result.findings += New-Finding critical 'LANG-002' $validation.reason }
            }
            catch { $result.validation = 'failed'; $result.findings += New-Finding critical 'RUN-002' "Pruefprozess konnte nicht sicher gestartet werden: $($_.Exception.Message)" }
        }

        if ($snapshotPaths.ContainsKey('blueprint') -and $snapshotPaths.ContainsKey('project-twin')) {
            $runtimeBindingInspected = $true
            $smokeRoot = Join-Path $SandboxRoot ("vertrag-{0}" -f [Guid]::NewGuid().ToString('N'))
            $smokeBlueprint = Join-Path $smokeRoot 'blueprint'
            $smokeTwin = Join-Path $smokeRoot 'project-twin'
            New-Item -ItemType Directory -Path $smokeRoot -Force | Out-Null
            try {
                New-UniversaarlCommitSnapshot -SourceRepository $projectPaths['blueprint'] -Commit $inputShas['blueprint'] -Destination $smokeBlueprint -SandboxRoot $smokeRoot -ExpectedBranch (@($results | Where-Object { $_.id -eq 'blueprint' })[0].branch) -AllowedVersionedMedia @($projectConfigs['blueprint'].allowedVersionedMedia) | Out-Null
                New-UniversaarlCommitSnapshot -SourceRepository $projectPaths['project-twin'] -Commit $inputShas['project-twin'] -Destination $smokeTwin -SandboxRoot $smokeRoot -ExpectedBranch (@($results | Where-Object { $_.id -eq 'project-twin' })[0].branch) -AllowedVersionedMedia @($projectConfigs['project-twin'].allowedVersionedMedia) | Out-Null
                $runtime = Get-NpmRuntime
                $node = Resolve-UniversaarlTool -Names @('node', 'node.exe') -Description 'Node.js'
                $smokeInstallLog = Join-Path $LogRoot "$RunId-vertrag-installation.log"
                $smokeInstall = Invoke-UniversaarlSanitizedProcess -Runner $runner -FilePath $runtime.executable -Arguments (@($runtime.prefix) + @('ci', '--ignore-scripts', '--no-audit', '--no-fund')) -WorkingDirectory $smokeTwin -SandboxRoot $smokeRoot -LogPath $smokeInstallLog -LogRoot $LogRoot -TimeoutSeconds ([int]$Config.validationTimeoutSeconds) -SensitiveRoots @($smokeTwin, $smokeBlueprint, $smokeRoot)
                if ($smokeInstall.exitCode -ne 0 -or $smokeInstall.outputTruncated) { throw 'Die frische, skriptfreie Vertragsinstallation ist fehlgeschlagen oder lieferte zu viel Ausgabe.' }

                $twinBeforeSmoke = Get-UniversaarlRepositoryFingerprint -Repository $smokeTwin
                $blueprintBeforeSmoke = Get-UniversaarlRepositoryFingerprint -Repository $smokeBlueprint
                $smokeScript = Join-Path $PSScriptRoot 'Invoke-TwinContractSmoke.mjs'
                $crossLog = Join-Path $LogRoot "$RunId-vertrag.log"
                $smokeEnvironment = @{
                    UABC_PORTABLE_PRODUCER_ROOT = $smokeBlueprint
                    UABC_REQUIRE_PORTABLE_PRODUCER = '1'
                }
                $smoke = Invoke-UniversaarlSanitizedProcess -Runner $runner -FilePath $node -Arguments @($smokeScript, $smokeTwin, $smokeBlueprint, $inputShas['project-twin'], $inputShas['blueprint'], [string]$snapshotProof.releaseId, [string]$snapshotProof.sourceCommit, [string]$snapshotProof.manifestSha256) -WorkingDirectory $smokeTwin -SandboxRoot $smokeRoot -LogPath $crossLog -LogRoot $LogRoot -AdditionalEnvironment $smokeEnvironment -TimeoutSeconds ([int]$Config.validationTimeoutSeconds) -SensitiveRoots @($smokeTwin, $smokeBlueprint, $smokeRoot)
                if ($smoke.exitCode -ne 0 -or $smoke.outputTruncated) { throw 'Der Twin konnte die frisch installierte Blueprint-Commitkopie nicht erfolgreich normalisieren.' }
                try {
                    $payload = $smoke.output.Trim() | ConvertFrom-Json
                    $crossStats = $payload.stats
                    $crossWarnings = @($payload.warnings)
                    $legacySmokeStatus = if ($crossWarnings.Count -gt 0) { 'warning' } else { 'passed' }
                    if ($crossWarnings.Count -gt 0) { $relationshipFindings.Add((New-Finding medium 'CROSS-003' "Der Twin-Blueprint-Vertrag liefert $($crossWarnings.Count) Warnung(en).")) }
                }
                catch { throw 'Die Ausgabe des Vertrags-Schnelltests ist ungueltig.' }

                $twinAfterSmoke = Get-UniversaarlRepositoryFingerprint -Repository $smokeTwin
                $blueprintAfterSmoke = Get-UniversaarlRepositoryFingerprint -Repository $smokeBlueprint
                if (-not (Test-UniversaarlFingerprintEqual -Expected $twinBeforeSmoke -Actual $twinAfterSmoke) -or -not (Test-UniversaarlFingerprintEqual -Expected $blueprintBeforeSmoke -Actual $blueprintAfterSmoke)) { throw 'Twin- oder Blueprint-Commitkopie wurde waehrend des Vertrags-Schnelltests veraendert.' }
            }
            catch {
                $legacySmokeStatus = 'failed'
                $relationshipFindings.Add((New-Finding critical 'CROSS-002' "Frischer commitgebundener Vertrags-Schnelltest fehlgeschlagen: $($_.Exception.Message)"))
            }
        }
    }
    finally {
        $resolved = if ($SandboxRoot) { [IO.Path]::GetFullPath($SandboxRoot) } else { $null }
        if ($resolved -and $resolved.StartsWith($tempBase + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved).StartsWith('uabc-a-') -and (Test-Path -LiteralPath $resolved)) {
            $sandboxItem = Get-Item -LiteralPath $resolved -Force -ErrorAction SilentlyContinue
            if ($null -ne $sandboxItem -and (($sandboxItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { Remove-Item -LiteralPath $resolved -Force -ErrorAction SilentlyContinue }
            else { Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

foreach ($result in $results) {
    if (-not $result.exists -or -not $result.commit) { continue }
    try {
        $after = Get-UniversaarlRepositoryFingerprint -Repository $projectPaths[[string]$result.id]
        $result.fingerprintAfter = $after
        $result.targetUnchanged = Test-UniversaarlFingerprintEqual -Expected $result.fingerprintBefore -Actual $after
        if (-not $result.targetUnchanged) { $result.findings += New-Finding critical 'SAFE-003' 'HEAD-, Status- oder Index-Fingerprint des Zielprojekts hat sich waehrend des Laufs veraendert.' }
    }
    catch { $result.targetUnchanged = $false; $result.findings += New-Finding critical 'SAFE-003' 'Der abschliessende HEAD-, Status- und Index-Fingerprint konnte nicht gelesen werden.' }
}
if ($verificationInput.exists -and $verificationInput.gitRepository) {
    try {
        $verificationInput.fingerprintAfter = Get-UniversaarlRepositoryFingerprint -Repository $verificationSourcePath
        $verificationInput.targetUnchanged = Test-UniversaarlFingerprintEqual -Expected $verificationInput.fingerprintBefore -Actual $verificationInput.fingerprintAfter
        if (-not $verificationInput.targetUnchanged) {
            $verificationInput.status = 'failed'
            $verificationInput.findings += New-Finding critical 'SPECTRA-SOURCE-004' 'HEAD-, Status- oder Index-Fingerprint der BCProjectOS-Evidence-Quelle hat sich waehrend des Laufs veraendert.'
        }
    }
    catch {
        $verificationInput.status = 'failed'
        $verificationInput.targetUnchanged = $false
        $verificationInput.findings += New-Finding critical 'SPECTRA-SOURCE-004' 'Der abschliessende Fingerprint der BCProjectOS-Evidence-Quelle konnte nicht gelesen werden.'
    }
}
foreach ($finding in $relationshipFindings) {
    foreach ($id in @('project-twin')) { $target = @($results | Where-Object id -eq $id)[0]; if ($null -ne $target) { $target.findings += $finding } }
}
foreach ($finding in @($spectraRelationship.findings) + @($verificationInput.findings)) {
    foreach ($id in @('blueprint', 'project-twin')) { $target = @($results | Where-Object id -eq $id)[0]; if ($null -ne $target) { $target.findings += $finding } }
}
foreach ($result in $results) { $result | Add-Member -NotePropertyName status -NotePropertyValue (Get-TrafficLight -Result $result) }

$statuses = @($results | ForEach-Object status)
$overallStatus = if ($statuses -contains 'ROT' -or [string]$spectraRelationship.status -ne 'passed' -or [string]$verificationInput.status -ne 'observed' -or @($relationshipFindings | Where-Object severity -eq 'critical').Count -gt 0) { 'ROT' } elseif ($statuses -contains 'GRAU') { 'GRAU' } elseif ($statuses -contains 'GELB' -or $crossStatus -eq 'warning') { 'GELB' } else { 'GRUEN' }
$report = [pscustomobject]@{
    schemaVersion = 2
    kind = 'audit'
    runId = $RunId
    completed = $true
    startedAt = $StartedAt.ToString('o')
    finishedAt = (Get-Date).ToUniversalTime().ToString('o')
    mode = if ($RunValidations) { 'isolated-validation' } else { 'read-only-observation' }
    overallStatus = $overallStatus
    inputShas = [pscustomobject]$inputShas
    verificationInputs = [pscustomobject]@{ bcprojectos = $verificationInput }
    projects = @($results)
    relationships = @(
        $spectraRelationship
        [pscustomobject]@{ id = 'twin-reads-blueprint'; contractType = 'portable-snapshot-release'; status = $crossStatus; fullValidationPassed = $crossFullValidationPassed; runtimeBindingInspected = $runtimeBindingInspected; legacySmokeStatus = $legacySmokeStatus; providerCommit = $inputShas['blueprint']; consumerCommit = $inputShas['project-twin']; stats = $crossStats; warnings = @($crossWarnings); findings = @($relationshipFindings) }
    )
    safety = [pscustomobject]@{ snapshotSource = 'exact-commit'; worktreeContentHashed = $false; realEnvironmentFilesRead = $false; operatingSystemSandbox = $false; gitOptionalLocksDisabled = $true }
}

$statusText = @{ GRUEN = 'GRUEN'; GELB = 'GELB'; ROT = 'ROT'; GRAU = 'GRAU' }
$validationText = @{ 'passed' = 'bestanden'; 'failed' = 'fehlgeschlagen'; 'not-run' = 'nicht ausgefuehrt' }
$severityText = @{ 'critical' = 'kritisch'; 'high' = 'hoch'; 'medium' = 'mittel'; 'low' = 'niedrig'; 'info' = 'Hinweis' }
$contractText = @{ 'passed' = 'bestanden'; 'failed' = 'fehlgeschlagen'; 'warning' = 'mit Warnungen'; 'not-run' = 'nicht ausgefuehrt' }
function Get-DisplayValue { param([hashtable]$Map, $Value) $key = [string]$Value; if ($Map.ContainsKey($key)) { $Map[$key] } else { 'unbekannt' } }
function Get-YesNoValue { param($Value) if ($Value -eq $true) { 'Ja' } elseif ($Value -eq $false) { 'Nein' } else { 'Unbekannt' } }
function Get-ShaDisplayValue { param($Value) if ($Value -is [string] -and $Value -match '^[0-9a-f]{40}$') { $Value } else { 'unbekannt' } }
$markdown = [Collections.Generic.List[string]]::new()
$markdown.Add('# Universaarl Gesundheitsbericht')
$markdown.Add('')
$markdown.Add("- Lauf: ``$RunId``")
$markdown.Add("- Zeitpunkt (UTC): $($report.finishedAt)")
$markdown.Add("- Gesamtstatus: **$($statusText[$overallStatus])**")
$markdown.Add('- Pruefkopie: exakter festgehaltener Commit; keine Arbeitskopie')
$markdown.Add('- Isolation: bereinigte Wegwerfkopie, jedoch keine Betriebssystem-Sandbox; Benutzertoken und Netzwerk bleiben technisch erreichbar')
$markdown.Add('')
foreach ($result in $results) {
    $markdown.Add("## $($result.name)")
    $markdown.Add('')
    $markdown.Add("- Zweig/Commit: ``$($result.branch)`` / ``$(Get-ShaDisplayValue $result.commit)``")
    $markdown.Add("- Status: **$($result.status)**")
    $markdown.Add("- Nachweisabdeckung: **$($result.evidenceCoverage) %**")
    $markdown.Add("- Technische Pruefung: **$(Get-DisplayValue $validationText $result.validation)**")
    $markdown.Add("- Projektspezifischer Deutsch-Nachweis: **$(Get-DisplayValue $validationText $result.germanValidation)**")
    $markdown.Add("- Ziel unveraendert: **$(Get-YesNoValue $result.targetUnchanged)**")
    $markdown.Add("- ``REVIEW.md`` in Arbeitskopie/Commit leer: **$(Get-YesNoValue $result.reviewWorkingEmpty) / $(Get-YesNoValue $result.reviewHeadEmpty)**")
    $markdown.Add('')
    if (@($result.findings).Count -eq 0) { $markdown.Add('- Keine Befunde.') }
    foreach ($finding in @($result.findings)) { $markdown.Add("- **$(Get-DisplayValue $severityText $finding.severity) / ``$($finding.code)``:** $($finding.message)") }
    $markdown.Add('')
}
$markdown.Add('## Spectra-Evidence-Quelle')
$markdown.Add('')
$markdown.Add("- Technisches Projekt: **$($verificationInput.technicalProjectName)**")
$markdown.Add("- Produkt / ID: **$($verificationInput.productName)** / ``$($verificationInput.productId)``")
$markdown.Add("- Commit: ``$(Get-ShaDisplayValue $verificationInput.sourceCommit)``")
$markdown.Add("- Quelle unveraendert: **$(Get-YesNoValue $verificationInput.targetUnchanged)**")
$markdown.Add("- Bindungsstatus: **$($spectraRelationship.bindingStatus)**")
$markdown.Add("- Vertragspruefung: **$(Get-DisplayValue $contractText $spectraRelationship.status)**")
foreach ($finding in @($spectraRelationship.findings) + @($verificationInput.findings)) { $markdown.Add("- **$(Get-DisplayValue $severityText $finding.severity) / ``$($finding.code)``:** $($finding.message)") }
$markdown.Add('')
$markdown.Add('## Zusammenspiel')
$markdown.Add('')
$markdown.Add("- Vertragspruefung: **$(Get-DisplayValue $contractText $crossStatus)**")
$markdown.Add("- Blueprint-Commit: ``$(Get-ShaDisplayValue $inputShas['blueprint'])``")
$markdown.Add("- Twin-Commit: ``$(Get-ShaDisplayValue $inputShas['project-twin'])``")
$markdown.Add('')
$markdown.Add('> Technische Zielprozesse liefen in commitgebundenen, bereinigten Wegwerfkopien. Diese Kopien sind keine Betriebssystem-Sandbox.')

$jsonText = $report | ConvertTo-Json -Depth 14
$markdownText = $markdown -join "`r`n"
$null = Write-UniversaarlNewUtf8File -TrustedRoot $ReportRoot -Path $runJsonPath -Text $jsonText
$null = Write-UniversaarlNewUtf8File -TrustedRoot $ReportRoot -Path $runMarkdownPath -Text $markdownText
$null = Write-UniversaarlAtomicUtf8File -TrustedRoot $ReportRoot -Path (Join-Path $ReportRoot 'latest.json') -Text $jsonText
$null = Write-UniversaarlAtomicUtf8File -TrustedRoot $ReportRoot -Path (Join-Path $ReportRoot 'latest.md') -Text $markdownText

Write-Host "Universaarl-Pruefung: $overallStatus"
Write-Host "Laufbericht: $runMarkdownPath"
if ($overallStatus -eq 'ROT' -or ($FailOnWarning -and $overallStatus -in @('GELB', 'GRAU'))) { exit 1 }
exit 0
