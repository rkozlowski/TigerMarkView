using TigerMarkView.Core.Monitoring;

namespace TigerMarkView.Core.Tests.Monitoring;

public class FileViewStateTests
{
    private static readonly DateTime Base = new(2026, 8, 8, 10, 0, 0, DateTimeKind.Utc);

    private static FileViewState StateWith(
        DateTime? rendered = null,
        DateTime? disk = null,
        DateTime? lastReload = null,
        string? error = null) =>
        new("C:\\doc.md", rendered, disk, lastReload, ReloadMode.Manual, error);

    [Fact]
    public void ErrorTakesPriorityOverEverythingElse()
    {
        // Newer-on-disk AND recently reloaded are both true, but an error must still win.
        var state = StateWith(
            rendered: Base,
            disk: Base.AddMinutes(5),
            lastReload: Base.AddSeconds(-1),
            error: "File not found.");

        Assert.Equal(DocumentStatusLevel.Error, state.GetStatusLevel(Base));
    }

    [Fact]
    public void NewerOnDiskTakesPriorityOverRecentlyReloaded()
    {
        var state = StateWith(rendered: Base, disk: Base.AddMinutes(1), lastReload: Base);

        Assert.Equal(DocumentStatusLevel.NewerOnDisk, state.GetStatusLevel(Base));
    }

    [Fact]
    public void RecentlyReloadedTakesPriorityOverNeutral()
    {
        var state = StateWith(rendered: Base, disk: Base, lastReload: Base);
        var now = Base.AddMinutes(1);

        Assert.Equal(DocumentStatusLevel.RecentlyReloaded, state.GetStatusLevel(now));
    }

    [Fact]
    public void FallsBackToNeutralWhenNothingElseApplies()
    {
        var state = StateWith(rendered: Base, disk: Base, lastReload: Base);
        var now = Base.Add(FileViewState.DefaultRecentReloadWindow).AddSeconds(1);

        Assert.Equal(DocumentStatusLevel.Neutral, state.GetStatusLevel(now));
    }

    [Fact]
    public void BrandNewDocumentWithNoTimestampsIsNeutral()
    {
        var state = FileViewState.Initial("C:\\doc.md", ReloadMode.Confirm);

        Assert.Equal(DocumentStatusLevel.Neutral, state.GetStatusLevel(Base));
    }

    [Fact]
    public void ExternalChangeToANewerDiskTimestampProducesNewerOnDiskState()
    {
        var state = StateWith(rendered: Base, disk: Base);

        var afterExternalChange = state with { DiskTimestampUtc = Base.AddSeconds(5) };

        Assert.True(afterExternalChange.IsNewerOnDisk);
        Assert.Equal(DocumentStatusLevel.NewerOnDisk, afterExternalChange.GetStatusLevel(Base));
    }

    [Fact]
    public void RecentlyReloadedWindowExpiresExactlyAtTheBoundary()
    {
        var state = StateWith(rendered: Base, disk: Base, lastReload: Base);
        var window = TimeSpan.FromMinutes(2);

        Assert.Equal(DocumentStatusLevel.RecentlyReloaded, state.GetStatusLevel(Base.Add(window), window));
        Assert.Equal(DocumentStatusLevel.Neutral, state.GetStatusLevel(Base.Add(window).AddTicks(1), window));
    }
}
