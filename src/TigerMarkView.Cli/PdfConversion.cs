using System.Security;
using ItTiger.TigerCli.Commands;
using ItTiger.TigerCli.Exceptions;
using TigerMarkView.Core.Exporting;
using TigerMarkView.Core.Rendering;
using TigerMarkView.Pdf;

namespace TigerMarkView.Cli;

/// <summary>
/// Markdown file in, PDF file out — the one thing <c>tiger-mark</c> does.
/// </summary>
/// <remarks>
/// <para>
/// Every step of the actual work belongs to somebody else: <see cref="MarkdownDocumentLoader"/>
/// produces exactly the HTML the viewer renders (same Markdig pipeline, same stylesheet, same
/// <c>&lt;base href&gt;</c> resolving relative images), and <see cref="PdfExporter"/> turns it into a
/// PDF through exactly the print path File &gt; Export to PDF uses. There is no second renderer and
/// no second export implementation, so a PDF from the CLI and a PDF from the GUI are the same PDF.
/// </para>
/// <para>
/// Failures are raised as <see cref="TigerCliCommandException"/> rather than reported here. TigerCli
/// renders one <c>Error: &lt;message&gt;</c> line on stderr and resolves the exit code through the
/// policy <see cref="TigerMarkApp"/> configures, so this project states each failure once — as a
/// sentence a reader can act on — and never formats an error or picks an exit code itself. The rules
/// behind the messages stay where they can be unit-tested without a framework: <see cref="InputFile"/>,
/// <see cref="OutputFile"/> and Core's <see cref="PdfExportRequestValidator"/>.
/// </para>
/// <para>
/// The one deliberate difference from the GUI is *which* version is converted. The GUI exports the
/// retained version the reader has read and checked; the CLI has no reader and no viewed version, so
/// it converts the file as it stands at the moment it is invoked.
/// </para>
/// </remarks>
internal static class PdfConversion
{
    /// <summary>
    /// Converts <paramref name="inputPath"/> to a PDF laid out for <paramref name="pageSetup"/>.
    /// </summary>
    /// <returns>The full path of the PDF that was written.</returns>
    /// <exception cref="TigerCliCommandException">The conversion could not be carried out.</exception>
    /// <exception cref="OperationCanceledException">The run was interrupted.</exception>
    public static async Task<string> RunAsync(
        string? inputPath,
        string? outputPath,
        PdfPageSetup pageSetup,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(pageSetup);

        if (!InputFile.TryResolve(inputPath, out var input, out var message))
        {
            throw new TigerCliCommandException(message, TigerCliExitKind.NotFound);
        }

        if (!OutputFile.TryResolve(input, outputPath, out var destination, out message))
        {
            throw new TigerCliCommandException(message);
        }

        // Light is not a choice offered here and is not a theme decision: the print rules re-declare
        // the light tokens inside @media print, so every PDF this project produces is a light one
        // whatever the viewer was showing. The page setup is passed because
        // the document's own @page rule is written from it, and the sheet the exporter asks for has to
        // be the one the HTML was laid out for.
        //
        // Rendering options are left at their default — emoji shortcodes and syntax highlighting off.
        // They are the GUI's preferences, and a script's output must not change because of a menu tick.
        string html;
        try
        {
            html = MarkdownDocumentLoader.LoadHtmlDocument(input, MarkdownTheme.Light, pageSetup);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or SecurityException or NotSupportedException)
        {
            throw new TigerCliCommandException($"Could not read {input}: {ex.Message}", TigerCliExitKind.GenericFail, innerException: ex);
        }

        // Nothing is started for a run that has already been given up on.
        cancellationToken.ThrowIfCancellationRequested();

        var result = await PdfExporter.ExportAsync(
            new PdfExportRequest(html, destination, pageSetup), cancellationToken);

        // A PDF that was written is a run that succeeded, whatever arrived while it was being written.
        // Asked before the token deliberately: an interrupt that lands in the moment between the file
        // being complete and this line would otherwise report a finished export as cancelled, leaving
        // the reader a perfectly good PDF and an exit code saying they do not have one.
        if (result.Success)
        {
            return result.OutputPath ?? destination;
        }

        // Asked of the token rather than matched against the failure text: PdfExporter turns a
        // cancelled export into an ordinary failed result ("PDF export was cancelled.") rather than
        // letting the exception out, so only the token can say the failure was the reader's doing.
        // Without this an interrupted conversion would be reported as exit 1, not 3.
        cancellationToken.ThrowIfCancellationRequested();

        throw new TigerCliCommandException(result.ErrorMessage ?? "Could not create the PDF.");
    }
}
