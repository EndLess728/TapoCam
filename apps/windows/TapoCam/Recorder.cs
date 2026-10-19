using System.Diagnostics;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace TapoCam;

/// Records the camera's original stream to MP4 without re-encoding the video.
public sealed class Recorder : ObservableObject
{
    private readonly Dispatcher dispatcher = Dispatcher.CurrentDispatcher;
    private Process? process;
    private string? file;

    private bool isRecording;
    public bool IsRecording { get => isRecording; private set => Set(ref isRecording, value); }

    public DateTime? StartedAt { get; private set; }

    public string? Start(string url)
    {
        if (IsRecording) return null;
        if (Tools.Find("ffmpeg") is not { } ffmpeg) return "ffmpeg not found";
        var output = Path.Combine(Tools.OutputDir(Environment.SpecialFolder.MyVideos), $"Tapo {Tools.Timestamp}.mp4");
        var p = new Process
        {
            StartInfo = Tools.StartInfo(ffmpeg, [
                "-hide_banner", "-loglevel", "error", "-rtsp_transport", "tcp", "-i", url,
                "-c:v", "copy", "-c:a", "aac", "-movflags", "+faststart", "-y", output], stdin: true),
            EnableRaisingEvents = true,
        };
        p.Exited += (_, _) => dispatcher.BeginInvoke(() => Finished(p));
        try
        {
            p.Start();
        }
        catch (Exception e)
        {
            return e.Message;
        }
        ChildProcesses.Track(p);
        process = p;
        file = output;
        StartedAt = DateTime.Now;
        IsRecording = true;
        return null;
    }

    public void Stop()
    {
        if (process is not { } p) return;
        // "q" makes ffmpeg finalise the MP4 cleanly.
        try
        {
            p.StandardInput.Write('q');
            p.StandardInput.Flush();
        }
        catch { }
        Task.Delay(5000).ContinueWith(_ => ChildProcesses.Kill(p));
    }

    /// Used on quit: give ffmpeg a moment to finish the file before the app (and its job object) goes away.
    public void StopAndWait()
    {
        if (process is not { } p) return;
        Stop();
        try { p.WaitForExit(5000); } catch { }
    }

    private void Finished(Process p)
    {
        if (p != process) return;
        IsRecording = false;
        StartedAt = null;
        process = null;
        if (file != null && File.Exists(file)) Tools.RevealInExplorer(file);
        file = null;
    }
}

public static class Snapshot
{
    public static string? Save(BitmapSource image)
    {
        var path = Path.Combine(Tools.OutputDir(Environment.SpecialFolder.MyPictures), $"Tapo {Tools.Timestamp}.png");
        try
        {
            var encoder = new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(image));
            using var stream = File.Create(path);
            encoder.Save(stream);
            return path;
        }
        catch
        {
            return null;
        }
    }
}
