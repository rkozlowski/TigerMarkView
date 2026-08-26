namespace TigerMarkView.Core.Printing;

/// <summary>
/// What the printing device reported, reduced to the three answers the application acts on
/// differently. The Windows/WebView2 side translates its own status into this, which keeps the
/// message the reader sees out of the platform layer and testable here.
/// </summary>
public enum PrintDeviceStatus
{
    Succeeded,

    /// <summary>The chosen printer could not be reached — unplugged, offline, or since removed.</summary>
    PrinterUnavailable,

    OtherError,
}

/// <summary>
/// Outcome of one print operation. Shaped like <see cref="Exporting.PdfExportResult"/> — failures are
/// values, not exceptions — with one addition it needs and export does not: cancellation is a distinct
/// answer rather than a failure, because the reader dismissing the printer dialog is a decision, not a
/// problem to report.
/// </summary>
public sealed record PrintResult(bool Success, bool WasCancelled, string? ErrorMessage)
{
    public static PrintResult Succeeded() => new(true, false, null);

    public static PrintResult Cancelled() => new(false, true, null);

    public static PrintResult Failed(string errorMessage) => new(false, false, errorMessage);

    /// <summary>
    /// Turns a device status into the outcome, naming the printer in the message — "not available" is
    /// only actionable if the reader knows which of their printers it is about.
    /// </summary>
    public static PrintResult For(PrintDeviceStatus status, string printerName)
    {
        var printer = string.IsNullOrWhiteSpace(printerName) ? "the printer" : printerName;

        return status switch
        {
            PrintDeviceStatus.Succeeded => Succeeded(),
            PrintDeviceStatus.PrinterUnavailable =>
                Failed($"{printer} is not available. Check that it is switched on and still connected."),
            _ => Failed($"The document could not be sent to {printer}."),
        };
    }
}
