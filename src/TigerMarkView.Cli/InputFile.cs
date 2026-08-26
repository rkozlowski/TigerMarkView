using TigerMarkView.Core.Navigation;

namespace TigerMarkView.Cli;

/// <summary>
/// Decides whether the thing named on the command line is a Markdown document this tool can convert,
/// before any browser is started.
/// </summary>
internal static class InputFile
{
    /// <summary>
    /// Resolves <paramref name="path"/> to an absolute Markdown file path.
    /// </summary>
    /// <returns><c>true</c> with <paramref name="fullPath"/> set, or <c>false</c> with a message for stderr.</returns>
    public static bool TryResolve(string? path, out string fullPath, out string error)
    {
        fullPath = "";
        error = "";

        if (string.IsNullOrWhiteSpace(path))
        {
            error = "No input file was given.";
            return false;
        }

        string resolved;
        try
        {
            resolved = Path.GetFullPath(path);
        }
        catch (Exception ex) when (ex is ArgumentException or NotSupportedException or PathTooLongException)
        {
            error = $"Invalid input path: {path}";
            return false;
        }

        // Checked before File.Exists, which is false for a directory and would report a folder the
        // reader can see as "not found".
        if (Directory.Exists(resolved))
        {
            error = $"Input path is a folder: {resolved}";
            return false;
        }

        if (!File.Exists(resolved))
        {
            error = $"Input file not found: {resolved}";
            return false;
        }

        // The same rule the File > Open picker, drag/drop, and local-link handling use, so every way
        // into TigerMarkView agrees on what a Markdown file is.
        if (!MarkdownLinkResolver.IsMarkdownPath(resolved))
        {
            var extensions = string.Join(", ", MarkdownLinkResolver.MarkdownExtensions);
            error = $"Not a Markdown file: {resolved} (expected {extensions})";
            return false;
        }

        fullPath = resolved;
        return true;
    }
}
