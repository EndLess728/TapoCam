using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Windows.Threading;

namespace TapoCam;

public sealed record Preset(string Id, string Name);

public sealed record CameraStatus
{
    public bool? Privacy { get; init; }
    public bool? Led { get; init; }
    public string? DayNight { get; init; }
    public bool? Motion { get; init; }
    public bool? Flip { get; init; }
    public List<Preset>? Presets { get; init; }
    public string? Model { get; init; }
    public string? Name { get; init; }
    public string? Firmware { get; init; }
}

public enum ControlState { Disconnected, Installing, Connecting, Connected, Failed }

/// Talks to the camera's local Tapo API through a long-lived Python helper (pytapo).
public sealed class TapoControl : ObservableObject
{
    private static readonly JsonSerializerOptions Json = new() { PropertyNameCaseInsensitive = true };

    private readonly Dispatcher dispatcher = Dispatcher.CurrentDispatcher;
    private Process? process;
    private StreamWriter? stdin;
    private int nextId = 1;
    private readonly Dictionary<int, TaskCompletionSource<JsonNode?>> pending = [];

    private ControlState state;
    public ControlState State { get => state; private set { if (Set(ref state, value)) Raise(nameof(IsConnected)); } }
    public bool IsConnected => State == ControlState.Connected;

    private string failure = "";
    public string Failure { get => failure; private set => Set(ref failure, value); }

    private CameraStatus status = new();
    public CameraStatus Status { get => status; set => Set(ref status, value); }

    private string? lastError;
    public string? LastError { get => lastError; private set => Set(ref lastError, value); }

    private static string Venv => Path.Combine(Tools.SupportDir, "venv");
    private static string VenvPython => Path.Combine(Venv, "Scripts", "python.exe");
    /// CI bundles an embedded Python with pytapo preinstalled, so most users never need their own.
    private static string BundledPython => Path.Combine(Tools.AppDir, "python", "python.exe");
    private static string HelperScript => Path.Combine(Tools.AppDir, "tapo_helper.py");

    public async Task Connect(CameraSettings s)
    {
        Disconnect();
        if (s.CloudPassword == "")
        {
            Fail("Add your Tapo account password in Settings to enable pan/tilt and camera controls.");
            return;
        }
        try
        {
            var python = await EnsureRuntime();
            State = ControlState.Connecting;
            LaunchHelper(python);
            var raw = await Call("connect", new() { ["host"] = s.Host, ["user"] = "admin", ["password"] = s.CloudPassword, ["cloudPassword"] = s.CloudPassword });
            Status = Decode<CameraStatus>(raw) ?? new();
            State = ControlState.Connected;
        }
        catch (Exception e)
        {
            Fail(e.Message);
            Disconnect(keepState: true);
        }
    }

    public void Disconnect(bool keepState = false)
    {
        ChildProcesses.Kill(process);
        process = null;
        stdin = null;
        foreach (var c in pending.Values) c.TrySetException(new HelperException("disconnected"));
        pending.Clear();
        if (!keepState) State = ControlState.Disconnected;
    }

    private void Fail(string message)
    {
        Failure = message;
        State = ControlState.Failed;
    }

    // Commands

    public void Move(int x, int y) => Fire("move", new() { ["x"] = x, ["y"] = y });
    public void Calibrate() => Fire("calibrate");
    public void GotoPreset(Preset p) => Fire("presetGoto", new() { ["id"] = p.Id });
    public void Reboot() => Fire("reboot");

    public async void SavePreset(string name)
    {
        if (await Run("presetSave", new() { ["name"] = name }) is { } raw && Decode<List<Preset>>(raw) is { } list)
            Status = Status with { Presets = list };
    }

    public async void DeletePreset(Preset p)
    {
        if (await Run("presetDelete", new() { ["id"] = p.Id }) is { } raw && Decode<List<Preset>>(raw) is { } list)
            Status = Status with { Presets = list };
    }

    public void SetPrivacy(bool on) { Status = Status with { Privacy = on }; Fire("privacy", new() { ["on"] = on }); }
    public void SetLed(bool on) { Status = Status with { Led = on }; Fire("led", new() { ["on"] = on }); }
    public void SetMotion(bool on) { Status = Status with { Motion = on }; Fire("motion", new() { ["on"] = on }); }
    public void SetFlip(bool on) { Status = Status with { Flip = on }; Fire("flip", new() { ["on"] = on }); }
    public void SetDayNight(string mode) { Status = Status with { DayNight = mode }; Fire("dayNight", new() { ["mode"] = mode }); }
    public void SetAlarm(bool on) => Fire("alarm", new() { ["on"] = on });

    public async void Refresh()
    {
        if (await Run("status") is { } raw && Decode<CameraStatus>(raw) is { } s) Status = s;
    }

    private async void Fire(string cmd, JsonObject? args = null) => await Run(cmd, args);

    private async Task<JsonNode?> Run(string cmd, JsonObject? args = null)
    {
        if (State != ControlState.Connected) return null;
        try
        {
            var r = await Call(cmd, args ?? []);
            LastError = null;
            return r;
        }
        catch (Exception e)
        {
            LastError = $"{cmd}: {e.Message}";
            return null;
        }
    }

    // Python runtime

    private async Task<string> EnsureRuntime()
    {
        if (File.Exists(BundledPython)) return BundledPython;
        if (File.Exists(VenvPython) && await Succeeds(VenvPython, "-c", "import pytapo")) return VenvPython;
        State = ControlState.Installing;
        if (!File.Exists(VenvPython))
        {
            // Prefer the py launcher: it finds real installs even when PATH only has the Store stub.
            if (Tools.FindOnPath("py") is { } py) await Shell(py, "-3", "-m", "venv", Venv);
            else if (Tools.FindOnPath("python") is { } python) await Shell(python, "-m", "venv", Venv);
            else throw new HelperException("Python not found. Install it from python.org (tick \"Add to PATH\"), then click Retry.");
        }
        await Shell(VenvPython, "-m", "pip", "install", "--quiet", "--disable-pip-version-check", "pytapo");
        return VenvPython;
    }

    private static async Task<bool> Succeeds(string exe, params string[] args)
    {
        try
        {
            await Shell(exe, args);
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static async Task<string> Shell(string exe, params string[] args)
    {
        using var p = new Process { StartInfo = Tools.StartInfo(exe, args, stdout: true, stderr: true) };
        p.Start();
        ChildProcesses.Track(p);
        var stdout = p.StandardOutput.ReadToEndAsync();
        var stderr = p.StandardError.ReadToEndAsync();
        await p.WaitForExitAsync();
        var text = await stdout + await stderr;
        if (p.ExitCode == 0) return text;
        var tail = text.Length > 300 ? text[^300..] : text;
        throw new HelperException($"{Path.GetFileName(exe)} failed: {tail.Trim()}");
    }

    private void LaunchHelper(string python)
    {
        if (!File.Exists(HelperScript)) throw new HelperException("tapo_helper.py is missing from the TapoCam folder");
        var psi = Tools.StartInfo(python, ["-u", HelperScript], stdin: true, stdout: true);
        psi.Environment["PYTHONIOENCODING"] = "utf-8";
        psi.StandardOutputEncoding = new System.Text.UTF8Encoding(false);
        psi.StandardInputEncoding = new System.Text.UTF8Encoding(false);
        var p = new Process { StartInfo = psi };
        p.Start();
        ChildProcesses.Track(p);
        process = p;
        stdin = p.StandardInput;
        stdin.AutoFlush = true;
        Task.Run(async () =>
        {
            string? line;
            while ((line = await p.StandardOutput.ReadLineAsync()) != null)
            {
                var l = line;
                _ = dispatcher.BeginInvoke(() => Receive(l));
            }
            _ = dispatcher.BeginInvoke(() =>
            {
                if (process != p) return;
                var wasConnected = State == ControlState.Connected;
                Disconnect(keepState: true);
                if (wasConnected) Fail("Control helper stopped. Click Reconnect.");
            });
        });
    }

    private void Receive(string line)
    {
        JsonObject? obj;
        try { obj = JsonNode.Parse(line) as JsonObject; } catch { return; }
        if (obj?["id"]?.GetValueKind() != JsonValueKind.Number) return;
        var id = obj["id"]!.GetValue<int>();
        if (!pending.Remove(id, out var tcs)) return;
        if (obj["ok"]?.GetValueKind() == JsonValueKind.True)
            tcs.TrySetResult(obj["result"]?.DeepClone());
        else
            tcs.TrySetException(new HelperException(Friendly(obj["error"]?.ToString() ?? "unknown error")));
    }

    private Task<JsonNode?> Call(string cmd, JsonObject args)
    {
        if (stdin == null) throw new HelperException("not connected");
        var id = nextId++;
        var tcs = new TaskCompletionSource<JsonNode?>();
        pending[id] = tcs;
        stdin.WriteLine(new JsonObject { ["id"] = id, ["cmd"] = cmd, ["args"] = args }.ToJsonString());
        return tcs.Task;
    }

    private static T? Decode<T>(JsonNode? raw)
    {
        try { return raw == null ? default : raw.Deserialize<T>(Json); } catch { return default; }
    }

    private static string Friendly(string e)
    {
        var l = e.ToLowerInvariant();
        if (l.Contains("invalid authentication") || l.Contains("-40401") || l.Contains("password"))
            return "Tapo rejected the login. Use your Tapo app account password (not the camera account).";
        if (l.Contains("temporary suspension") || l.Contains("-40404"))
            return "Too many failed logins. The camera has locked logins for ~30 minutes.";
        return e;
    }
}

public sealed class HelperException(string message) : Exception(message);
