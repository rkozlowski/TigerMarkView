using System.Globalization;

namespace TigerMarkView.Core.Exporting;

/// <summary>
/// Derives the PDF name/location suggested in the save dialog from the Markdown file being viewed
/// (<c>Architecture.md</c> → <c>Architecture.pdf</c>, alongside the source document).
/// </summary>
public static class PdfFileNaming
{
    public const string PdfExtension = ".pdf";

    /// <summary>
    /// The suffix a timestamped sibling carries. Sortable, punctuation-free, and second-resolution:
    /// the names of a day's exports line up in a folder listing in the order they were made.
    /// </summary>
    public const string TimestampSuffixFormat = "yyyyMMddHHmmss";

    /// <summary>
    /// The same PDF, named for the moment it was written:
    /// <c>Report.pdf</c> → <c>Report-20260830142530.pdf</c>, in the same folder.
    /// </summary>
    /// <remarks>
    /// Used when a PDF must be written somewhere that certainly is not locked before an attempt is made
    /// to put it where it was asked for. The folder is deliberately the requested one rather than a
    /// temporary directory: if the final move cannot happen, the file the reader is left with is beside
    /// the file they asked for, under a name that says when it was made.
    /// </remarks>
    public static string TimestampedVariant(string pdfPath, DateTimeOffset timestamp)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(pdfPath);

        var fullPath = Path.GetFullPath(pdfPath);
        var stamp = timestamp.ToString(TimestampSuffixFormat, CultureInfo.InvariantCulture);
        var name = Path.GetFileNameWithoutExtension(fullPath) + "-" + stamp + Path.GetExtension(fullPath);
        var directory = Path.GetDirectoryName(fullPath);

        return string.IsNullOrEmpty(directory) ? name : Path.Combine(directory, name);
    }

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
