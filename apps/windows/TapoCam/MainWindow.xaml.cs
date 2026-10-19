using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;

namespace TapoCam;

public partial class MainWindow : Window
{
    private readonly AppModel model = new();
    private readonly DispatcherTimer recordingTimer = new() { Interval = TimeSpan.FromMilliseconds(500) };
    private bool sirenOn;

    public MainWindow()
    {
        InitializeComponent();
        DataContext = model;

        model.PropertyChanged += (_, _) => Refresh();
        model.Player.PropertyChanged += (_, e) => { if (e.PropertyName != nameof(StreamPlayer.Frame)) Refresh(); };
        model.Control.PropertyChanged += (_, _) => Refresh();
        model.Recorder.PropertyChanged += (_, _) => Refresh();
        model.SettingsRequested += () => Dispatcher.BeginInvoke(ShowSettings);
        recordingTimer.Tick += (_, _) => UpdateRecordingTime();

        SourceInitialized += (_, _) => App.UseDarkTitleBar(this);
        Loaded += (_, _) =>
        {
            VideoPane.Focus();
            Refresh();
            model.Start();
        };
        PreviewKeyDown += OnPreviewKeyDown;
    }

    protected override void OnClosing(CancelEventArgs e)
    {
        model.Shutdown();
        base.OnClosing(e);
    }

    // State → UI

    private void Refresh()
    {
        var player = model.Player;
        var control = model.Control;
        var status = control.Status;
        var settings = model.Settings;

        var name = status.Name ?? status.Model ?? "Camera";
        (StatusDot.Fill, StatusText.Text) = player.State switch
        {
            PlayState.Playing => ((Brush)Brushes.LimeGreen, $"{name} · {player.Fps} fps"),
            PlayState.Connecting => (Brushes.Gold, "Connecting…"),
            PlayState.Failed => (Brushes.IndianRed, "Offline"),
            _ => (Brushes.Gray, "Not configured"),
        };

        ConnectingOverlay.Visibility = Show(player.State == PlayState.Connecting && player.Frame == null);
        ConnectingText.Text = $"Connecting to {settings.Host}…";
        FailedOverlay.Visibility = Show(player.State == PlayState.Failed);
        FailedText.Text = player.Error;
        IdleOverlay.Visibility = Show(player.State == PlayState.Idle);
        PrivacyPill.Visibility = Show(status.Privacy == true);
        ToastBorder.Visibility = Show(model.Toast != null);
        ToastText.Text = model.Toast ?? "";

        HdButton.IsChecked = settings.HighQuality;
        SdButton.IsChecked = !settings.HighQuality;
        StepSlider.Value = settings.PanStep;
        StepText.Text = $"{settings.PanStep}°";

        var recording = model.Recorder.IsRecording;
        RecordIcon.Text = recording ? "" : "";
        RecordLabel.Text = recording ? "Stop" : "Record";
        RecordButton.Foreground = recording ? (Brush)FindResource("Danger") : (Brush)FindResource("Text");
        RecordingPill.Visibility = Show(recording);
        if (recording && !recordingTimer.IsEnabled) { recordingTimer.Start(); UpdateRecordingTime(); }
        if (!recording) recordingTimer.Stop();

        BusyBanner.Visibility = Show(control.State is ControlState.Installing or ControlState.Connecting);
        BusyText.Text = control.State == ControlState.Installing
            ? "Setting up camera controls (first launch only)…"
            : "Connecting to camera controls…";
        FailBanner.Visibility = Show(control.State == ControlState.Failed);
        FailText.Text = control.Failure;
        LastErrorText.Visibility = Show(control.IsConnected && control.LastError != null);
        LastErrorText.Text = control.LastError ?? "";

        var presets = status.Presets ?? [];
        if (!ReferenceEquals(PresetList.ItemsSource, presets)) PresetList.ItemsSource = presets;
        NoPresetsText.Visibility = Show(presets.Count == 0);
        SavePresetButton.IsEnabled = control.IsConnected && PresetName.Text.Trim() != "";

        SetSwitch(PrivacySwitch, status.Privacy);
        SetSwitch(LedSwitch, status.Led);
        SetSwitch(MotionSwitch, status.Motion);
        SetSwitch(FlipSwitch, status.Flip);
        var night = status.DayNight ?? "auto";
        NightAuto.IsChecked = night == "auto";
        NightOn.IsChecked = night == "on";
        NightOff.IsChecked = night == "off";
        NightVisionRow.IsEnabled = control.IsConnected;
        ActionsSection.IsEnabled = control.IsConnected;

        SirenText.Text = sirenOn ? "Stop siren" : "Sound siren";
        SirenIcon.Text = sirenOn ? "" : "";
        SirenButton.Background = (Brush)FindResource(sirenOn ? "Danger" : "Accent");

        var info = new[] { status.Model, status.Firmware is { } fw ? $"FW {fw}" : null, settings.Host == "" ? null : settings.Host }
            .OfType<string>().ToList();
        InfoText.Text = string.Join(" · ", info);
        InfoText.Visibility = Show(info.Count > 0);
    }

    private void SetSwitch(CheckBox box, bool? value)
    {
        box.IsChecked = value ?? false;
        box.IsEnabled = model.Control.IsConnected && value != null;
    }

    private static Visibility Show(bool visible) => visible ? Visibility.Visible : Visibility.Collapsed;

    private void UpdateRecordingTime()
    {
        if (model.Recorder.StartedAt is not { } start) return;
        var t = DateTime.Now - start;
        RecordingTime.Text = t.TotalHours >= 1 ? t.ToString(@"h\:mm\:ss") : t.ToString(@"m\:ss");
    }

    // Keyboard

    private void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        var ctrl = Keyboard.Modifiers.HasFlag(ModifierKeys.Control);
        var shift = Keyboard.Modifiers.HasFlag(ModifierKeys.Shift);
        if (ctrl && shift && e.Key == Key.S) { model.Snapshot(); e.Handled = true; return; }
        if (ctrl && shift && e.Key == Key.R) { model.ToggleRecording(); e.Handled = true; return; }
        if (ctrl && e.Key == Key.R || e.Key == Key.F5) { model.Reconnect(); e.Handled = true; return; }
        if (ctrl && e.Key == Key.OemComma) { ShowSettings(); e.Handled = true; return; }

        // Arrow keys pan/tilt, unless the user is typing.
        if (Keyboard.FocusedElement is TextBox { IsReadOnly: false } or PasswordBox) return;
        var s = model.Settings.PanStep;
        (int x, int y)? move = e.Key switch
        {
            Key.Up => (0, s),
            Key.Down => (0, -s),
            Key.Left => (-s, 0),
            Key.Right => (s, 0),
            _ => null,
        };
        if (move is { } m)
        {
            model.Control.Move(m.x, m.y);
            e.Handled = true;
        }
    }

    private void VideoPane_MouseDown(object sender, MouseButtonEventArgs e) => VideoPane.Focus();

    // Toolbar

    private void ShowSettings()
    {
        if (OwnedWindows.OfType<SettingsWindow>().Any()) return;
        var dialog = new SettingsWindow(model.Settings) { Owner = this };
        if (dialog.ShowDialog() == true) model.Apply(dialog.Result);
    }

    private void Settings_Click(object sender, RoutedEventArgs e) => ShowSettings();
    private void Reconnect_Click(object sender, RoutedEventArgs e) => model.Reconnect();
    private void Snapshot_Click(object sender, RoutedEventArgs e) => model.Snapshot();
    private void Record_Click(object sender, RoutedEventArgs e) => model.ToggleRecording();
    private void Quality_Click(object sender, RoutedEventArgs e) => model.SetQuality(sender == HdButton);

    private void ToggleSidebar_Click(object sender, RoutedEventArgs e)
    {
        var show = Sidebar.Visibility != Visibility.Visible;
        Sidebar.Visibility = Show(show);
        SidebarColumn.Width = show ? new GridLength(290) : new GridLength(0);
    }

    // Sidebar

    private void RetryControls_Click(object sender, RoutedEventArgs e) => _ = model.Control.Connect(model.Settings);

    private void Pad_Click(object sender, RoutedEventArgs e)
    {
        var s = model.Settings.PanStep;
        switch ((string)((RepeatButton)sender).Tag)
        {
            case "up": model.Control.Move(0, s); break;
            case "down": model.Control.Move(0, -s); break;
            case "left": model.Control.Move(-s, 0); break;
            default: model.Control.Move(s, 0); break;
        }
    }

    private void StepSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (IsLoaded) model.SetPanStep((int)e.NewValue);
    }

    private void GotoPreset_Click(object sender, RoutedEventArgs e) =>
        model.Control.GotoPreset((Preset)((FrameworkElement)sender).DataContext);

    private void DeletePreset_Click(object sender, RoutedEventArgs e) =>
        model.Control.DeletePreset((Preset)((FrameworkElement)sender).DataContext);

    private void SavePreset_Click(object sender, RoutedEventArgs e) => SavePreset();

    private void PresetName_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter) SavePreset();
    }

    private void PresetName_TextChanged(object sender, TextChangedEventArgs e)
    {
        PresetPlaceholder.Visibility = Show(PresetName.Text == "");
        SavePresetButton.IsEnabled = model.Control.IsConnected && PresetName.Text.Trim() != "";
    }

    private void SavePreset()
    {
        var name = PresetName.Text.Trim();
        if (name == "" || !model.Control.IsConnected) return;
        model.Control.SavePreset(name);
        PresetName.Text = "";
        VideoPane.Focus();
    }

    private void Privacy_Click(object sender, RoutedEventArgs e) => model.Control.SetPrivacy(PrivacySwitch.IsChecked == true);
    private void Led_Click(object sender, RoutedEventArgs e) => model.Control.SetLed(LedSwitch.IsChecked == true);
    private void Motion_Click(object sender, RoutedEventArgs e) => model.Control.SetMotion(MotionSwitch.IsChecked == true);
    private void Flip_Click(object sender, RoutedEventArgs e) => model.Control.SetFlip(FlipSwitch.IsChecked == true);
    private void NightVision_Click(object sender, RoutedEventArgs e) => model.Control.SetDayNight((string)((RadioButton)sender).Tag);

    private void Siren_Click(object sender, RoutedEventArgs e)
    {
        sirenOn = !sirenOn;
        model.Control.SetAlarm(sirenOn);
        Refresh();
    }

    private void Calibrate_Click(object sender, RoutedEventArgs e) => model.Control.Calibrate();
    private void RefreshStatus_Click(object sender, RoutedEventArgs e) => model.Control.Refresh();

    private void Reboot_Click(object sender, RoutedEventArgs e)
    {
        var answer = MessageBox.Show(this, "The live view will drop for about a minute.", "Reboot the camera?",
                                     MessageBoxButton.OKCancel, MessageBoxImage.Warning);
        if (answer == MessageBoxResult.OK) model.Control.Reboot();
    }
}
