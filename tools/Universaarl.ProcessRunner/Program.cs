using System.ComponentModel;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

internal sealed class ProcessRequest
{
    public string FilePath { get; set; } = "";
    public string[] Arguments { get; set; } = Array.Empty<string>();
    public string WorkingDirectory { get; set; } = "";
    public Dictionary<string, string> Environment { get; set; } = new(StringComparer.OrdinalIgnoreCase);
    public int TimeoutMilliseconds { get; set; } = 240_000;
    public int MaximumOutputCharacters { get; set; } = 131_072;
    public string[] SensitiveRoots { get; set; } = Array.Empty<string>();
}

internal sealed class ProcessResult
{
    public int ExitCode { get; set; }
    public bool TimedOut { get; set; }
    public bool OutputTruncated { get; set; }
    public string StandardOutput { get; set; } = "";
    public string StandardError { get; set; } = "";
}

internal sealed class WindowsProcess : IDisposable
{
    private SafeFileHandle? _jobHandle;

    public WindowsProcess(
        SafeFileHandle jobHandle,
        SafeFileHandle processHandle,
        FileStream standardOutput,
        FileStream standardError)
    {
        _jobHandle = jobHandle;
        ProcessHandle = processHandle;
        StandardOutput = standardOutput;
        StandardError = standardError;
    }

    public SafeFileHandle ProcessHandle { get; }
    public FileStream StandardOutput { get; }
    public FileStream StandardError { get; }

    public void CloseJob()
    {
        var handle = Interlocked.Exchange(ref _jobHandle, null);
        handle?.Dispose();
    }

    public void Dispose()
    {
        CloseJob();
        StandardOutput.Dispose();
        StandardError.Dispose();
        ProcessHandle.Dispose();
    }
}

internal static class Program
{
    private const uint HandleFlagInherit = 0x00000001;
    private const uint StartfUseStdHandles = 0x00000100;
    private const uint CreateSuspended = 0x00000004;
    private const uint CreateUnicodeEnvironment = 0x00000400;
    private const uint ExtendedStartupInfoPresent = 0x00080000;
    private const uint CreateNoWindow = 0x08000000;
    private const uint JobObjectLimitKillOnJobClose = 0x00002000;
    private const int JobObjectExtendedLimitInformationClass = 9;
    private const int ErrorInsufficientBuffer = 122;
    private const uint WaitObject0 = 0x00000000;
    private const uint WaitFailed = 0xffffffff;
    private const uint Infinite = 0xffffffff;
    private const uint ProcThreadAttributeHandleList = 0x00020002;

    [StructLayout(LayoutKind.Sequential)]
    private struct SecurityAttributes
    {
        public int Length;
        public IntPtr SecurityDescriptor;

        [MarshalAs(UnmanagedType.Bool)]
        public bool InheritHandle;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct StartupInfo
    {
        public int Size;
        public string? Reserved;
        public string? Desktop;
        public string? Title;
        public uint X;
        public uint Y;
        public uint XSize;
        public uint YSize;
        public uint XCountChars;
        public uint YCountChars;
        public uint FillAttribute;
        public uint Flags;
        public ushort ShowWindow;
        public ushort Reserved2Size;
        public IntPtr Reserved2;
        public IntPtr StandardInput;
        public IntPtr StandardOutput;
        public IntPtr StandardError;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct StartupInfoEx
    {
        public StartupInfo StartupInfo;
        public IntPtr AttributeList;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct ProcessInformation
    {
        public IntPtr Process;
        public IntPtr Thread;
        public uint ProcessId;
        public uint ThreadId;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct JobObjectBasicLimitInformation
    {
        public long PerProcessUserTimeLimit;
        public long PerJobUserTimeLimit;
        public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize;
        public UIntPtr MaximumWorkingSetSize;
        public uint ActiveProcessLimit;
        public UIntPtr Affinity;
        public uint PriorityClass;
        public uint SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct IoCounters
    {
        public ulong ReadOperationCount;
        public ulong WriteOperationCount;
        public ulong OtherOperationCount;
        public ulong ReadTransferCount;
        public ulong WriteTransferCount;
        public ulong OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct JobObjectExtendedLimitInformation
    {
        public JobObjectBasicLimitInformation BasicLimitInformation;
        public IoCounters IoInfo;
        public UIntPtr ProcessMemoryLimit;
        public UIntPtr JobMemoryLimit;
        public UIntPtr PeakProcessMemoryUsed;
        public UIntPtr PeakJobMemoryUsed;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CreatePipe(
        out SafeFileHandle readPipe,
        out SafeFileHandle writePipe,
        ref SecurityAttributes pipeAttributes,
        uint size);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetHandleInformation(
        SafeFileHandle handle,
        uint mask,
        uint flags);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CreateProcessW(
        string applicationName,
        StringBuilder commandLine,
        IntPtr processAttributes,
        IntPtr threadAttributes,
        [MarshalAs(UnmanagedType.Bool)] bool inheritHandles,
        uint creationFlags,
        IntPtr environment,
        string currentDirectory,
        ref StartupInfoEx startupInfo,
        out ProcessInformation processInformation);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool InitializeProcThreadAttributeList(
        IntPtr attributeList,
        int attributeCount,
        uint flags,
        ref IntPtr size);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UpdateProcThreadAttribute(
        IntPtr attributeList,
        uint flags,
        IntPtr attribute,
        IntPtr value,
        IntPtr size,
        IntPtr previousValue,
        IntPtr returnSize);

    [DllImport("kernel32.dll")]
    private static extern void DeleteProcThreadAttributeList(IntPtr attributeList);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern SafeFileHandle CreateJobObjectW(IntPtr jobAttributes, string? name);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetInformationJobObject(
        SafeFileHandle job,
        int informationClass,
        IntPtr information,
        uint informationLength);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool AssignProcessToJobObject(
        SafeFileHandle job,
        SafeFileHandle process);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint ResumeThread(SafeFileHandle thread);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool TerminateProcess(SafeFileHandle process, uint exitCode);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint WaitForSingleObject(SafeFileHandle handle, uint milliseconds);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetExitCodeProcess(SafeFileHandle process, out uint exitCode);

    private static readonly Regex[] SecretPatterns =
    {
        new(@"-----BEGIN\s+(?:RSA |EC |OPENSSH )?PRIVATE KEY-----[\s\S]*?-----END\s+(?:RSA |EC |OPENSSH )?PRIVATE KEY-----", RegexOptions.IgnoreCase),
        new(@"\b(?:gh[oprsu]_[A-Za-z0-9]{20,}|glpat-[A-Za-z0-9_-]{16,}|xox[baprs]-[A-Za-z0-9-]{12,}|AKIA[0-9A-Z]{16})\b", RegexOptions.IgnoreCase),
        new(@"\beyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b", RegexOptions.IgnoreCase),
        new(@"\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b", RegexOptions.IgnoreCase),
        new(@"\b[A-Za-z0-9.-]+\.onmicrosoft\.com\b", RegexOptions.IgnoreCase),
        new(@"\b(?:TENANT(?:_ID)?|MANDANT(?:ENKENNUNG)?|PRIVATE_KEY|SIGNING_KEY|ACCESS_KEY|API_KEY|CLIENT_SECRET|CREDENTIALS?|DATABASE_URL|CONNECTION_STRING|PASSWORD|PASSWD|TOKEN|SECRET|AUTH(?:ORIZATION)?|SESSION|COOKIE)\s*[=:]\s*[^\s]+", RegexOptions.IgnoreCase),
        new(@"\b[a-z][a-z0-9+.-]*://[^/\s:@]+:[^@\s]+@", RegexOptions.IgnoreCase),
    };

    public static async Task<int> Main(string[] args)
    {
        if (args.Length != 2)
        {
            Console.Error.WriteLine("Anforderungs- und Ergebnisdatei sind erforderlich.");
            return 2;
        }

        try
        {
            if (!OperatingSystem.IsWindows())
                throw new PlatformNotSupportedException("Der sichere Prozesshelfer benoetigt Windows-Jobobjekte.");

            var requestInfo = new FileInfo(args[0]);
            if (!requestInfo.Exists || requestInfo.Length > 1_048_576)
                throw new InvalidOperationException("Prozessanforderung fehlt oder ist zu gross.");
            await using var requestStream = new FileStream(
                requestInfo.FullName,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                4096,
                FileOptions.Asynchronous);
            if (requestStream.Length > 1_048_576)
                throw new InvalidOperationException("Prozessanforderung ist zu gross.");
            var request = await JsonSerializer.DeserializeAsync<ProcessRequest>(requestStream)
                ?? throw new InvalidOperationException("Leere Prozessanforderung.");
            Validate(request);
            await using var resultStream = new FileStream(
                Path.GetFullPath(args[1]),
                FileMode.CreateNew,
                FileAccess.Write,
                FileShare.None,
                4096,
                FileOptions.Asynchronous);

            var result = await RunWindowsProcessAsync(request);
            await JsonSerializer.SerializeAsync(resultStream, result);
            await resultStream.FlushAsync();
            resultStream.Flush(flushToDisk: true);
            return 0;
        }
        catch (Exception error)
        {
            Console.Error.WriteLine($"Prozesshelfer fehlgeschlagen: {error.Message}");
            return 3;
        }
    }

    private static async Task<ProcessResult> RunWindowsProcessAsync(ProcessRequest request)
    {
        using var process = StartWindowsProcess(request);
        using var outputCancellation = new CancellationTokenSource();
        using var stdoutReader = new StreamReader(process.StandardOutput, new UTF8Encoding(false), true, 4096, leaveOpen: true);
        using var stderrReader = new StreamReader(process.StandardError, new UTF8Encoding(false), true, 4096, leaveOpen: true);
        var stdoutTask = ReadBoundedAsync(stdoutReader, request.MaximumOutputCharacters, outputCancellation.Token);
        var stderrTask = ReadBoundedAsync(stderrReader, request.MaximumOutputCharacters, outputCancellation.Token);
        var waitTask = WaitForExitAsync(process.ProcessHandle);
        var completed = await Task.WhenAny(waitTask, Task.Delay(request.TimeoutMilliseconds));
        var timedOut = completed != waitTask;
        var exitCode = 124;

        if (!timedOut)
        {
            await waitTask;
            exitCode = GetProcessExitCode(process.ProcessHandle);
            process.CloseJob();
        }
        else
        {
            process.CloseJob();
            if (await Task.WhenAny(waitTask, Task.Delay(5_000)) != waitTask)
            {
                try { TerminateProcess(process.ProcessHandle, 124); } catch { }
                if (await Task.WhenAny(waitTask, Task.Delay(2_000)) != waitTask)
                    throw new InvalidOperationException("Der Prozessbaum konnte nach dem Zeitlimit nicht beendet werden.");
            }
            await waitTask;
        }

        var drainTask = Task.WhenAll(stdoutTask, stderrTask);
        if (await Task.WhenAny(drainTask, Task.Delay(5_000)) != drainTask)
        {
            timedOut = true;
            process.CloseJob();
            outputCancellation.Cancel();
            stdoutReader.Dispose();
            stderrReader.Dispose();
            if (await Task.WhenAny(drainTask, Task.Delay(2_000)) != drainTask)
            {
                return new ProcessResult
                {
                    ExitCode = 124,
                    TimedOut = true,
                    OutputTruncated = true,
                    StandardOutput = "<AUSGABE WEGEN OFFENER KINDPROZESS-PIPE GEKUERZT>",
                    StandardError = "",
                };
            }
        }

        var stdout = await stdoutTask;
        var stderr = await stderrTask;
        return new ProcessResult
        {
            ExitCode = timedOut ? 124 : exitCode,
            TimedOut = timedOut,
            OutputTruncated = stdout.Truncated || stderr.Truncated,
            StandardOutput = Redact(stdout.Text, request.SensitiveRoots),
            StandardError = Redact(stderr.Text, request.SensitiveRoots),
        };
    }

    private static WindowsProcess StartWindowsProcess(ProcessRequest request)
    {
        SafeFileHandle? jobHandle = null;
        SafeFileHandle? processHandle = null;
        SafeFileHandle? threadHandle = null;
        SafeFileHandle? standardInputRead = null;
        SafeFileHandle? standardInputWrite = null;
        SafeFileHandle? standardOutputRead = null;
        SafeFileHandle? standardOutputWrite = null;
        SafeFileHandle? standardErrorRead = null;
        SafeFileHandle? standardErrorWrite = null;
        FileStream? outputStream = null;
        FileStream? errorStream = null;
        IntPtr jobInformation = IntPtr.Zero;
        IntPtr environment = IntPtr.Zero;
        IntPtr attributeList = IntPtr.Zero;
        IntPtr inheritedHandles = IntPtr.Zero;
        var attributeListInitialized = false;
        var processCreated = false;
        var assignedToJob = false;
        var success = false;

        try
        {
            jobHandle = CreateJobObjectW(IntPtr.Zero, null);
            if (jobHandle.IsInvalid)
                throw NewWin32Exception("Das Prozess-Jobobjekt konnte nicht erstellt werden.");
            var limits = new JobObjectExtendedLimitInformation();
            limits.BasicLimitInformation.LimitFlags = JobObjectLimitKillOnJobClose;
            var limitSize = Marshal.SizeOf<JobObjectExtendedLimitInformation>();
            jobInformation = Marshal.AllocHGlobal(limitSize);
            Marshal.StructureToPtr(limits, jobInformation, false);
            if (!SetInformationJobObject(jobHandle, JobObjectExtendedLimitInformationClass, jobInformation, checked((uint)limitSize)))
                throw NewWin32Exception("Das Prozess-Jobobjekt konnte nicht fail-closed konfiguriert werden.");

            var pipeAttributes = new SecurityAttributes
            {
                Length = Marshal.SizeOf<SecurityAttributes>(),
                InheritHandle = true,
            };
            CreateInheritedPipe(out standardInputRead, out standardInputWrite, ref pipeAttributes, "Standardeingabe");
            CreateInheritedPipe(out standardOutputRead, out standardOutputWrite, ref pipeAttributes, "Standardausgabe");
            CreateInheritedPipe(out standardErrorRead, out standardErrorWrite, ref pipeAttributes, "Standardfehlerausgabe");
            MakeNonInheritable(standardInputWrite, "Standardeingabe-Schreibhandle");
            MakeNonInheritable(standardOutputRead, "Standardausgabe-Lesehandle");
            MakeNonInheritable(standardErrorRead, "Standardfehler-Lesehandle");

            var attributeListSize = IntPtr.Zero;
            _ = InitializeProcThreadAttributeList(IntPtr.Zero, 1, 0, ref attributeListSize);
            var sizeError = Marshal.GetLastWin32Error();
            if (attributeListSize == IntPtr.Zero || sizeError != ErrorInsufficientBuffer)
                throw new Win32Exception(sizeError, "Die explizite Handle-Liste konnte nicht vorbereitet werden.");
            attributeList = Marshal.AllocHGlobal(attributeListSize);
            if (!InitializeProcThreadAttributeList(attributeList, 1, 0, ref attributeListSize))
                throw NewWin32Exception("Die explizite Handle-Liste konnte nicht initialisiert werden.");
            attributeListInitialized = true;
            inheritedHandles = Marshal.AllocHGlobal(3 * IntPtr.Size);
            Marshal.WriteIntPtr(inheritedHandles, 0 * IntPtr.Size, standardInputRead.DangerousGetHandle());
            Marshal.WriteIntPtr(inheritedHandles, 1 * IntPtr.Size, standardOutputWrite.DangerousGetHandle());
            Marshal.WriteIntPtr(inheritedHandles, 2 * IntPtr.Size, standardErrorWrite.DangerousGetHandle());
            if (!UpdateProcThreadAttribute(
                    attributeList,
                    0,
                    new IntPtr(unchecked((long)ProcThreadAttributeHandleList)),
                    inheritedHandles,
                    new IntPtr(3 * IntPtr.Size),
                    IntPtr.Zero,
                    IntPtr.Zero))
                throw NewWin32Exception("Die vererbbaren Prozesshandles konnten nicht eingeschraenkt werden.");

            var startupInfo = new StartupInfoEx
            {
                StartupInfo = new StartupInfo
                {
                    Size = Marshal.SizeOf<StartupInfoEx>(),
                    Flags = StartfUseStdHandles,
                    StandardInput = standardInputRead.DangerousGetHandle(),
                    StandardOutput = standardOutputWrite.DangerousGetHandle(),
                    StandardError = standardErrorWrite.DangerousGetHandle(),
                },
                AttributeList = attributeList,
            };
            environment = Marshal.StringToHGlobalUni(CreateEnvironmentBlock(request.Environment));
            var commandLine = new StringBuilder(CreateCommandLine(request.FilePath, request.Arguments));
            var creationFlags = CreateSuspended | CreateUnicodeEnvironment | ExtendedStartupInfoPresent | CreateNoWindow;
            if (!CreateProcessW(
                    request.FilePath,
                    commandLine,
                    IntPtr.Zero,
                    IntPtr.Zero,
                    true,
                    creationFlags,
                    environment,
                    request.WorkingDirectory,
                    ref startupInfo,
                    out var processInformation))
                throw NewWin32Exception("Der Zielprozess konnte nicht angehalten erzeugt werden.");

            processCreated = true;
            processHandle = new SafeFileHandle(processInformation.Process, ownsHandle: true);
            threadHandle = new SafeFileHandle(processInformation.Thread, ownsHandle: true);
            standardInputRead.Dispose();
            standardInputRead = null;
            standardInputWrite.Dispose();
            standardInputWrite = null;
            standardOutputWrite.Dispose();
            standardOutputWrite = null;
            standardErrorWrite.Dispose();
            standardErrorWrite = null;

            if (!AssignProcessToJobObject(jobHandle, processHandle))
                throw NewWin32Exception("Der angehaltene Zielprozess konnte dem Jobobjekt nicht zugewiesen werden.");
            assignedToJob = true;
            if (ResumeThread(threadHandle) == uint.MaxValue)
                throw NewWin32Exception("Der zugewiesene Zielprozess konnte nicht fortgesetzt werden.");
            threadHandle.Dispose();
            threadHandle = null;

            outputStream = new FileStream(standardOutputRead, FileAccess.Read, 4096, isAsync: false);
            standardOutputRead = null;
            errorStream = new FileStream(standardErrorRead, FileAccess.Read, 4096, isAsync: false);
            standardErrorRead = null;
            var result = new WindowsProcess(jobHandle, processHandle, outputStream, errorStream);
            outputStream = null;
            errorStream = null;
            jobHandle = null;
            processHandle = null;
            success = true;
            return result;
        }
        finally
        {
            if (!success && processCreated && processHandle is { IsInvalid: false, IsClosed: false })
            {
                if (assignedToJob)
                    jobHandle?.Dispose();
                else
                    _ = TerminateProcess(processHandle, 125);
                _ = WaitForSingleObject(processHandle, 5_000);
            }
            threadHandle?.Dispose();
            processHandle?.Dispose();
            jobHandle?.Dispose();
            standardInputRead?.Dispose();
            standardInputWrite?.Dispose();
            standardOutputRead?.Dispose();
            standardOutputWrite?.Dispose();
            standardErrorRead?.Dispose();
            standardErrorWrite?.Dispose();
            outputStream?.Dispose();
            errorStream?.Dispose();
            if (attributeListInitialized) DeleteProcThreadAttributeList(attributeList);
            if (attributeList != IntPtr.Zero) Marshal.FreeHGlobal(attributeList);
            if (inheritedHandles != IntPtr.Zero) Marshal.FreeHGlobal(inheritedHandles);
            if (environment != IntPtr.Zero) Marshal.FreeHGlobal(environment);
            if (jobInformation != IntPtr.Zero) Marshal.FreeHGlobal(jobInformation);
        }
    }

    private static void CreateInheritedPipe(
        out SafeFileHandle readPipe,
        out SafeFileHandle writePipe,
        ref SecurityAttributes attributes,
        string description)
    {
        if (!CreatePipe(out readPipe, out writePipe, ref attributes, 0))
            throw NewWin32Exception($"Die Pipe fuer {description} konnte nicht erstellt werden.");
    }

    private static void MakeNonInheritable(SafeFileHandle handle, string description)
    {
        if (!SetHandleInformation(handle, HandleFlagInherit, 0))
            throw NewWin32Exception($"{description} konnte nicht gegen Vererbung gesperrt werden.");
    }

    private static string CreateCommandLine(string filePath, IEnumerable<string> arguments)
    {
        return string.Join(" ", new[] { filePath }.Concat(arguments).Select(QuoteWindowsArgument));
    }

    private static string QuoteWindowsArgument(string argument)
    {
        var quoted = new StringBuilder(argument.Length + 2);
        quoted.Append('"');
        var backslashes = 0;
        foreach (var character in argument)
        {
            if (character == '\\')
            {
                backslashes++;
                continue;
            }
            if (character == '"')
            {
                quoted.Append('\\', backslashes * 2 + 1);
                quoted.Append('"');
                backslashes = 0;
                continue;
            }
            quoted.Append('\\', backslashes);
            backslashes = 0;
            quoted.Append(character);
        }
        quoted.Append('\\', backslashes * 2);
        quoted.Append('"');
        return quoted.ToString();
    }

    private static string CreateEnvironmentBlock(IReadOnlyDictionary<string, string> environment)
    {
        var entries = environment
            .OrderBy(pair => pair.Key, StringComparer.OrdinalIgnoreCase)
            .Select(pair => $"{pair.Key}={pair.Value}");
        return string.Join('\0', entries) + '\0';
    }

    private static Task WaitForExitAsync(SafeFileHandle process)
    {
        return Task.Run(() =>
        {
            var waitResult = WaitForSingleObject(process, Infinite);
            if (waitResult == WaitObject0) return;
            var error = waitResult == WaitFailed ? Marshal.GetLastWin32Error() : unchecked((int)waitResult);
            throw new Win32Exception(error, "Das Warten auf den Zielprozess ist fehlgeschlagen.");
        });
    }

    private static int GetProcessExitCode(SafeFileHandle process)
    {
        if (!GetExitCodeProcess(process, out var exitCode))
            throw NewWin32Exception("Der Rueckgabecode des Zielprozesses konnte nicht gelesen werden.");
        return unchecked((int)exitCode);
    }

    private static Win32Exception NewWin32Exception(string message)
    {
        return new Win32Exception(Marshal.GetLastWin32Error(), message);
    }

    private static void Validate(ProcessRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.FilePath) || !Path.IsPathFullyQualified(request.FilePath))
            throw new InvalidOperationException("Der auszufuehrende Pfad muss absolut sein.");
        if (string.IsNullOrWhiteSpace(request.WorkingDirectory) || !Path.IsPathFullyQualified(request.WorkingDirectory))
            throw new InvalidOperationException("Das Arbeitsverzeichnis muss absolut sein.");
        if (request.TimeoutMilliseconds is < 1 or > 3_600_000)
            throw new InvalidOperationException("Das Zeitlimit ist ungueltig.");
        if (request.MaximumOutputCharacters is < 1024 or > 1_048_576)
            throw new InvalidOperationException("Die Ausgabegrenze ist ungueltig.");
        if (request.Arguments is null || request.Arguments.Any(argument => argument is null || argument.IndexOf('\0') >= 0))
            throw new InvalidOperationException("Ein Prozessargument ist ungueltig.");
        if (request.Environment is null)
            throw new InvalidOperationException("Die Prozessumgebung fehlt.");
        foreach (var pair in request.Environment)
        {
            if (string.IsNullOrEmpty(pair.Key) || pair.Key.IndexOfAny(new[] { '=', '\0' }) >= 0 || pair.Value is null || pair.Value.IndexOf('\0') >= 0)
                throw new InvalidOperationException("Eine Prozessumgebungsvariable ist ungueltig.");
        }
        if (request.SensitiveRoots is null)
            throw new InvalidOperationException("Die Liste vertraulicher Pfade fehlt.");
    }

    private static async Task<(string Text, bool Truncated)> ReadBoundedAsync(StreamReader reader, int maximum, CancellationToken cancellationToken)
    {
        var builder = new StringBuilder(Math.Min(maximum, 16_384));
        var buffer = new char[4096];
        var truncated = false;
        try
        {
            while (true)
            {
                var read = await reader.ReadAsync(buffer.AsMemory(0, buffer.Length), cancellationToken);
                if (read == 0) break;
                var remaining = maximum - builder.Length;
                if (remaining > 0) builder.Append(buffer, 0, Math.Min(read, remaining));
                if (read > remaining) truncated = true;
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { truncated = true; }
        catch (ObjectDisposedException) when (cancellationToken.IsCancellationRequested) { truncated = true; }
        catch (IOException) when (cancellationToken.IsCancellationRequested) { truncated = true; }
        if (truncated) builder.Append("\n<AUSGABE GEKUERZT>");
        return (builder.ToString(), truncated);
    }

    private static string Redact(string value, IEnumerable<string> roots)
    {
        foreach (var root in roots.Where(root => !string.IsNullOrWhiteSpace(root)))
        {
            value = value.Replace(root, "<PFAD>", StringComparison.OrdinalIgnoreCase)
                .Replace(root.Replace('\\', '/'), "<PFAD>", StringComparison.OrdinalIgnoreCase);
        }
        foreach (var pattern in SecretPatterns) value = pattern.Replace(value, "<GEHEIMNIS>");
        return value;
    }
}
