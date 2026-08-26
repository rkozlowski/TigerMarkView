using System.Threading;
using Microsoft.Web.WebView2.Core;
using TigerMarkView.Core.Printing;

namespace TigerMarkView.Pdf;

/// <summary>
/// The invisible WebView2 host used for one print: an already-written PDF file in, a spooled job out.
/// </summary>
/// <remarks>
/// <para>
/// The PDF is opened in WebView2's own PDF viewer and printed with <c>CoreWebView2.PrintAsync</c> to
/// the printer the reader chose. That is what makes printing independent of whatever application
/// happens to be registered for <c>.pdf</c> on the machine — the Edge WebView2 Runtime is already a
/// hard requirement of TigerMarkView, and it can render a PDF to a printer itself.
/// </para>
/// <para>
/// Nothing is re-rendered here. The PDF handed in was produced by <see cref="PdfExporter"/> from the
/// document the reader is looking at, so the paper, margins, page numbers, highlighting and emoji are
/// already baked into it; this host only carries it to the spooler.
/// </para>
/// </remarks>
internal sealed class OffScreenPrintHost : OffScreenWebViewHost
{
    /// <summary>
    /// How long the PDF viewer is given to lay the document out after navigation completes.
    /// </summary>
    /// <remarks>
    /// The readiness script the exporter polls is no use here: the page is WebView2's internal PDF
    /// viewer, not our own HTML, so there is no document of ours to interrogate. A short fixed settle
    /// is the honest alternative, and it costs nothing next to the printer dialog the reader has just
    /// been through.
    /// </remarks>
    private static readonly TimeSpan ViewerSettleDelay = TimeSpan.FromSeconds(2);

    protected override string ProfileName => "Print";

    public async Task<PrintResult> PrintAsync(PdfPrintRequest request, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        var core = await CreateCoreAsync();
        var pdfPath = Path.GetFullPath(request.PdfPath);

        if (await NavigateAsync(core, new Uri(pdfPath).AbsoluteUri, "for printing", cancellationToken) is
            { } navigationError)
        {
            return PrintResult.Failed(navigationError);
        }

        await Task.Delay(ViewerSettleDelay, cancellationToken);
        cancellationToken.ThrowIfCancellationRequested();

        var status = await core.PrintAsync(CreatePrintSettings(core, request));

        return PrintResult.For(Translate(status), request.Printer.PrinterName);
    }

    /// <summary>
    /// The job's settings: the reader's printer and copies, plus the page geometry the PDF was laid out
    /// for.
    /// </summary>
    /// <remarks>
    /// <para>
    /// <strong>The page setup governs the document, not the sheet.</strong> Printing an A5 landscape
    /// document can still use the printer's configured paper, because the source here is a
    /// <em>PDF</em> and its pages are already laid out — the printer's own paper is what they are placed
    /// on, rotated or centred to fit, exactly as any PDF reader would. <c>MediaSize.Custom</c> is not
    /// set: asking a physical printer for a custom media size can select an unsupported form. A reader
    /// who wants a different sheet chooses it under
    /// <em>Preferences</em> in the print dialog. The width and height are still stated, because they are
    /// the truth about the document and are what an engine that does honour them should use.
    /// </para>
    /// <para>
    /// Orientation is always <see cref="CoreWebView2PrintOrientation.Portrait"/> for the same reason it
    /// is in <see cref="OffScreenPdfHost"/>: <see cref="Core.Exporting.PdfPageSetup.For"/> has already
    /// resolved landscape by swapping width and height, so nothing below that line has to know
    /// orientation exists. Margins are zeroed because the PDF's pages already carry theirs.
    /// </para>
    /// </remarks>
    private static CoreWebView2PrintSettings CreatePrintSettings(CoreWebView2 core, PdfPrintRequest request)
    {
        var settings = core.Environment.CreatePrintSettings();

        settings.PrinterName = request.Printer.PrinterName;
        settings.Copies = request.Printer.Copies;
        settings.Collation = request.Printer.Collate
            ? CoreWebView2PrintCollation.Collated
            : CoreWebView2PrintCollation.Uncollated;

        settings.PageWidth = request.Page.WidthInches;
        settings.PageHeight = request.Page.HeightInches;
        settings.Orientation = CoreWebView2PrintOrientation.Portrait;
        settings.ScaleFactor = 1.0;

        settings.MarginTop = 0;
        settings.MarginBottom = 0;
        settings.MarginLeft = 0;
        settings.MarginRight = 0;

        settings.ShouldPrintBackgrounds = true;

        // Same rule as export: TigerMarkView owns what appears on the page. A file:/// URL and a date
        // in the margins of a printed review copy are noise, and page numbers are the document's own.
        settings.ShouldPrintHeaderAndFooter = false;
        settings.HeaderTitle = string.Empty;
        settings.FooterUri = string.Empty;

        return settings;
    }

    /// <summary>
    /// WebView2's status, reduced to the three answers the application acts on differently. The message
    /// itself is <see cref="PrintResult.For"/>'s, in Core, where it is testable.
    /// </summary>
    private static PrintDeviceStatus Translate(CoreWebView2PrintStatus status) => status switch
    {
        CoreWebView2PrintStatus.Succeeded => PrintDeviceStatus.Succeeded,
        CoreWebView2PrintStatus.PrinterUnavailable => PrintDeviceStatus.PrinterUnavailable,
        _ => PrintDeviceStatus.OtherError,
    };
}
