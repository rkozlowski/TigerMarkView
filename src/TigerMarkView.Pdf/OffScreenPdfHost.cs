using System.Text;
using System.Threading;
using Microsoft.Web.WebView2.Core;
using TigerMarkView.Core.Exporting;

namespace TigerMarkView.Pdf;

/// <summary>
/// The invisible WebView2 host used for one export: rendered HTML in, PDF file out.
/// </summary>
/// <remarks>
/// The window itself — off-screen but genuinely shown, unactivatable, out of alt-tab — and the
/// navigation wait belong to <see cref="OffScreenWebViewHost"/>, which printing uses too. What is here
/// is only what makes this an <em>export</em>: the temporary HTML, the print settings built from the
/// page setup, and <c>PrintToPdfAsync</c>.
/// </remarks>
internal sealed class OffScreenPdfHost : OffScreenWebViewHost
{
    private static readonly TimeSpan ResourceSettleTimeout = TimeSpan.FromSeconds(10);
    private static readonly TimeSpan ResourcePollInterval = TimeSpan.FromMilliseconds(100);

    /// <summary>
    /// Reports <c>true</c> once the document is loaded and every &lt;img&gt; has settled. <c>complete</c>
    /// is also true for images that failed to load, so a missing relative image cannot hang an export.
    /// </summary>
    private const string ReadinessScript = """
        (function () {
          if (document.readyState !== 'complete') { return false; }
          return Array.prototype.every.call(document.images, function (i) { return i.complete; });
        })()
        """;

    protected override string ProfileName => "Export";

    public async Task<PdfExportResult> ExportAsync(PdfExportRequest request, CancellationToken cancellationToken)
    {
        string? htmlPath = null;

        try
        {
            cancellationToken.ThrowIfCancellationRequested();

            var core = await CreateCoreAsync();

            // The HTML is navigated to as a real file:// document rather than pushed in as a string:
            // its <base href> points at the source Markdown folder, and only a file:// document is
            // allowed to pull in the relative local images that base href resolves to.
            htmlPath = WriteTemporaryHtml(request.Html);

            if (await NavigateAsync(core, new Uri(htmlPath).AbsoluteUri, "for export", cancellationToken) is
                { } navigationError)
            {
                return PdfExportResult.Failed(navigationError);
            }

            await WaitForResourcesAsync(core, cancellationToken);

            var outputPath = Path.GetFullPath(request.OutputPath);
            var printed = await core.PrintToPdfAsync(outputPath, CreatePrintSettings(core, request.PageSetup));

            return printed
                ? PdfExportResult.Succeeded(outputPath)
                // PrintToPdfAsync reports every write failure the same way (a plain false), so the
                // message has to cover the realistic causes: locked target, or an unwritable folder.
                : PdfExportResult.Failed(
                    $"Could not write the PDF to {outputPath}. Check that the file is not open in " +
                    "another application and that the folder is writable.");
        }
        finally
        {
            TryDelete(htmlPath);
        }
    }

    private static CoreWebView2PrintSettings CreatePrintSettings(CoreWebView2 core, PdfPageSetup page)
    {
        var settings = core.Environment.CreatePrintSettings();

        settings.PageWidth = page.WidthInches;
        settings.PageHeight = page.HeightInches;
        settings.Orientation = CoreWebView2PrintOrientation.Portrait;
        settings.ScaleFactor = 1.0;

        // Zero the engine's own margins so the printable area comes solely from the document's
        // @page rule — one stylesheet governs both screen and print layout.
        settings.MarginTop = 0;
        settings.MarginBottom = 0;
        settings.MarginLeft = 0;
        settings.MarginRight = 0;

        settings.ShouldPrintBackgrounds = true;

        // No Chromium-supplied page title, source URL, date or page numbers: TigerMarkView owns what
        // appears on the page, and a file:/// URL in the footer of a shared PDF is noise at best.
        settings.ShouldPrintHeaderAndFooter = false;
        settings.HeaderTitle = string.Empty;
        settings.FooterUri = string.Empty;

        return settings;
    }

    /// <summary>
    /// Navigation completion already implies the load event fired, but relative local images can still
    /// be settling. Polls a deterministic readiness signal instead of sleeping a fixed amount, and gives
    /// up after a bounded wait — printing a document with one slow image beats failing the export.
    /// </summary>
    private static async Task WaitForResourcesAsync(CoreWebView2 core, CancellationToken cancellationToken)
    {
        var deadline = DateTime.UtcNow + ResourceSettleTimeout;

        while (DateTime.UtcNow < deadline)
        {
            cancellationToken.ThrowIfCancellationRequested();

            if (string.Equals(await core.ExecuteScriptAsync(ReadinessScript), "true", StringComparison.Ordinal))
            {
                return;
            }

            await Task.Delay(ResourcePollInterval, cancellationToken);
        }
    }

    private static string WriteTemporaryHtml(string html)
    {
        var directory = Path.Combine(Path.GetTempPath(), "TigerMarkView", "pdf");
        Directory.CreateDirectory(directory);

        var path = Path.Combine(directory, $"export-{Guid.NewGuid():N}.html");
        File.WriteAllText(path, html, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));

        return path;
    }
}
