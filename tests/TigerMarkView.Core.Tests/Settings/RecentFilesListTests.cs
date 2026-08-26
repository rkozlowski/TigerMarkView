using TigerMarkView.Core.Settings;

namespace TigerMarkView.Core.Tests.Settings;

public class RecentFilesListTests
{
    [Fact]
    public void NewestOpenedFileComesFirst()
    {
        var list = RecentFilesList.Add(RecentFilesList.Add([], @"C:\a.md"), @"C:\b.md");

        Assert.Equal(new[] { @"C:\b.md", @"C:\a.md" }, list);
    }

    [Fact]
    public void ReopeningAFileMovesItToTheFrontInsteadOfDuplicatingIt()
    {
        var list = RecentFilesList.Add([@"C:\a.md", @"C:\b.md", @"C:\c.md"], @"C:\c.md");

        Assert.Equal(new[] { @"C:\c.md", @"C:\a.md", @"C:\b.md" }, list);
    }

    /// <summary>Windows paths are case-insensitive, so two casings of one file are one entry.</summary>
    [Fact]
    public void DuplicatesAreDetectedCaseInsensitively()
    {
        var list = RecentFilesList.Add([@"C:\Docs\Notes.md"], @"c:\docs\notes.MD");

        Assert.Equal(new[] { @"c:\docs\notes.MD" }, list);
    }

    [Fact]
    public void TheListIsCappedAtTheMaximumKeepingTheMostRecent()
    {
        var list = new List<string>();
        for (var i = 1; i <= 15; i++)
        {
            list = RecentFilesList.Add(list, $@"C:\file{i}.md");
        }

        Assert.Equal(RecentFilesList.DefaultMaximum, list.Count);
        Assert.Equal(@"C:\file15.md", list[0]);
        Assert.Equal(@"C:\file6.md", list[^1]);
        Assert.DoesNotContain(@"C:\file5.md", list);
    }

    [Fact]
    public void AddRespectsAnExplicitMaximum()
    {
        var list = RecentFilesList.Add([@"C:\a.md", @"C:\b.md", @"C:\c.md"], @"C:\d.md", maximum: 2);

        Assert.Equal(new[] { @"C:\d.md", @"C:\a.md" }, list);
    }

    [Fact]
    public void NormalizeDropsBlankAndDuplicateEntriesFromAHandEditedFile()
    {
        var list = RecentFilesList.Normalize([@"C:\a.md", "", "   ", null, @"C:\A.MD", @"C:\b.md"]);

        Assert.Equal(new[] { @"C:\a.md", @"C:\b.md" }, list);
    }

    [Fact]
    public void NormalizeHandlesAMissingList()
    {
        Assert.Empty(RecentFilesList.Normalize(null));
    }

    [Fact]
    public void AddRejectsABlankPath()
    {
        Assert.Throws<ArgumentException>(() => RecentFilesList.Add([], "  "));
    }
}
