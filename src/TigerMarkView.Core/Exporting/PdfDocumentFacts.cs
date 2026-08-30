using TigerMarkView.Core.Rendering;

namespace TigerMarkView.Core.Exporting;

/// <summary>
/// Everything a running head or foot can say about the document it belongs to, resolved once, before
/// a single page is laid out.
/// </summary>
/// <remarks>
/// <para>
/// The point of resolving up front is <em>consistency across pages</em>. A header template is turned
/// into one CSS <c>content</c> value that every page's margin box shares, so a run that starts at
/// 23:59:59 cannot print one date on page 1 and the next day's on page 2 — there is only ever one
/// timestamp, taken when generation starts and carried here.
/// </para>
/// <para>
/// It is deliberately inert data. Nothing here reads a file, and the values are already the strings
/// that will be printed, which is what lets templates be resolved and tested without a document, a
/// browser, or a clock.
/// </para>
/// </remarks>
/// <param name="Title">
/// What the document calls itself — see <see cref="MarkdownDocumentTitle"/> for the three sources and
/// their order.
/// </param>
/// <param name="FileName">The file name without its extension.</param>
/// <param name="FileNameWithExtension">The file name as it appears in the folder.</param>
/// <param name="FilePath">The document's full path.</param>
/// <param name="GeneratedAt">
/// The single moment the whole PDF is dated by. Local time, because a running foot is read by a
/// person holding the page rather than by a machine correlating logs.
/// </param>
public sealed record PdfDocumentFacts(
    string Title,
    string FileName,
    string FileNameWithExtension,
    string FilePath,
    DateTimeOffset GeneratedAt)
{
    /// <summary>
    /// The facts of <paramref name="markdownFilePath"/>, whose content is
    /// <paramref name="markdown"/>, for a PDF generated at <paramref name="generatedAt"/>.
    /// </summary>
    /// <remarks>
    /// The Markdown is passed in rather than read: the caller has already read it — or is about to
    /// render exactly this text — and a second read could resolve a title out of a version that is not
    /// the one being converted.
    /// </remarks>
    public static PdfDocumentFacts For(string markdownFilePath, string markdown, DateTimeOffset generatedAt)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(markdownFilePath);

        var fullPath = Path.GetFullPath(markdownFilePath);
        var fileName = Path.GetFileNameWithoutExtension(fullPath);

        return new PdfDocumentFacts(
            MarkdownDocumentTitle.Resolve(markdown, fileName),
            fileName,
            Path.GetFileName(fullPath),
            fullPath,
            generatedAt);
    }
}
