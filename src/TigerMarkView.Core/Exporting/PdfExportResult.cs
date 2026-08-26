namespace TigerMarkView.Core.Exporting;

/// <summary>
/// Outcome of a PDF export. Failures are reported as values rather than exceptions: every known
/// failure mode (bad path, locked output file, WebView2 unavailable, navigation failure) is something
/// the caller shows to the user, not something that should take the application down.
/// </summary>
public sealed record PdfExportResult(bool Success, string? OutputPath, string? ErrorMessage)
{
    public static PdfExportResult Succeeded(string outputPath) => new(true, outputPath, null);

    public static PdfExportResult Failed(string errorMessage) => new(false, null, errorMessage);
}
