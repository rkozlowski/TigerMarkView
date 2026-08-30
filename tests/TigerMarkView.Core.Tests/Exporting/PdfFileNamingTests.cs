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

    /// <summary>
    /// The name a PDF is written under before it is moved over a target that might be locked. Sortable,
    /// second-resolution, and beside the file it is standing in for.
    /// </summary>
    [Theory]
    [InlineData(@"C:\Reports\Quarterly.pdf", @"C:\Reports\Quarterly-20260830142530.pdf")]
    [InlineData(@"C:\Reports\release-notes-v1.2.pdf", @"C:\Reports\release-notes-v1.2-20260830142530.pdf")]
    [InlineData(@"C:\Reports\My Report.pdf", @"C:\Reports\My Report-20260830142530.pdf")]
    public void TimestampedVariantNamesASiblingForTheMomentItWasWritten(string input, string expected)
    {
        var moment = new DateTimeOffset(2026, 8, 30, 14, 25, 30, TimeSpan.FromHours(2));

        Assert.Equal(expected, PdfFileNaming.TimestampedVariant(input, moment));
    }

    /// <summary>The suffix is the local wall-clock reading, not an instant normalised to UTC.</summary>
    [Fact]
    public void TimestampedVariantUsesTheOffsetItWasGiven()
    {
        var path = @"C:\Reports\Quarterly.pdf";
        var berlin = new DateTimeOffset(2026, 8, 30, 14, 25, 30, TimeSpan.FromHours(2));

        Assert.Equal(@"C:\Reports\Quarterly-20260830142530.pdf", PdfFileNaming.TimestampedVariant(path, berlin));
        Assert.Equal(
            @"C:\Reports\Quarterly-20260830122530.pdf",
            PdfFileNaming.TimestampedVariant(path, berlin.ToUniversalTime()));
    }

    /// <summary>A relative path keeps its folder, because the sibling has to land beside the target.</summary>
    [Fact]
    public void TimestampedVariantStaysInTheTargetsFolder()
    {
        var moment = new DateTimeOffset(2026, 1, 2, 3, 4, 5, TimeSpan.Zero);
        var variant = PdfFileNaming.TimestampedVariant(Path.Combine("reports", "out.pdf"), moment);

        Assert.Equal(Path.GetFullPath(Path.Combine("reports", "out-20260102030405.pdf")), variant);
    }
}
