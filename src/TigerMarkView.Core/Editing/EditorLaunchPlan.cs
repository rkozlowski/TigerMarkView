namespace TigerMarkView.Core.Editing;

/// <summary>
/// A resolved, ready-to-launch plan. <see cref="UseShellExecute"/> distinguishes the two supported
/// launch styles: System Default hands the file path to the OS shell association; every other editor
/// is launched as a direct process with an explicit argument list (never through cmd.exe/PowerShell).
/// </summary>
public sealed record EditorLaunchPlan(bool UseShellExecute, string FileNameOrExecutable, IReadOnlyList<string> Arguments)
{
    public static EditorLaunchPlan ShellExecute(string filePath) => new(true, filePath, Array.Empty<string>());

    public static EditorLaunchPlan DirectProcess(string executablePath, IReadOnlyList<string> arguments) =>
        new(false, executablePath, arguments);
}
