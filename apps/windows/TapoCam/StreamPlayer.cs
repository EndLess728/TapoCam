using System.Diagnostics;
using System.Text;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace TapoCam;

public enum PlayState { Idle, Connecting, Playing, Failed }

/// Pulls the RTSP stream through ffmpeg, which re-emits it as a pipe of JPEG frames.
public sealed class StreamPlayer : ObservableObject
{
    private readonly Dispatcher dispatcher = Dispatcher.CurrentDispatcher;
    private readonly DispatcherTimer fpsTimer;
    private Process? process;
    private string? url;
    private int generation;
    private CancellationTokenSource? retry;
    private int frameCount;
    private BitmapSource? pendingFrame;

    private BitmapSource? frame;
    public BitmapSource? Frame { get => frame; private set => Set(ref frame, value); }

    private PlayState state;
    public PlayState State { get => state; private set => Set(ref state, value); }

    private string error = "";
    public string Error { get => error; private set => Set(ref error, value); }

    private int fps;
    public int Fps { get => fps; private set => Set(ref fps, value); }

    public StreamPlayer()
    {
        fpsTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        fpsTimer.Tick += (_, _) => { Fps = frameCount; frameCount = 0; };
    }

    public void Play(string url)
    {
        Stop();
        this.url = url;
        State = PlayState.Connecting;
        Start();
        fpsTimer.Start();
    }

    public void Stop()
    {
        generation++;
        retry?.Cancel();
        fpsTimer.Stop();
        ChildProcesses.Kill(process);
        process = null;
        url = null;
        Fps = 0;
        State = PlayState.Idle;
    }

    private void Start()
    {
        if (url == null) return;
        if (Tools.Find("ffmpeg") is not { } ffmpeg)
        {
            Fail("ffmpeg not found. Reinstall TapoCam, or install ffmpeg and add it to PATH.");
            return;
        }
        var gen = ++generation;
        var p = new Process
        {
            StartInfo = Tools.StartInfo(ffmpeg, [
                "-hide_banner", "-loglevel", "error", "-nostdin",
                "-rtsp_transport", "tcp", "-timeout", "5000000",
                "-fflags", "nobuffer", "-flags", "low_delay",
                "-hwaccel", "auto",
                "-i", url, "-an",
                "-f", "image2pipe", "-c:v", "mjpeg", "-q:v", "4", "-"], stdout: true, stderr: true),
        };
        try
        {
            p.Start();
        }
        catch (Exception e)
        {
            Fail($"Could not start ffmpeg: {e.Message}");
            return;
        }
        ChildProcesses.Track(p);
        process = p;

        var log = new ErrorLog();
        var frames = Task.Run(() => ReadFrames(p.StandardOutput.BaseStream, gen));
        var errors = Task.Run(async () =>
        {
            var buf = new char[1024];
            int n;
            while ((n = await p.StandardError.ReadAsync(buf)) > 0) log.Append(buf.AsSpan(0, n));
        });
        Task.WhenAll(frames, errors).ContinueWith(_ =>
        {
            try { p.WaitForExit(); } catch { }
            dispatcher.BeginInvoke(() => Ended(gen, log.Text));
        });
    }

    private void ReadFrames(Stream stdout, int gen)
    {
        var parser = new JpegStreamParser();
        var buf = new byte[1 << 16];
        int n;
        while ((n = stdout.Read(buf, 0, buf.Length)) > 0)
        {
            if (parser.Feed(buf.AsSpan(0, n)) is not { } jpeg) continue;
            BitmapSource image;
            try
            {
                var decoder = new JpegBitmapDecoder(new MemoryStream(jpeg), BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
                image = decoder.Frames[0];
                image.Freeze();
            }
            catch
            {
                continue;
            }
            // Only the newest frame matters: if the UI hasn't shown the last one yet, just replace it.
            if (Interlocked.Exchange(ref pendingFrame, image) == null)
                dispatcher.BeginInvoke(() => ShowFrame(gen));
        }
    }

    private void ShowFrame(int gen)
    {
        var image = Interlocked.Exchange(ref pendingFrame, null);
        if (image == null || gen != generation) return;
        Frame = image;
        frameCount++;
        if (State != PlayState.Playing) State = PlayState.Playing;
    }

    private void Ended(int gen, string log)
    {
        if (gen != generation) return;
        Fail(Explain(log));
        // Tapo blocks an IP after repeated failed logins, so don't hammer it with a bad password.
        var authFailed = log.Contains("401") || log.Contains("unauthorized", StringComparison.OrdinalIgnoreCase);
        var cts = retry = new CancellationTokenSource();
        Task.Delay(TimeSpan.FromSeconds(authFailed ? 60 : 3), cts.Token).ContinueWith(t =>
        {
            if (t.IsCanceled) return;
            dispatcher.BeginInvoke(() =>
            {
                if (gen != generation || cts.IsCancellationRequested) return;
                State = PlayState.Connecting;
                Start();
            });
        });
    }

    private void Fail(string message)
    {
        Error = message;
        State = PlayState.Failed;
    }

    private static string Explain(string log)
    {
        var l = log.ToLowerInvariant();
        if (l.Contains("401") || l.Contains("unauthorized"))
            return "The camera refused the login. Check the Camera Account (Tapo app → Camera Settings → Advanced Settings → Camera Account). Retrying in 60 s…";
        if (l.Contains("connection refused") || l.Contains("timed out") || l.Contains("no route") || l.Contains("host is down")
            || l.Contains("error number -138") || l.Contains("connection to tcp://"))
            return "Can't reach the camera. Check its IP address and that it's on the same Wi-Fi. Retrying…";
        var last = log.Split('\n', StringSplitOptions.RemoveEmptyEntries).LastOrDefault()?.Trim() ?? "";
        return last == "" ? "Stream ended. Retrying…" : $"{last} Retrying…";
    }
}

/// Splits a byte stream of concatenated JPEGs on SOI (FFD8) / EOI (FFD9) markers.
public sealed class JpegStreamParser
{
    private byte[] buffer = new byte[1 << 20];
    private int length;

    /// Returns the newest complete JPEG in the data seen so far, if any.
    public byte[]? Feed(ReadOnlySpan<byte> data)
    {
        if (length + data.Length > buffer.Length) Array.Resize(ref buffer, Math.Max(buffer.Length * 2, length + data.Length));
        data.CopyTo(buffer.AsSpan(length));
        length += data.Length;

        byte[]? newest = null;
        var start = 0;
        while (true)
        {
            var span = buffer.AsSpan(start, length - start);
            var soi = span.IndexOf([(byte)0xFF, (byte)0xD8]);
            if (soi < 0)
            {
                // Keep a trailing 0xFF in case it's the first half of the next SOI.
                start = length > start && buffer[length - 1] == 0xFF ? length - 1 : length;
                break;
            }
            var eoi = span[(soi + 2)..].IndexOf([(byte)0xFF, (byte)0xD9]);
            if (eoi < 0)
            {
                start += soi;
                break;
            }
            var end = start + soi + 2 + eoi + 2;
            newest = buffer[(start + soi)..end];
            start = end;
        }
        Buffer.BlockCopy(buffer, start, buffer, 0, length - start);
        length -= start;
        return newest;
    }
}

public sealed class ErrorLog
{
    private readonly StringBuilder text = new();

    public void Append(ReadOnlySpan<char> s)
    {
        lock (text)
        {
            text.Append(s);
            if (text.Length > 8192) text.Remove(0, text.Length - 4096);
        }
    }

    public string Text
    {
        get { lock (text) return text.ToString().Trim(); }
    }
}
