using TigerMarkView.Cli;

namespace TigerMarkView.Cli.Tests;

public class InputFileTests : IDisposable
{
    private readonly string _dir;

    public InputFileTests()
    {
        _dir = Path.Combine(Path.GetTempPath(), "TigerMarkViewCliTests_" + Guid.NewGuid());
        Directory.CreateDirectory(_dir);
    }

    public void Dispose() => Directory.Delete(_dir, recursive: true);

    [Theory]
    [InlineData("notes.md")]
    [InlineData("notes.markdown")]
    [InlineData("NOTES.MD")]
    [InlineData("My Notes.md")]
    public void AnExistingMarkdownFileResolvesToItsAbsolutePath(string fileName)
    {
        var path = Path.Combine(_dir, fileName);
        File.WriteAllText(path, "# Hello");

        Assert.True(InputFile.TryResolve(path, out var resolved, out var error));
        Assert.Equal(Path.GetFullPath(path), resolved);
        Assert.Empty(error);
    }

    [Fact]
    public void AMissingFileIsReportedAsMissing()
    {
        var path = Path.Combine(_dir, "does-not-exist.md");

        Assert.False(InputFile.TryResolve(path, out _, out var error));
        Assert.Contains("not found", error, StringComparison.OrdinalIgnoreCase);
        Assert.Contains(path, error, StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// File.Exists is false for a directory, so without its own check a folder the reader can plainly
    /// see would be reported as "not found".
    /// </summary>
    [Fact]
    public void AFolderIsReportedAsAFolder()
    {
        Assert.False(InputFile.TryResolve(_dir, out _, out var error));
        Assert.Contains("folder", error, StringComparison.OrdinalIgnoreCase);
    }

    [Theory]
    [InlineData("notes.txt")]
    [InlineData("notes.html")]
    [InlineData("README")]
    public void AFileThatIsNotMarkdownIsRefused(string fileName)
    {
        var path = Path.Combine(_dir, fileName);
        File.WriteAllText(path, "# Hello");

        Assert.False(InputFile.TryResolve(path, out _, out var error));
        Assert.Contains("Markdown", error, StringComparison.OrdinalIgnoreCase);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void NothingAtAllIsReportedRatherThanProbed(string? path)
    {
        Assert.False(InputFile.TryResolve(path, out _, out var error));
        Assert.False(string.IsNullOrWhiteSpace(error));
    }

    [Fact]
    public void APathNoFileCouldHaveIsRejectedWithoutThrowing()
    {
        Assert.False(InputFile.TryResolve("C:\\bad\0path\\notes.md", out _, out var error));
        Assert.False(string.IsNullOrWhiteSpace(error));
    }
}
