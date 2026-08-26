namespace TigerMarkView.Core.Exporting;

/// <summary>
/// Derives the PDF name/location suggested in the save dialog from the Markdown file being viewed
/// (<c>Architecture.md</c> → <c>Architecture.pdf</c>, alongside the source document).
/// </summary>
public static class PdfFileNaming
{
    public const string PdfExtension = ".pdf";

    /// <summary>File name only, e.g. <c>Architecture.md</c> → <c>Architecture.pdf</c>.</summary>
    public static string SuggestFileName(string markdownPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(markdownPath);

        var fileName = Path.GetFileName(markdownPath.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar));
        if (string.IsNullOrEmpty(fileName))
        {
            return "document" + PdfExtension;
        }

        // ChangeExtension handles ".md", ".markdown", an unexpected extension, and no extension at
        // all identically — replace whatever trailing extension exists, or append when there is none.
        return Path.ChangeExtension(fileName, PdfExtension);
    }

    /// <summary>The source document's own folder, or <c>null</c> when it cannot be determined.</summary>
    public static string? SuggestDirectory(string markdownPath)
    {
        if (string.IsNullOrWhiteSpace(markdownPath))
        {
            return null;
        }

        try
        {
            var directory = Path.GetDirectoryName(Path.GetFullPath(markdownPath));
            return string.IsNullOrEmpty(directory) ? null : directory;
        }
        catch (Exception ex) when (ex is ArgumentException or NotSupportedException or PathTooLongException)
        {
            return null;
        }
    }
}
