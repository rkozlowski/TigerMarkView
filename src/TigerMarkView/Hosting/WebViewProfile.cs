using Avalonia.Controls;
using Avalonia.Platform;

namespace TigerMarkView.Hosting;

/// <summary>
/// Points a <see cref="NativeWebView"/> at a browser profile under <c>%LocalAppData%</c> instead of
/// the one WebView2 would otherwise create beside the executable.
/// </summary>
/// <remarks>
/// <para>
/// With no user data folder set, WebView2 uses <c>&lt;exe name&gt;.WebView2</c> in the application
/// directory. That is writable for a per-user install and is <em>not</em> writable for an all-users
/// install under <c>%ProgramFiles%</c>. WebView2 cannot initialise there when it cannot create the
/// profile directory. The installer offers an all-users mode, so the profile has to live somewhere
/// the reader can write.
/// </para>
/// <para>
/// It is a sibling of the PDF exporter's profile rather than the same folder. Two WebView2
/// environments in one process may share a user data folder only when their creation options match,
/// and the viewer's options are Avalonia's to choose, not this project's — so the two are kept apart
/// instead of coupled through something outside our control.
/// </para>
/// <para>
/// Best-effort, like <see cref="Windowing.NativeTitleBar"/>: if the folder cannot be created the
/// default is left in place, because a browser cache location must never be the reason a window fails
/// to open.
/// </para>
/// </remarks>
internal static class WebViewProfile
{
    /// <summary>
    /// Attaches the profile to <paramref name="webView"/>. Call it before the control is first shown —
    /// the environment is requested once, when the native view is created.
    /// </summary>
    internal static void Attach(NativeWebView webView) =>
        webView.EnvironmentRequested += OnEnvironmentRequested;

    private static void OnEnvironmentRequested(object? sender, WebViewEnvironmentRequestedEventArgs e)
    {
        if (e is not WindowsWebView2EnvironmentRequestedEventArgs windows)
        {
            return;
        }

        var folder = TryCreateViewerProfileFolder();
        if (folder is not null)
        {
            windows.UserDataFolder = folder;
        }
    }

    private static string? TryCreateViewerProfileFolder()
    {
        try
        {
            var path = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "TigerMarkView",
                "WebView2",
                "Viewer");

            Directory.CreateDirectory(path);
            return path;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            return null;
        }
    }
}
