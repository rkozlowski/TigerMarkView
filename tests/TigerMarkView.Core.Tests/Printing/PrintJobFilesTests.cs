using TigerMarkView.Core.Printing;

namespace TigerMarkView.Core.Tests.Printing;

/// <summary>
/// The rules the temporary PDFs printing produces have to obey. Every one of them exists to keep a
/// print from touching something that is not TigerMarkView's: the reader's folders, the reader's files,
/// or another print job's file.
/// </summary>
public class PrintJobFilesTests
{
    [Fact]
    public void PrintFilesLiveInTheApplicationsOwnTempFolder()
    {
        var directory = PrintJobFiles.DirectoryIn(@"C:\Temp");

        Assert.Equal(Path.Combine(@"C:\Temp", "TigerMarkView", "Print"), directory);
    }

    /// <summary>
    /// The single most important property: a print PDF is never written beside the document it came
    /// from, so printing can never overwrite, shadow, or clutter the reader's own folder.
    /// </summary>
    [Fact]
    public void APrintFileIsNeverWrittenBesideTheSourceDocument()
    {
        var path = PrintJobFiles.PathIn(@"C:\Temp", @"C:\Notes\Architecture.md", Guid.NewGuid());

        Assert.StartsWith(PrintJobFiles.DirectoryIn(@"C:\Temp"), path, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain(@"C:\Notes", path, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void APrintFileKeepsTheDocumentsNameSoItCanBeRecognised()
    {
        var name = PrintJobFiles.FileName(@"C:\Notes\Architecture.md", Guid.NewGuid());

        Assert.StartsWith("print-Architecture-", name, StringComparison.Ordinal);
        Assert.EndsWith(".pdf", name, StringComparison.Ordinal);
    }

    /// <summary>
    /// Two prints of the same document — in one session, or in two copies of the application running at
    /// once — must not land on the same path.
    /// </summary>
    [Fact]
    public void TwoPrintsOfOneDocumentNeverCollide()
    {
        var names = Enumerable
            .Range(0, 100)
            .Select(_ => PrintJobFiles.FileName(@"C:\Notes\Architecture.md", Guid.NewGuid()))
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        Assert.Equal(100, names.Count);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData(@"C:\Notes\...")]
    public void AnUnusableDocumentNameStillProducesAUsableFileName(string? markdownPath)
    {
        var name = PrintJobFiles.FileName(markdownPath, Guid.NewGuid());

        Assert.StartsWith("print-document-", name, StringComparison.Ordinal);
        Assert.Equal(-1, name.IndexOfAny(Path.GetInvalidFileNameChars()));
    }

    /// <summary>A long document name must not push the temp path past what Windows will accept.</summary>
    [Fact]
    public void AVeryLongDocumentNameIsShortened()
    {
        var name = PrintJobFiles.FileName(new string('a', 300) + ".md", Guid.NewGuid());

        Assert.True(name.Length < 100, $"name was {name.Length} characters");
    }

    /// <summary>
    /// Cleanup after a finished print is immediate, so only crash residue ever reaches this age. The
    /// threshold's whole job is to be far longer than any print job could possibly take.
    /// </summary>
    [Fact]
    public void TheStaleThresholdCannotRaceALivePrintJob()
    {
        Assert.True(PrintJobFiles.StaleAfter >= TimeSpan.FromHours(1));
    }

    [Fact]
    public void AFreshPrintFileIsNeverStale()
    {
        var now = new DateTime(2026, 8, 17, 12, 0, 0, DateTimeKind.Utc);

        Assert.False(PrintJobFiles.IsStale("print-Doc-abc.pdf", now.AddMinutes(-5), now));
    }

    [Fact]
    public void AnOldPrintFileIsStale()
    {
        var now = new DateTime(2026, 8, 17, 12, 0, 0, DateTimeKind.Utc);

        Assert.True(PrintJobFiles.IsStale("print-Doc-abc.pdf", now - PrintJobFiles.StaleAfter, now));
    }

    /// <summary>
    /// A sweep is a delete loop, so it has to be incapable of deleting anything that is not ours — even
    /// though the folder is the application's, and even though the file is old.
    /// </summary>
    [Theory]
    [InlineData("notes.pdf")]
    [InlineData("print-Doc-abc.txt")]
    [InlineData("export-abc.html")]
    [InlineData("")]
    public void ASweepNeverTouchesAFileItDidNotCreate(string fileName)
    {
        var now = new DateTime(2026, 8, 17, 12, 0, 0, DateTimeKind.Utc);

        Assert.False(PrintJobFiles.IsStale(fileName, now.AddYears(-1), now));
    }

    /// <summary>A clock that jumped backwards must not make every file look ancient — or brand new.</summary>
    [Fact]
    public void AFileWrittenInTheFutureIsNotStale()
    {
        var now = new DateTime(2026, 8, 17, 12, 0, 0, DateTimeKind.Utc);

        Assert.False(PrintJobFiles.IsStale("print-Doc-abc.pdf", now.AddDays(1), now));
    }

    /// <summary>A full path is accepted wherever a bare name is — the sweep enumerates paths.</summary>
    [Fact]
    public void StalenessIsJudgedOnTheFileNameNotTheWholePath()
    {
        var now = new DateTime(2026, 8, 17, 12, 0, 0, DateTimeKind.Utc);

        Assert.True(PrintJobFiles.IsStale(
            @"C:\Temp\TigerMarkView\Print\print-Doc-abc.pdf", now.AddDays(-3), now));
    }
}
