using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using TigerMarkView.Editing;

namespace TigerMarkView.Navigation;

/// <summary>
/// Hands an <c>http</c>/<c>https</c>/<c>mailto</c> link to the user's default browser or mail client.
/// </summary>
/// <remarks>
/// The only <see cref="Process.Start(ProcessStartInfo)"/> call site for links, mirroring
/// <see cref="ExternalEditorLauncher"/>: launch failures become an outcome value rather than an
/// unhandled exception. TigerMarkView is a Markdown reader, so a web link leaves the application
/// entirely instead of turning the viewer into a browser tab.
/// </remarks>
public sealed class ExternalLinkLauncher
{
    public LaunchOutcome Open(Uri target)
    {
        ArgumentNullException.ThrowIfNull(target);

        // Whitelisted by the caller (MainWindow.IsExternalWebLink); re-checked here because this class
        // shells out, and "open whatever URI you are given with the system handler" is not something
        // that should be reachable from a document TigerMarkView did not write.
        if (!IsLaunchableScheme(target))
        {
            return LaunchOutcome.Failed($"Refusing to open a {target.Scheme} link.");
        }

        try
        {
            Process.Start(new ProcessStartInfo(target.AbsoluteUri) { UseShellExecute = true });
            return LaunchOutcome.Ok();
        }
        catch (Win32Exception ex)
        {
            return LaunchOutcome.Failed($"Could not open the link: {ex.Message}");
        }
        catch (Exception ex) when (ex is IOException or InvalidOperationException or ObjectDisposedException)
        {
            return LaunchOutcome.Failed($"Could not open the link: {ex.Message}");
        }
    }

    public static bool IsLaunchableScheme(Uri target) =>
        target.IsAbsoluteUri &&
        (target.Scheme == Uri.UriSchemeHttp ||
         target.Scheme == Uri.UriSchemeHttps ||
         target.Scheme == Uri.UriSchemeMailto);
}
