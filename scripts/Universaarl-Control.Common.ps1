Set-StrictMode -Version Latest

$script:UniversaarlTextBlobLimit = 1048576
$script:UniversaarlReportLimit = 8388608
$script:UniversaarlLogCharacterLimit = 131072
if ($null -eq (Get-Variable -Scope Script -Name UniversaarlDirectoryLockRegistry -ErrorAction SilentlyContinue)) {
    $script:UniversaarlDirectoryLockRegistry = @{}
}

if ($env:OS -eq 'Windows_NT' -and $null -eq ('Universaarl.NativeFile' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using Microsoft.Win32.SafeHandles;
using System.Runtime.InteropServices;
using System.Text;

namespace Universaarl {
    public static class NativeFile {
        public const uint FileAttributeDirectory = 0x00000010;
        public const uint FileAttributeReparsePoint = 0x00000400;

        [StructLayout(LayoutKind.Sequential)]
        public struct FileAttributeTagInfo {
            public uint FileAttributes;
            public uint ReparseTag;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern SafeFileHandle CreateFile(
            string fileName,
            uint desiredAccess,
            uint shareMode,
            IntPtr securityAttributes,
            uint creationDisposition,
            uint flagsAndAttributes,
            IntPtr templateFile);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GetFileInformationByHandleEx(
            SafeFileHandle fileHandle,
            int fileInformationClass,
            out FileAttributeTagInfo fileInformation,
            uint bufferSize);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern uint GetFinalPathNameByHandle(
            IntPtr fileHandle,
            StringBuilder path,
            uint pathLength,
            uint flags);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetFileInformationByHandle(
            SafeFileHandle fileHandle,
            int fileInformationClass,
            IntPtr fileInformation,
            uint bufferSize);

        public static bool RenameOpenFile(SafeFileHandle fileHandle, string destinationPath, bool replaceExisting) {
            byte[] name = Encoding.Unicode.GetBytes(destinationPath);
            int rootOffset = IntPtr.Size == 8 ? 8 : 4;
            int lengthOffset = rootOffset + IntPtr.Size;
            int nameOffset = lengthOffset + 4;
            IntPtr buffer = Marshal.AllocHGlobal(nameOffset + name.Length + 2);
            try {
                for (int index = 0; index < nameOffset + name.Length + 2; index++) Marshal.WriteByte(buffer, index, 0);
                Marshal.WriteByte(buffer, 0, replaceExisting ? (byte)1 : (byte)0);
                Marshal.WriteIntPtr(buffer, rootOffset, IntPtr.Zero);
                Marshal.WriteInt32(buffer, lengthOffset, name.Length);
                Marshal.Copy(name, 0, IntPtr.Add(buffer, nameOffset), name.Length);
                return SetFileInformationByHandle(fileHandle, 3, buffer, (uint)(nameOffset + name.Length));
            }
            finally { Marshal.FreeHGlobal(buffer); }
        }
    }
}
'@
}

function Assert-UniversaarlRunId {
    param([Parameter(Mandatory)][string]$RunId)
    if ($RunId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$') {
        throw 'Die Laufkennung ist ungueltig.'
    }
}

function New-UniversaarlRunId {
    param([string]$Prefix = 'lauf')
    '{0}-{1}-{2}' -f $Prefix, (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'), ([Guid]::NewGuid().ToString('N'))
}

function Assert-FullCommitSha {
    param([Parameter(Mandatory)][string]$Commit)
    if ($Commit -notmatch '^[0-9a-f]{40}$') { throw 'Eine vollstaendige 40-stellige Commit-SHA ist erforderlich.' }
}

function Get-UniversaarlSha256 {
    param([AllowEmptyString()][string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes([string]$Text)
        ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Get-UniversaarlConfiguredPath {
    param([Parameter(Mandatory)]$Project)
    $override = [Environment]::GetEnvironmentVariable([string]$Project.pathEnvironmentVariable)
    $candidate = if ([string]::IsNullOrWhiteSpace($override)) { [string]$Project.defaultPath } else { $override }
    if (-not [IO.Path]::IsPathRooted($candidate)) { throw "Der Pfad fuer '$($Project.id)' muss absolut sein." }
    [IO.Path]::GetFullPath($candidate).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
}

function Get-UniversaarlRawPushUrl {
    param([Parameter(Mandatory)][string]$Repository, [Parameter(Mandatory)][string]$Remote)
    if ($Remote -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { throw 'Der konfigurierte Remote-Name ist ungueltig.' }
    $pushUrls = Invoke-UniversaarlGitRead -Repository $Repository -Arguments @('config', '--local', '--get-all', "remote.$Remote.pushurl") -PreserveWhitespace
    if ($pushUrls.exitCode -gt 1) { throw 'Rohe Push-URL kann nicht sicher aus der lokalen Git-Konfiguration gelesen werden.' }
    $values = @(if ($pushUrls.exitCode -eq 0) { $pushUrls.output -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } })
    if ($values.Count -eq 0) {
        $urls = Invoke-UniversaarlGitRead -Repository $Repository -Arguments @('config', '--local', '--get-all', "remote.$Remote.url") -PreserveWhitespace
        if ($urls.exitCode -ne 0) { throw 'Rohe Remote-URL fehlt in der lokalen Git-Konfiguration.' }
        $values = @($urls.output -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    if ($values.Count -ne 1 -or $values[0] -match '[\x00-\x1f]') { throw 'Remote besitzt keine eindeutige sichere rohe Push-URL.' }
    [string]$values[0]
}

function Assert-UniversaarlExpectedPushRemote {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$Remote,
        [Parameter(Mandatory)][string]$ExpectedUrl
    )
    if ($ExpectedUrl -notmatch '^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\.git$') { throw 'Die Positivlisten-URL ist ungueltig.' }
    $raw = Get-UniversaarlRawPushUrl -Repository $Repository -Remote $Remote
    if ($raw -cne $ExpectedUrl) { throw 'Rohe Remote-Push-URL stimmt nicht exakt mit der Positivliste ueberein; Git-URL-Aliase und Umschreibungen sind unzulaessig.' }
    $ExpectedUrl
}

function Assert-UniversaarlMonitorConfiguration {
    param([Parameter(Mandatory)]$Configuration)
    if ($Configuration.schemaVersion -ne 1) { throw 'Die Kontrollzentrum-Konfiguration besitzt eine unbekannte Schemaversion.' }
    $projects = @($Configuration.projects)
    $ids = @($projects | ForEach-Object { [string]$_.id })
    if ($projects.Count -ne 2 -or @($ids | Sort-Object -Unique).Count -ne 2 -or $ids -cnotcontains 'blueprint' -or $ids -cnotcontains 'project-twin') {
        throw 'Die Konfiguration muss genau Blueprint und Project Twin enthalten.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$Configuration.reportDirectory) -or [IO.Path]::IsPathRooted([string]$Configuration.reportDirectory) -or [string]$Configuration.reportDirectory -match '(^|[\\/])\.\.([\\/]|$)') {
        throw 'Das Berichtverzeichnis muss ein sicherer relativer Kontrollzentrum-Pfad sein.'
    }
    if ([int]$Configuration.validationTimeoutSeconds -lt 1 -or [int]$Configuration.validationTimeoutSeconds -gt 3600) { throw 'Das konfigurierte Pruefzeitlimit ist ungueltig.' }
    foreach ($project in $projects) {
        if ([string]$project.pathEnvironmentVariable -notmatch '^UNIVERSAARL_[A-Z0-9_]+_PATH$') { throw "Ungueltige Pfad-Umgebungsvariable fuer '$($project.id)'." }
        if (-not [IO.Path]::IsPathRooted([string]$project.defaultPath)) { throw "Standardpfad fuer '$($project.id)' muss absolut sein." }
        $null = Assert-SafeRepositoryRelativePath -Path ([string]$project.reviewFile)
        if ([string]::IsNullOrWhiteSpace([string]$project.requiredNpmScript) -or @($project.validationArguments).Count -eq 0) { throw "Technische Pruefung fuer '$($project.id)' ist unvollstaendig konfiguriert." }
        if ($null -eq $project.germanCheck -or [string]::IsNullOrWhiteSpace([string]$project.germanCheck.npmScript) -or [int]$project.germanCheck.resultSchemaVersion -ne 1) { throw "Deutsch-Pruefung fuer '$($project.id)' ist unvollstaendig konfiguriert." }
        $mediaProperty = @($project.PSObject.Properties | Where-Object { $_.Name -ceq 'allowedVersionedMedia' })
        if ($mediaProperty.Count -ne 1) { throw "Projektbezogene Positivliste versionierter Medien fuer '$($project.id)' fehlt oder ist nicht exakt benannt." }
        $allowedMedia = @($mediaProperty[0].Value)
        if ([string]$project.id -ceq 'blueprint') {
            if ($allowedMedia.Count -ne 1) { throw 'Blueprint muss genau ein versioniertes Produktmedienartefakt positivlisten.' }
            $entryProperties = @($allowedMedia[0].PSObject.Properties.Name)
            if ($entryProperties.Count -ne 3 -or $entryProperties -cnotcontains 'path' -or $entryProperties -cnotcontains 'maxBytes' -or $entryProperties -cnotcontains 'mode' -or
                [string]$allowedMedia[0].path -cne 'artifacts/walkthrough/generated/UABC-WT-ENV-001/walkthrough.webm' -or
                $allowedMedia[0].maxBytes -isnot [int] -or [int]$allowedMedia[0].maxBytes -ne 1048576 -or
                $allowedMedia[0].mode -isnot [string] -or [string]$allowedMedia[0].mode -cne '100644') {
                throw 'Blueprint-Positivliste muss exakt den kanonischen Walkthrough-WebM-Pfad mit 1 MiB Grenze und Blobmodus 100644 enthalten.'
            }
        }
        elseif ($allowedMedia.Count -ne 0) { throw 'Project Twin darf keine versionierten Medienartefakte positivlisten.' }
        if ([int]$project.maxActiveChanges -lt 0 -or [int]$project.maxActiveChanges -gt 10) { throw "Grenze aktiver Aenderungen fuer '$($project.id)' ist ungueltig." }
    }
    $relationships = @($Configuration.relationships)
    if ($relationships.Count -ne 1 -or [string]$relationships[0].id -ne 'twin-reads-blueprint' -or [string]$relationships[0].consumerProjectId -ne 'project-twin' -or [string]$relationships[0].providerProjectId -ne 'blueprint') {
        throw 'Die Konfiguration muss genau den Vertrag Twin liest Blueprint enthalten.'
    }
}

function Assert-UniversaarlGoalConfiguration {
    param([Parameter(Mandatory)]$Configuration)
    if ($Configuration.schemaVersion -ne 1) { throw 'Die Zielkonfiguration besitzt eine unbekannte Schemaversion.' }
    foreach ($id in @('blueprint', 'project-twin')) {
        $property = $Configuration.projects.PSObject.Properties[$id]
        if ($null -eq $property -or [string]::IsNullOrWhiteSpace([string]$property.Value.objective) -or [string]::IsNullOrWhiteSpace([string]$property.Value.currentGoal)) {
            throw "Projektziel fuer '$id' fehlt oder ist unvollstaendig."
        }
    }
    if (@($Configuration.projects.PSObject.Properties).Count -ne 2) { throw 'Die Zielkonfiguration darf nur Blueprint und Project Twin enthalten.' }
    Assert-FullCommitSha -Commit ([string]$Configuration.projects.'project-twin'.requiredBaseCommit)
    if ([string]$Configuration.projects.'project-twin'.currentChange -notmatch '^[a-z0-9][a-z0-9-]+$') { throw 'Die aktuelle Twin-Aenderung ist in der Zielkonfiguration ungueltig.' }
    $relationship = $Configuration.relationships.PSObject.Properties['twin-reads-blueprint']
    if ($null -eq $relationship -or @($Configuration.relationships.PSObject.Properties).Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$relationship.Value.objective)) {
        throw 'Das Zusammenspielziel Twin liest Blueprint fehlt oder ist unvollstaendig.'
    }
}

function Invoke-UniversaarlGitRead {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$PreserveWhitespace
    )
    $nonGitNames = @('SSL_CERT_FILE', 'SSL_CERT_DIR', 'CURL_CA_BUNDLE', 'SSH_ASKPASS', 'SSH_ASKPASS_REQUIRE')
    $savedEnvironment = @(
        foreach ($entry in [Environment]::GetEnvironmentVariables().GetEnumerator()) {
            $name = [string]$entry.Key
            $selected = $name.StartsWith('GIT_', [StringComparison]::OrdinalIgnoreCase) -or $name.StartsWith('GCM_', [StringComparison]::OrdinalIgnoreCase)
            if (-not $selected) {
                foreach ($fixedName in $nonGitNames) {
                    if ([string]::Equals($name, $fixedName, [StringComparison]::OrdinalIgnoreCase)) { $selected = $true; break }
                }
            }
            if ($selected) { [pscustomobject]@{ name = $name; value = [string]$entry.Value } }
        }
    )
    $oldPreference = $ErrorActionPreference
    $oldEncoding = [Console]::OutputEncoding
    try {
        foreach ($entry in $savedEnvironment) { [Environment]::SetEnvironmentVariable([string]$entry.name, $null) }
        [Environment]::SetEnvironmentVariable('GIT_OPTIONAL_LOCKS', '0')
        [Environment]::SetEnvironmentVariable('GIT_TERMINAL_PROMPT', '0')
        [Environment]::SetEnvironmentVariable('GIT_PAGER', 'cat')
        [Environment]::SetEnvironmentVariable('GIT_CONFIG_NOSYSTEM', '1')
        [Environment]::SetEnvironmentVariable('GIT_CONFIG_GLOBAL', 'NUL')
        [Environment]::SetEnvironmentVariable('GIT_ATTR_NOSYSTEM', '1')
        # Standard-Proxys bleiben absichtlich erhalten: Der positivgelistete HTTPS-Zugriff auf GitHub kann einen Unternehmensproxy benoetigen. CA-/TLS-Ueberschreibungen und Helper-Steuerung sind dagegen bereinigt.
        [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
        $ErrorActionPreference = 'SilentlyContinue'
        $lines = @(& git -C $Repository @Arguments 2>$null)
        $joined = $lines -join "`n"
        [pscustomobject]@{
            exitCode = $LASTEXITCODE
            output = if ($PreserveWhitespace) { $joined } else { $joined.Trim() }
        }
    }
    finally {
        try {
            foreach ($entry in [Environment]::GetEnvironmentVariables().GetEnumerator()) {
                $name = [string]$entry.Key
                $selected = $name.StartsWith('GIT_', [StringComparison]::OrdinalIgnoreCase) -or $name.StartsWith('GCM_', [StringComparison]::OrdinalIgnoreCase)
                if (-not $selected) {
                    foreach ($fixedName in $nonGitNames) {
                        if ([string]::Equals($name, $fixedName, [StringComparison]::OrdinalIgnoreCase)) { $selected = $true; break }
                    }
                }
                if ($selected) { [Environment]::SetEnvironmentVariable($name, $null) }
            }
            foreach ($entry in $savedEnvironment) { [Environment]::SetEnvironmentVariable([string]$entry.name, [string]$entry.value) }
        }
        finally {
            [Console]::OutputEncoding = $oldEncoding
            $ErrorActionPreference = $oldPreference
        }
    }
}

function Get-UniversaarlRepositoryFingerprint {
    param([Parameter(Mandatory)][string]$Repository)
    if (-not (Test-Path -LiteralPath $Repository -PathType Container)) { throw 'Git-Arbeitsbereich ist nicht erreichbar.' }

    $inside = Invoke-UniversaarlGitRead -Repository $Repository -Arguments @('rev-parse', '--is-inside-work-tree')
    if ($inside.exitCode -ne 0 -or $inside.output -ne 'true') { throw 'Kein lesbarer Git-Arbeitsbereich.' }
    $head = Invoke-UniversaarlGitRead -Repository $Repository -Arguments @('rev-parse', '--verify', 'HEAD^{commit}')
    if ($head.exitCode -ne 0) { throw 'HEAD kann nicht als Commit aufgeloest werden.' }
    Assert-FullCommitSha -Commit $head.output
    $branch = Invoke-UniversaarlGitRead -Repository $Repository -Arguments @('branch', '--show-current')
    if ($branch.exitCode -ne 0) { throw 'Der aktuelle Zweig kann nicht gelesen werden.' }
    $status = Invoke-UniversaarlGitRead -Repository $Repository -Arguments @('-c', 'core.fsmonitor=false', '-c', 'core.untrackedCache=false', 'status', '--porcelain=v1', '--untracked-files=all') -PreserveWhitespace
    if ($status.exitCode -ne 0) { throw 'Der Arbeitsbaumstatus kann nicht gelesen werden.' }
    $index = Invoke-UniversaarlGitRead -Repository $Repository -Arguments @('ls-files', '--stage') -PreserveWhitespace
    if ($index.exitCode -ne 0) { throw 'Der Git-Index kann nicht gelesen werden.' }

    $statusText = [string]$status.output
    $indexText = [string]$index.output
    $statusHash = Get-UniversaarlSha256 -Text $statusText
    $indexHash = Get-UniversaarlSha256 -Text $indexText
    [pscustomobject]@{
        head = $head.output
        branch = $branch.output
        dirty = -not [string]::IsNullOrWhiteSpace($statusText)
        statusHash = $statusHash
        indexHash = $indexHash
        fingerprint = Get-UniversaarlSha256 -Text "$($head.output)`n$($branch.output)`n$statusHash`n$indexHash"
    }
}

function Test-UniversaarlFingerprintEqual {
    param([Parameter(Mandatory)]$Expected, [Parameter(Mandatory)]$Actual)
    [string]$Expected.head -eq [string]$Actual.head -and
        [string]$Expected.branch -eq [string]$Actual.branch -and
        [string]$Expected.statusHash -eq [string]$Actual.statusHash -and
        [string]$Expected.indexHash -eq [string]$Actual.indexHash -and
        [string]$Expected.fingerprint -eq [string]$Actual.fingerprint
}

function Assert-SafeRepositoryRelativePath {
    param([Parameter(Mandatory)][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or [IO.Path]::IsPathRooted($Path) -or $Path -match '[\x00-\x1f]' -or $Path -match '(^|[\\/])\.\.([\\/]|$)') {
        throw 'Unsicherer repository-relativer Pfad.'
    }
    $Path.Replace('\', '/')
}

function Assert-UniversaarlNoReparseComponents {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$FullPath)
    $normalizedRoot = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $normalizedPath = [IO.Path]::GetFullPath($FullPath)
    $rootItem = Get-Item -LiteralPath $normalizedRoot -Force -ErrorAction Stop
    if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Freigegebene Wurzel ist ein Reparse-Punkt: $normalizedRoot" }
    if ($normalizedPath -eq $normalizedRoot) { return }
    if (-not $normalizedPath.StartsWith($normalizedRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Pfad liegt ausserhalb der freigegebenen Wurzel.' }
    $relative = $normalizedPath.Substring($normalizedRoot.Length).TrimStart([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $current = $normalizedRoot
    foreach ($segment in $relative -split '[\\/]') {
        $current = Join-Path $current $segment
        $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse-Punkt ist nicht zulaessig: $current" }
    }
}

function Get-UniversaarlFinalPathFromStream {
    param([Parameter(Mandatory)][IO.FileStream]$Stream)
    Get-UniversaarlFinalPathFromHandle -Handle $Stream.SafeFileHandle
}

function Get-UniversaarlFinalPathFromHandle {
    param([Parameter(Mandatory)][Microsoft.Win32.SafeHandles.SafeFileHandle]$Handle)
    if ($env:OS -ne 'Windows_NT') { throw 'Die handlegebundene Pfadpruefung ist auf diesem Betriebssystem nicht verfuegbar.' }
    $capacity = 32768
    $builder = [Text.StringBuilder]::new($capacity)
    $length = [Universaarl.NativeFile]::GetFinalPathNameByHandle($Handle.DangerousGetHandle(), $builder, [uint32]$capacity, 0)
    if ($length -eq 0 -or $length -ge $capacity) { throw 'Der endgueltige Dateipfad kann nicht handlegebunden aufgeloest werden.' }
    $path = $builder.ToString()
    if ($path.StartsWith('\\?\UNC\', [StringComparison]::OrdinalIgnoreCase)) { $path = '\\' + $path.Substring(8) }
    elseif ($path.StartsWith('\\?\', [StringComparison]::OrdinalIgnoreCase)) { $path = $path.Substring(4) }
    [IO.Path]::GetFullPath($path)
}

function Close-UniversaarlDirectoryLock {
    param($Lock)
    if ($null -eq $Lock) { return }
    if ($null -ne $Lock.PSObject.Properties['keys']) {
        for ($index = $Lock.keys.Count - 1; $index -ge 0; $index--) {
            $key = [string]$Lock.keys[$index]
            if (-not $script:UniversaarlDirectoryLockRegistry.ContainsKey($key)) { continue }
            $record = $script:UniversaarlDirectoryLockRegistry[$key]
            $record.referenceCount = [int]$record.referenceCount - 1
            if ($record.referenceCount -le 0) {
                $record.handle.Dispose()
                $script:UniversaarlDirectoryLockRegistry.Remove($key)
            }
        }
        return
    }
    if ($null -ne $Lock.PSObject.Properties['handles']) {
        for ($index = $Lock.handles.Count - 1; $index -ge 0; $index--) { $Lock.handles[$index].Dispose() }
    }
}

function Open-UniversaarlLockedDirectoryChain {
    param([Parameter(Mandatory)][string]$Directory, [switch]$Create)
    if ($env:OS -ne 'Windows_NT') { throw 'Gesperrte Verzeichnisketten sind auf diesem Betriebssystem nicht verfuegbar.' }
    $target = [IO.Path]::GetFullPath($Directory).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $volumeRoot = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Directory))
    if ([string]::IsNullOrWhiteSpace($volumeRoot)) { throw 'Verzeichnis besitzt keine sichere Volume-Wurzel.' }
    $relative = [IO.Path]::GetFullPath($Directory).Substring($volumeRoot.Length).Trim([char[]]@('\', '/'))
    $paths = [Collections.Generic.List[string]]::new()
    $paths.Add($volumeRoot)
    $current = $volumeRoot
    foreach ($segment in @($relative -split '[\\/]' | Where-Object { $_ })) { $current = Join-Path $current $segment; $paths.Add($current) }
    $keys = [Collections.Generic.List[string]]::new()
    $deleteProtectionStarted = $false
    try {
        foreach ($path in $paths) {
            if (-not (Test-Path -LiteralPath $path)) {
                if (-not $Create) { throw "Verzeichniskomponente fehlt: $path" }
                $null = [IO.Directory]::CreateDirectory($path)
            }
            $pathComparable = [IO.Path]::GetFullPath($path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
            $key = $pathComparable.ToLowerInvariant()
            if ($script:UniversaarlDirectoryLockRegistry.ContainsKey($key)) {
                $record = $script:UniversaarlDirectoryLockRegistry[$key]
                if ($record.handle.IsInvalid -or $record.handle.IsClosed) { throw "Bestehende Verzeichnissperre ist ungueltig: $path" }
                $record.referenceCount = [int]$record.referenceCount + 1
                $keys.Add($key)
                if ($record.deleteProtected) { $deleteProtectionStarted = $true }
                continue
            }

            $deleteProtected = $true
            $handle = [Universaarl.NativeFile]::CreateFile($path, [uint32]0x00010000, 3, [IntPtr]::Zero, 3, 0x02200000, [IntPtr]::Zero)
            if ($null -eq $handle -or $handle.IsInvalid) {
                $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
                if ($null -ne $handle) { $handle.Dispose() }
                if ($errorCode -eq 32) {
                    # Ein bestehender Verzeichnishandle verweigert DELETE. Der
                    # nachfolgende gepruefte Fallbackhandle wird ebenfalls ohne
                    # FILE_SHARE_DELETE geoeffnet und haelt den Schutz danach
                    # selbst aufrecht, auch wenn der fremde Handle schliesst.
                    $deleteProtected = $true
                }
                elseif ($errorCode -eq 5 -and -not $deleteProtectionStarted) {
                    # Volume- und Systemvorfahren koennen per ACL bereits ausserhalb des Benutzereinflusses liegen.
                    $deleteProtected = $false
                }
                else { throw "Verzeichniskomponente kann nicht mit Loeschschutz gesperrt werden: $path (Win32 $errorCode)" }
                $handle = [Universaarl.NativeFile]::CreateFile($path, 0, 3, [IntPtr]::Zero, 3, 0x02200000, [IntPtr]::Zero)
            }
            if ($null -eq $handle -or $handle.IsInvalid) { if ($null -ne $handle) { $handle.Dispose() }; throw "Verzeichniskomponente kann nicht gegen Austausch gesperrt werden: $path" }
            $info = New-Object 'Universaarl.NativeFile+FileAttributeTagInfo'
            $infoSize = [Runtime.InteropServices.Marshal]::SizeOf([type]'Universaarl.NativeFile+FileAttributeTagInfo')
            if (-not [Universaarl.NativeFile]::GetFileInformationByHandleEx($handle, 9, [ref]$info, [uint32]$infoSize)) { $handle.Dispose(); throw "Attribute der gesperrten Verzeichniskomponente sind nicht lesbar: $path" }
            if (($info.FileAttributes -band [Universaarl.NativeFile]::FileAttributeDirectory) -eq 0 -or ($info.FileAttributes -band [Universaarl.NativeFile]::FileAttributeReparsePoint) -ne 0) { $handle.Dispose(); throw "Verzeichniskomponente ist kein regulaeres reparse-freies Verzeichnis: $path" }
            $final = Get-UniversaarlFinalPathFromHandle -Handle $handle
            $finalComparable = $final.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
            if (-not [string]::Equals($finalComparable, $pathComparable, [StringComparison]::OrdinalIgnoreCase)) { $handle.Dispose(); throw "Verzeichniskomponente wurde auf einen anderen Pfad umgeleitet: $path" }
            if ($pathComparable -eq $target -and -not $deleteProtected) { $handle.Dispose(); throw 'Zielverzeichnis kann nicht mit einem umbenennungssicheren Loeschhandle gesperrt werden.' }
            if ($deleteProtected) { $deleteProtectionStarted = $true }
            $script:UniversaarlDirectoryLockRegistry[$key] = [pscustomobject]@{ handle = $handle; referenceCount = 1; deleteProtected = $deleteProtected }
            $keys.Add($key)
        }
        $targetKey = $target.ToLowerInvariant()
        if (-not $script:UniversaarlDirectoryLockRegistry.ContainsKey($targetKey) -or -not $script:UniversaarlDirectoryLockRegistry[$targetKey].deleteProtected) { throw 'Zielverzeichnis besitzt keine wirksame Umbenennungssperre.' }
        [pscustomobject]@{ path = $target; keys = $keys }
    }
    catch {
        Close-UniversaarlDirectoryLock -Lock ([pscustomobject]@{ keys = $keys })
        throw
    }
}

function Assert-UniversaarlStreamBytes {
    param([Parameter(Mandatory)][IO.FileStream]$Stream, [Parameter(Mandatory)][byte[]]$Expected)
    $Stream.Flush($true)
    if ($Stream.Length -ne $Expected.LongLength) { throw 'Handlegebundene Ausgabegroesse stimmt nicht ueberein.' }
    $Stream.Position = 0
    $buffer = [byte[]]::new(8192)
    $offset = 0
    while (($read = $Stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
        for ($index = 0; $index -lt $read; $index++) { if ($buffer[$index] -ne $Expected[$offset + $index]) { throw 'Handlegebundener Ausgabeinhalt stimmt nicht ueberein.' } }
        $offset += $read
    }
    if ($offset -ne $Expected.Length) { throw 'Handlegebundene Ausgabemenge stimmt nicht ueberein.' }
}

function Read-UniversaarlRegularUtf8File {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][int64]$MaximumBytes
    )
    if ($MaximumBytes -lt 0) { throw 'Die Dateigroessengrenze ist ungueltig.' }
    $normalizedRoot = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $normalizedPath = [IO.Path]::GetFullPath($Path)
    if (-not $normalizedPath.StartsWith($normalizedRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Datei liegt ausserhalb der freigegebenen Wurzel.' }
    $directoryLock = Open-UniversaarlLockedDirectoryChain -Directory (Split-Path -Parent $normalizedPath)
    $stream = $null
    try {
        $stream = [IO.File]::Open($normalizedPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $finalPath = Get-UniversaarlFinalPathFromStream -Stream $stream
        if (-not [string]::Equals($finalPath, $normalizedPath, [StringComparison]::OrdinalIgnoreCase)) { throw 'Der geoeffnete Dateihandle verweist nicht auf die erwartete Datei.' }
        if ($stream.Length -gt $MaximumBytes) { throw "Datei ueberschreitet die Groessengrenze von $MaximumBytes Byte." }
        $memory = [IO.MemoryStream]::new()
        try {
            $buffer = [byte[]]::new(8192)
            $total = [int64]0
            while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                if ($total -gt $MaximumBytes - $read) { throw "Datei ueberschreitet beim Lesen die Groessengrenze von $MaximumBytes Byte." }
                $memory.Write($buffer, 0, $read)
                $total += $read
            }
            $text = [Text.UTF8Encoding]::new($false, $true).GetString($memory.ToArray())
            if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
            $text
        }
        finally { $memory.Dispose() }
    }
    finally {
        if ($null -ne $stream) { $stream.Dispose() }
        Close-UniversaarlDirectoryLock -Lock $directoryLock
    }
}

function Initialize-UniversaarlSafeDirectory {
    param(
        [Parameter(Mandatory)][string]$TrustedRoot,
        [Parameter(Mandatory)][string]$Directory
    )
    $root = [IO.Path]::GetFullPath($TrustedRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $target = [IO.Path]::GetFullPath($Directory).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if ($target -ne $root -and -not $target.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Ausgabeverzeichnis liegt ausserhalb der vertrauenswuerdigen Wurzel.' }
    $lock = Open-UniversaarlLockedDirectoryChain -Directory $target -Create
    try { $target }
    finally { Close-UniversaarlDirectoryLock -Lock $lock }
}

function Write-UniversaarlNewUtf8File {
    param(
        [Parameter(Mandatory)][string]$TrustedRoot,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [int64]$MaximumBytes = 8388608
    )
    $root = [IO.Path]::GetFullPath($TrustedRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Ausgabedatei liegt ausserhalb der vertrauenswuerdigen Wurzel.' }
    $parent = Split-Path -Parent $full
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes([string]$Text)
    if ($bytes.LongLength -gt $MaximumBytes) { throw "Ausgabedatei ueberschreitet die Groessengrenze von $MaximumBytes Byte." }
    $directoryLock = Open-UniversaarlLockedDirectoryChain -Directory $parent
    $stream = $null
    try {
        $stream = [IO.File]::Open($full, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        $finalPath = Get-UniversaarlFinalPathFromStream -Stream $stream
        if (-not [string]::Equals($finalPath, $full, [StringComparison]::OrdinalIgnoreCase)) { throw 'Geoeffneter Ausgabehandle verweist nicht auf die erwartete Datei.' }
        $stream.Write($bytes, 0, $bytes.Length)
        Assert-UniversaarlStreamBytes -Stream $stream -Expected $bytes
    }
    finally {
        if ($null -ne $stream) { $stream.Dispose() }
        Close-UniversaarlDirectoryLock -Lock $directoryLock
    }
    $full
}

function Write-UniversaarlAtomicUtf8File {
    param(
        [Parameter(Mandatory)][string]$TrustedRoot,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [int64]$MaximumBytes = 8388608
    )
    $root = [IO.Path]::GetFullPath($TrustedRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Atomare Ausgabedatei liegt ausserhalb der vertrauenswuerdigen Wurzel.' }
    $parent = Split-Path -Parent $full
    $temporary = Join-Path $parent ('.universaarl-{0}.tmp' -f [Guid]::NewGuid().ToString('N'))
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes([string]$Text)
    if ($bytes.LongLength -gt $MaximumBytes) { throw "Atomare Ausgabedatei ueberschreitet die Groessengrenze von $MaximumBytes Byte." }
    $directoryLock = Open-UniversaarlLockedDirectoryChain -Directory $parent
    $stream = $null
    try {
        $temporaryHandle = [Universaarl.NativeFile]::CreateFile($temporary, [uint32]3221291008, 0, [IntPtr]::Zero, 1, 0x00000080, [IntPtr]::Zero)
        if ($null -eq $temporaryHandle -or $temporaryHandle.IsInvalid) { if ($null -ne $temporaryHandle) { $temporaryHandle.Dispose() }; throw 'Exklusiver temporaerer Ausgabehandle konnte nicht erstellt werden.' }
        $stream = [IO.FileStream]::new($temporaryHandle, [IO.FileAccess]::ReadWrite)
        $temporaryFinal = Get-UniversaarlFinalPathFromStream -Stream $stream
        if (-not [string]::Equals($temporaryFinal, $temporary, [StringComparison]::OrdinalIgnoreCase)) { throw 'Temporaerer Ausgabehandle verweist nicht auf die erwartete Datei.' }
        $stream.Write($bytes, 0, $bytes.Length)
        Assert-UniversaarlStreamBytes -Stream $stream -Expected $bytes
        if (Test-Path -LiteralPath $full) {
            $existingStream = [IO.File]::Open($full, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
            try {
                $existingFinal = Get-UniversaarlFinalPathFromStream -Stream $existingStream
                if (-not [string]::Equals($existingFinal, $full, [StringComparison]::OrdinalIgnoreCase)) { throw 'Bestehender Zielhandle verweist nicht auf die erwartete Datei.' }
            }
            finally { $existingStream.Dispose() }
        }
        if (-not [Universaarl.NativeFile]::RenameOpenFile($stream.SafeFileHandle, $full, $true)) { throw 'Handlegebundener atomarer Austausch der Zieldatei ist fehlgeschlagen.' }
        $movedFinal = Get-UniversaarlFinalPathFromStream -Stream $stream
        if (-not [string]::Equals($movedFinal, $full, [StringComparison]::OrdinalIgnoreCase)) { throw 'Verschobener Ausgabehandle verweist nicht auf das erwartete Ziel.' }
        Assert-UniversaarlStreamBytes -Stream $stream -Expected $bytes
        $full
    }
    finally {
        if ($null -ne $stream) { $stream.Dispose() }
        if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
        Close-UniversaarlDirectoryLock -Lock $directoryLock
    }
}

function Get-UniversaarlCommitTree {
    param([Parameter(Mandatory)][string]$Repository, [Parameter(Mandatory)][string]$Commit)
    Assert-FullCommitSha -Commit $Commit
    $tree = Invoke-UniversaarlGitRead -Repository $Repository -Arguments @('-c', 'core.quotePath=false', 'ls-tree', '-r', '-l', '--full-tree', $Commit) -PreserveWhitespace
    if ($tree.exitCode -ne 0) { throw 'Der Commit-Baum kann nicht gelesen werden.' }
    $entries = [Collections.Generic.List[object]]::new()
    foreach ($line in @($tree.output -split "`n" | Where-Object { $_ })) {
        $tab = $line.IndexOf("`t")
        if ($tab -lt 1) { throw 'Ungueltiger Eintrag im Commit-Baum.' }
        $metadata = @($line.Substring(0, $tab) -split '\s+' | Where-Object { $_ })
        if ($metadata.Count -ne 4) { throw 'Ungueltige Metadaten im Commit-Baum.' }
        $rawPath = $line.Substring($tab + 1)
        if ($rawPath.StartsWith('"')) { throw 'Commit-Baum enthaelt einen nicht sicher darstellbaren Dateinamen.' }
        $path = Assert-SafeRepositoryRelativePath -Path $rawPath
        $size = if ($metadata[3] -eq '-') { $null } elseif ($metadata[3] -match '^\d+$') { [int64]$metadata[3] } else { throw 'Ungueltige Groesse im Commit-Baum.' }
        $entries.Add([pscustomobject]@{ mode = $metadata[0]; type = $metadata[1]; object = $metadata[2]; size = $size; path = $path })
    }
    @($entries)
}

function Get-UniversaarlBlobEntry {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$Commit,
        [Parameter(Mandatory)][string]$Path,
        [switch]$Required
    )
    Assert-FullCommitSha -Commit $Commit
    $safePath = Assert-SafeRepositoryRelativePath -Path $Path
    $entryResult = Invoke-UniversaarlGitRead -Repository $Repository -Arguments @('-c', 'core.quotePath=false', 'ls-tree', $Commit, '--', $safePath)
    if ($entryResult.exitCode -ne 0 -or [string]::IsNullOrWhiteSpace($entryResult.output)) {
        if ($Required) { throw "Pflichtdatei '$safePath' fehlt im Commit." }
        return $null
    }
    $lines = @($entryResult.output -split "`n" | Where-Object { $_ })
    if ($lines.Count -ne 1) { throw "Pfad '$safePath' ist im Commit nicht eindeutig." }
    $tab = $lines[0].IndexOf("`t")
    if ($tab -lt 1) { throw "Pfad '$safePath' besitzt ungueltige Git-Metadaten." }
    $metadata = $lines[0].Substring(0, $tab) -split ' '
    if ($metadata.Count -ne 3 -or $metadata[1] -ne 'blob' -or $metadata[0] -notin @('100644', '100755')) {
        throw "Pfad '$safePath' ist keine regulaere versionierte Datei."
    }
    $type = Invoke-UniversaarlGitRead -Repository $Repository -Arguments @('cat-file', '-t', $metadata[2])
    $size = Invoke-UniversaarlGitRead -Repository $Repository -Arguments @('cat-file', '-s', $metadata[2])
    if ($type.exitCode -ne 0 -or $type.output -ne 'blob' -or $size.exitCode -ne 0 -or $size.output -notmatch '^\d+$') {
        throw "Blob-Metadaten fuer '$safePath' koennen nicht gelesen werden."
    }
    [pscustomobject]@{ path = $safePath; mode = $metadata[0]; object = $metadata[2]; size = [int64]$size.output }
}

function Read-UniversaarlCommitText {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$Commit,
        [Parameter(Mandatory)][string]$Path,
        [int64]$MaximumBytes = $script:UniversaarlTextBlobLimit,
        [switch]$Required
    )
    $entry = Get-UniversaarlBlobEntry -Repository $Repository -Commit $Commit -Path $Path -Required:$Required
    if ($null -eq $entry) { return $null }
    if ($entry.size -gt $MaximumBytes) { throw "Versionierte Datei '$($entry.path)' ueberschreitet die Groessengrenze von $MaximumBytes Byte." }
    $content = Invoke-UniversaarlGitRead -Repository $Repository -Arguments @('cat-file', 'blob', $entry.object) -PreserveWhitespace
    if ($content.exitCode -ne 0) { throw "Versionierte Datei '$($entry.path)' kann nicht gelesen werden." }
    [pscustomobject]@{ path = $entry.path; object = $entry.object; size = $entry.size; content = [string]$content.output }
}

function Read-UniversaarlWorkingText {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$Path,
        [int64]$MaximumBytes = 65536,
        [switch]$RequireCleanRepository
    )
    $safePath = Assert-SafeRepositoryRelativePath -Path $Path
    if ([IO.Path]::GetFileName($safePath) -like '.env*') { throw 'Reale `.env*` duerfen nicht aus der Arbeitskopie gelesen werden.' }
    if ($RequireCleanRepository) {
        $fingerprint = Get-UniversaarlRepositoryFingerprint -Repository $Repository
        if ($fingerprint.dirty) { throw 'Die Arbeitskopie ist nicht sauber; die Datei wird nicht gelesen.' }
    }
    $root = [IO.Path]::GetFullPath($Repository).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $full = [IO.Path]::GetFullPath((Join-Path $root $safePath))
    if (-not $full.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Arbeitskopiedatei liegt ausserhalb des Repositories.' }
    Assert-UniversaarlNoReparseComponents -Root $root -FullPath $full
    Read-UniversaarlRegularUtf8File -Root $root -Path $full -MaximumBytes $MaximumBytes
}

function Test-UniversaarlProhibitedRuntimePath {
    param([Parameter(Mandatory)][string]$Path, [switch]$AllowVersionedProductMedia)
    $normalized = $Path.Replace('\', '/')
    $segments = $normalized -split '/'
    $leaf = $segments[-1]
    if ($leaf -like '.env*' -and $leaf -ne '.env.example') { return $true }
    if ($leaf -match '^(?i)(\.npmrc|\.yarnrc(?:\..*)?|\.pypirc|\.netrc|\.git-credentials|\.gitconfig|NuGet\.Config|settings\.xml|gradle\.properties|pip\.conf|auth\.json|credentials?|credentials\.tfrc\.json|application_default_credentials\.json|service-account[^/]*\.json|known_hosts|id_(?:rsa|dsa|ecdsa|ed25519)|accessTokens\.json|azureProfile\.json|logins\.json|key4\.db|cert9\.db|cookies\.sqlite|Login Data|Web Data|Local State)$') { return $true }
    if ($segments | Where-Object { $_ -match '^(?i)(\.auth|\.azure|\.aws|\.docker|\.kube|\.nuget|\.terraform\.d|\.playwright-cli|auth-state|storage-state|browser-profile|browser-profiles|user-data-dir|runtime|traces?|videos?|source-cache|test-results|playwright-report|blob-report|allure-results|allure-report|\.nyc_output)$' }) { return $true }
    if ($normalized -match '(?i)(^|/)\.config/(?:gh|gcloud|glab|hub|doctl|azure)(?:/|$)') { return $true }
    if ($leaf -match '(?i)(^|[._-])(storage-?state|auth-?state|credentials?|cookies?|sessions?|secrets?|tokens?)([._-]|$)') { return $true }
    if ($leaf -match '(?i)\.(pem|key|pfx|p12|jks|keystore|trace|log|zip)$') { return $true }
    if ($leaf -match '(?i)\.(webm|mp4|mov)$') { return -not $AllowVersionedProductMedia }
    return $false
}

function Assert-UniversaarlCommitRuntimeSafe {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$Commit,
        [object[]]$AllowedVersionedMedia = @(),
        [int]$MaximumFiles = 25000,
        [int64]$MaximumBytes = 1073741824
    )
    $allowedMediaByPath = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($allowed in @($AllowedVersionedMedia)) {
        if ($null -eq $allowed) { throw 'Leerer Eintrag in der Positivliste versionierter Medien.' }
        $allowedProperties = @($allowed.PSObject.Properties.Name)
        $safeAllowedPath = Assert-SafeRepositoryRelativePath -Path ([string]$allowed.path)
        $allowedExtension = [IO.Path]::GetExtension($safeAllowedPath)
        if ($allowedProperties.Count -ne 3 -or $allowedProperties -cnotcontains 'path' -or $allowedProperties -cnotcontains 'maxBytes' -or $allowedProperties -cnotcontains 'mode' -or
            $allowedExtension -cnotin @('.webm', '.mp4', '.mov') -or $allowed.maxBytes -isnot [int] -or
            [int]$allowed.maxBytes -lt 1 -or [int]$allowed.maxBytes -gt 16777216 -or $allowed.mode -isnot [string] -or
            [string]$allowed.mode -cnotin @('100644', '100755') -or $allowedMediaByPath.ContainsKey($safeAllowedPath)) {
            throw 'Positivliste versionierter Medien ist nicht eindeutig, exakt typisiert oder eng begrenzt.'
        }
        $allowedMediaByPath.Add($safeAllowedPath, $allowed)
    }
    $entries = @(Get-UniversaarlCommitTree -Repository $Repository -Commit $Commit)
    if ($entries.Count -gt $MaximumFiles) { throw "Commit ueberschreitet die Grenze von $MaximumFiles Dateien." }
    $totalBytes = [int64]0
    foreach ($entry in $entries) {
        if ($entry.type -eq 'commit') { throw "Submodul '$($entry.path)' ist fuer die bereinigte Pruefkopie nicht zulaessig." }
        if ($entry.type -ne 'blob' -or $entry.mode -notin @('100644', '100755')) { throw "Nichtregulaerer Commit-Eintrag ist fuer die Pruefkopie nicht zulaessig: $($entry.path)" }
        $isAllowedMedia = $allowedMediaByPath.ContainsKey([string]$entry.path)
        if ($isAllowedMedia -and [string]$entry.mode -cne [string]$allowedMediaByPath[[string]$entry.path].mode) { throw "Positivgelistetes Medienartefakt besitzt nicht den exakt freigegebenen Blobmodus: $($entry.path)" }
        if ($isAllowedMedia -and ($null -eq $entry.size -or [int64]$entry.size -gt [int64]$allowedMediaByPath[[string]$entry.path].maxBytes)) { throw "Positivgelistetes Medienartefakt ueberschreitet seine Groessengrenze: $($entry.path)" }
        if (Test-UniversaarlProhibitedRuntimePath -Path $entry.path -AllowVersionedProductMedia:$isAllowedMedia) { throw "Verbotenes Laufzeitmaterial im Commit: $($entry.path)" }
        if ($null -ne $entry.size) {
            if ($entry.size -gt $MaximumBytes -or $totalBytes -gt $MaximumBytes - $entry.size) { throw "Commit ueberschreitet die Groessengrenze von $MaximumBytes Byte." }
            $totalBytes += [int64]$entry.size
        }
    }
}

function Invoke-UniversaarlIsolatedGit {
    param(
        [Parameter(Mandatory)][string]$GitHome,
        [Parameter(Mandatory)][string[]]$Arguments,
        [string]$Repository,
        [switch]$UseExplicitRepositoryPaths
    )
    $gitHomeParent = Split-Path -Parent ([IO.Path]::GetFullPath($GitHome))
    $null = Initialize-UniversaarlSafeDirectory -TrustedRoot $gitHomeParent -Directory $GitHome
    $emptyTemplate = Join-Path $GitHome 'leere-git-vorlage'
    $null = Initialize-UniversaarlSafeDirectory -TrustedRoot $GitHome -Directory $emptyTemplate
    if (@(Get-ChildItem -LiteralPath $emptyTemplate -Force -ErrorAction Stop).Count -ne 0) { throw 'Kontrollierte Git-Vorlage ist nicht leer.' }
    $nonGitNames = @('HOME', 'USERPROFILE', 'SSL_CERT_FILE', 'SSL_CERT_DIR', 'CURL_CA_BUNDLE', 'SSH_ASKPASS', 'SSH_ASKPASS_REQUIRE')
    $savedEnvironment = @(
        foreach ($entry in [Environment]::GetEnvironmentVariables().GetEnumerator()) {
            $name = [string]$entry.Key
            $selected = $name.StartsWith('GIT_', [StringComparison]::OrdinalIgnoreCase) -or $name.StartsWith('GCM_', [StringComparison]::OrdinalIgnoreCase)
            if (-not $selected) {
                foreach ($fixedName in $nonGitNames) {
                    if ([string]::Equals($name, $fixedName, [StringComparison]::OrdinalIgnoreCase)) { $selected = $true; break }
                }
            }
            if ($selected) { [pscustomobject]@{ name = $name; value = [string]$entry.Value } }
        }
    )
    $oldPreference = $ErrorActionPreference
    try {
        foreach ($entry in $savedEnvironment) { [Environment]::SetEnvironmentVariable([string]$entry.name, $null) }
        [Environment]::SetEnvironmentVariable('HOME', $GitHome)
        [Environment]::SetEnvironmentVariable('USERPROFILE', $GitHome)
        [Environment]::SetEnvironmentVariable('GIT_CONFIG_NOSYSTEM', '1')
        [Environment]::SetEnvironmentVariable('GIT_CONFIG_GLOBAL', (Join-Path $GitHome 'leere-gitconfig'))
        [Environment]::SetEnvironmentVariable('GIT_TEMPLATE_DIR', $emptyTemplate)
        [Environment]::SetEnvironmentVariable('GIT_TERMINAL_PROMPT', '0')
        [Environment]::SetEnvironmentVariable('GIT_OPTIONAL_LOCKS', '0')
        [Environment]::SetEnvironmentVariable('GIT_PAGER', 'cat')
        [Environment]::SetEnvironmentVariable('GIT_ATTR_NOSYSTEM', '1')
        # Standard-Proxys bleiben absichtlich erhalten: Der positivgelistete HTTPS-Zugriff auf GitHub kann einen Unternehmensproxy benoetigen. CA-/TLS-Ueberschreibungen und Helper-Steuerung sind dagegen bereinigt.
        $ErrorActionPreference = 'SilentlyContinue'
        $all = if ($UseExplicitRepositoryPaths) {
            if ([string]::IsNullOrWhiteSpace($Repository)) { throw 'Explizite Git-Repositorypfade benoetigen ein Repository.' }
            $repositoryRoot = [IO.Path]::GetFullPath($Repository).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
            @("--git-dir=$(Join-Path $repositoryRoot '.git')", "--work-tree=$repositoryRoot") + $Arguments
        }
        elseif ($Repository) { @('-C', $Repository) + $Arguments }
        else { $Arguments }
        $output = @(& git @all 2>&1)
        [pscustomobject]@{ exitCode = $LASTEXITCODE; output = (($output | ForEach-Object { [string]$_ }) -join "`n").Trim() }
    }
    finally {
        try {
            foreach ($entry in [Environment]::GetEnvironmentVariables().GetEnumerator()) {
                $name = [string]$entry.Key
                $selected = $name.StartsWith('GIT_', [StringComparison]::OrdinalIgnoreCase) -or $name.StartsWith('GCM_', [StringComparison]::OrdinalIgnoreCase)
                if (-not $selected) {
                    foreach ($fixedName in $nonGitNames) {
                        if ([string]::Equals($name, $fixedName, [StringComparison]::OrdinalIgnoreCase)) { $selected = $true; break }
                    }
                }
                if ($selected) { [Environment]::SetEnvironmentVariable($name, $null) }
            }
            foreach ($entry in $savedEnvironment) { [Environment]::SetEnvironmentVariable([string]$entry.name, [string]$entry.value) }
        }
        finally { $ErrorActionPreference = $oldPreference }
    }
}

function Assert-UniversaarlCleanPushRepositoryConfiguration {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$GitHome,
        [Parameter(Mandatory)][string]$ExpectedHooksPath,
        [Parameter(Mandatory)][string]$TrustedSandboxRoot,
        [switch]$RequireCredentialManager
    )
    $listed = Invoke-UniversaarlIsolatedGit -GitHome $GitHome -Repository $Repository -UseExplicitRepositoryPaths -Arguments @('config', '--local', '--name-only', '--list')
    if ($listed.exitCode -ne 0) { throw 'Lokale Git-Konfiguration der Push-Kopie kann nicht vollstaendig gelesen werden.' }
    $names = @($listed.output -split "`n" | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })
    $forbidden = @($names | Where-Object { $_ -match '^(?:url\.|include\.|includeif\.|remote\.)' -or $_ -match '\.(?:insteadof|pushinsteadof)$' })
    if ($forbidden.Count -gt 0) { throw "Push-Kopie enthaelt verbotene Git-Konfiguration: $($forbidden -join ', ')" }
    $allowed = @('core.repositoryformatversion', 'core.filemode', 'core.bare', 'core.logallrefupdates', 'core.symlinks', 'core.ignorecase', 'core.hookspath')
    if ($RequireCredentialManager) { $allowed += 'credential.helper' }
    $unexpected = @($names | Where-Object { $allowed -notcontains $_ })
    if ($unexpected.Count -gt 0) { throw "Push-Kopie enthaelt nicht positivgelistete Git-Konfiguration: $($unexpected -join ', ')" }
    foreach ($group in @($names | Group-Object)) { if ($group.Count -ne 1) { throw "Git-Konfigurationsschluessel ist nicht eindeutig: $($group.Name)" } }
    $trustedRoot = [IO.Path]::GetFullPath($TrustedSandboxRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $expectedHooks = [IO.Path]::GetFullPath($ExpectedHooksPath).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if (-not $expectedHooks.StartsWith($trustedRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Git-Hook-Pfad liegt nicht innerhalb der kontrollierten Publisher-Wegwerfkopie.' }
    $hookDirectoryLock = Open-UniversaarlLockedDirectoryChain -Directory $expectedHooks
    try {
        if (@(Get-ChildItem -LiteralPath $expectedHooks -Force -ErrorAction Stop).Count -ne 0) { throw 'Kontrollierter Git-Hook-Pfad der Push-Kopie ist nicht leer.' }
    }
    finally { Close-UniversaarlDirectoryLock -Lock $hookDirectoryLock }
    $hooks = Invoke-UniversaarlIsolatedGit -GitHome $GitHome -Repository $Repository -UseExplicitRepositoryPaths -Arguments @('config', '--local', '--get-all', 'core.hooksPath')
    if ($hooks.exitCode -ne 0 -or @($hooks.output -split "`n" | Where-Object { $_ }).Count -ne 1 -or -not [string]::Equals([IO.Path]::GetFullPath($hooks.output), $expectedHooks, [StringComparison]::OrdinalIgnoreCase)) { throw 'Git-Hook-Pfad der Push-Kopie stimmt nicht exakt mit dem kontrollierten leeren Publisher-Pfad ueberein.' }
    $bare = Invoke-UniversaarlIsolatedGit -GitHome $GitHome -Repository $Repository -UseExplicitRepositoryPaths -Arguments @('config', '--local', '--get', 'core.bare')
    if ($bare.exitCode -ne 0 -or $bare.output -ne 'false') { throw 'Kernkonfiguration der Push-Kopie entspricht nicht der exakten nicht-baren Commitkopie.' }
    if ($RequireCredentialManager) {
        $credential = Invoke-UniversaarlIsolatedGit -GitHome $GitHome -Repository $Repository -UseExplicitRepositoryPaths -Arguments @('config', '--local', '--get-all', 'credential.helper')
        if ($credential.exitCode -ne 0 -or $credential.output -ne 'manager') { throw 'Push-Kopie verwendet nicht exakt den freigegebenen Git Credential Manager.' }
    }
    $remotes = Invoke-UniversaarlIsolatedGit -GitHome $GitHome -Repository $Repository -UseExplicitRepositoryPaths -Arguments @('remote')
    if ($remotes.exitCode -ne 0 -or -not [string]::IsNullOrWhiteSpace($remotes.output)) { throw 'Push-Kopie besitzt ein entferntes Git-Ziel.' }
    $gitDirectory = Invoke-UniversaarlIsolatedGit -GitHome $GitHome -Repository $Repository -UseExplicitRepositoryPaths -Arguments @('rev-parse', '--absolute-git-dir')
    if ($gitDirectory.exitCode -ne 0) { throw 'Git-Verzeichnis der Push-Kopie ist unbekannt.' }
    $internalHooks = Join-Path $gitDirectory.output 'hooks'
    if (Test-Path -LiteralPath $internalHooks) {
        $hookLock = Open-UniversaarlLockedDirectoryChain -Directory $internalHooks
        try { if (@(Get-ChildItem -LiteralPath $internalHooks -Force -ErrorAction Stop).Count -ne 0) { throw 'Interne Hook-Vorlage der Push-Kopie ist nicht leer.' } }
        finally { Close-UniversaarlDirectoryLock -Lock $hookLock }
    }
}

function Assert-UniversaarlCleanQueryRepositoryConfiguration {
    param([Parameter(Mandatory)][string]$Repository, [Parameter(Mandatory)][string]$GitHome)
    $listed = Invoke-UniversaarlIsolatedGit -GitHome $GitHome -Repository $Repository -Arguments @('config', '--local', '--name-only', '--list')
    if ($listed.exitCode -ne 0) { throw 'Lokale Git-Konfiguration der Remote-Abfrage kann nicht vollstaendig gelesen werden.' }
    $names = @($listed.output -split "`n" | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })
    $allowed = @('core.repositoryformatversion', 'core.filemode', 'core.bare', 'core.symlinks', 'core.ignorecase', 'core.precomposeunicode')
    $unexpected = @($names | Where-Object { $allowed -notcontains $_ })
    if ($unexpected.Count -gt 0) { throw "Remote-Abfrage enthaelt nicht positivgelistete Git-Konfiguration: $($unexpected -join ', ')" }
    foreach ($group in @($names | Group-Object)) { if ($group.Count -ne 1) { throw "Git-Konfigurationsschluessel der Remote-Abfrage ist nicht eindeutig: $($group.Name)" } }
    $bare = Invoke-UniversaarlIsolatedGit -GitHome $GitHome -Repository $Repository -Arguments @('config', '--local', '--get', 'core.bare')
    if ($bare.exitCode -ne 0 -or $bare.output -ne 'true') { throw 'Remote-Abfrage ist kein kontrolliertes bares Git-Repository.' }
    $remotes = Invoke-UniversaarlIsolatedGit -GitHome $GitHome -Repository $Repository -Arguments @('remote')
    if ($remotes.exitCode -ne 0 -or -not [string]::IsNullOrWhiteSpace($remotes.output)) { throw 'Remote-Abfrage besitzt ein konfiguriertes entferntes Git-Ziel.' }
    $gitDirectory = Invoke-UniversaarlIsolatedGit -GitHome $GitHome -Repository $Repository -Arguments @('rev-parse', '--absolute-git-dir')
    if ($gitDirectory.exitCode -ne 0) { throw 'Git-Verzeichnis der Remote-Abfrage ist unbekannt.' }
    $internalHooks = Join-Path $gitDirectory.output 'hooks'
    if (Test-Path -LiteralPath $internalHooks) {
        $hookLock = Open-UniversaarlLockedDirectoryChain -Directory $internalHooks
        try { if (@(Get-ChildItem -LiteralPath $internalHooks -Force -ErrorAction Stop).Count -ne 0) { throw 'Hook-Vorlage der Remote-Abfrage ist nicht leer.' } }
        finally { Close-UniversaarlDirectoryLock -Lock $hookLock }
    }
}

function Invoke-UniversaarlCleanLsRemote {
    param([Parameter(Mandatory)][string]$Url, [Parameter(Mandatory)][string]$Ref)
    if ($Ref -notmatch '^refs/heads/[A-Za-z0-9][A-Za-z0-9._/-]*$' -or $Ref -match '(?:\.\.|@\{|//|/\.|\.lock(?:/|$)|[./]$)') { throw 'Remote-Ref ist ungueltig.' }
    $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $root = Join-Path $tempBase ("universaarl-remote-{0}" -f [Guid]::NewGuid().ToString('N'))
    $null = Initialize-UniversaarlSafeDirectory -TrustedRoot $tempBase -Directory $root
    try {
        $repository = Join-Path $root 'query.git'
        $gitHome = Join-Path $root 'git-home'
        $init = Invoke-UniversaarlIsolatedGit -GitHome $gitHome -Arguments @('init', '--quiet', '--bare', $repository)
        if ($init.exitCode -ne 0) { throw 'Bereinigtes Repository fuer die Remote-Abfrage konnte nicht erstellt werden.' }
        Assert-UniversaarlCleanQueryRepositoryConfiguration -Repository $repository -GitHome $gitHome
        Invoke-UniversaarlIsolatedGit -GitHome $gitHome -Repository $repository -Arguments @('ls-remote', '--heads', $Url, $Ref)
    }
    finally {
        if (Test-Path -LiteralPath $root) {
            $item = Get-Item -LiteralPath $root -Force -ErrorAction SilentlyContinue
            if ($null -ne $item -and (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { Remove-Item -LiteralPath $root -Force -ErrorAction SilentlyContinue }
            else { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

function New-UniversaarlCommitSnapshot {
    param(
        [Parameter(Mandatory)][string]$SourceRepository,
        [Parameter(Mandatory)][string]$Commit,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$SandboxRoot,
        [object[]]$AllowedVersionedMedia = @()
    )
    Assert-FullCommitSha -Commit $Commit
    Assert-UniversaarlCommitRuntimeSafe -Repository $SourceRepository -Commit $Commit -AllowedVersionedMedia $AllowedVersionedMedia
    $environmentExample = Test-UniversaarlEnvironmentExample -Repository $SourceRepository -Commit $Commit
    if ($environmentExample.present -and $environmentExample.safe -ne $true) { throw 'Unsichere versionierte `.env.example` verhindert die Commit-Kopie.' }
    if (Test-Path -LiteralPath $Destination) { throw 'Ziel der Commit-Kopie existiert bereits.' }
    $gitHome = Join-Path $SandboxRoot 'git-home'
    $hooks = Join-Path $SandboxRoot 'leere-hooks'
    $sandboxParent = Split-Path -Parent ([IO.Path]::GetFullPath($SandboxRoot))
    $null = Initialize-UniversaarlSafeDirectory -TrustedRoot $sandboxParent -Directory $SandboxRoot
    foreach ($directory in @($Destination, $gitHome, $hooks)) { $null = Initialize-UniversaarlSafeDirectory -TrustedRoot $SandboxRoot -Directory $directory }
    $init = Invoke-UniversaarlIsolatedGit -GitHome $gitHome -Arguments @('init', '--quiet', $Destination)
    if ($init.exitCode -ne 0) { throw "Temporaeres Git-Repository konnte nicht angelegt werden: $($init.output)" }
    $config = Invoke-UniversaarlIsolatedGit -GitHome $gitHome -Repository $Destination -Arguments @('config', 'core.hooksPath', $hooks)
    if ($config.exitCode -ne 0) { throw 'Git-Hooks konnten in der Wegwerfkopie nicht isoliert werden.' }
    $fetch = Invoke-UniversaarlIsolatedGit -GitHome $gitHome -Repository $Destination -Arguments @('-c', 'protocol.file.allow=always', 'fetch', '--quiet', '--no-tags', '--depth=1', $SourceRepository, $Commit)
    if ($fetch.exitCode -ne 0) { throw "Commit konnte nicht in die Wegwerfkopie uebernommen werden: $($fetch.output)" }
    # `git checkout` ist auf Windows fuer frisch geholte, grosse Baume gelegentlich
    # an kurzlebigen Dateisperren gescheitert. HEAD und Arbeitsbaum werden deshalb
    # ohne Hook-Ausfuehrung direkt an den bereits geprueften Commit gebunden.
    $detach = Invoke-UniversaarlIsolatedGit -GitHome $gitHome -Repository $Destination -Arguments @('update-ref', '--no-deref', 'HEAD', $Commit)
    if ($detach.exitCode -ne 0) { throw "Commit konnte nicht als abgeloester HEAD gebunden werden: $($detach.output)" }
    $populateAttempts = [Collections.Generic.List[string]]::new()
    $populate = $null
    for ($attempt = 0; $attempt -lt 2; $attempt++) {
        $populate = Invoke-UniversaarlIsolatedGit -GitHome $gitHome -Repository $Destination -Arguments @('read-tree', '-mu', 'HEAD')
        $populateAttempts.Add("Versuch $($attempt + 1) (Code $($populate.exitCode)): $($populate.output)")
        if ($populate.exitCode -eq 0) { break }
        if ($attempt -eq 0) { Start-Sleep -Milliseconds 200 }
    }
    if ($null -eq $populate -or $populate.exitCode -ne 0) { throw "Arbeitsbaum des gebundenen Commits konnte nicht erzeugt werden: $($populateAttempts -join ' | ')" }
    Remove-Item -LiteralPath (Join-Path $Destination '.git\FETCH_HEAD') -Force -ErrorAction SilentlyContinue
    $remotes = Invoke-UniversaarlIsolatedGit -GitHome $gitHome -Repository $Destination -Arguments @('remote')
    if ($remotes.exitCode -ne 0 -or -not [string]::IsNullOrWhiteSpace($remotes.output)) { throw 'Die Wegwerfkopie besitzt ein entferntes Git-Ziel.' }
    $head = Invoke-UniversaarlGitRead -Repository $Destination -Arguments @('rev-parse', '--verify', 'HEAD^{commit}')
    if ($head.exitCode -ne 0 -or $head.output -ne $Commit) { throw 'Die Wegwerfkopie ist nicht an die erwartete Commit-SHA gebunden.' }
    $Destination
}

function Test-UniversaarlBoundReportExitCode {
    param([Parameter(Mandatory)][int]$ExitCode)
    # Die Berichte verwenden 1 fuer einen vollstaendig erzeugten, aber global
    # roten Zustand. Der Publisher bewertet danach nur das gewaehlte Projekt und
    # dessen Beziehungen. Andere Rueckgabecodes bedeuten einen Laufzeitfehler.
    $ExitCode -in @(0, 1)
}

function Get-UniversaarlScopedPublishGateBlockers {
    param(
        [Parameter(Mandatory)]$ProjectResult,
        [Parameter(Mandatory)]$TechnicalRelationship,
        [Parameter(Mandatory)]$ProjectGoalResult,
        [Parameter(Mandatory)]$GoalRelationship
    )
    $blockers = [Collections.Generic.List[string]]::new()
    if ([string]$ProjectResult.status -notin @('GRUEN', 'GELB')) { $blockers.Add("Projektstatus ist $($ProjectResult.status), nicht GRUEN oder GELB.") }
    if ([string]$ProjectResult.validation -ne 'passed') { $blockers.Add('Die technische Pruefung ist nicht bestanden.') }
    if ([string]$ProjectResult.germanValidation -ne 'passed') { $blockers.Add('Der projektspezifische maschinenlesbare Deutsch-Nachweis ist nicht bestanden.') }
    if ($ProjectResult.targetUnchanged -ne $true) { $blockers.Add('Unveraendertheitsnachweis des Zielprojekts fehlt.') }
    if ([string]$TechnicalRelationship.status -notin @('passed', 'warning')) { $blockers.Add('Die commitgebundene Twin-Blueprint-Vertragspruefung ist fehlgeschlagen oder unbekannt.') }
    if ([string]$ProjectGoalResult.status -notin @('GRUEN', 'GELB')) { $blockers.Add('Die strategische Projektziel-Pruefstufe ist rot oder unbekannt.') }
    if ([string]$GoalRelationship.status -notin @('GRUEN', 'GELB')) { $blockers.Add('Die strategische Zusammenspiel-Pruefstufe ist rot oder unbekannt.') }
    @($blockers)
}

function Get-UniversaarlSecretFindings {
    param([AllowEmptyString()][string]$Text)
    $patterns = @(
        '(?i)-----BEGIN\s+(?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
        '(?i)\bgh[oprsu]_[A-Za-z0-9]{20,}\b',
        '(?i)\bglpat-[A-Za-z0-9_-]{16,}\b',
        '(?i)\bxox[baprs]-[A-Za-z0-9-]{12,}\b',
        '(?i)\bAKIA[0-9A-Z]{16}\b',
        '(?i)\beyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b',
        '(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b',
        '(?i)\b[A-Za-z0-9.-]+\.onmicrosoft\.com\b',
        '(?i)\b[a-z][a-z0-9+.-]*://[^/\s:@]+:[^@\s]+@'
    )
    @($patterns | Where-Object { $Text -match $_ })
}

function Protect-UniversaarlLogText {
    param([AllowEmptyString()][string]$Text, [string[]]$SensitiveRoots = @())
    $value = [string]$Text
    foreach ($root in @($SensitiveRoots | Where-Object { $_ })) {
        $value = $value.Replace($root, '<PFAD>').Replace($root.Replace('\', '/'), '<PFAD>')
    }
    $value = [regex]::Replace($value, '(?i)-----BEGIN\s+(?:RSA |EC |OPENSSH )?PRIVATE KEY-----[\s\S]*?-----END\s+(?:RSA |EC |OPENSSH )?PRIVATE KEY-----', '<GEHEIMNIS>')
    $value = [regex]::Replace($value, '(?i)\b(?:gh[oprsu]_[A-Za-z0-9]{20,}|glpat-[A-Za-z0-9_-]{16,}|xox[baprs]-[A-Za-z0-9-]{12,}|AKIA[0-9A-Z]{16})\b', '<GEHEIMNIS>')
    $value = [regex]::Replace($value, '(?i)\beyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b', '<GEHEIMNIS>')
    $value = [regex]::Replace($value, '(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b', '<MANDANTENKENNUNG>')
    $value = [regex]::Replace($value, '(?i)\b[A-Za-z0-9.-]+\.onmicrosoft\.com\b', '<MANDANTENKENNUNG>')
    $value = [regex]::Replace($value, '(?i)\b(?:TENANT(?:_ID)?|MANDANT(?:ENKENNUNG)?|PRIVATE_KEY|SIGNING_KEY|ACCESS_KEY|API_KEY|CLIENT_SECRET|CREDENTIALS?|DATABASE_URL|CONNECTION_STRING|PASSWORD|PASSWD|TOKEN|SECRET|AUTH(?:ORIZATION)?|SESSION|COOKIE)\s*[=:]\s*[^\s]+', '<GEHEIMNIS>')
    $value = [regex]::Replace($value, '(?i)\b[a-z][a-z0-9+.-]*://[^/\s:@]+:[^@\s]+@', '<ZUGANGSDATEN>@')
    if ($value.Length -gt $script:UniversaarlLogCharacterLimit) { $value = $value.Substring(0, $script:UniversaarlLogCharacterLimit) + "`n<AUSGABE GEKUERZT>" }
    $value
}

function Initialize-UniversaarlProcessRunner {
    param(
        [Parameter(Mandatory)][string]$ControlRoot,
        [Parameter(Mandatory)][string]$SandboxRoot
    )
    $dotnet = Get-Command dotnet.exe -ErrorAction SilentlyContinue
    if ($null -eq $dotnet) { $dotnet = Get-Command dotnet -ErrorAction SilentlyContinue }
    if ($null -eq $dotnet) { throw 'Die .NET-6-Werkzeugkette fuer den sicheren Prozesshelfer fehlt.' }
    $project = Join-Path $ControlRoot 'tools\Universaarl.ProcessRunner\Universaarl.ProcessRunner.csproj'
    if (-not (Test-Path -LiteralPath $project -PathType Leaf)) { throw 'Der sichere Prozesshelfer fehlt.' }
    $output = Join-Path $SandboxRoot 'prozesshelfer'
    $intermediate = Join-Path $SandboxRoot 'prozesshelfer-obj'
    New-Item -ItemType Directory -Path $output, $intermediate -Force | Out-Null
    $oldTelemetry = [Environment]::GetEnvironmentVariable('DOTNET_CLI_TELEMETRY_OPTOUT')
    $oldLogo = [Environment]::GetEnvironmentVariable('DOTNET_NOLOGO')
    [Environment]::SetEnvironmentVariable('DOTNET_CLI_TELEMETRY_OPTOUT', '1')
    [Environment]::SetEnvironmentVariable('DOTNET_NOLOGO', '1')
    try {
        $intermediateArgument = $intermediate.Replace('\', '/') + '/'
        $buildOutput = @(& $dotnet.Source build $project '--configuration' 'Release' '--output' $output '--nologo' '--verbosity' 'quiet' "-p:BaseIntermediateOutputPath=$intermediateArgument" "-p:MSBuildProjectExtensionsPath=$intermediateArgument" 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "Der sichere Prozesshelfer konnte nicht erstellt werden: $((($buildOutput | ForEach-Object { [string]$_ }) -join ' ').Trim())" }
    }
    finally {
        [Environment]::SetEnvironmentVariable('DOTNET_CLI_TELEMETRY_OPTOUT', $oldTelemetry)
        [Environment]::SetEnvironmentVariable('DOTNET_NOLOGO', $oldLogo)
    }
    $dll = Join-Path $output 'Universaarl.ProcessRunner.dll'
    if (-not (Test-Path -LiteralPath $dll -PathType Leaf)) { throw 'Der erstellte Prozesshelfer ist nicht auffindbar.' }
    [pscustomobject]@{ dotnet = $dotnet.Source; dll = $dll }
}

function Invoke-UniversaarlSanitizedProcess {
    param(
        [Parameter(Mandatory)]$Runner,
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string]$SandboxRoot,
        [Parameter(Mandatory)][string]$LogPath,
        [Parameter(Mandatory)][string]$LogRoot,
        [hashtable]$AdditionalEnvironment = @{},
        [int]$TimeoutSeconds = 240,
        [string[]]$SensitiveRoots = @()
    )
    $isolatedHome = Join-Path $SandboxRoot 'home'
    $cache = Join-Path $SandboxRoot 'npm-cache'
    $appData = Join-Path $isolatedHome 'AppData\Roaming'
    $localAppData = Join-Path $isolatedHome 'AppData\Local'
    $sandboxParent = Split-Path -Parent ([IO.Path]::GetFullPath($SandboxRoot))
    $null = Initialize-UniversaarlSafeDirectory -TrustedRoot $sandboxParent -Directory $SandboxRoot
    foreach ($directory in @($isolatedHome, $cache, $appData, $localAppData)) { $null = Initialize-UniversaarlSafeDirectory -TrustedRoot $SandboxRoot -Directory $directory }
    $logParent = Split-Path -Parent ([IO.Path]::GetFullPath($LogPath))
    $null = Initialize-UniversaarlSafeDirectory -TrustedRoot $LogRoot -Directory $logParent
    $logDirectoryLock = Open-UniversaarlLockedDirectoryChain -Directory $logParent
    $logStream = $null
    try {
        $logStream = [IO.File]::Open([IO.Path]::GetFullPath($LogPath), [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        $logFinalPath = Get-UniversaarlFinalPathFromStream -Stream $logStream
        if (-not [string]::Equals($logFinalPath, [IO.Path]::GetFullPath($LogPath), [StringComparison]::OrdinalIgnoreCase)) { throw 'Geoeffneter Protokollhandle verweist nicht auf die erwartete Protokolldatei.' }
    }
    catch {
        if ($null -ne $logStream) { $logStream.Dispose() }
        Close-UniversaarlDirectoryLock -Lock $logDirectoryLock
        throw
    }
    $environment = @{
        PATH = [Environment]::GetEnvironmentVariable('PATH')
        PATHEXT = [Environment]::GetEnvironmentVariable('PATHEXT')
        SystemRoot = [Environment]::GetEnvironmentVariable('SystemRoot')
        ComSpec = [Environment]::GetEnvironmentVariable('ComSpec')
        TEMP = $SandboxRoot
        TMP = $SandboxRoot
        HOME = $isolatedHome
        USERPROFILE = $isolatedHome
        APPDATA = $appData
        LOCALAPPDATA = $localAppData
        CI = 'true'
        NO_COLOR = '1'
        FORCE_COLOR = '0'
        TERM = 'dumb'
        GIT_OPTIONAL_LOCKS = '0'
        GIT_TERMINAL_PROMPT = '0'
        GIT_CONFIG_NOSYSTEM = '1'
        GIT_CONFIG_GLOBAL = (Join-Path $isolatedHome 'leere-gitconfig')
        npm_config_cache = $cache
        npm_config_audit = 'false'
        npm_config_fund = 'false'
        npm_config_update_notifier = 'false'
    }
    foreach ($entry in $AdditionalEnvironment.GetEnumerator()) { $environment[[string]$entry.Key] = [string]$entry.Value }
    $request = [pscustomobject]@{
        FilePath = [IO.Path]::GetFullPath($FilePath)
        Arguments = @($Arguments)
        WorkingDirectory = [IO.Path]::GetFullPath($WorkingDirectory)
        Environment = $environment
        TimeoutMilliseconds = $TimeoutSeconds * 1000
        MaximumOutputCharacters = $script:UniversaarlLogCharacterLimit
        SensitiveRoots = @($SensitiveRoots + $SandboxRoot)
    }
    $requestPath = Join-Path $SandboxRoot ("prozess-{0}.json" -f [Guid]::NewGuid().ToString('N'))
    $resultPath = Join-Path $SandboxRoot ("ergebnis-{0}.json" -f [Guid]::NewGuid().ToString('N'))
    $runnerStdoutPath = Join-Path $SandboxRoot ("helfer-ausgabe-{0}.log" -f [Guid]::NewGuid().ToString('N'))
    $runnerStderrPath = Join-Path $SandboxRoot ("helfer-fehler-{0}.log" -f [Guid]::NewGuid().ToString('N'))
    try {
        $null = Write-UniversaarlNewUtf8File -TrustedRoot $SandboxRoot -Path $requestPath -Text ($request | ConvertTo-Json -Depth 8 -Compress) -MaximumBytes 1048576
        if ($TimeoutSeconds -lt 1 -or $TimeoutSeconds -gt 3600) { throw 'Das Prozesszeitlimit ist ungueltig.' }
        foreach ($helperArgument in @([string]$Runner.dll, $requestPath, $resultPath)) {
            if ($helperArgument.IndexOf('"') -ge 0) { throw 'Ein Pfadargument fuer den Prozesshelfer ist ungueltig.' }
        }
        $helperArguments = ((@([string]$Runner.dll, $requestPath, $resultPath) | ForEach-Object { '"' + $_ + '"' }) -join ' ')
        $runnerProcess = Start-Process -FilePath ([string]$Runner.dotnet) -ArgumentList $helperArguments -RedirectStandardOutput $runnerStdoutPath -RedirectStandardError $runnerStderrPath -WindowStyle Hidden -PassThru
        $waitMilliseconds = [int][Math]::Min(3660000, ([int64]$TimeoutSeconds + 30) * 1000)
        if (-not $runnerProcess.WaitForExit($waitMilliseconds)) {
            try { $runnerProcess.Kill() } catch { }
            throw 'Der sichere Prozesshelfer hat sein aeusseres Zeitlimit ueberschritten.'
        }
        $runnerProcess.WaitForExit()
        $runnerExitCode = [int]$runnerProcess.ExitCode
        $runnerProcess.Dispose()
        if ($runnerExitCode -ne 0 -or -not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
            $runnerParts = [Collections.Generic.List[string]]::new()
            foreach ($helperLog in @($runnerStdoutPath, $runnerStderrPath)) {
                if (Test-Path -LiteralPath $helperLog -PathType Leaf) {
                    try { $runnerParts.Add((Read-UniversaarlRegularUtf8File -Root $SandboxRoot -Path $helperLog -MaximumBytes 65536)) } catch { $runnerParts.Add('<HELFERAUSGABE NICHT SICHER LESBAR>') }
                }
            }
            $runnerError = Protect-UniversaarlLogText -Text (($runnerParts -join ' ').Trim()) -SensitiveRoots @($SensitiveRoots + $SandboxRoot)
            throw "Der sichere Prozesshelfer ist mit Rueckgabecode $runnerExitCode fehlgeschlagen: $runnerError"
        }
        $resultText = Read-UniversaarlRegularUtf8File -Root $SandboxRoot -Path $resultPath -MaximumBytes (4 * $script:UniversaarlLogCharacterLimit)
        $result = $resultText | ConvertFrom-Json
        $stdout = Protect-UniversaarlLogText -Text ([string]$result.StandardOutput) -SensitiveRoots $SensitiveRoots
        $stderr = Protect-UniversaarlLogText -Text ([string]$result.StandardError) -SensitiveRoots $SensitiveRoots
        $log = ($stdout + "`n" + $stderr).Trim()
        $logBytes = [Text.UTF8Encoding]::new($false).GetBytes($log)
        if ($logBytes.LongLength -gt 2 * $script:UniversaarlLogCharacterLimit + 64) { throw 'Redigiertes Prozessprotokoll ist unerwartet gross.' }
        $logStream.Write($logBytes, 0, $logBytes.Length)
        Assert-UniversaarlStreamBytes -Stream $logStream -Expected $logBytes
        [pscustomobject]@{
            exitCode = [int]$result.ExitCode
            timedOut = [bool]$result.TimedOut
            outputTruncated = [bool]$result.OutputTruncated
            output = $stdout
            error = $stderr
        }
    }
    finally {
        if ($null -ne $logStream) { $logStream.Dispose() }
        Close-UniversaarlDirectoryLock -Lock $logDirectoryLock
        Remove-Item -LiteralPath $requestPath, $resultPath, $runnerStdoutPath, $runnerStderrPath -Force -ErrorAction SilentlyContinue
    }
}

function Test-UniversaarlEnvironmentExample {
    param([Parameter(Mandatory)][string]$Repository, [Parameter(Mandatory)][string]$Commit)
    $findings = [Collections.Generic.List[object]]::new()
    try {
        $entry = Get-UniversaarlBlobEntry -Repository $Repository -Commit $Commit -Path '.env.example'
        if ($null -eq $entry) { return [pscustomobject]@{ present = $false; safe = $null; findings = @() } }
        if ($entry.size -gt 65536) {
            $findings.Add([pscustomobject]@{ severity = 'high'; code = 'ENV-EXAMPLE-001'; message = 'Die versionierte `.env.example` ist groesser als 64 KiB.' })
            return [pscustomobject]@{ present = $true; safe = $false; findings = @($findings) }
        }
        $blob = Read-UniversaarlCommitText -Repository $Repository -Commit $Commit -Path '.env.example' -MaximumBytes 65536 -Required
    }
    catch {
        $findings.Add([pscustomobject]@{ severity = 'high'; code = 'ENV-EXAMPLE-006'; message = "Die versionierte `.env.example` kann nicht sicher als regulaerer Textblob geprueft werden: $($_.Exception.Message)" })
        return [pscustomobject]@{ present = $true; safe = $false; findings = @($findings) }
    }

    $placeholderPattern = '^(?:|<[A-Z0-9][A-Z0-9_.:-]*>|\$\{[A-Z_][A-Z0-9_]*\}|REPLACE_ME|REPLACE|CHANGEME)$'
    $harmlessPattern = '^(?i:true|false|0|1|development|test|localhost|127\.0\.0\.1|http://localhost(?::[0-9]{2,5})?|http://127\.0\.0\.1(?::[0-9]{2,5})?)$'
    $sensitiveNamePattern = '(?i)(?:tenant|private|signing|access[_-]?key|api[_-]?key|client[_-]?(?:id|secret)|credential|connection|database|db[_-]?url|password|passwd|token|secret|cookie|session|auth)'
    $lineNumber = 0
    foreach ($line in ([string]$blob.content -split "`n")) {
        $lineNumber++
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        if ($trimmed.StartsWith('#')) {
            $comment = $trimmed.TrimStart('#').Trim()
            $commentSecret = @(Get-UniversaarlSecretFindings -Text $comment).Count -gt 0
            $commentSensitiveValue = $false
            $commentAbsolutePath = $comment -match '(?i)(?:[A-Za-z]:[\\/]|\\\\[^\\/\s]+[\\/]|(?<![A-Za-z0-9_.:/-])/(?!/)[A-Za-z0-9._-]+(?:/|\b))'
            if ($comment -match '(?i)\b(?:tenant|tenant[_-]?id|mandant|mandantenkennung)\s*[:=]\s*([^\s#]+)') {
                $tenantValue = $Matches[1].Trim([char[]]@('"', "'"))
                if ($tenantValue -notmatch $placeholderPattern) { $commentSensitiveValue = $true }
            }
            if ($comment -match '^([A-Za-z_][A-Za-z0-9_]*)\s*[:=]\s*(.*)$') {
                $commentName = $Matches[1]
                $commentValue = $Matches[2].Trim().Trim([char[]]@('"', "'"))
                $commentSensitiveValue = $commentName -match $sensitiveNamePattern -and $commentValue -notmatch $placeholderPattern
                $commentAbsolutePath = $commentAbsolutePath -or $commentValue -match '^(?:[A-Za-z]:[\\/]|\\\\|[\\/])'
            }
            elseif ($comment -match "(?i)\b($sensitiveNamePattern)\b\s*(?:[:=]|is\b|ist\b)\s*([^\s#]+)") {
                $commentSensitiveValue = $Matches[2].Trim([char[]]@('"', "'")) -notmatch $placeholderPattern
            }
            if ($commentSecret -or $commentSensitiveValue) {
                $findings.Add([pscustomobject]@{ severity = 'critical'; code = 'ENV-EXAMPLE-005'; message = "Die versionierte `.env.example` enthaelt in Kommentarzeile $lineNumber eine Mandanten- oder Geheimniskennung." })
            }
            if ($commentAbsolutePath) { $findings.Add([pscustomobject]@{ severity = 'high'; code = 'ENV-EXAMPLE-004'; message = "Die versionierte `.env.example` enthaelt in Kommentarzeile $lineNumber einen absoluten Hostpfad." }) }
            continue
        }
        if ($trimmed -notmatch '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
            $findings.Add([pscustomobject]@{ severity = 'medium'; code = 'ENV-EXAMPLE-002'; message = "Die versionierte `.env.example` enthaelt in Zeile $lineNumber keinen gueltigen Schluessel-Platzhalter." })
            continue
        }
        $name = $Matches[1]
        $value = $Matches[2].Trim().Trim([char[]]@('"', "'"))
        $isPlaceholder = $value -match $placeholderPattern
        $isHarmless = $value -match $harmlessPattern -or ($name -match '(?i)(?:^|_)PORT$' -and $value -match '^\d{1,5}$' -and [int]$value -ge 1 -and [int]$value -le 65535)
        $absolutePath = $value -match '^(?:[A-Za-z]:[\\/]|\\\\|[\\/])'
        $secretShape = @(Get-UniversaarlSecretFindings -Text $value).Count -gt 0
        $sensitiveName = $name -match $sensitiveNamePattern
        if ($sensitiveName -and -not $isPlaceholder) {
            $findings.Add([pscustomobject]@{ severity = 'critical'; code = 'ENV-EXAMPLE-003'; message = "Die versionierte `.env.example` enthaelt fuer den vertraulichen Schluessel '$name' einen echten Wert statt eines Platzhalters." })
        }
        elseif (-not $isPlaceholder -and -not $isHarmless) {
            $findings.Add([pscustomobject]@{ severity = 'high'; code = 'ENV-EXAMPLE-003'; message = "Die versionierte `.env.example` enthaelt fuer '$name' einen nicht freigegebenen echten Wert statt eines Platzhalters." })
        }
        if ($absolutePath) {
            $findings.Add([pscustomobject]@{ severity = 'high'; code = 'ENV-EXAMPLE-004'; message = "Die versionierte `.env.example` enthaelt fuer '$name' einen absoluten Hostpfad." })
        }
        if ($secretShape) {
            $findings.Add([pscustomobject]@{ severity = 'critical'; code = 'ENV-EXAMPLE-005'; message = "Die versionierte `.env.example` enthaelt fuer '$name' eine Mandanten- oder Geheimniskennung." })
        }
    }
    [pscustomobject]@{ present = $true; safe = $findings.Count -eq 0; findings = @($findings) }
}

function Get-UniversaarlApprovalTaskState {
    param([AllowEmptyString()][string]$Text)
    $pattern = '(?m)^[ \t]*-[ \t]+\[(?<mark>[ xX])\][ \t]+(?:Human approval and archive|Menschliche Freigabe und Archivierung)[ \t]*\r?$'
    $matches = @([regex]::Matches([string]$Text, $pattern))
    if ($matches.Count -ne 1) { return 'invalid' }
    if ($matches[0].Groups['mark'].Value -cmatch '^[xX]$') { return 'approved' }
    'open'
}

function Test-UniversaarlGermanEvidencePayload {
    param(
        [Parameter(Mandatory)][string]$Json,
        [Parameter(Mandatory)][string]$ProjectId,
        [Parameter(Mandatory)][string]$Commit,
        [int]$SchemaVersion = 1
    )
    Assert-FullCommitSha -Commit $Commit
    try { $payload = $Json.Trim() | ConvertFrom-Json } catch { return $false }
    if ($payload -isnot [Management.Automation.PSCustomObject]) { return $false }
    $expectedProperties = @('schemaVersion', 'status', 'language', 'projectId', 'commit', 'userVisibleOwnContentGerman')
    $actualProperties = @($payload.PSObject.Properties.Name)
    if ($actualProperties.Count -ne $expectedProperties.Count -or @($expectedProperties | Where-Object { $actualProperties -cnotcontains $_ }).Count -ne 0) { return $false }
    $schemaIsInteger = $payload.schemaVersion -is [int] -or $payload.schemaVersion -is [long]
    $schemaIsInteger -and [int64]$payload.schemaVersion -eq $SchemaVersion -and
        $payload.status -is [string] -and $payload.status -ceq 'passed' -and
        $payload.language -is [string] -and $payload.language -ceq 'de' -and
        $payload.projectId -is [string] -and $payload.projectId -ceq $ProjectId -and
        $payload.commit -is [string] -and $payload.commit -ceq $Commit -and
        $payload.userVisibleOwnContentGerman -is [bool] -and $payload.userVisibleOwnContentGerman -eq $true
}

function Get-UniversaarlExactPushRefSpec {
    param([Parameter(Mandatory)][string]$Commit, [Parameter(Mandatory)][string]$Branch)
    Assert-FullCommitSha -Commit $Commit
    if ($Branch -notmatch '^[A-Za-z0-9][A-Za-z0-9._/-]*$' -or $Branch -match '(?:\.\.|@\{|//|/\.|\.lock(?:/|$)|[./]$)') { throw 'Ungueltiger Zielzweig.' }
    "$Commit`:refs/heads/$Branch"
}

function Read-UniversaarlBoundReport {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$RunId,
        [ValidateSet('audit', 'goal')][string]$Kind,
        [string]$TrustedRoot
    )
    Assert-UniversaarlRunId -RunId $RunId
    if (-not [string]::IsNullOrWhiteSpace($TrustedRoot)) { Assert-UniversaarlNoReparseComponents -Root $TrustedRoot -FullPath $Path }
    if ([string]::IsNullOrWhiteSpace($TrustedRoot)) { throw 'Eine vertrauenswuerdige Berichtswurzel ist erforderlich.' }
    $text = Read-UniversaarlRegularUtf8File -Root $TrustedRoot -Path $Path -MaximumBytes $script:UniversaarlReportLimit
    $report = $text | ConvertFrom-Json
    if ([int]$report.schemaVersion -ne 2 -or [string]$report.runId -ne $RunId -or $report.completed -ne $true -or [string]$report.kind -ne $Kind) {
        throw 'Laufbericht ist veraltet, unvollstaendig oder gehoert zu einem anderen Lauf.'
    }
    $inputShaProperties = @($report.inputShas.PSObject.Properties)
    $inputShaNames = @($inputShaProperties.Name)
    if ($inputShaProperties.Count -ne 2 -or $inputShaNames -cnotcontains 'blueprint' -or $inputShaNames -cnotcontains 'project-twin') { throw 'Laufbericht enthaelt nicht exakt beide projektbezogenen Eingabe-SHAs.' }
    foreach ($property in $inputShaProperties) { Assert-FullCommitSha -Commit ([string]$property.Value) }
    $report
}
