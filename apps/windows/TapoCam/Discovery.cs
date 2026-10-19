using System.Net.NetworkInformation;
using System.Net.Sockets;

namespace TapoCam;

/// Finds Tapo cameras on the local /24 by probing the ports they always expose (ONVIF 2020 + RTSP 554).
public static class Discovery
{
    public static async Task<List<string>> Scan()
    {
        if (LocalPrefix() is not { } prefix) return [];
        var hosts = await Task.WhenAll(Enumerable.Range(1, 254).Select(async i =>
        {
            var host = $"{prefix}.{i}";
            return await IsOpen(host, 2020) && await IsOpen(host, 554) ? host : null;
        }));
        return hosts.OfType<string>().ToList();
    }

    public static async Task<bool> IsOpen(string host, int port, int timeoutMs = 1500)
    {
        using var cts = new CancellationTokenSource(timeoutMs);
        using var client = new TcpClient();
        try
        {
            await client.ConnectAsync(host, port, cts.Token);
            return true;
        }
        catch
        {
            return false;
        }
    }

    /// First three octets of this PC's IPv4 address on Wi-Fi/Ethernet (adapters with a gateway, so not VPN/Hyper-V).
    public static string? LocalPrefix()
    {
        foreach (var nic in NetworkInterface.GetAllNetworkInterfaces())
        {
            if (nic.OperationalStatus != OperationalStatus.Up) continue;
            if (nic.NetworkInterfaceType is not (NetworkInterfaceType.Ethernet or NetworkInterfaceType.Wireless80211)) continue;
            var props = nic.GetIPProperties();
            if (!props.GatewayAddresses.Any(g => g.Address.AddressFamily == AddressFamily.InterNetwork)) continue;
            var ip = props.UnicastAddresses.FirstOrDefault(a => a.Address.AddressFamily == AddressFamily.InterNetwork);
            if (ip == null) continue;
            var parts = ip.Address.ToString().Split('.');
            return string.Join('.', parts.Take(3));
        }
        return null;
    }
}
