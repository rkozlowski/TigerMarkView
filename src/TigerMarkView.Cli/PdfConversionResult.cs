namespace TigerMarkView.Cli;

/// <summary>
/// What came of a conversion: the PDF that now exists, and — only when it is not the one that was asked
/// for — the file that could not be replaced.
/// </summary>
/// <param name="OutputPath">
/// The PDF that exists on disk. Always a real file, and always the one named on stdout.
/// </param>
/// <param name="UnreplacedTarget">
/// The requested output, when it is still the older file because it could not be replaced. <c>null</c>
/// on an ordinary conversion, which is the whole difference between exit 0 and exit 4.
/// </param>
internal sealed record PdfConversionResult(string OutputPath, string? UnreplacedTarget = null);
