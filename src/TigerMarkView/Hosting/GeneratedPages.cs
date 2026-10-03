using System.Diagnostics;

namespace TigerMarkView.Hosting;

/// <summary>
/// Where the viewer and Help write the pages they show: <c>%TEMP%\TigerMarkView</c>, one file per
/// purpose and per process.
/// </summary>
/// <remarks>
/// <para>
/// Each TigerMarkView window is its own process. With one shared <c>preview.html</c>, two windows
/// reloading at the same moment — both watching a document that was just saved — could each display
/// the page the other had just written, in the other's theme, or fail the write while the other held
/// the file. The process id in the name keeps every window's pages its own.
/// </para>
/// <para>
/// A window removes its own pages when it closes. <see cref="RemoveStale"/> removes those of processes
/// that are no longer running — a crash leaves its pages behind — and the single shared names earlier
/// versions used. A process id the system has since reused only delays removal until that process
/// ends; nothing of a running window is ever removed. Uninstall removes the whole folder.
/// </para>
/// </remarks>
internal static class GeneratedPages
{
    private static readonly string Folder = Path.Combine(Path.GetTempPath(), "TigerMarkView");

    /// <summary>The page file named <paramref name="purpose"/> for this process.</summary>
    internal static string ForThisProcess(string purpose) =>
        Path.Combine(Folder, $"{purpose}-{Environment.ProcessId}.html");

    /// <summary>Removes one page file, best effort.</summary>
    internal static void Remove(string path)
    {
        try
        {
            File.Delete(path);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            // A page left behind is removed by a later start, or by uninstall.
        }
    }

    /// <summary>
    /// Removes pages no running process owns: those named for a process id that is not running, and
    /// the shared <c>preview.html</c>/<c>help.html</c> of earlier versions. Best effort throughout.
    /// </summary>
    internal static void RemoveStale()
    {
        try
        {
            if (!Directory.Exists(Folder))
            {
                return;
            }

            foreach (var path in Directory.EnumerateFiles(Folder, "*.html"))
            {
                if (IsStale(Path.GetFileNameWithoutExtension(path)))
                {
                    Remove(path);
                }
            }
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            // Nothing here is worth delaying a window for.
        }
    }

    private static bool IsStale(string name)
    {
        if (name is "preview" or "help")
        {
            return true;
        }

        var dash = name.LastIndexOf('-');
        if (dash <= 0 || name[..dash] is not ("preview" or "help")
            || !int.TryParse(name[(dash + 1)..], out var processId))
        {
            // Not a page this class names, such as the PDF exporter's own temporary files.
            return false;
        }

        if (processId == Environment.ProcessId)
        {
            return false;
        }

        try
        {
            using var process = Process.GetProcessById(processId);
            return false;
        }
        catch (ArgumentException)
        {
            return true;
        }
        catch (InvalidOperationException)
        {
            return true;
        }
    }
}
