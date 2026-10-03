namespace TigerMarkView.Core.Exporting;

/// <summary>
/// One PDF export: an already-rendered HTML document plus where to write the result. Held in Core
/// (no Avalonia, no WebView2) so both the GUI and <c>tiger-mark</c> can build one, and so the
/// platform-independent parts are unit-testable without a browser.
/// </summary>
/// <param name="Html">
/// The complete HTML document to print, exactly as produced by
/// <see cref="Rendering.MarkdownRenderer.ToHtmlDocument"/> — the same HTML the viewer displays.
/// Its &lt;base href&gt; is what resolves relative images/links, so the exporter does not need to be
/// told the source document's directory separately.
/// </param>
/// <param name="OutputPath">Destination <c>.pdf</c> path. An existing file is overwritten.</param>
/// <param name="Page">
/// Physical page geometry; <see cref="PdfPageSetup.Default"/> unless overridden. It has to match the
/// setup the HTML was rendered with — the sheet size comes from here and the printable area from the
/// document's own <c>@page</c> rule, so the two are halves of one answer.
/// </param>
/// <param name="RemoteImages">
/// Asked at each <c>http</c>/<c>https</c> image request: whether the export may fetch it now. The GUI
/// passes the reader's shared <c>Load Remote Images</c> setting, so a PDF shows what the viewer shows
/// and a change made in any window during the export applies to its next request; <c>tiger-mark</c>
/// keeps the default, <see langword="null"/>, under which they may.
/// </param>
public sealed record PdfExportRequest(string Html, string OutputPath, PdfPageSetup? Page = null, Func<bool>? RemoteImages = null)
{
    public PdfPageSetup PageSetup => Page ?? PdfPageSetup.Default;
}
