using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace TapoCam;

public partial class App : Application
{
    /// Dark title bar to match the app (Windows 10 20H1+ / 11; ignored elsewhere).
    public static void UseDarkTitleBar(Window window)
    {
        var hwnd = new WindowInteropHelper(window).Handle;
        var on = 1;
        _ = DwmSetWindowAttribute(hwnd, 20 /* DWMWA_USE_IMMERSIVE_DARK_MODE */, ref on, sizeof(int));
    }

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
}
