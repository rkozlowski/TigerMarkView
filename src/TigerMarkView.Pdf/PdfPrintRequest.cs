using TigerMarkView.Core.Exporting;

namespace TigerMarkView.Pdf;

/// <summary>
/// The printer the reader picked out of the Windows print dialog, and the little they were asked
/// about the job itself.
/// </summary>
/// <remarks>
/// Deliberately three fields. TigerMarkView has no Print Setup of its own — paper, orientation,
/// margins and page numbers are answered once under <c>Tools &gt; PDF Export</c> and travel with the
/// document — so the only thing the print dialog decides is where the job goes and how many copies.
/// </remarks>
public sealed record PrinterChoice(string PrinterName, short Copies, bool Collate);

/// <summary>
/// One print: an already-written PDF file, the printer to send it to, and the page geometry that PDF
/// was laid out for.
/// </summary>
/// <remarks>
/// A <em>file path</em> rather than HTML, and that is the whole design: printing does not render
/// anything. <see cref="PdfExporter"/> produces the PDF from the rendered document exactly as
/// <c>File &gt; Export to PDF</c> does, and printing carries that file to the spooler. There is one
/// Markdown pipeline, one stylesheet, and one PDF renderer behind both commands.
/// </remarks>
public sealed record PdfPrintRequest(string PdfPath, PrinterChoice Printer, PdfPageSetup Page);
