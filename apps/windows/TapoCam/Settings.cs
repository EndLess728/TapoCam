using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace TapoCam;

/// Connection details. Stored in %APPDATA%\TapoCam\settings.json, passwords encrypted with DPAPI (current user).
public sealed record CameraSettings
{
    public string Host { get; init; } = "";
    /// "Camera Account" created in the Tapo app (Advanced Settings → Camera Account). Used for RTSP video.
    public string StreamUser { get; init; } = "";
    public string StreamPassword { get; init; } = "";
    /// Tapo cloud account password. Used (with user "admin") for pan/tilt and settings.
    public string CloudPassword { get; init; } = "";
    public bool HighQuality { get; init; } = true;
    public int PanStep { get; init; } = 15;

    public bool IsConfigured => Host != "" && StreamUser != "" && StreamPassword != "";

    public string RtspUrl(bool? high = null) =>
        $"rtsp://{Uri.EscapeDataString(StreamUser)}:{Uri.EscapeDataString(StreamPassword)}@{Host}:554/" +
        ((high ?? HighQuality) ? "stream1" : "stream2");

    private static string FilePath => Path.Combine(Tools.SupportDir, "settings.json");

    private sealed record Stored(string Host, string StreamUser, string StreamPassword, string CloudPassword,
                                 bool HighQuality, int PanStep);

    public static CameraSettings Load()
    {
        try
        {
            var s = JsonSerializer.Deserialize<Stored>(File.ReadAllText(FilePath));
            if (s == null) return new();
            return new()
            {
                Host = s.Host ?? "",
                StreamUser = s.StreamUser ?? "",
                StreamPassword = Unprotect(s.StreamPassword),
                CloudPassword = Unprotect(s.CloudPassword),
                HighQuality = s.HighQuality,
                PanStep = s.PanStep is >= 5 and <= 45 ? s.PanStep : 15,
            };
        }
        catch
        {
            return new();
        }
    }

    public void Save()
    {
        var s = new Stored(Host, StreamUser, Protect(StreamPassword), Protect(CloudPassword), HighQuality, PanStep);
        File.WriteAllText(FilePath, JsonSerializer.Serialize(s, new JsonSerializerOptions { WriteIndented = true }));
    }

    private static string Protect(string value) => value == "" ? "" :
        Convert.ToBase64String(ProtectedData.Protect(Encoding.UTF8.GetBytes(value), null, DataProtectionScope.CurrentUser));

    private static string Unprotect(string? value)
    {
        if (string.IsNullOrEmpty(value)) return "";
        try
        {
            return Encoding.UTF8.GetString(ProtectedData.Unprotect(Convert.FromBase64String(value), null, DataProtectionScope.CurrentUser));
        }
        catch
        {
            return "";
        }
    }
}

public static class Tools
{
    public static string AppDir => AppContext.BaseDirectory;

    /// Bundled copy first (CI ships ffmpeg\ffmpeg.exe and python\python.exe next to TapoCam.exe), then PATH.
    public static string? Find(string name)
    {
        foreach (var local in new[] { Path.Combine(AppDir, name, name + ".exe"), Path.Combine(AppDir, name + ".exe") })
            if (File.Exists(local)) return local;
        return FindOnPath(name);
    }

    public static string? FindOnPath(string name)
    {
        foreach (var dir in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator))
        {
            // Skip the Microsoft Store "python.exe" stub, which only opens the Store.
            if (dir == "" || dir.Contains("WindowsApps", StringComparison.OrdinalIgnoreCase)) continue;
            var path = Path.Combine(dir.Trim('"'), name + ".exe");
            if (File.Exists(path)) return path;
        }
        return null;
    }

    public static string SupportDir => Dir(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData));

    public static string OutputDir(Environment.SpecialFolder folder) => Dir(Environment.GetFolderPath(folder));

    private static string Dir(string parent)
    {
        var path = Path.Combine(parent, "TapoCam");
        Directory.CreateDirectory(path);
        return path;
    }

    public static string Timestamp => DateTime.Now.ToString("yyyy-MM-dd 'at' HH.mm.ss");

    public static ProcessStartInfo StartInfo(string exe, IEnumerable<string> args, bool stdin = false, bool stdout = false, bool stderr = false)
    {
        var psi = new ProcessStartInfo(exe)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardInput = stdin,
            RedirectStandardOutput = stdout,
            RedirectStandardError = stderr,
        };
        foreach (var a in args) psi.ArgumentList.Add(a);
        return psi;
    }

    public static void RevealInExplorer(string file)
    {
        try { Process.Start("explorer.exe", $"/select,\"{file}\""); } catch { }
    }
}

/// Puts child processes (ffmpeg, python) in a job object so Windows kills them if TapoCam exits or crashes.
public static class ChildProcesses
{
    private static readonly IntPtr Job = CreateJob();

    public static void Track(Process p)
    {
        if (Job != IntPtr.Zero)
        {
            try { AssignProcessToJobObject(Job, p.Handle); } catch { }
        }
    }

    public static void Kill(Process? p)
    {
        if (p == null) return;
        try { if (!p.HasExited) p.Kill(entireProcessTree: true); } catch { }
    }

    private static IntPtr CreateJob()
    {
        if (!OperatingSystem.IsWindows()) return IntPtr.Zero;
        var job = CreateJobObject(IntPtr.Zero, null);
        var info = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
        info.BasicLimitInformation.LimitFlags = 0x2000; // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
        var size = Marshal.SizeOf(info);
        var ptr = Marshal.AllocHGlobal(size);
        try
        {
            Marshal.StructureToPtr(info, ptr, false);
            SetInformationJobObject(job, 9 /* JobObjectExtendedLimitInformation */, ptr, (uint)size);
        }
        finally
        {
            Marshal.FreeHGlobal(ptr);
        }
        return job;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr CreateJobObject(IntPtr attributes, string? name);

    [DllImport("kernel32.dll")]
    private static extern bool SetInformationJobObject(IntPtr job, int infoClass, IntPtr info, uint length);

    [DllImport("kernel32.dll")]
    private static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);

    [StructLayout(LayoutKind.Sequential)]
    private struct JOBOBJECT_BASIC_LIMIT_INFORMATION
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
    private struct IO_COUNTERS
    {
        public ulong ReadOperationCount, WriteOperationCount, OtherOperationCount;
        public ulong ReadTransferCount, WriteTransferCount, OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION
    {
        public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
        public IO_COUNTERS IoInfo;
        public UIntPtr ProcessMemoryLimit;
        public UIntPtr JobMemoryLimit;
        public UIntPtr PeakProcessMemoryUsed;
        public UIntPtr PeakJobMemoryUsed;
    }
}
