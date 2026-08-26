using TigerMarkView.Core.Exporting;

namespace TigerMarkView.Cli;

/// <summary>
/// Decides where the PDF goes: beside the source document by default, or wherever
/// <c>-o</c>/<c>--output</c> says.
/// </summary>
internal static class OutputFile
{
    /// <summary>
    /// Resolves the destination for <paramref name="inputFullPath"/>, honouring
    /// <paramref name="requested"/> when the reader gave one.
    /// </summary>
    /// <remarks>
    /// A relative <c>--output</c> resolves against the working directory, which is what a reader
    /// typing a path into a shell means by it — deliberately not against the source document's folder,
    /// where the default (no <c>--output</c> at all) already puts the file.
    /// <para>
    /// A missing output folder is not checked here: <see cref="PdfExportRequestValidator"/> already
    /// rejects that, before the exporter starts a browser, and one rule stated twice is one rule that
    /// can disagree with itself.
    /// </para>
    /// </remarks>
    public static bool TryResolve(string inputFullPath, string? requested, out string fullPath, out string error)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(inputFullPath);

        fullPath = "";
        error = "";

        string resolved;

        if (string.IsNullOrWhiteSpace(requested))
        {
            // Architecture.md -> Architecture.pdf, in the document's own folder: the same naming the
            // GUI's save dialog suggests, from the same Core rule.
            if (PdfFileNaming.SuggestDirectory(inputFullPath) is not { } directory)
            {
                error = $"Could not work out where to write the PDF for {inputFullPath}";
                return false;
            }

            resolved = Path.Combine(directory, PdfFileNaming.SuggestFileName(inputFullPath));
        }
        else
        {
            try
            {
                resolved = Path.GetFullPath(requested);
            }
            catch (Exception ex) when (ex is ArgumentException or NotSupportedException or PathTooLongException)
            {
                error = $"Invalid output path: {requested}";
                return false;
            }
        }

        if (Directory.Exists(resolved))
        {
            error = $"Output path is a folder: {resolved}. Give the PDF a file name.";
            return false;
        }

        // Writing the PDF over the document it was made from would destroy the source. Only reachable
        // through an explicit --output, since the default derives a .pdf name from a .md one.
        if (string.Equals(resolved, inputFullPath, StringComparison.OrdinalIgnoreCase))
        {
            error = $"Output path is the input file: {resolved}";
            return false;
        }

        fullPath = resolved;
        return true;
    }
}
