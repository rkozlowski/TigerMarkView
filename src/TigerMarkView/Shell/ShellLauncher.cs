using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using TigerMarkView.Editing;

namespace TigerMarkView.Shell;

/// <summary>
/// Opens a file with its default application, and shows a file in Windows Explorer. The only
/// <see cref="Process.Start(ProcessStartInfo)"/> call site for exported PDFs.
/// </summary>
/// <remarks>
/// Same shape as <see cref="ExternalEditorLauncher"/> and
/// <see cref="TigerMarkView.Navigation.ExternalLinkLauncher"/>: a failed launch is an outcome value,
/// never an escaping exception, and no shell interpreter (<c>cmd.exe</c>, PowerShell) is ever involved.
/// Two methods and nothing else — this is a helper, not a launching framework.
/// </remarks>
public sealed class ShellLauncher
{
    /// <summary>Hands the file to the Windows shell association (Edge, Acrobat, whatever is registered).</summary>
    public LaunchOutcome OpenFile(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);

        return Run(
            new ProcessStartInfo(path) { UseShellExecute = true },
            "Could not open the file");
    }

    /// <summary>
    /// Opens Explorer at the file's folder with the file itself selected, falling back to opening the
    /// folder alone if Explorer cannot be started that way.
    /// </summary>
    /// <remarks>
    /// <c>/select,</c> is passed through <see cref="ProcessStartInfo.Arguments"/> rather than
    /// <see cref="ProcessStartInfo.ArgumentList"/> because Explorer parses its own command line and does
    /// not follow the normal argv quoting rules the argument list builds. That is safe here rather than
    /// merely convenient: a Windows path cannot contain a double quote, so wrapping the path in quotes
    /// cannot be escaped out of. No shell is involved either way — this is <c>explorer.exe</c> started
    /// directly.
    /// </remarks>
    public LaunchOutcome RevealFile(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);

        var outcome = Run(
            new ProcessStartInfo("explorer.exe")
            {
                Arguments = $"/select,\"{path}\"",
                UseShellExecute = false,
            },
            "Could not open the containing folder");

        if (outcome.Success)
        {
            return outcome;
        }

        var folder = TryGetDirectory(path);
        return folder is null
            ? outcome
            : Run(
                new ProcessStartInfo(folder) { UseShellExecute = true },
                "Could not open the containing folder");
    }

    private static LaunchOutcome Run(ProcessStartInfo startInfo, string failureSummary)
    {
        try
        {
            Process.Start(startInfo);
            return LaunchOutcome.Ok();
        }
        catch (Win32Exception ex)
        {
            // Covers "no application is associated with this file type" as well as a failed start.
            return LaunchOutcome.Failed($"{failureSummary}: {ex.Message}");
        }
        catch (Exception ex) when (ex is IOException or InvalidOperationException or ObjectDisposedException)
        {
            return LaunchOutcome.Failed($"{failureSummary}: {ex.Message}");
        }
    }

    private static string? TryGetDirectory(string path)
    {
        try
        {
            var directory = Path.GetDirectoryName(path);
            return string.IsNullOrEmpty(directory) ? null : directory;
        }
        catch (Exception ex) when (ex is ArgumentException or PathTooLongException)
        {
            return null;
        }
    }
}
