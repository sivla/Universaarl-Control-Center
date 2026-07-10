[CmdletBinding()]
param(
    [switch]$RunValidations,
    [switch]$FailOnWarning
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$MonitorRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$ConfigPath = Join-Path $MonitorRoot 'monitor.config.json'
$Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$RunId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$StartedAt = (Get-Date).ToUniversalTime()
$ReportRoot = Join-Path $MonitorRoot $Config.reportDirectory
$RunReportRoot = Join-Path $ReportRoot 'runs'
$LogRoot = Join-Path $ReportRoot 'logs'

$ExcludedDirectoryNames = @(
    '.git', 'node_modules', 'dist', 'output', '.playwright-cli', '.tmp',
    'playwright-report', 'test-results', '.auth', 'runtime', 'source-cache'
)
$ExcludedFilePatterns = @(
    '.git', '.env', '.env.*', '.npmrc', '.yarnrc', '.yarnrc.*', '*.pem', '*.key',
    '*.pfx', '*.p12', '*.log', '*.zip', '*.webm', '*.trace', '*.tsbuildinfo',
    '.dev-server.pid'
)

function New-Finding {
    param(
        [Parameter(Mandatory)][ValidateSet('critical', 'high', 'medium', 'low', 'info')][string]$Severity,
        [Parameter(Mandatory)][string]$Code,
        [Parameter(Mandatory)][string]$Message
    )
    [pscustomobject]@{ severity = $Severity; code = $Code; message = $Message }
}

function Get-ConfiguredPath {
    param([Parameter(Mandatory)]$Project)

    $override = [Environment]::GetEnvironmentVariable([string]$Project.pathEnvironmentVariable)
    $candidate = if ([string]::IsNullOrWhiteSpace($override)) { [string]$Project.defaultPath } else { $override }
    if (-not [IO.Path]::IsPathRooted($candidate)) {
        throw "Der Pfad fuer '$($Project.id)' muss absolut sein."
    }
    [IO.Path]::GetFullPath($candidate).TrimEnd([IO.Path]::DirectorySeparatorChar)
}

function Invoke-GitRead {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $oldOptionalLocks = [Environment]::GetEnvironmentVariable('GIT_OPTIONAL_LOCKS')
    $oldErrorActionPreference = $ErrorActionPreference
    [Environment]::SetEnvironmentVariable('GIT_OPTIONAL_LOCKS', '0')
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        $lines = @(& git -C $Repository @Arguments 2>$null)
        [pscustomobject]@{
            exitCode = $LASTEXITCODE
            output = ($lines -join "`n").Trim()
        }
    }
    finally {
        $ErrorActionPreference = $oldErrorActionPreference
        [Environment]::SetEnvironmentVariable('GIT_OPTIONAL_LOCKS', $oldOptionalLocks)
    }
}

function Test-VersionedEnvironmentExample {
    param([Parameter(Mandatory)][string]$Repository)

    $findings = [Collections.Generic.List[object]]::new()
    $contentResult = Invoke-GitRead -Repository $Repository -Arguments @('show', 'HEAD:.env.example')
    if ($contentResult.exitCode -ne 0) {
        return [pscustomobject]@{ present = $false; safe = $null; findings = @() }
    }

    $content = [string]$contentResult.output
    if ([Text.Encoding]::UTF8.GetByteCount($content) -gt 65536) {
        $findings.Add((New-Finding high 'ENV-EXAMPLE-001' 'Die versionierte `.env.example` ist groesser als 64 KiB.'))
    }

    $lineNumber = 0
    foreach ($line in $content -split "`n") {
        $lineNumber++
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) { continue }
        if ($trimmed -notmatch '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
            $findings.Add((New-Finding medium 'ENV-EXAMPLE-002' "Die versionierte `.env.example` enthaelt in Zeile $lineNumber keinen gueltigen Schluessel-Platzhalter."))
            continue
        }

        $name = $Matches[1]
        $value = $Matches[2].Trim().Trim([char[]]@('"', "'"))
        $isPlaceholder = [string]::IsNullOrWhiteSpace($value) -or $value -match '^(?:<[^>]+>|\$\{[^}]+\}|REPLACE(?:_ME)?|CHANGEME)$'
        $sensitiveName = $name -match '(?i)(token|secret|password|passwd|api[_-]?key|client[_-]?secret|cookie|session|auth)'
        $absoluteHostPath = $value -match '^(?:[A-Za-z]:[\\/]|\\\\|/(?:Users|home|tmp|var/tmp)/)'
        $tenantOrTokenShape = $value -match '(?i)(?:\.onmicrosoft\.com\b|\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b|\beyJ[A-Za-z0-9_-]{20,}|\bgh[oprsu]_[A-Za-z0-9]{20,})'

        if ($sensitiveName -and -not $isPlaceholder) {
            $findings.Add((New-Finding critical 'ENV-EXAMPLE-003' "Die versionierte `.env.example` enthaelt fuer den vertraulichen Schluessel '$name' einen echten Wert statt eines Platzhalters."))
        }
        if ($absoluteHostPath) {
            $findings.Add((New-Finding high 'ENV-EXAMPLE-004' "Die versionierte `.env.example` enthaelt fuer '$name' einen absoluten Hostpfad."))
        }
        if ($tenantOrTokenShape) {
            $findings.Add((New-Finding critical 'ENV-EXAMPLE-005' "Die versionierte `.env.example` enthaelt fuer '$name' eine Mandanten- oder Geheimniskennung."))
        }
    }

    [pscustomobject]@{ present = $true; safe = $findings.Count -eq 0; findings = @($findings) }
}

function Test-IsExcludedRelativePath {
    param([Parameter(Mandatory)][string]$RelativePath)

    $segments = $RelativePath -split '[\\/]'
    foreach ($segment in $segments) {
        if ($ExcludedDirectoryNames -contains $segment) { return $true }
    }

    $leaf = if ($segments.Count -gt 0) { $segments[-1] } else { $RelativePath }
    foreach ($pattern in $ExcludedFilePatterns) {
        if ($leaf -like $pattern) { return $true }
    }
    return $false
}

function Get-InventoryFingerprint {
    param([Parameter(Mandatory)][string]$Root)

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return $null }

    $items = Get-ChildItem -LiteralPath $Root -File -Recurse -Force -ErrorAction SilentlyContinue |
        ForEach-Object {
            $relative = $_.FullName.Substring($Root.Length).TrimStart([char[]]@('\', '/'))
            if (-not (Test-IsExcludedRelativePath -RelativePath $relative)) {
                try {
                    $contentHash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
                    '{0}|{1}' -f $relative.Replace('\', '/'), $contentHash
                }
                catch {
                    '{0}|<unreadable>' -f $relative.Replace('\', '/')
                }
            }
        } |
        Sort-Object

    $payload = [Text.Encoding]::UTF8.GetBytes(($items -join "`n"))
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        ([BitConverter]::ToString($sha.ComputeHash($payload))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-ProjectObservation {
    param(
        [Parameter(Mandatory)]$Project,
        [Parameter(Mandatory)][string]$TargetPath
    )

    $findings = [Collections.Generic.List[object]]::new()
    $score = 0
    $checksObserved = 0
    $checksTotal = 10
    $exists = Test-Path -LiteralPath $TargetPath -PathType Container
    $gitRepository = $false
    $hasCommit = $false
    $branch = '(unavailable)'
    $commit = '(none)'
    $dirty = $false
    $staged = 0
    $unstaged = 0
    $untracked = 0
    $conflicts = 0
    $packageName = $null
    $requiredScriptFound = $false
    $lockfileFound = $false
    $dependenciesPresent = $false
    $unpinnedDependencyCount = 0
    $activeChangeCount = $null
    $activeChangeName = $null
    $reviewWorkingEmpty = $false
    $reviewHeadEmpty = $false
    $environmentExamplePresent = $false
    $environmentExampleSafe = $null

    if ($exists) {
        $score += 15
        $checksObserved++
    }
    else {
        $findings.Add((New-Finding critical 'PATH-001' "Das konfigurierte Projekt ist nicht erreichbar."))
        return [pscustomobject]@{
            id = [string]$Project.id; name = [string]$Project.name; pathAlias = [string]$Project.pathAlias
            exists = $false; gitRepository = $false; hasCommit = $false; branch = $branch; commit = $commit
            dirty = $false; staged = 0; unstaged = 0; untracked = 0; conflicts = 0
            packageName = $null; requiredScriptFound = $false; lockfileFound = $false
            dependenciesPresent = $false; unpinnedDependencyCount = 0; activeChangeCount = $null; activeChangeName = $null
            reviewWorkingEmpty = $false; reviewHeadEmpty = $false; environmentExamplePresent = $false; environmentExampleSafe = $null
            structuralScore = 0; evidenceCoverage = 8; validation = 'not-run'; validationExitCode = $null
            fingerprintBefore = $null; fingerprintAfter = $null; targetUnchanged = $null
            findings = @($findings)
        }
    }

    $fingerprint = Get-InventoryFingerprint -Root $TargetPath

    if (Get-Command git -ErrorAction SilentlyContinue) {
        $inside = Invoke-GitRead -Repository $TargetPath -Arguments @('rev-parse', '--is-inside-work-tree')
        $gitRepository = $inside.exitCode -eq 0 -and $inside.output -eq 'true'
    }
    if ($gitRepository) {
        $score += 10
        $checksObserved++
        $branchResult = Invoke-GitRead -Repository $TargetPath -Arguments @('branch', '--show-current')
        if ($branchResult.exitCode -eq 0 -and $branchResult.output) { $branch = $branchResult.output }

        $commitResult = Invoke-GitRead -Repository $TargetPath -Arguments @('rev-parse', '--short', 'HEAD')
        $hasCommit = $commitResult.exitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($commitResult.output)
        if ($hasCommit) {
            $commit = $commitResult.output
            $score += 15
        }
        else {
            $findings.Add((New-Finding high 'GIT-002' 'Das Projekt besitzt noch keinen Commit und damit keinen belastbaren Ausgangsstand.'))
        }
        $checksObserved++

        $statusResult = Invoke-GitRead -Repository $TargetPath -Arguments @('status', '--porcelain=v1', '--untracked-files=all')
        if ($statusResult.exitCode -eq 0) {
            $statusLines = @($statusResult.output -split "`n" | Where-Object { $_ })
            foreach ($line in $statusLines) {
                if ($line.StartsWith('??')) { $untracked++; continue }
                if ($line.Length -ge 2) {
                    $xy = $line.Substring(0, 2)
                    if ($xy -match '^(DD|AU|UD|UA|DU|AA|UU)$') { $conflicts++ }
                    if ($line[0] -ne ' ') { $staged++ }
                    if ($line[1] -ne ' ') { $unstaged++ }
                }
            }
            $dirty = $statusLines.Count -gt 0
            if (-not $dirty) {
                $score += 15
            }
            else {
                $findings.Add((New-Finding medium 'GIT-003' "Lokaler Arbeitsstand ist nicht sauber: $staged vorgemerkt, $unstaged nicht vorgemerkt, $untracked unversioniert."))
            }
            if ($conflicts -gt 0) {
                $findings.Add((New-Finding critical 'GIT-004' "$conflicts Git-Konflikt(e) erkannt."))
            }
            $checksObserved++
        }
    }
    else {
        $findings.Add((New-Finding high 'GIT-001' 'Kein lesbares Git-Repository erkannt.'))
    }

    $packagePath = Join-Path $TargetPath 'package.json'
    if (Test-Path -LiteralPath $packagePath -PathType Leaf) {
        try {
            $package = Get-Content -LiteralPath $packagePath -Raw | ConvertFrom-Json
            $packageName = [string]$package.name
            $score += 10
            $checksObserved++

            if ($null -ne $package.scripts -and $package.scripts.PSObject.Properties.Name -contains [string]$Project.requiredNpmScript) {
                $requiredScriptFound = $true
                $score += 10
            }
            else {
                $findings.Add((New-Finding critical 'RUN-001' "Das erforderliche npm-Skript '$($Project.requiredNpmScript)' fehlt."))
            }
            $checksObserved++

            $dependencyProperties = @()
            if ($package.PSObject.Properties.Name -contains 'dependencies' -and $null -ne $package.dependencies) {
                $dependencyProperties += $package.dependencies.PSObject.Properties
            }
            if ($package.PSObject.Properties.Name -contains 'devDependencies' -and $null -ne $package.devDependencies) {
                $dependencyProperties += $package.devDependencies.PSObject.Properties
            }
            $unpinnedDependencyCount = @($dependencyProperties | Where-Object { [string]$_.Value -eq 'latest' -or [string]$_.Value -eq '*' }).Count
            if ($unpinnedDependencyCount -eq 0) {
                $score += 5
            }
            else {
                $dependencySeverity = if (Test-Path -LiteralPath (Join-Path $TargetPath 'package-lock.json') -PathType Leaf) { 'low' } else { 'medium' }
                $findings.Add((New-Finding $dependencySeverity 'DEP-002' "$unpinnedDependencyCount Abhaengigkeit(en) verwenden den technischen Versionswert 'latest' oder '*'; eine vorhandene Sperrdatei begrenzt das Risiko bei `npm ci`."))
            }
            $checksObserved++
        }
        catch {
            $findings.Add((New-Finding critical 'MANIFEST-001' 'package.json kann nicht gelesen oder geparst werden.'))
        }
    }
    else {
        $findings.Add((New-Finding high 'MANIFEST-001' 'package.json fehlt.'))
    }

    $lockfileFound = Test-Path -LiteralPath (Join-Path $TargetPath 'package-lock.json') -PathType Leaf
    if ($lockfileFound) { $score += 10 } else { $findings.Add((New-Finding high 'DEP-001' 'package-lock.json fehlt.')) }
    $checksObserved++

    $dependenciesPresent = Test-Path -LiteralPath (Join-Path $TargetPath 'node_modules') -PathType Container
    if ($dependenciesPresent) { $score += 5 } else { $findings.Add((New-Finding low 'DEP-003' 'Lokale Abhaengigkeiten sind nicht installiert; die abgeschottete technische Pruefung installiert sie getrennt.')) }
    $checksObserved++

    $changesRoot = Join-Path $TargetPath 'openspec\changes'
    if (Test-Path -LiteralPath $changesRoot -PathType Container) {
        $activeChangeDirectories = @(Get-ChildItem -LiteralPath $changesRoot -Directory -Force |
            Where-Object { $_.Name -notin @('archive', 'archived') })
        $activeChangeCount = $activeChangeDirectories.Count
        if ($activeChangeCount -eq 1) { $activeChangeName = $activeChangeDirectories[0].Name }
        if ($activeChangeCount -le [int]$Project.maxActiveChanges) {
            $score += 5
        }
        else {
            $findings.Add((New-Finding high 'WIP-001' "$activeChangeCount aktive OpenSpec-Aenderungen ueberschreiten das erlaubte Maximum $($Project.maxActiveChanges)."))
        }
        $checksObserved++
    }
    else {
        $findings.Add((New-Finding low 'WIP-002' 'Kein Verzeichnis fuer OpenSpec-Aenderungen gefunden.'))
    }

    $workflowRoot = Join-Path $TargetPath '.github\workflows'
    $workflowCount = if (Test-Path -LiteralPath $workflowRoot -PathType Container) {
        @(Get-ChildItem -LiteralPath $workflowRoot -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in @('.yml', '.yaml') }).Count
    }
    else { 0 }
    if ($workflowCount -eq 0) {
        $findings.Add((New-Finding low 'CI-001' 'Keine versionierte Konfiguration fuer fortlaufende Integration gefunden.'))
    }

    if ([string]$Project.id -eq 'blueprint') {
        $openSpecConfig = Join-Path $TargetPath 'openspec\config.yaml'
        $readmePath = Join-Path $TargetPath 'README.md'
        if ((Test-Path -LiteralPath $openSpecConfig -PathType Leaf) -and (Test-Path -LiteralPath $readmePath -PathType Leaf)) {
            $configText = Get-Content -LiteralPath $openSpecConfig -Raw
            $readmeText = Get-Content -LiteralPath $readmePath -Raw
            $configMatch = [regex]::Match($configText, '(?m)^\s*activeChange:\s*([^\s#]+)')
            $readmeMatch = [regex]::Match($readmeText, '(?s)##\s+Aktiver Change.*?`([^`]+)`')
            if ($readmeMatch.Success -and ($configMatch.Success -or $activeChangeName)) {
                $configuredChange = if ($configMatch.Success) {
                    $configMatch.Groups[1].Value.Trim([char[]]@('"', "'"))
                }
                else {
                    $activeChangeName
                }
                $documentedChange = $readmeMatch.Groups[1].Value
                if ($configuredChange -ne $documentedChange) {
                    $findings.Add((New-Finding medium 'DOC-001' "Die Einstiegshilfe nennt '$documentedChange', die aktive Aenderung ist aber '$configuredChange'."))
                }
            }
        }
    }

    if ([string]$Project.id -eq 'project-twin' -and (Test-Path -LiteralPath $changesRoot -PathType Container)) {
        $openTaskCount = @(Get-ChildItem -LiteralPath $changesRoot -File -Recurse -Filter 'tasks.md' -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '[\\/](archive|archived)[\\/]' } |
            Select-String -Pattern '^\s*-\s*\[\s\]\s+' -AllMatches).Count
        if ($openTaskCount -gt 0) {
            $findings.Add((New-Finding low 'WIP-003' "$openTaskCount offene Aufgabe(n) in der aktiven Twin-Aenderung."))
        }
    }

    $reviewFile = [string]$Project.reviewFile
    if ([string]::IsNullOrWhiteSpace($reviewFile) -or [IO.Path]::IsPathRooted($reviewFile) -or $reviewFile -match '(^|[\\/])\.\.([\\/]|$)') {
        $findings.Add((New-Finding high 'REVIEW-001' 'Keine sichere Pruefdatei konfiguriert.'))
    }
    else {
        $reviewPath = Join-Path $TargetPath $reviewFile
        if (-not (Test-Path -LiteralPath $reviewPath -PathType Leaf)) {
            $findings.Add((New-Finding high 'REVIEW-002' "Pruefdatei '$reviewFile' fehlt in der Arbeitskopie."))
        }
        else {
            $reviewContent = Get-Content -LiteralPath $reviewPath -Raw
            $reviewWorkingEmpty = [string]::IsNullOrWhiteSpace([string]$reviewContent)
            if (-not $reviewWorkingEmpty) {
                $findings.Add((New-Finding high 'REVIEW-003' "Pruefdatei '$reviewFile' ist in der Arbeitskopie nicht leer."))
            }
        }

        if ($hasCommit) {
            $reviewHeadResult = Invoke-GitRead -Repository $TargetPath -Arguments @('show', "HEAD:$reviewFile")
            $reviewHeadEmpty = $reviewHeadResult.exitCode -eq 0 -and [string]::IsNullOrWhiteSpace($reviewHeadResult.output)
            if ($reviewHeadResult.exitCode -ne 0) {
                $findings.Add((New-Finding high 'REVIEW-004' "Pruefdatei '$reviewFile' fehlt im aktuellen Commit."))
            }
            elseif (-not $reviewHeadEmpty) {
                $findings.Add((New-Finding high 'REVIEW-005' "Pruefdatei '$reviewFile' ist im aktuellen Commit nicht leer."))
            }
        }
    }

    if ($hasCommit) {
        $environmentExample = Test-VersionedEnvironmentExample -Repository $TargetPath
        $environmentExamplePresent = $environmentExample.present
        $environmentExampleSafe = $environmentExample.safe
        foreach ($finding in @($environmentExample.findings)) { $findings.Add($finding) }
    }

    [pscustomobject]@{
        id = [string]$Project.id; name = [string]$Project.name; pathAlias = [string]$Project.pathAlias
        exists = $exists; gitRepository = $gitRepository; hasCommit = $hasCommit; branch = $branch; commit = $commit
        dirty = $dirty; staged = $staged; unstaged = $unstaged; untracked = $untracked; conflicts = $conflicts
        packageName = $packageName; requiredScriptFound = $requiredScriptFound; lockfileFound = $lockfileFound
        dependenciesPresent = $dependenciesPresent; unpinnedDependencyCount = $unpinnedDependencyCount
        activeChangeCount = $activeChangeCount; activeChangeName = $activeChangeName
        reviewWorkingEmpty = $reviewWorkingEmpty; reviewHeadEmpty = $reviewHeadEmpty
        environmentExamplePresent = $environmentExamplePresent; environmentExampleSafe = $environmentExampleSafe
        structuralScore = [Math]::Min(100, $score)
        evidenceCoverage = [Math]::Round(($checksObserved / $checksTotal) * 80)
        validation = 'not-run'; validationExitCode = $null
        fingerprintBefore = $fingerprint; fingerprintAfter = $null; targetUnchanged = $null
        findings = @($findings)
    }
}

function New-IsolatedSnapshot {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $arguments = @($Source, $Destination, '/E', '/COPY:DAT', '/DCOPY:T', '/R:1', '/W:1', '/XJ', '/NFL', '/NDL', '/NJH', '/NJS', '/NP')
    $arguments += '/XD'
    $arguments += $ExcludedDirectoryNames
    $arguments += '/XF'
    $arguments += $ExcludedFilePatterns
    & robocopy @arguments | Out-Null
    if ($LASTEXITCODE -gt 7) {
        throw "Die isolierte Kopie konnte nicht erstellt werden (robocopy exit $LASTEXITCODE)."
    }
}

function Initialize-SnapshotGit {
    param([Parameter(Mandatory)][string]$SnapshotPath)

    $oldErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        & git -C $SnapshotPath init --quiet 2>$null
        if ($LASTEXITCODE -ne 0) { throw '`git init` ist in der abgeschotteten Pruefumgebung fehlgeschlagen.' }
        & git -C $SnapshotPath -c core.autocrlf=false add --all 2>$null
        if ($LASTEXITCODE -ne 0) { throw '`git add` ist in der abgeschotteten Pruefumgebung fehlgeschlagen.' }
        & git -C $SnapshotPath -c user.name='Universaarl Audit' -c user.email='audit@localhost' `
            -c core.autocrlf=false commit --quiet -m 'audit snapshot' 2>$null
        if ($LASTEXITCODE -ne 0) { throw '`git commit` ist in der abgeschotteten Pruefumgebung fehlgeschlagen.' }
    }
    finally {
        $ErrorActionPreference = $oldErrorActionPreference
    }
}

function Invoke-SanitizedProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string]$SandboxRoot,
        [Parameter(Mandatory)][string]$LogPath,
        [hashtable]$AdditionalEnvironment = @{},
        [int]$TimeoutSeconds = 240
    )

    $isolatedHome = Join-Path $SandboxRoot 'home'
    $cache = Join-Path $SandboxRoot 'npm-cache'
    $appData = Join-Path $isolatedHome 'AppData\Roaming'
    $localAppData = Join-Path $isolatedHome 'AppData\Local'
    New-Item -ItemType Directory -Path $isolatedHome, $cache, $appData, $localAppData -Force | Out-Null

    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FilePath
    $psi.Arguments = (($Arguments | ForEach-Object {
        $argument = [string]$_
        if ($argument -match '[\s"]') { '"' + $argument.Replace('"', '\"') + '"' } else { $argument }
    }) -join ' ')
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
    $psi.EnvironmentVariables.Clear()

    $safeEnvironment = @{
        'PATH' = [Environment]::GetEnvironmentVariable('PATH')
        'PATHEXT' = [Environment]::GetEnvironmentVariable('PATHEXT')
        'SystemRoot' = [Environment]::GetEnvironmentVariable('SystemRoot')
        'ComSpec' = [Environment]::GetEnvironmentVariable('ComSpec')
        'TEMP' = $SandboxRoot
        'TMP' = $SandboxRoot
        'HOME' = $isolatedHome
        'USERPROFILE' = $isolatedHome
        'APPDATA' = $appData
        'LOCALAPPDATA' = $localAppData
        'CI' = 'true'
        'NO_COLOR' = '1'
        'FORCE_COLOR' = '0'
        'TERM' = 'dumb'
        'GIT_OPTIONAL_LOCKS' = '0'
        'npm_config_cache' = $cache
        'npm_config_audit' = 'false'
        'npm_config_fund' = 'false'
        'npm_config_update_notifier' = 'false'
    }
    foreach ($entry in $AdditionalEnvironment.GetEnumerator()) { $safeEnvironment[$entry.Key] = [string]$entry.Value }
    foreach ($entry in $safeEnvironment.GetEnumerator()) {
        if ($null -ne $entry.Value) { $psi.EnvironmentVariables[$entry.Key] = [string]$entry.Value }
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $psi
    $null = $process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $finished = $process.WaitForExit($TimeoutSeconds * 1000)
    if (-not $finished) {
        & taskkill /PID $process.Id /T /F 2>$null | Out-Null
        $process.WaitForExit()
    }
    $stdout = $stdoutTask.Result.Trim()
    $stderr = $stderrTask.Result.Trim()
    $clean = {
        param([string]$Value)
        $sanitized = $Value.Replace($SandboxRoot, '<SANDBOX>').Replace($SandboxRoot.Replace('\', '/'), '<SANDBOX>')
        [regex]::Replace($sanitized, "$([char]27)\[[0-?]*[ -/]*[@-~]", '')
    }
    $stdout = & $clean $stdout
    $stderr = & $clean $stderr
    $content = ($stdout + "`n" + $stderr).Trim()
    [IO.File]::WriteAllText($LogPath, $content, [Text.UTF8Encoding]::new($false))
    [pscustomobject]@{
        exitCode = if ($finished) { $process.ExitCode } else { 124 }
        timedOut = -not $finished
        output = $stdout
    }
}

function Invoke-ProjectValidation {
    param(
        [Parameter(Mandatory)]$Project,
        [Parameter(Mandatory)][string]$SnapshotPath,
        [Parameter(Mandatory)][string]$SandboxRoot,
        [Parameter(Mandatory)][hashtable]$AdditionalEnvironment
    )

    $node = Get-Command node.exe -ErrorAction SilentlyContinue
    if ($null -eq $node) { $node = Get-Command node -ErrorAction SilentlyContinue }
    $npmCommand = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if ($null -eq $npmCommand) { $npmCommand = Get-Command npm -ErrorAction SilentlyContinue }
    if ($null -eq $node -or $null -eq $npmCommand) {
        return [pscustomobject]@{ status = 'failed'; exitCode = 127; log = $null; reason = 'Node.js oder npm wurde nicht gefunden.' }
    }
    $npmCli = Join-Path (Split-Path -Parent $npmCommand.Source) 'node_modules\npm\bin\npm-cli.js'
    if (-not (Test-Path -LiteralPath $npmCli -PathType Leaf)) {
        return [pscustomobject]@{ status = 'failed'; exitCode = 127; log = $null; reason = 'npm-cli.js wurde nicht gefunden.' }
    }

    $installLog = Join-Path $LogRoot "$RunId-$($Project.id)-install.log"
    $validationLog = Join-Path $LogRoot "$RunId-$($Project.id)-validation.log"
    $install = Invoke-SanitizedProcess -FilePath $node.Source -Arguments @($npmCli, 'ci', '--ignore-scripts', '--no-audit', '--no-fund') `
        -WorkingDirectory $SnapshotPath -SandboxRoot $SandboxRoot -LogPath $installLog `
        -AdditionalEnvironment $AdditionalEnvironment -TimeoutSeconds ([int]$Config.validationTimeoutSeconds)
    if ($install.exitCode -ne 0) {
        return [pscustomobject]@{ status = 'failed'; exitCode = $install.exitCode; log = $installLog; reason = '`npm ci` ist in der abgeschotteten Pruefumgebung fehlgeschlagen.' }
    }

    $validation = Invoke-SanitizedProcess -FilePath $node.Source -Arguments (@($npmCli) + @($Project.validationArguments)) `
        -WorkingDirectory $SnapshotPath -SandboxRoot $SandboxRoot -LogPath $validationLog `
        -AdditionalEnvironment $AdditionalEnvironment -TimeoutSeconds ([int]$Config.validationTimeoutSeconds)
    [pscustomobject]@{
        status = if ($validation.exitCode -eq 0) { 'passed' } else { 'failed' }
        exitCode = $validation.exitCode
        log = $validationLog
        reason = if ($validation.timedOut) { 'Zeitlimit ueberschritten.' } else { $null }
    }
}

function Get-TrafficLight {
    param([Parameter(Mandatory)]$Result)

    $severities = @($Result.findings | ForEach-Object { $_.severity })
    if ($Result.evidenceCoverage -lt 70) { return 'GRAU' }
    if ($severities -contains 'critical' -or $Result.validation -eq 'failed' -or -not $Result.hasCommit -or $Result.structuralScore -lt 70) { return 'ROT' }
    if ($Result.validation -ne 'passed') { return 'GRAU' }
    if ($severities -contains 'high' -or $severities -contains 'medium' -or $Result.structuralScore -lt 85) { return 'GELB' }
    return 'GRUEN'
}

New-Item -ItemType Directory -Path $ReportRoot, $RunReportRoot, $LogRoot -Force | Out-Null

$projectPaths = @{}
$results = [Collections.Generic.List[object]]::new()
foreach ($project in $Config.projects) {
    $path = Get-ConfiguredPath -Project $project
    $projectPaths[[string]$project.id] = $path
    $results.Add((Get-ProjectObservation -Project $project -TargetPath $path))
}

$relationshipFindings = [Collections.Generic.List[object]]::new()
$contractMarkerFound = $false
$crossStatus = 'not-run'
$crossStats = $null
$crossWarnings = @()
$crossLog = $null
$runtimeBindingInspected = $false
$twinPath = $projectPaths['project-twin']
if ($twinPath -and (Test-Path -LiteralPath $twinPath -PathType Container)) {
    $markerFiles = @('README.md', 'src\server\adapter.ts', 'vite.config.ts')
    foreach ($relative in $markerFiles) {
        $candidate = Join-Path $twinPath $relative
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $content = Get-Content -LiteralPath $candidate -Raw
            if ($content -match 'UABC_SOURCE_REPO') { $contractMarkerFound = $true; break }
        }
    }
}
if (-not $contractMarkerFound) {
    $relationshipFindings.Add((New-Finding high 'CROSS-001' 'Der Twin deklariert den erwarteten Blueprint-Quellvertrag nicht.'))
}

$SandboxRoot = $null
if ($RunValidations) {
    $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $SandboxRoot = Join-Path $tempBase "universaarl-audit-$RunId-$([Guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $SandboxRoot -Force | Out-Null
    try {
        $snapshotPaths = @{}
        foreach ($project in $Config.projects) {
            $result = @($results | Where-Object { $_.id -eq [string]$project.id })[0]
            if (-not $result.exists) { continue }
            $snapshot = Join-Path $SandboxRoot ([string]$project.id)
            New-IsolatedSnapshot -Source $projectPaths[[string]$project.id] -Destination $snapshot
            $snapshotPaths[[string]$project.id] = $snapshot
        }

        if ($snapshotPaths.ContainsKey('blueprint')) {
            Initialize-SnapshotGit -SnapshotPath $snapshotPaths['blueprint']
        }

        foreach ($project in $Config.projects) {
            $result = @($results | Where-Object { $_.id -eq [string]$project.id })[0]
            if (-not $result.exists -or -not $snapshotPaths.ContainsKey([string]$project.id)) { continue }
            $extraEnvironment = @{}
            if ([string]$project.id -eq 'project-twin' -and $snapshotPaths.ContainsKey('blueprint')) {
                $extraEnvironment['UABC_SOURCE_REPO'] = $snapshotPaths['blueprint']
            }
            $validation = Invoke-ProjectValidation -Project $project -SnapshotPath $snapshotPaths[[string]$project.id] `
                -SandboxRoot $SandboxRoot -AdditionalEnvironment $extraEnvironment
            $result.validation = $validation.status
            $result.validationExitCode = $validation.exitCode
            $result.evidenceCoverage = [Math]::Min(100, $result.evidenceCoverage + 20)
            if ($validation.status -eq 'failed') {
                $validationReason = if ([string]::IsNullOrWhiteSpace([string]$validation.reason)) {
                    'Die abgeschottete technische Pruefung ist fehlgeschlagen.'
                }
                else {
                    [string]$validation.reason
                }
                $result.findings += New-Finding critical 'RUN-002' $validationReason
            }
        }

        if ($snapshotPaths.ContainsKey('blueprint') -and $snapshotPaths.ContainsKey('project-twin')) {
            $runtimeBindingInspected = $true
            $crossLog = Join-Path $LogRoot "$RunId-cross-contract.log"
            $smokeScript = Join-Path $PSScriptRoot 'Invoke-TwinContractSmoke.mjs'
            $node = Get-Command node.exe -ErrorAction SilentlyContinue
            if ($null -eq $node) { $node = Get-Command node -ErrorAction SilentlyContinue }
            if ($null -eq $node) {
                $crossStatus = 'failed'
                $relationshipFindings.Add((New-Finding critical 'CROSS-002' 'Node.js fuer den abgeschotteten Vertrags-Schnelltest fehlt.'))
            }
            else {
                $smoke = Invoke-SanitizedProcess -FilePath $node.Source `
                    -Arguments @($smokeScript, $snapshotPaths['project-twin'], $snapshotPaths['blueprint']) `
                    -WorkingDirectory $snapshotPaths['project-twin'] -SandboxRoot $SandboxRoot -LogPath $crossLog `
                    -TimeoutSeconds ([int]$Config.validationTimeoutSeconds)
                if ($smoke.exitCode -ne 0) {
                    $crossStatus = 'failed'
                    $relationshipFindings.Add((New-Finding critical 'CROSS-002' 'Der Twin konnte die aktuelle Blueprint-Momentaufnahme nicht erfolgreich normalisieren.'))
                }
                else {
                    try {
                        $crossPayload = $smoke.output.Trim() | ConvertFrom-Json
                        $crossStats = $crossPayload.stats
                        $crossWarnings = @($crossPayload.warnings)
                        if ($crossWarnings.Count -gt 0) {
                            $crossStatus = 'warning'
                            $relationshipFindings.Add((New-Finding medium 'CROSS-003' "Der reale Twin-Blueprint-Vertrag liefert $($crossWarnings.Count) Warnung(en)."))
                        }
                        else {
                            $crossStatus = 'passed'
                        }
                    }
                    catch {
                        $crossStatus = 'failed'
                        $relationshipFindings.Add((New-Finding critical 'CROSS-004' 'Die Ausgabe des Vertrags-Schnelltests ist ungueltig.'))
                    }
                }
            }

            $twinResult = @($results | Where-Object { $_.id -eq 'project-twin' })[0]
            foreach ($finding in $relationshipFindings) {
                if ($finding.code -like 'CROSS-00*') { $twinResult.findings += $finding }
            }
        }
    }
    finally {
        $resolvedSandbox = if ($SandboxRoot) { [IO.Path]::GetFullPath($SandboxRoot) } else { $null }
        if ($resolvedSandbox -and $resolvedSandbox.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase) -and
            (Split-Path -Leaf $resolvedSandbox).StartsWith('universaarl-audit-')) {
            Remove-Item -LiteralPath $resolvedSandbox -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

foreach ($project in $Config.projects) {
    $result = @($results | Where-Object { $_.id -eq [string]$project.id })[0]
    if (-not $result.exists) { continue }
    $result.fingerprintAfter = Get-InventoryFingerprint -Root $projectPaths[[string]$project.id]
    $result.targetUnchanged = $result.fingerprintBefore -eq $result.fingerprintAfter
    if (-not $result.targetUnchanged) {
        $result.findings += New-Finding critical 'SAFE-003' 'Die Ziel-Inhaltspruefsumme hat sich waehrend des Laufs veraendert; der Lauf ist ungueltig.'
    }
}

foreach ($result in $results) {
    $result | Add-Member -NotePropertyName status -NotePropertyValue (Get-TrafficLight -Result $result)
}

$coverageValues = @($results | ForEach-Object { [double]$_.evidenceCoverage })
$overallCoverage = if ($coverageValues.Count) { [Math]::Round(($coverageValues | Measure-Object -Average).Average) } else { 0 }
$statuses = @($results | ForEach-Object { $_.status })
$relationshipCritical = @($relationshipFindings | Where-Object { $_.severity -eq 'critical' }).Count -gt 0
$overallStatus = if ($relationshipCritical -or $statuses -contains 'ROT') { 'ROT' } elseif ($overallCoverage -lt 70 -or $statuses -contains 'GRAU') { 'GRAU' } elseif ($statuses -contains 'GELB') { 'GELB' } else { 'GRUEN' }

$report = [pscustomobject]@{
    schemaVersion = 1
    runId = $RunId
    startedAt = $StartedAt.ToString('o')
    finishedAt = (Get-Date).ToUniversalTime().ToString('o')
    mode = if ($RunValidations) { 'isolated-validation' } else { 'read-only-observation' }
    overallStatus = $overallStatus
    evidenceCoverage = $overallCoverage
    targetCount = $results.Count
    projects = @($results)
    relationships = @(
        [pscustomobject]@{
            id = 'twin-reads-blueprint'
            status = if (-not $contractMarkerFound) { 'failed' } elseif ($RunValidations) { $crossStatus } else { 'declared' }
            runtimeBindingInspected = $runtimeBindingInspected
            note = 'Lokale .env-Dateien werden aus Sicherheitsgruenden nicht gelesen.'
            stats = $crossStats
            warnings = @($crossWarnings)
            log = if ($crossLog) { Split-Path -Leaf $crossLog } else { $null }
            findings = @($relationshipFindings)
        }
    )
}

$statusIcon = @{ 'GRUEN' = '[GRUEN]'; 'GELB' = '[GELB]'; 'ROT' = '[ROT]'; 'GRAU' = '[GRAU]' }
$modeText = @{ 'isolated-validation' = 'abgeschottete technische Pruefung'; 'read-only-observation' = 'ausschliesslich lesende Beobachtung' }
$validationText = @{ 'passed' = 'bestanden'; 'failed' = 'fehlgeschlagen'; 'not-run' = 'nicht ausgefuehrt' }
$severityText = @{ 'critical' = 'kritisch'; 'high' = 'hoch'; 'medium' = 'mittel'; 'low' = 'niedrig'; 'info' = 'Hinweis' }
$contractText = @{ 'passed' = 'bestanden'; 'failed' = 'fehlgeschlagen'; 'warning' = 'mit Warnungen'; 'not-run' = 'nicht ausgefuehrt'; 'declared' = 'deklariert' }
function Get-DisplayText {
    param([Parameter(Mandatory)][hashtable]$Map, [AllowNull()]$Value)
    $key = [string]$Value
    if ($Map.ContainsKey($key)) { return [string]$Map[$key] }
    'unbekannt'
}
function Get-YesNoText {
    param([AllowNull()]$Value)
    if ($Value -eq $true) { return 'Ja' }
    if ($Value -eq $false) { return 'Nein' }
    'Unbekannt'
}
$markdown = [Collections.Generic.List[string]]::new()
$markdown.Add('# Universaarl Gesundheitsbericht')
$markdown.Add('')
$markdown.Add("- Lauf: ``$RunId``")
$markdown.Add("- Zeitpunkt (UTC): $($report.finishedAt)")
$markdown.Add("- Modus: **$(Get-DisplayText -Map $modeText -Value $report.mode)**")
$markdown.Add("- Gesamtstatus: $($statusIcon[$overallStatus]) **$overallStatus**")
$markdown.Add("- Nachweisabdeckung: **$overallCoverage %**")
$markdown.Add('')
$markdown.Add('| Projekt | Status | Struktur | Validierung | Git-Stand |')
$markdown.Add('|---|---:|---:|---|---|')
foreach ($result in $results) {
    $gitState = if (-not $result.gitRepository) { 'kein Git-Arbeitsbereich' } elseif (-not $result.hasCommit) { 'kein Commit' } elseif ($result.dirty) { "nicht sauber ($($result.staged) vorgemerkt/$($result.unstaged) nicht vorgemerkt/$($result.untracked) unversioniert)" } else { 'sauber' }
    $validationDisplay = Get-DisplayText -Map $validationText -Value $result.validation
    $markdown.Add("| $($result.name) | $($statusIcon[$result.status]) $($result.status) | $($result.structuralScore)/100 | $validationDisplay | $gitState |")
}
$markdown.Add('')
foreach ($result in $results) {
    $markdown.Add("## $($result.name)")
    $markdown.Add('')
    $markdown.Add("- Quelle: ``$($result.pathAlias)``")
    $markdown.Add("- Branch/Commit: ``$($result.branch)`` / ``$($result.commit)``")
    $markdown.Add("- Ziel unveraendert: **$(Get-YesNoText $result.targetUnchanged)**")
    $markdown.Add("- Abhaengigkeiten mit nicht festgelegter Version: **$($result.unpinnedDependencyCount)**")
    $markdown.Add("- Aktive OpenSpec-Aenderungen: **$($result.activeChangeCount)**")
    if ($result.activeChangeName) { $markdown.Add("- Aktive Aenderung: ``$($result.activeChangeName)``") }
    $markdown.Add("- ``REVIEW.md`` in Arbeitskopie/HEAD leer: **$(Get-YesNoText $result.reviewWorkingEmpty) / $(Get-YesNoText $result.reviewHeadEmpty)**")
    $environmentExampleDisplay = if (-not $result.environmentExamplePresent) { 'nicht vorhanden' } else { Get-YesNoText $result.environmentExampleSafe }
    $markdown.Add("- Versionierte ``.env.example`` im Commit geprueft und sicher: **$environmentExampleDisplay**")
    $markdown.Add('')
    if (@($result.findings).Count -eq 0) {
        $markdown.Add('Keine Befunde.')
    }
    else {
        $markdown.Add('| Schwere | Code | Befund |')
        $markdown.Add('|---|---|---|')
        foreach ($finding in $result.findings) {
            $markdown.Add("| $(Get-DisplayText -Map $severityText -Value $finding.severity) | ``$($finding.code)`` | $($finding.message) |")
        }
    }
    $markdown.Add('')
}
$markdown.Add('## Zusammenspiel')
$markdown.Add('')
$markdown.Add("- Quellvertrag des Twin deklariert: **$(Get-YesNoText $contractMarkerFound)**")
$markdown.Add("- Abgeschottete Vertragspruefung: **$(Get-DisplayText -Map $contractText -Value $crossStatus)**")
if ($null -ne $crossStats) {
    $markdown.Add("- Gelesene Artefakte: **$($crossStats.capabilities) Faehigkeiten, $($crossStats.changes) Aenderungen, $($crossStats.documents) Dokumente, $($crossStats.evidence) Nachweisbilder**")
}
$markdown.Add("- Vertragswarnungen: **$($crossWarnings.Count)**")
if ($crossWarnings.Count -gt 0) { $markdown.Add('  - Einzelheiten stehen im maschinenlesbaren Bericht und im zugehoerigen Pruefprotokoll.') }
$markdown.Add('- Laufzeitbindung aus `.env.local`: **nicht gelesen (Sicherheitsregel)**')
foreach ($finding in $relationshipFindings) { $markdown.Add("- **$(Get-DisplayText -Map $severityText -Value $finding.severity)** ``$($finding.code)``: $($finding.message)") }
$markdown.Add('')
$markdown.Add('> Der Monitor hat keine Reparatur in den Zielprojekten vorgenommen. Technische Pruefungen laufen nur in einer bereinigten Wegwerfkopie.')

$markdownText = $markdown -join "`r`n"
$jsonText = $report | ConvertTo-Json -Depth 10
$runMarkdownPath = Join-Path $RunReportRoot "$RunId.md"
$runJsonPath = Join-Path $RunReportRoot "$RunId.json"
[IO.File]::WriteAllText($runMarkdownPath, $markdownText, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($runJsonPath, $jsonText, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $ReportRoot 'latest.md'), $markdownText, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $ReportRoot 'latest.json'), $jsonText, [Text.UTF8Encoding]::new($false))

Write-Host "Universaarl-Pruefung: $overallStatus ($overallCoverage% Nachweisabdeckung)"
foreach ($result in $results) {
    Write-Host ("- {0}: {1}, Struktur {2}/100, Pruefung {3}" -f $result.name, $result.status, $result.structuralScore, (Get-DisplayText -Map $validationText -Value $result.validation))
}
Write-Host "Bericht: $(Join-Path $ReportRoot 'latest.md')"

if ($overallStatus -eq 'ROT' -or ($FailOnWarning -and $overallStatus -in @('GELB', 'GRAU'))) { exit 1 }
exit 0
