using TigerMarkView.Core.Exporting;

namespace TigerMarkView.Core.Tests.Exporting;

public class PdfExportRequestValidatorTests
{
    private static string ValidOutputPath() => Path.Combine(Path.GetTempPath(), "tigermarkview-test.pdf");

    [Fact]
    public void AcceptsAWellFormedRequest()
    {
        var request = new PdfExportRequest("<html><body>Hi</body></html>", ValidOutputPath());

        Assert.Null(PdfExportRequestValidator.Validate(request));
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public void RejectsEmptyHtml(string html)
    {
        var request = new PdfExportRequest(html, ValidOutputPath());

        Assert.Equal("There is nothing to export.", PdfExportRequestValidator.Validate(request));
    }

    [Fact]
    public void RejectsEmptyOutputPath()
    {
        var request = new PdfExportRequest("<html></html>", "   ");

        Assert.Equal("No output file was specified.", PdfExportRequestValidator.Validate(request));
    }

    [Fact]
    public void RejectsAnOutputFolderThatDoesNotExist()
    {
        var path = Path.Combine(Path.GetTempPath(), $"tigermarkview-missing-{Guid.NewGuid():N}", "out.pdf");

        var error = PdfExportRequestValidator.Validate(new PdfExportRequest("<html></html>", path));

        Assert.NotNull(error);
        Assert.StartsWith("Output folder does not exist:", error);
    }

    [Fact]
    public void RejectsAPathThatCannotBeParsed()
    {
        var request = new PdfExportRequest("<html></html>", "C:\\bad\0path\\out.pdf");

        var error = PdfExportRequestValidator.Validate(request);

        Assert.NotNull(error);
        Assert.StartsWith("Invalid output path:", error);
    }

    [Fact]
    public void RejectsANonPositivePageSize()
    {
        var request = new PdfExportRequest(
            "<html></html>",
            ValidOutputPath(),
            new PdfPageSetup(0, 297, PdfPageMargins.Normal));

        Assert.Equal("Page size must be positive.", PdfExportRequestValidator.Validate(request));
    }

    [Fact]
    public void DefaultsToA4WhenNoPageSetupIsGiven()
    {
        var request = new PdfExportRequest("<html></html>", ValidOutputPath());

        Assert.Equal(PdfPageSetup.Default, request.PageSetup);

        // A4 is defined in millimetres; the page setup must carry it at full precision rather than
        // the rounded 8.27 x 11.69 inches, which is a third of a point short of the real page.
        Assert.Equal(210.0, request.PageSetup.WidthInches * 25.4, 6);
        Assert.Equal(297.0, request.PageSetup.HeightInches * 25.4, 6);
    }
}
