using System.Windows;
using System.Windows.Controls;

namespace TapoCam;

public partial class SettingsWindow : Window
{
    private readonly CameraSettings initial;
    private bool scanning;

    public CameraSettings Result { get; private set; }

    public SettingsWindow(CameraSettings settings)
    {
        InitializeComponent();
        initial = Result = settings;
        HostBox.Text = settings.Host;
        UserBox.Text = settings.StreamUser;
        StreamPasswordBox.Password = settings.StreamPassword;
        CloudPasswordBox.Password = settings.CloudPassword;
        SourceInitialized += (_, _) => App.UseDarkTitleBar(this);
        Loaded += async (_, _) =>
        {
            Validate();
            if (settings.Host == "") await Scan();
        };
    }

    private CameraSettings Current => initial with
    {
        Host = HostBox.Text.Trim(),
        StreamUser = UserBox.Text.Trim(),
        StreamPassword = StreamPasswordBox.Password,
        CloudPassword = CloudPasswordBox.Password,
    };

    private void Validate()
    {
        HostPlaceholder.Visibility = HostBox.Text == "" ? Visibility.Visible : Visibility.Collapsed;
        ConnectButton.IsEnabled = Current.IsConfigured;
    }

    private void Field_Changed(object sender, RoutedEventArgs e)
    {
        if (IsLoaded) Validate();
    }

    private async void Find_Click(object sender, RoutedEventArgs e) => await Scan();

    private async Task Scan()
    {
        if (scanning) return;
        scanning = true;
        FindButton.IsEnabled = false;
        FindButton.Content = "Scanning…";
        var found = await Discovery.Scan();
        FoundList.ItemsSource = found;
        if (HostBox.Text.Trim() == "" && found.Count > 0) HostBox.Text = found[0];
        FindButton.Content = found.Count == 0 ? "None found" : "Find";
        FindButton.IsEnabled = true;
        scanning = false;
    }

    private void Found_Click(object sender, RoutedEventArgs e) => HostBox.Text = (string)((Button)sender).Content;

    private void Connect_Click(object sender, RoutedEventArgs e)
    {
        Result = Current;
        DialogResult = true;
    }
}
