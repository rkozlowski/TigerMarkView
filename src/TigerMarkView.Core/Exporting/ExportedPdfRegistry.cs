using System.Diagnostics.CodeAnalysis;

namespace TigerMarkView.Core.Exporting;

/// <summary>
/// Remembers, for the current application session only, the most recent <em>successful</em> PDF export
/// of each Markdown document.
/// </summary>
/// <remarks>
/// <para>
/// This is what lets the status bar offer "Open containing folder" for the document being read without
/// ever pointing at some unrelated PDF: the lookup is by the Markdown document, so moving to a document
/// that has not been exported simply finds nothing.
/// </para>
/// <para>
/// Deliberately <strong>not</strong> persisted. An exported PDF is the product of one reading session;
/// remembering across restarts would resurrect actions for files the user has since moved or deleted,
/// and would mean adding a settings field for something no one asked to keep. Nothing here touches the
/// filesystem either — a remembered path is a claim about what was written, not a guarantee that it is
/// still there, so callers check existence at the moment they act on it.
/// </para>
/// </remarks>
public sealed class ExportedPdfRegistry
{
    // Windows paths compare case-insensitively, as everywhere else in the app.
    private readonly Dictionary<string, string> _byDocument = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>
    /// Records a successful export, replacing any earlier one for the same document — a re-export
    /// supersedes its predecessor, which is what "the latest export" means to the reader.
    /// </summary>
    public void Record(string documentPath, string pdfPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(documentPath);
        ArgumentException.ThrowIfNullOrWhiteSpace(pdfPath);

        _byDocument[documentPath] = pdfPath;
    }

    /// <summary>The latest PDF exported from <paramref name="documentPath"/>, or <c>null</c>.</summary>
    public string? Find(string? documentPath)
    {
        if (string.IsNullOrWhiteSpace(documentPath))
        {
            return null;
        }

        return _byDocument.TryGetValue(documentPath, out var pdfPath) ? pdfPath : null;
    }

    /// <inheritdoc cref="Find"/>
    public bool TryFind(string? documentPath, [NotNullWhen(true)] out string? pdfPath)
    {
        pdfPath = Find(documentPath);
        return pdfPath is not null;
    }

    /// <summary>
    /// Drops every record pointing at <paramref name="pdfPath"/>, used when the file turns out to be
    /// gone. Keyed by the PDF rather than by the document because the same export can legitimately be
    /// recorded against more than one document, and because the caller discovers the loss while holding
    /// the PDF path, not necessarily the document it came from.
    /// </summary>
    public bool ForgetExport(string? pdfPath)
    {
        if (string.IsNullOrWhiteSpace(pdfPath))
        {
            return false;
        }

        var stale = _byDocument
            .Where(entry => string.Equals(entry.Value, pdfPath, StringComparison.OrdinalIgnoreCase))
            .Select(entry => entry.Key)
            .ToList();

        foreach (var documentPath in stale)
        {
            _byDocument.Remove(documentPath);
        }

        return stale.Count > 0;
    }
}
