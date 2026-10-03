using TigerMarkView.Core.Editing;
using TigerMarkView.Core.Exporting;
using TigerMarkView.Core.Rendering;
using TigerMarkView.Core.Settings;

namespace TigerMarkView.Core.Tests.Settings;

/// <summary>
/// One settings file shared by several windows, each holding its own copy loaded when it started. Each
/// test plays two (or more) windows against one file the way two processes do: separate
/// <see cref="ApplicationSettingsFile"/> instances, separate in-memory settings, one path.
/// </summary>
public sealed class ApplicationSettingsFileTests : IDisposable
{
    private readonly string _folder = Path.Combine(Path.GetTempPath(), "TigerMarkView.Tests", Guid.NewGuid().ToString("N"));

    private string FilePath => Path.Combine(_folder, "settings.json");

    public void Dispose()
    {
        if (Directory.Exists(_folder))
        {
            Directory.Delete(_folder, recursive: true);
        }
    }

    [Fact]
    public void RecentFilesClearedInOneWindowStayClearedWhenAnotherWindowLaterChangesASetting()
    {
        Seed(settings =>
        {
            settings.AddRecentFile(@"C:\docs\b.md");
            settings.AddRecentFile(@"C:\docs\a.md");
        });

        var windowA = new ApplicationSettingsFile(FilePath);
        var windowB = new ApplicationSettingsFile(FilePath);
        var copyB = windowB.Load();
        Assert.Equal(2, copyB.RecentFiles.Count);

        windowA.Update(settings => settings.ClearRecentFiles());

        // Window B still remembers both files, then changes three unrelated things.
        windowB.Update(settings => settings.Theme = MarkdownTheme.Dark);
        windowB.Update(settings => settings.ApplyEditorConfiguration(EditorConfiguration.VisualStudioCode()));
        windowB.Update(settings => settings.Window.Width = 900);

        var saved = new ApplicationSettingsFile(FilePath).Load();
        Assert.Empty(saved.RecentFiles);
        Assert.Equal(MarkdownTheme.Dark, saved.Theme);
        Assert.Equal(EditorType.VisualStudioCode, saved.EditorType);
        Assert.Equal(900, saved.Window.Width);
    }

    [Fact]
    public void RecentFilesOpenedInTwoWindowsAreBothKeptMostRecentFirst()
    {
        var windowA = new ApplicationSettingsFile(FilePath);
        var windowB = new ApplicationSettingsFile(FilePath);

        windowA.Update(settings => settings.AddRecentFile(@"C:\docs\a.md"));
        windowB.Update(settings => settings.AddRecentFile(@"C:\docs\b.md"));
        var merged = windowA.Update(settings => settings.AddRecentFile(@"C:\docs\c.md"));

        Assert.NotNull(merged);
        Assert.Equal([@"C:\docs\c.md", @"C:\docs\b.md", @"C:\docs\a.md"], merged.RecentFiles);
        Assert.Equal(merged.RecentFiles, new ApplicationSettingsFile(FilePath).Load().RecentFiles);
    }

    [Fact]
    public void ReopeningAFileAnotherWindowAddedMovesItToTheTopWithoutDuplicatingIt()
    {
        var windowA = new ApplicationSettingsFile(FilePath);
        var windowB = new ApplicationSettingsFile(FilePath);

        windowA.Update(settings => settings.AddRecentFile(@"C:\docs\a.md"));
        windowB.Update(settings => settings.AddRecentFile(@"C:\docs\b.md"));
        var merged = windowB.Update(settings => settings.AddRecentFile(@"c:\DOCS\A.md"));

        Assert.NotNull(merged);
        Assert.Equal([@"c:\DOCS\A.md", @"C:\docs\b.md"], merged.RecentFiles);
    }

    [Fact]
    public void EachWindowChangesOnlyTheSettingItTouched()
    {
        var windowA = new ApplicationSettingsFile(FilePath);
        var windowB = new ApplicationSettingsFile(FilePath);

        windowA.Update(settings => settings.PdfPaperSize = PdfPaperSize.Letter);
        windowB.Update(settings => settings.LoadRemoteImages = false);
        windowA.Update(settings => settings.SyntaxHighlighting = true);
        windowB.Update(settings => settings.StatusBarVisible = false);
        windowA.Update(settings => settings.AddRecentFile(@"C:\docs\a.md"));

        var saved = new ApplicationSettingsFile(FilePath).Load();
        Assert.Equal(PdfPaperSize.Letter, saved.PdfPaperSize);
        Assert.False(saved.LoadRemoteImages);
        Assert.True(saved.SyntaxHighlighting);
        Assert.False(saved.StatusBarVisible);
        Assert.Equal([@"C:\docs\a.md"], saved.RecentFiles);
    }

    /// <summary>
    /// The lock is what keeps simultaneous read-change-write cycles from overwriting each other; every
    /// one of many concurrent additions has to survive.
    /// </summary>
    [Fact]
    public void ConcurrentUpdatesFromManyWindowsAreAllKept()
    {
        const int Windows = 8;
        var paths = Enumerable.Range(0, Windows).Select(i => $@"C:\docs\{i}.md").ToArray();

        Parallel.ForEach(paths, new ParallelOptions { MaxDegreeOfParallelism = Windows }, path =>
            Assert.NotNull(new ApplicationSettingsFile(FilePath).Update(settings => settings.AddRecentFile(path))));

        var saved = new ApplicationSettingsFile(FilePath).Load();
        Assert.Equal(paths.OrderBy(path => path), saved.RecentFiles.OrderBy(path => path));
    }

    [Fact]
    public void AnUpdateWithNoFileStartsFromTheDefaults()
    {
        var written = new ApplicationSettingsFile(FilePath).Update(settings => settings.Theme = MarkdownTheme.Dark);

        Assert.NotNull(written);
        var saved = new ApplicationSettingsFile(FilePath).Load();
        Assert.Equal(MarkdownTheme.Dark, saved.Theme);
        Assert.True(saved.LoadRemoteImages);
        Assert.Empty(saved.RecentFiles);
    }

    [Fact]
    public void AnUnparseableFileIsSetAsideAndTheUpdateStartsAfresh()
    {
        Directory.CreateDirectory(_folder);
        File.WriteAllText(FilePath, "{ this is not json");

        var written = new ApplicationSettingsFile(FilePath).Update(settings => settings.Theme = MarkdownTheme.Dark);

        Assert.NotNull(written);
        Assert.Equal("{ this is not json", File.ReadAllText(FilePath + ApplicationSettingsFile.InvalidSuffix));
        Assert.Equal(MarkdownTheme.Dark, new ApplicationSettingsFile(FilePath).Load().Theme);
    }

    /// <summary>
    /// A file that exists but cannot be read right now must not be replaced by defaults plus one
    /// change: that would lose everything else the reader had.
    /// </summary>
    [Fact]
    public void AFileThatCannotBeReadIsLeftAloneRatherThanOverwrittenWithDefaults()
    {
        Seed(settings =>
        {
            settings.Theme = MarkdownTheme.Dark;
            settings.AddRecentFile(@"C:\docs\a.md");
        });
        var before = File.ReadAllBytes(FilePath);

        ApplicationSettings? written;
        using (new FileStream(FilePath, FileMode.Open, FileAccess.Read, FileShare.None))
        {
            written = new ApplicationSettingsFile(FilePath).Update(settings => settings.PdfPageNumbers = true);
        }

        Assert.Null(written);
        Assert.Equal(before, File.ReadAllBytes(FilePath));
    }

    [Fact]
    public void AnUpdateLeavesNoTemporaryFileBehind()
    {
        new ApplicationSettingsFile(FilePath).Update(settings => settings.Theme = MarkdownTheme.Dark);

        Assert.Equal(["settings.json"], Directory.GetFiles(_folder).Select(Path.GetFileName));
    }

    [Fact]
    public void LoadNeverThrowsForAMissingFile()
    {
        var loaded = new ApplicationSettingsFile(FilePath).Load();

        Assert.Equal(MarkdownTheme.Light, loaded.Theme);
        Assert.False(File.Exists(FilePath));
    }

    private void Seed(Action<ApplicationSettings> change) =>
        Assert.NotNull(new ApplicationSettingsFile(FilePath).Update(change));
}
