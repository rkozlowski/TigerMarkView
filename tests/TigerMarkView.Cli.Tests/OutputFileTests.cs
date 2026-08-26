using TigerMarkView.Cli;

namespace TigerMarkView.Cli.Tests;

public class OutputFileTests : IDisposable
{
    private readonly string _dir;

    public OutputFileTests()
    {
        _dir = Path.Combine(Path.GetTempPath(), "TigerMarkViewCliTests_" + Guid.NewGuid());
        Directory.CreateDirectory(_dir);
    }

    public void Dispose() => Directory.Delete(_dir, recursive: true);

    [Theory]
    [InlineData("Architecture.md", "Architecture.pdf")]
    [InlineData("Architecture.markdown", "Architecture.pdf")]
    [InlineData("release-notes-v1.2.md", "release-notes-v1.2.pdf")]
    [InlineData("My Notes.md", "My Notes.pdf")]
    public void WithNoOutputOptionThePdfLandsBesideTheSourceDocument(string input, string expected)
    {
        var inputPath = Path.Combine(_dir, input);

        Assert.True(OutputFile.TryResolve(inputPath, requested: null, out var output, out var error));
        Assert.Equal(Path.Combine(_dir, expected), output);
        Assert.Empty(error);
    }

    [Fact]
    public void AnAbsoluteOutputPathIsUsedAsGiven()
    {
        var inputPath = Path.Combine(_dir, "notes.md");
        var requested = Path.Combine(_dir, "reports", "Q3 Report.pdf");

        Assert.True(OutputFile.TryResolve(inputPath, requested, out var output, out _));
        Assert.Equal(requested, output);
    }

    /// <summary>
    /// Against the working directory, which is what someone typing a path into a shell means by it.
    /// The source document's folder is what the *default* already covers.
    /// </summary>
    [Fact]
    public void ARelativeOutputPathResolvesAgainstTheWorkingDirectory()
    {
        var inputPath = Path.Combine(_dir, "notes.md");

        Assert.True(OutputFile.TryResolve(inputPath, "report.pdf", out var output, out _));
        Assert.Equal(Path.GetFullPath("report.pdf"), output);
    }

    [Fact]
    public void AnOutputPathThatIsAFolderIsRefused()
    {
        var inputPath = Path.Combine(_dir, "notes.md");

        Assert.False(OutputFile.TryResolve(inputPath, _dir, out _, out var error));
        Assert.Contains("folder", error, StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>Writing the PDF over the document it was made from would destroy the source.</summary>
    [Theory]
    [InlineData("notes.md")]
    [InlineData("NOTES.MD")]
    public void WritingOverTheInputFileIsRefused(string requested)
    {
        var inputPath = Path.Combine(_dir, "notes.md");

        Assert.False(OutputFile.TryResolve(inputPath, Path.Combine(_dir, requested), out _, out var error));
        Assert.False(string.IsNullOrWhiteSpace(error));
    }

    [Fact]
    public void APathNoFileCouldHaveIsRejectedWithoutThrowing()
    {
        var inputPath = Path.Combine(_dir, "notes.md");

        Assert.False(OutputFile.TryResolve(inputPath, "C:\\bad\0path\\out.pdf", out _, out var error));
        Assert.False(string.IsNullOrWhiteSpace(error));
    }
}
