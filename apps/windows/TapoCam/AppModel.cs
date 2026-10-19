using System.Windows.Threading;

namespace TapoCam;

public sealed class AppModel : ObservableObject
{
    public StreamPlayer Player { get; } = new();
    public TapoControl Control { get; } = new();
    public Recorder Recorder { get; } = new();

    private CameraSettings settings = CameraSettings.Load();
    public CameraSettings Settings { get => settings; private set => Set(ref settings, value); }

    private string? toast;
    public string? Toast { get => toast; private set => Set(ref toast, value); }

    /// Raised when the settings dialog should open (first launch, or nothing configured).
    public event Action? SettingsRequested;

    public void Start()
    {
        if (Settings.IsConfigured) Reconnect();
        else SettingsRequested?.Invoke();
    }

    public void Apply(CameraSettings s)
    {
        Settings = s;
        Settings.Save();
        Reconnect();
    }

    public void Reconnect()
    {
        if (!Settings.IsConfigured) { SettingsRequested?.Invoke(); return; }
        Player.Play(Settings.RtspUrl());
        _ = Control.Connect(Settings);
    }

    public void SetQuality(bool high)
    {
        if (Settings.HighQuality == high) return;
        Settings = Settings with { HighQuality = high };
        Settings.Save();
        if (Settings.IsConfigured) Player.Play(Settings.RtspUrl());
    }

    public void SetPanStep(int step)
    {
        if (Settings.PanStep == step) return;
        Settings = Settings with { PanStep = step };
        Settings.Save();
    }

    public void Snapshot()
    {
        if (Player.Frame is not { } frame || TapoCam.Snapshot.Save(frame) is not { } path) { Show("No picture to save yet"); return; }
        Show($"Saved to Pictures\\TapoCam\\{Path.GetFileName(path)}");
    }

    public void ToggleRecording()
    {
        if (Recorder.IsRecording) { Recorder.Stop(); Show("Recording saved to Videos\\TapoCam"); }
        else if (!Settings.IsConfigured) SettingsRequested?.Invoke();
        else if (Recorder.Start(Settings.RtspUrl(high: true)) is { } err) Show(err);
    }

    public async void Show(string message)
    {
        Toast = message;
        await Task.Delay(3000);
        if (Toast == message) Toast = null;
    }

    public void Shutdown()
    {
        Recorder.StopAndWait();
        Player.Stop();
        Control.Disconnect();
    }
}
