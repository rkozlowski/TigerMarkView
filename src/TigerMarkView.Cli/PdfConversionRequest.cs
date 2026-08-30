using TigerMarkView.Core.Exporting;

namespace TigerMarkView.Cli;

/// <summary>
/// One conversion, as asked for: the paths, the page, and the two decisions that are not the page's —
/// whether to route the write through a timestamped file, and what moment the whole run is dated by.
/// </summary>
/// <param name="GeneratedAt">
/// The single moment the run uses for everything a reader could later compare: the date and time a
/// header template prints, and the suffix a timestamped fallback file carries. Captured once, by
/// <see cref="ConvertCommand"/>, so those two can never disagree and no page can be dated differently
/// from its neighbour.
/// </param>
internal sealed record PdfConversionRequest(
    string? InputPath,
    string? OutputPath,
    PdfPageSetup PageSetup,
    bool TimestampedFallback,
    DateTimeOffset GeneratedAt);
