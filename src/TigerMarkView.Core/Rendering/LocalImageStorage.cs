using System.Runtime.InteropServices;
using System.Text;

namespace TigerMarkView.Core.Rendering;

/// <summary>Checks Windows image paths without opening a network target to classify it.</summary>
public static class LocalImageStorage
{
    /// <summary>
    /// Accepts drive-letter paths backed by local storage, including local links and SUBST aliases.
    /// Unknown device providers and links to network storage fail closed. Call again at request time:
    /// drive mappings and links can change after rendering.
    /// </summary>
    public static bool IsLocal(Uri uri)
    {
        if (!WebResourcePolicy.IsLocalFile(uri)) { return false; }
        if (!OperatingSystem.IsWindows()) { return true; }

        try { return CheckPath(uri.LocalPath); }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or ArgumentException)
        {
            return false;
        }
    }

    private static bool CheckPath(string path)
    {
        for (var links = 0; links < 32; links++)
        {
            if (!Uri.TryCreate(path, UriKind.Absolute, out var uri) || !WebResourcePolicy.IsLocalFile(uri)) { return false; }
            path = uri.LocalPath;

            // GetDriveType/DriveInfo can follow a SUBST alias into SMB merely to classify its root.
            // QueryDosDevice reads the DOS namespace mapping without opening that target.
            var buffer = new StringBuilder(32768);
            if (QueryDosDevice(path[..2], buffer, buffer.Capacity) == 0) { return false; }
            var device = buffer.ToString(); // first (current) mapping in the native multi-string
            if (device.StartsWith(@"\??\", StringComparison.Ordinal))
            {
                path = device[4..].TrimEnd('\\') + path[2..];
                continue;
            }
            if (!IsLocalDevice(device)) { return false; }

            var rewritten = false;
            for (var start = 3; start < path.Length;)
            {
                var end = path.IndexOf('\\', start);
                if (end < 0) { end = path.Length; }
                FileSystemInfo entry = end == path.Length ? new FileInfo(path[..end]) : new DirectoryInfo(path[..end]);
                FileSystemInfo? target;
                try { target = entry.ResolveLinkTarget(returnFinalTarget: false); }
                catch (FileNotFoundException) { return true; }
                catch (DirectoryNotFoundException) { return true; }
                // Only the immediate reparse target is read. Check it before opening any component.
                if (target is not null)
                {
                    path = target.FullName + path[end..];
                    rewritten = true;
                    break;
                }
                start = end + 1;
            }
            if (!rewritten) { return true; }
        }
        return false;
    }

    private static bool IsLocalDevice(string device)
    {
        foreach (var prefix in new[] { @"\Device\HarddiskVolume", @"\Device\CdRom", @"\Device\Floppy", @"\Device\Ramdisk" })
        {
            if (device.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)
                && device.Length > prefix.Length && device.AsSpan(prefix.Length).IndexOfAnyExceptInRange('0', '9') < 0)
            {
                return true;
            }
        }
        return false;
    }

    [DllImport("kernel32.dll", EntryPoint = "QueryDosDeviceW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint QueryDosDevice(string name, StringBuilder target, int capacity);
}
