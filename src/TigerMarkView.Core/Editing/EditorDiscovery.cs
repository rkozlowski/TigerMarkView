namespace TigerMarkView.Core.Editing;

/// <summary>
/// Locates preset editor executables by checking a short, ordered list of common install locations.
/// Deliberately does not use the "code" launcher on PATH: on Windows that's normally a <c>code.cmd</c>
/// shim, and shim scripts can't be launched directly via <see cref="System.Diagnostics.Process.Start(System.Diagnostics.ProcessStartInfo)"/>
/// with <c>UseShellExecute = false</c> — running one would require going through cmd.exe, which this
/// app avoids for security reasons (see <see cref="EditorCommandBuilder"/>). Targeting the real
/// <c>Code.exe</c> in its install directory sidesteps that entirely.
/// </summary>
public sealed class EditorDiscovery
{
    private readonly Func<string, bool> _fileExists;

    public EditorDiscovery(Func<string, bool>? fileExists = null)
    {
        _fileExists = fileExists ?? File.Exists;
    }

    public static readonly EditorDiscovery Default = new();

    public string? FindVisualStudioCode() => FindFirstExisting(VisualStudioCodeCandidates());

    public string? FindNotepad3() => FindFirstExisting(Notepad3Candidates());

    private string? FindFirstExisting(IEnumerable<string> candidates)
    {
        foreach (var candidate in candidates)
        {
            if (!string.IsNullOrEmpty(candidate) && _fileExists(candidate))
            {
                return candidate;
            }
        }

        return null;
    }

    private static IEnumerable<string> VisualStudioCodeCandidates()
    {
        // Per-user install (the default for VS Code's own installer) is checked first, then the
        // system-wide install locations for both 64- and 32-bit distributions.
        var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        if (!string.IsNullOrEmpty(localAppData))
        {
            yield return Path.Combine(localAppData, "Programs", "Microsoft VS Code", "Code.exe");
        }

        var programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        if (!string.IsNullOrEmpty(programFiles))
        {
            yield return Path.Combine(programFiles, "Microsoft VS Code", "Code.exe");
        }

        var programFilesX86 = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86);
        if (!string.IsNullOrEmpty(programFilesX86))
        {
            yield return Path.Combine(programFilesX86, "Microsoft VS Code", "Code.exe");
        }
    }

    private static IEnumerable<string> Notepad3Candidates()
    {
        var programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        if (!string.IsNullOrEmpty(programFiles))
        {
            yield return Path.Combine(programFiles, "Notepad3", "Notepad3.exe");
        }

        var programFilesX86 = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86);
        if (!string.IsNullOrEmpty(programFilesX86))
        {
            yield return Path.Combine(programFilesX86, "Notepad3", "Notepad3.exe");
        }
    }
}
