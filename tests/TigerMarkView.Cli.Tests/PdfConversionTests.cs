using ItTiger.TigerCli.Commands;
using ItTiger.TigerCli.Exceptions;
using TigerMarkView.Core.Exporting;

namespace TigerMarkView.Cli.Tests;

/// <summary>
/// The failure half of the conversion workflow: everything that must be settled, and reported, before
/// a browser is ever started. A successful conversion needs the WebView2 runtime and writes a real
/// PDF, so it is covered by end-to-end validation of the built command rather than here.
/// </summary>
/// <remarks>
/// Each failure is a <see cref="TigerCliCommandException"/> carrying the sentence the reader sees:
/// TigerCli renders it and resolves the exit code, so what is asserted here is the message and the
/// classification, not any formatting or numeric code of this project's own.
/// </remarks>
public class PdfConversionTests : IDisposable
{
    private readonly string _dir;

    public PdfConversionTests()
    {
        _dir = Path.Combine(Path.GetTempPath(), "TigerMarkViewCliTests_" + Guid.NewGuid());
        Directory.CreateDirectory(_dir);
    }

    public void Dispose() => Directory.Delete(_dir, recursive: true);

    private Task<TigerCliCommandException> ConvertFailsAsync(string? input, string? output = null) =>
        Assert.ThrowsAsync<TigerCliCommandException>(() =>
            PdfConversion.RunAsync(input, output, PdfPageSetup.Default, CancellationToken.None));

    private string WriteDocument(string name = "notes.md")
    {
        var path = Path.Combine(_dir, name);
        File.WriteAllText(path, "# Hello");
        return path;
    }

    [Fact]
    public async Task AMissingInputFileFailsAsNotFound()
    {
        var failure = await ConvertFailsAsync(Path.Combine(_dir, "does-not-exist.md"));

        Assert.Equal(TigerCliExitKind.NotFound, failure.ExitKind);
        Assert.False(string.IsNullOrWhiteSpace(failure.Message));
    }

    [Fact]
    public async Task ANonMarkdownInputFileFails()
    {
        var failure = await ConvertFailsAsync(WriteDocument("notes.txt"));

        Assert.Contains("Markdown", failure.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task AnUnusableOutputPathFails()
    {
        // A folder cannot be written to as if it were the PDF.
        var failure = await ConvertFailsAsync(WriteDocument(), _dir);

        Assert.Contains("folder", failure.Message, StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>Writing the PDF over the document it was made from would destroy the source.</summary>
    [Fact]
    public async Task AnOutputPathThatIsTheInputFileFails()
    {
        var input = WriteDocument();

        var failure = await ConvertFailsAsync(input, input);

        Assert.Contains("input file", failure.Message, StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// The output folder rule lives in Core's PdfExportRequestValidator and is reached through the
    /// exporter, which checks it before starting a browser. This asserts the CLI surfaces it rather
    /// than restating it.
    /// </summary>
    [Fact]
    public async Task AMissingOutputFolderFails()
    {
        var failure = await ConvertFailsAsync(WriteDocument(), Path.Combine(_dir, "no-such-folder", "out.pdf"));

        Assert.Contains("folder", failure.Message, StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>Ctrl+C is not a failure, and does not report itself as one.</summary>
    [Fact]
    public async Task AnAlreadyCancelledRunReportsCancellationRatherThanFailure()
    {
        using var cancellation = new CancellationTokenSource();
        await cancellation.CancelAsync();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => PdfConversion.RunAsync(
            WriteDocument(), Path.Combine(_dir, "out.pdf"), PdfPageSetup.Default, cancellation.Token));
    }
}
