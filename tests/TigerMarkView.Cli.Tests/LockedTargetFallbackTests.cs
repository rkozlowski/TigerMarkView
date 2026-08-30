namespace TigerMarkView.Cli.Tests;

/// <summary>
/// The half of <c>--timestamped-fallback</c> that does not need a browser: where the PDF is written
/// first, and what happens when it is moved over a target somebody else is holding.
/// </summary>
/// <remarks>
/// The locked case is exercised against a genuinely locked file rather than a mock, because the whole
/// point of the mode is what Windows does when a PDF is open in a reader — and nothing but the real
/// file system can say that.
/// </remarks>
public class LockedTargetFallbackTests : IDisposable
{
    private readonly string _dir;

    public LockedTargetFallbackTests()
    {
        _dir = Path.Combine(Path.GetTempPath(), "TigerMarkViewCliTests_" + Guid.NewGuid());
        Directory.CreateDirectory(_dir);
    }

    public void Dispose() => Directory.Delete(_dir, recursive: true);

    private string Write(string name, string content)
    {
        var path = Path.Combine(_dir, name);
        File.WriteAllText(path, content);
        return path;
    }

    [Fact]
    public void ThePdfIsWrittenBesideTheTargetUnderATimestampedName()
    {
        var moment = new DateTimeOffset(2026, 8, 30, 14, 25, 30, TimeSpan.FromHours(2));
        var target = Path.Combine(_dir, "Report.pdf");

        Assert.Equal(
            Path.Combine(_dir, "Report-20260830142530.pdf"),
            LockedTargetFallback.PathFor(target, moment));
    }

    [Fact]
    public void ReplacingAnAbsentTargetSimplyRenames()
    {
        var written = Write("Report-20260830142530.pdf", "new");
        var target = Path.Combine(_dir, "Report.pdf");

        Assert.True(LockedTargetFallback.TryReplace(written, target, out var error));
        Assert.Empty(error);
        Assert.Equal("new", File.ReadAllText(target));
        Assert.False(File.Exists(written));
    }

    [Fact]
    public void ReplacingAnExistingTargetOverwritesIt()
    {
        var written = Write("Report-20260830142530.pdf", "new");
        var target = Write("Report.pdf", "old");

        Assert.True(LockedTargetFallback.TryReplace(written, target, out _));
        Assert.Equal("new", File.ReadAllText(target));
        Assert.False(File.Exists(written));
    }

    /// <summary>
    /// The reason the mode exists: the reader still has the PDF, under a name that says when it was
    /// made, and the file they could not overwrite is untouched.
    /// </summary>
    [Fact]
    public void ALockedTargetIsLeftAloneAndTheWrittenPdfIsKept()
    {
        var written = Write("Report-20260830142530.pdf", "new");
        var target = Write("Report.pdf", "old");

        var holder = new FileStream(target, FileMode.Open, FileAccess.Read, FileShare.None);
        try
        {
            Assert.False(LockedTargetFallback.TryReplace(written, target, out var error));
            Assert.False(string.IsNullOrWhiteSpace(error));

            Assert.True(File.Exists(written));
            Assert.Equal("new", File.ReadAllText(written));
        }
        finally
        {
            holder.Dispose();
        }

        // And once the reader closes it, what they still have is the older PDF plus a timestamped one.
        Assert.Equal("old", File.ReadAllText(target));
    }

    /// <summary>A target in a folder that does not exist cannot be replaced, and nothing is lost.</summary>
    [Fact]
    public void AnUnreachableTargetKeepsTheWrittenPdfToo()
    {
        var written = Write("Report-20260830142530.pdf", "new");
        var target = Path.Combine(_dir, "no-such-folder", "Report.pdf");

        Assert.False(LockedTargetFallback.TryReplace(written, target, out var error));
        Assert.False(string.IsNullOrWhiteSpace(error));
        Assert.True(File.Exists(written));
    }
}
