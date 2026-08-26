namespace TigerMarkView.Core.Exporting;

/// <summary>
/// Cheap up-front checks so obviously impossible exports fail with a clear message instead of
/// spinning up a browser first. Pure and platform-independent — it never touches the output file
/// itself; genuinely racy conditions (the file being locked at write time) surface from the exporter.
/// </summary>
public static class PdfExportRequestValidator
{
    /// <returns>An error message, or <c>null</c> when the request looks exportable.</returns>
    public static string? Validate(PdfExportRequest request)
    {
        ArgumentNullException.ThrowIfNull(request);

        if (string.IsNullOrWhiteSpace(request.Html))
        {
            return "There is nothing to export.";
        }

        if (string.IsNullOrWhiteSpace(request.OutputPath))
        {
            return "No output file was specified.";
        }

        string fullPath;
        try
        {
            fullPath = Path.GetFullPath(request.OutputPath);
        }
        catch (Exception ex) when (ex is ArgumentException or NotSupportedException or PathTooLongException)
        {
            return $"Invalid output path: {request.OutputPath}";
        }

        var directory = Path.GetDirectoryName(fullPath);
        if (string.IsNullOrEmpty(directory) || !Directory.Exists(directory))
        {
            return $"Output folder does not exist: {directory}";
        }

        if (request.PageSetup.WidthInches <= 0 || request.PageSetup.HeightInches <= 0)
        {
            return "Page size must be positive.";
        }

        return null;
    }
}
