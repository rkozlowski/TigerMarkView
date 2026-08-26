using System.Threading;
using Microsoft.Web.WebView2.Core;
using TigerMarkView.Core.Exporting;

namespace TigerMarkView.Pdf;

/// <summary>
/// Turns a rendered HTML document into a PDF file using Microsoft WebView2's
/// <c>PrintToPdfAsync</c>, driven entirely from the document's own <c>@page</c>/<c>@media print</c>
/// CSS. This is the whole public surface of the component — no DI, no browser abstraction, no
/// document-conversion framework.
/// </summary>
/// <remarks>
/// Each export runs on its own dedicated STA thread with its own WinForms message loop, hosting an
/// off-screen but genuinely shown WebView2. That isolation lets the same code be called from the
/// Avalonia GUI, whose UI thread already runs its own loop, and from the <c>tiger-mark</c> CLI, which
/// has no loop at all.
/// </remarks>
public static class PdfExporter
{
    public static Task<PdfExportResult> ExportAsync(
        PdfExportRequest request,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);

        if (PdfExportRequestValidator.Validate(request) is { } validationError)
        {
            return Task.FromResult(PdfExportResult.Failed(validationError));
        }

        var completion = new TaskCompletionSource<PdfExportResult>(TaskCreationOptions.RunContinuationsAsynchronously);

        var thread = new Thread(() => RunExport(request, cancellationToken, completion))
        {
            IsBackground = true,
            Name = "TigerMarkView PDF export",
        };
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();

        return completion.Task;
    }

    private static void RunExport(
        PdfExportRequest request,
        CancellationToken cancellationToken,
        TaskCompletionSource<PdfExportResult> completion)
    {
        var result = PdfExportResult.Failed("PDF export did not run.");

        try
        {
            using var host = new OffScreenPdfHost();

            host.Shown += async (_, _) =>
            {
                try
                {
                    result = await host.ExportAsync(request, cancellationToken);
                }
                catch (Exception ex)
                {
                    result = PdfExportResult.Failed(Describe(ex));
                }
                finally
                {
                    // Ends Application.Run below, which ends this thread — one host per export, so
                    // nothing native survives a completed export.
                    host.Close();
                }
            };

            Application.Run(host);
        }
        catch (Exception ex)
        {
            result = PdfExportResult.Failed(Describe(ex));
        }
        finally
        {
            completion.TrySetResult(result);
        }
    }

    private static string Describe(Exception exception) => exception switch
    {
        OperationCanceledException => "PDF export was cancelled.",
        WebView2RuntimeNotFoundException =>
            "PDF export needs the Microsoft Edge WebView2 Runtime, which is not installed on this computer.",
        UnauthorizedAccessException => $"Access denied while writing the PDF: {exception.Message}",
        IOException => $"Could not write the PDF: {exception.Message}",
        _ => $"PDF export failed: {exception.Message}",
    };
}
