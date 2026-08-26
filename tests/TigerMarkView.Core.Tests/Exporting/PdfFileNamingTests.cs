using TigerMarkView.Core.Exporting;

namespace TigerMarkView.Core.Tests.Exporting;

public class PdfFileNamingTests
{
    [Theory]
    [InlineData("Architecture.md", "Architecture.pdf")]
    [InlineData("Architecture.markdown", "Architecture.pdf")]
    [InlineData("README.MD", "README.pdf")]
    [InlineData("release-notes-v1.2.md", "release-notes-v1.2.pdf")]
    [InlineData("CHANGELOG", "CHANGELOG.pdf")]
    [InlineData("My Test Document.md", "My Test Document.pdf")]
    public void SuggestFileNameReplacesTheMarkdownExtension(string input, string expected)
    {
        Assert.Equal(expected, PdfFileNaming.SuggestFileName(input));
    }

    [Fact]
    public void SuggestFileNameDropsTheDirectoryPortion()
    {
        Assert.Equal("Architecture.pdf", PdfFileNaming.SuggestFileName(@"C:\My Docs\notes\Architecture.md"));
    }

    [Fact]
    public void SuggestDirectoryReturnsTheDocumentsOwnFolder()
    {
        var path = Path.Combine(Path.GetTempPath(), "notes", "Architecture.md");

        Assert.Equal(Path.GetDirectoryName(Path.GetFullPath(path)), PdfFileNaming.SuggestDirectory(path));
    }

    [Fact]
    public void SuggestDirectoryReturnsNullForBlankInput()
    {
        Assert.Null(PdfFileNaming.SuggestDirectory("   "));
    }
}
