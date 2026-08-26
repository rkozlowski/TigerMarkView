namespace TigerMarkView.Core.Printing;

/// <summary>
/// Names and ages the temporary PDFs printing produces. In Core, and expressed as pure functions over
/// strings and timestamps, so the rules a print job's file has to obey are unit-testable without a
/// printer, a temp directory, or a WebView.
/// </summary>
/// <remarks>
/// <para>
/// Printing goes through the PDF pipeline (see <c>PdfExporter</c>), so every print produces a real PDF
/// file somewhere first. That file is TigerMarkView's, never the reader's: it lives in an application
/// folder under the user's temp directory, never beside the Markdown source, and its name carries a
/// GUID so two prints — in one session or in two running copies of the application — can never collide
/// or overwrite one another.
/// </para>
/// <para>
/// The normal lifecycle is deterministic: the file is deleted as soon as the print operation finishes,
/// fails, or is cancelled. <see cref="IsStale"/> exists only for what a crash or a kill leaves behind,
/// which is why its threshold uses hours rather than minutes — a sweep must never be able to
/// delete a job another instance is still printing.
/// </para>
/// </remarks>
public static class PrintJobFiles
{
    /// <summary>Folder under the temp root, kept apart from the exporter's own <c>pdf</c> scratch folder.</summary>
    public const string FolderName = "Print";

    /// <summary>
    /// Marks a file as one of ours. A sweep only ever deletes files matching this and
    /// <see cref="Extension"/>, so anything that finds its way into the folder by other means is left
    /// alone rather than assumed to be rubbish.
    /// </summary>
    public const string FilePrefix = "print-";

    public const string Extension = ".pdf";

    /// <summary>Longest run of the source document's name kept in the temp name, to bound path length.</summary>
    private const int MaximumStemLength = 48;

    /// <summary>
    /// How old a leftover print file has to be before a sweep may delete it.
    /// </summary>
    /// <remarks>
    /// Generous on purpose. Cleanup after a completed, failed, or cancelled print is immediate, so
    /// nothing reaches this age except crash residue; the only thing the threshold has to guarantee is
    /// that it can never race a print job that is still running, in this process or another.
    /// </remarks>
    public static TimeSpan StaleAfter { get; } = TimeSpan.FromHours(24);

    /// <summary>The print folder inside a temp root — <c>&lt;tempRoot&gt;\TigerMarkView\Print</c>.</summary>
    public static string DirectoryIn(string tempRoot)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(tempRoot);

        return Path.Combine(tempRoot, "TigerMarkView", FolderName);
    }

    /// <summary>
    /// A collision-proof file name for printing <paramref name="markdownPath"/>. The document's own name
    /// is kept (sanitised and shortened) so a leftover file can be recognised; <paramref name="token"/>
    /// is what makes it unique.
    /// </summary>
    public static string FileName(string? markdownPath, Guid token) =>
        $"{FilePrefix}{Stem(markdownPath)}-{token:N}{Extension}";

    /// <inheritdoc cref="FileName"/>
    public static string PathIn(string tempRoot, string? markdownPath, Guid token) =>
        Path.Combine(DirectoryIn(tempRoot), FileName(markdownPath, token));

    /// <summary>
    /// Whether a file in the print folder is leftover rubbish a sweep may delete: one of ours by name,
    /// and older than <see cref="StaleAfter"/>. A file from the future (a clock change) is never stale.
    /// </summary>
    public static bool IsStale(string fileName, DateTime lastWriteUtc, DateTime nowUtc)
    {
        if (string.IsNullOrWhiteSpace(fileName))
        {
            return false;
        }

        var name = Path.GetFileName(fileName);

        return name.StartsWith(FilePrefix, StringComparison.OrdinalIgnoreCase)
            && name.EndsWith(Extension, StringComparison.OrdinalIgnoreCase)
            && nowUtc - lastWriteUtc >= StaleAfter;
    }

    /// <summary>
    /// The document's name, reduced to something safe and short enough to sit inside a file name.
    /// Anything unusable — no name, only invalid characters — falls back to a fixed word rather than
    /// producing an empty or hidden name.
    /// </summary>
    private static string Stem(string? markdownPath)
    {
        if (string.IsNullOrWhiteSpace(markdownPath))
        {
            return "document";
        }

        string name;
        try
        {
            name = Path.GetFileNameWithoutExtension(markdownPath.Trim());
        }
        catch (ArgumentException)
        {
            return "document";
        }

        var invalid = Path.GetInvalidFileNameChars();
        var cleaned = new string(name.Select(c => Array.IndexOf(invalid, c) >= 0 ? '-' : c).ToArray())
            .Trim('-', '.', ' ');

        if (cleaned.Length > MaximumStemLength)
        {
            cleaned = cleaned[..MaximumStemLength].TrimEnd('-', '.', ' ');
        }

        return cleaned.Length == 0 ? "document" : cleaned;
    }
}
