using TigerMarkView.Core.Exporting;

namespace TigerMarkView.Core.Tests.Exporting;

public class ExportedPdfRegistryTests
{
    private const string DocumentA = @"C:\Docs\README.md";
    private const string DocumentB = @"C:\Docs\notes\Architecture.md";
    private const string ExportA = @"C:\Exports\README.pdf";
    private const string ExportB = @"C:\Exports\Architecture.pdf";

    [Fact]
    public void ASuccessfulExportIsRememberedForItsDocument()
    {
        var registry = new ExportedPdfRegistry();

        registry.Record(DocumentA, ExportA);

        Assert.Equal(ExportA, registry.Find(DocumentA));
    }

    [Fact]
    public void ALaterExportOfTheSameDocumentReplacesTheEarlierOne()
    {
        var registry = new ExportedPdfRegistry();

        registry.Record(DocumentA, ExportA);
        registry.Record(DocumentA, @"C:\Exports\README (final).pdf");

        Assert.Equal(@"C:\Exports\README (final).pdf", registry.Find(DocumentA));
    }

    /// <summary>
    /// The failed/cancelled case is expressed as an absence of <see cref="ExportedPdfRegistry.Record"/>:
    /// nothing but a success records anything, so the previous successful path survives untouched.
    /// </summary>
    [Fact]
    public void AnExportThatIsNeverRecordedLeavesThePreviousPathInPlace()
    {
        var registry = new ExportedPdfRegistry();
        registry.Record(DocumentA, ExportA);

        // A cancelled save dialog or a failed export reaches this point having recorded nothing.

        Assert.Equal(ExportA, registry.Find(DocumentA));
    }

    [Fact]
    public void ADocumentThatWasNeverExportedHasNoRememberedPath()
    {
        var registry = new ExportedPdfRegistry();
        registry.Record(DocumentA, ExportA);

        Assert.Null(registry.Find(DocumentB));
    }

    [Fact]
    public void EachDocumentKeepsItsOwnExport()
    {
        var registry = new ExportedPdfRegistry();

        registry.Record(DocumentA, ExportA);
        registry.Record(DocumentB, ExportB);

        Assert.Equal(ExportA, registry.Find(DocumentA));
        Assert.Equal(ExportB, registry.Find(DocumentB));
    }

    /// <summary>
    /// Export A, move to B (nothing offered), come back to A (A's export is offered again), re-export A
    /// (the latest path wins) — the whole per-document policy in one pass.
    /// </summary>
    [Fact]
    public void ReturningToAnExportedDocumentFindsItsExportAgain()
    {
        var registry = new ExportedPdfRegistry();
        var current = DocumentA;

        registry.Record(current, ExportA);
        Assert.Equal(ExportA, registry.Find(current));

        current = DocumentB;
        Assert.Null(registry.Find(current));

        current = DocumentA;
        Assert.Equal(ExportA, registry.Find(current));

        registry.Record(current, @"C:\Exports\README v2.pdf");
        Assert.Equal(@"C:\Exports\README v2.pdf", registry.Find(current));
    }

    [Fact]
    public void DocumentPathsAreComparedCaseInsensitivelyLikeWindowsPaths()
    {
        var registry = new ExportedPdfRegistry();

        registry.Record(DocumentA, ExportA);

        Assert.Equal(ExportA, registry.Find(@"c:\docs\readme.MD"));
    }

    [Fact]
    public void TryFindReportsWhetherAnExportIsKnown()
    {
        var registry = new ExportedPdfRegistry();
        registry.Record(DocumentA, ExportA);

        Assert.True(registry.TryFind(DocumentA, out var found));
        Assert.Equal(ExportA, found);

        Assert.False(registry.TryFind(DocumentB, out var missing));
        Assert.Null(missing);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void ABlankDocumentPathFindsNothingRatherThanThrowing(string? documentPath)
    {
        var registry = new ExportedPdfRegistry();
        registry.Record(DocumentA, ExportA);

        Assert.Null(registry.Find(documentPath));
        Assert.False(registry.TryFind(documentPath, out _));
    }

    [Fact]
    public void ForgettingAnExportRemovesEveryDocumentPointingAtIt()
    {
        var registry = new ExportedPdfRegistry();
        registry.Record(DocumentA, ExportA);
        registry.Record(DocumentB, ExportA);

        Assert.True(registry.ForgetExport(@"c:\exports\readme.pdf"));

        Assert.Null(registry.Find(DocumentA));
        Assert.Null(registry.Find(DocumentB));
    }

    [Fact]
    public void ForgettingLeavesUnrelatedExportsAlone()
    {
        var registry = new ExportedPdfRegistry();
        registry.Record(DocumentA, ExportA);
        registry.Record(DocumentB, ExportB);

        Assert.True(registry.ForgetExport(ExportA));

        Assert.Null(registry.Find(DocumentA));
        Assert.Equal(ExportB, registry.Find(DocumentB));
    }

    [Fact]
    public void ForgettingAnUnknownExportReportsThatNothingChanged()
    {
        var registry = new ExportedPdfRegistry();
        registry.Record(DocumentA, ExportA);

        Assert.False(registry.ForgetExport(ExportB));
        Assert.False(registry.ForgetExport(null));

        Assert.Equal(ExportA, registry.Find(DocumentA));
    }

    [Fact]
    public void RecordingRejectsBlankPaths()
    {
        var registry = new ExportedPdfRegistry();

        Assert.Throws<ArgumentException>(() => registry.Record("  ", ExportA));
        Assert.Throws<ArgumentException>(() => registry.Record(DocumentA, "  "));
    }
}
