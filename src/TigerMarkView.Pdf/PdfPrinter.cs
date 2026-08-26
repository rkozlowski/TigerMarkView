using System.ComponentModel;
using System.Drawing.Printing;
using System.Runtime.InteropServices;
using System.Threading;
using Microsoft.Web.WebView2.Core;
using TigerMarkView.Core.Exporting;
using TigerMarkView.Core.Printing;

namespace TigerMarkView.Pdf;

/// <summary>
/// Sends an already-written PDF to a printer, and asks the reader which printer that is. The whole
/// Windows print handoff, and the only place in TigerMarkView that knows printers exist.
/// </summary>
/// <remarks>
/// <para>
/// <strong>Why not the shell's <c>print</c> verb.</strong> Handing the PDF to whatever application is
/// registered for <c>.pdf</c> is unreliable because the verb is
/// registered by the <em>handler</em>, and Microsoft Edge — the out-of-the-box default on Windows —
/// registers only <c>open</c> and <c>runas</c> for <c>MSEdgePDF</c>, as does Chrome. Adobe Acrobat does
/// register <c>Print</c>. So a shell-verb implementation would print on some machines and silently fall
/// back on others, and could never tell when the job had finished. WebView2 is already a hard
/// requirement of TigerMarkView and can render a PDF to a printer itself, so it does.
/// </para>
/// <para>
/// <strong>Never silent.</strong> The printer always comes from the standard Windows print dialog. This
/// class has no default-printer path and no way to print without the reader having chosen a printer
/// first.
/// </para>
/// </remarks>
public static class PdfPrinter
{
    /// <summary>
    /// Shows the standard Windows print dialog, opened on the page <paramref name="page"/> describes,
    /// and reports what the reader chose.
    /// </summary>
    /// <param name="ownerHandle">
    /// The window the dialog is modal to, or <see cref="IntPtr.Zero"/> for none. Passed as a raw handle
    /// so the caller need not be a WinForms application — the Avalonia window supplies its own, and
    /// passing it is what makes the dialog modal to TigerMarkView rather than a window of its own.
    /// </param>
    /// <param name="page">
    /// The geometry the PDF being printed was laid out for. Used only to preselect what the dialog
    /// shows; see <see cref="ApplyPageDefaults"/> for what that does and does not mean.
    /// </param>
    /// <remarks>
    /// <para>
    /// <strong>The dialog opens on the calling thread; the driver is questioned off it.</strong> A modal
    /// window owned by the main window has to be shown by the thread that owns that window, so
    /// <c>ShowDialog</c> stays where it is called from. What does <em>not</em> have to happen there is
    /// <see cref="PreparePrinterSettings"/>: building the <see cref="PrinterSettings"/> enumerates the
    /// default printer's paper sizes, which is an unbounded device query when a printer is unavailable
    /// or on a network. That
    /// is why this is a task rather than a method call.
    /// </para>
    /// <para>
    /// Page range and "print to file" are switched off — the first because TigerMarkView prints the
    /// whole document, the second because a "printer" that writes a file is a route WebView2 cannot
    /// carry out and the reader already has <c>File &gt; Export to PDF</c> for.
    /// </para>
    /// </remarks>
    public static async Task<PrinterSelection> SelectPrinterAsync(IntPtr ownerHandle, PdfPageSetup page)
    {
        ArgumentNullException.ThrowIfNull(page);

        var (printerSettings, preparationError) = await Task.Run(() => PreparePrinterSettings(page));
        if (printerSettings is null)
        {
            return PrinterSelection.Failed(preparationError!);
        }

        try
        {
            using var dialog = new PrintDialog
            {
                AllowPrintToFile = false,
                AllowSelection = false,
                AllowSomePages = false,
                AllowCurrentPage = false,

                // Required on 64-bit Windows: the older PrintDlg-based dialog does not show there.
                UseEXDialog = true,
                PrinterSettings = printerSettings,
            };

            var result = ownerHandle == IntPtr.Zero
                ? dialog.ShowDialog()
                : dialog.ShowDialog(new OwnerWindow(ownerHandle));

            if (result != DialogResult.OK)
            {
                return PrinterSelection.Cancelled();
            }

            var settings = dialog.PrinterSettings;
            if (string.IsNullOrWhiteSpace(settings.PrinterName))
            {
                return PrinterSelection.Failed("No printer was selected.");
            }

            // Copies is a short in the print API and a printer may report 0; one copy is the only
            // sensible reading of "print this".
            var copies = (short)Math.Clamp((int)settings.Copies, 1, short.MaxValue);

            return PrinterSelection.Chosen(new PrinterChoice(settings.PrinterName, copies, settings.Collate));
        }
        catch (InvalidPrinterException)
        {
            return PrinterSelection.Failed(NoPrinterMessage);
        }
        catch (Exception ex) when (ex is Win32Exception or InvalidOperationException or ExternalException)
        {
            return PrinterSelection.Failed(DialogFailedMessage(ex));
        }
    }

    /// <summary>
    /// Builds the settings the dialog opens on, off the UI thread. Reports a failure rather than
    /// throwing, because the two things that can go wrong here — no printer at all, or a driver that
    /// cannot be questioned — are exactly what <see cref="SelectPrinterAsync"/> already tells the
    /// reader about.
    /// </summary>
    private static (PrinterSettings? Settings, string? ErrorMessage) PreparePrinterSettings(PdfPageSetup page)
    {
        try
        {
            var settings = new PrinterSettings();
            ApplyPageDefaults(settings, page);

            return (settings, null);
        }
        catch (InvalidPrinterException)
        {
            return (null, NoPrinterMessage);
        }
        catch (Exception ex) when (ex is Win32Exception or InvalidOperationException or ExternalException)
        {
            return (null, DialogFailedMessage(ex));
        }
    }

    private const string NoPrinterMessage =
        "No printer is available. Add a printer in Windows Settings and try again.";

    private static string DialogFailedMessage(Exception exception) =>
        $"The Windows print dialog could not be opened: {exception.Message}";

    /// <summary>
    /// Prints <paramref name="request"/>'s PDF on the chosen printer.
    /// </summary>
    /// <remarks>
    /// Same shape as <see cref="PdfExporter.ExportAsync"/> and for the same reason: a dedicated STA
    /// thread with its own WinForms message loop, so the one implementation works from the Avalonia GUI
    /// (whose UI thread already runs a loop of its own) without either loop interfering with the other.
    /// The returned task completes when the job has been handed to the spooler, which is what makes the
    /// temporary PDF's cleanup deterministic rather than a guess.
    /// </remarks>
    public static Task<PrintResult> PrintAsync(PdfPrintRequest request, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);

        if (!File.Exists(request.PdfPath))
        {
            return Task.FromResult(PrintResult.Failed("The prepared document is no longer available to print."));
        }

        var completion = new TaskCompletionSource<PrintResult>(TaskCreationOptions.RunContinuationsAsynchronously);

        var thread = new Thread(() => RunPrint(request, cancellationToken, completion))
        {
            IsBackground = true,
            Name = "TigerMarkView print",
        };
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();

        return completion.Task;
    }

    private static void RunPrint(
        PdfPrintRequest request,
        CancellationToken cancellationToken,
        TaskCompletionSource<PrintResult> completion)
    {
        var result = PrintResult.Failed("Printing did not run.");

        try
        {
            using var host = new OffScreenPrintHost();

            host.Shown += async (_, _) =>
            {
                try
                {
                    result = await host.PrintAsync(request, cancellationToken);
                }
                catch (Exception ex)
                {
                    result = Describe(ex);
                }
                finally
                {
                    // Ends Application.Run below, which ends this thread — one host per print, so
                    // nothing native survives a finished job.
                    host.Close();
                }
            };

            Application.Run(host);
        }
        catch (Exception ex)
        {
            result = Describe(ex);
        }
        finally
        {
            completion.TrySetResult(result);
        }
    }

    private static PrintResult Describe(Exception exception) => exception switch
    {
        OperationCanceledException => PrintResult.Cancelled(),
        WebView2RuntimeNotFoundException =>
            PrintResult.Failed(
                "Printing needs the Microsoft Edge WebView2 Runtime, which is not installed on this computer."),
        UnauthorizedAccessException => PrintResult.Failed($"Access denied while printing: {exception.Message}"),
        IOException => PrintResult.Failed($"Could not read the prepared document: {exception.Message}"),
        _ => PrintResult.Failed($"Printing failed: {exception.Message}"),
    };

    /// <summary>
    /// Opens the print dialog showing the page the document was laid out for, rather than whatever the
    /// printer was last set to.
    /// </summary>
    /// <remarks>
    /// <para>
    /// <strong>This preselects; it does not decide.</strong> The PDF's pages are already laid out by the
    /// time this runs — orientation and paper were answered under
    /// <c>Tools &gt; PDF Export Settings</c> and are baked into the file — so what is
    /// written here is a description of that file, offered to the dialog so an A4 landscape document
    /// does not open a dialog insisting it is portrait. Whatever the reader then chooses is theirs:
    /// TigerMarkView reads back only the printer, the copies and the collation, and never re-lays-out
    /// the document.
    /// </para>
    /// <para>
    /// Both values reach Windows' print dialog through the DEVMODE WinForms builds from
    /// <see cref="PrinterSettings.DefaultPageSettings"/>, and both are honoured only while the dialog's
    /// <em>Let the app change my printing preferences</em> box is ticked. Unticking it reverts the
    /// dialog to the printer's own saved preferences. That
    /// box belongs to Windows: there is no API to read it, set it, or remove it, and none should be
    /// sought.
    /// </para>
    /// <para>
    /// <strong>Paper is only ever chosen from the printer's own list.</strong> A named size is matched
    /// against <see cref="PrinterSettings.PaperSizes"/> by <see cref="PaperSize.Kind"/>, so what is
    /// requested is always a form that printer really has; a page with no matching name, or a printer
    /// without that size, leaves the media alone. Nothing here constructs a custom size — see
    /// <c>OffScreenPrintHost</c> for why <c>MediaSize.Custom</c> stays out of the print path.
    /// </para>
    /// <para>
    /// Best-effort by nature, but not silent: what this can throw is a missing or broken printer, which
    /// is exactly what the caller already reports, so those exceptions are left to reach
    /// <see cref="SelectPrinter"/>'s own handlers rather than being swallowed here into a dialog opened
    /// on the wrong page.
    /// </para>
    /// </remarks>
    private static void ApplyPageDefaults(PrinterSettings settings, PdfPageSetup page)
    {
        var defaults = PrinterPageDefaults.For(page);

        settings.DefaultPageSettings.Landscape = defaults.Orientation == PdfOrientation.Landscape;

        if (defaults.Paper is not { } paper || ToPaperKind(paper) is not { } kind)
        {
            return;
        }

        foreach (PaperSize size in settings.PaperSizes)
        {
            if (size.Kind == kind)
            {
                settings.DefaultPageSettings.PaperSize = size;
                return;
            }
        }
    }

    /// <summary>
    /// TigerMarkView's five named papers as Windows knows them. The only place the two vocabularies
    /// meet, and deliberately partial: a paper this cannot name leaves the printer's media alone.
    /// </summary>
    private static PaperKind? ToPaperKind(PdfPaperSize paper) => paper switch
    {
        PdfPaperSize.A3 => PaperKind.A3,
        PdfPaperSize.A4 => PaperKind.A4,
        PdfPaperSize.A5 => PaperKind.A5,
        PdfPaperSize.Letter => PaperKind.Letter,
        PdfPaperSize.Legal => PaperKind.Legal,
        _ => null,
    };

    /// <summary>Wraps a raw window handle so a WinForms modal dialog can be owned by a foreign window.</summary>
    private sealed class OwnerWindow(IntPtr handle) : IWin32Window
    {
        public IntPtr Handle { get; } = handle;
    }
}

/// <summary>
/// What came back from the print dialog: a printer, a cancellation, or a reason it could not be asked.
/// </summary>
/// <remarks>
/// Three states rather than a nullable printer, because the caller treats them differently — a
/// cancellation is silent, a failure is worth telling the reader about, and only a choice prints.
/// </remarks>
public sealed record PrinterSelection(PrinterChoice? Printer, string? ErrorMessage)
{
    public static PrinterSelection Chosen(PrinterChoice printer) => new(printer, null);

    public static PrinterSelection Cancelled() => new(null, null);

    public static PrinterSelection Failed(string errorMessage) => new(null, errorMessage);

    public bool WasCancelled => Printer is null && ErrorMessage is null;
}
