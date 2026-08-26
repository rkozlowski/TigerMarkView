using TigerMarkView.Core.Monitoring;

namespace TigerMarkView.Core.Tests.Monitoring;

public class FileStateTransitionsTests
{
    private static readonly DateTime Rendered = new(2026, 8, 8, 10, 0, 0, DateTimeKind.Utc);

    private static FileViewState Initial() =>
        FileViewState.Initial("C:\\doc.md", ReloadMode.Automatic) with
        {
            RenderedTimestampUtc = Rendered,
            DiskTimestampUtc = Rendered,
            LastReloadTimestampUtc = Rendered,
        };

    [Fact]
    public void ObserveDiskTimestampUpdatesDiskTimeAndClearsError()
    {
        var state = Initial() with { ErrorMessage = "stale error" };
        var newDiskTime = Rendered.AddMinutes(10);

        var result = FileStateTransitions.ObserveDiskTimestamp(state, newDiskTime);

        Assert.Equal(newDiskTime, result.DiskTimestampUtc);
        Assert.Equal(Rendered, result.RenderedTimestampUtc);
        Assert.False(result.HasError);
        Assert.True(result.IsNewerOnDisk);
    }

    [Fact]
    public void ReloadSucceededUpdatesAllThreeTimestampsAndClearsStaleState()
    {
        var state = Initial() with { DiskTimestampUtc = Rendered.AddMinutes(10) };
        var newVersion = Rendered.AddMinutes(10);
        var reloadTime = Rendered.AddMinutes(10).AddSeconds(1);

        var result = FileStateTransitions.ReloadSucceeded(state, newVersion, reloadTime);

        Assert.Equal(newVersion, result.RenderedTimestampUtc);
        Assert.Equal(newVersion, result.DiskTimestampUtc);
        Assert.Equal(reloadTime, result.LastReloadTimestampUtc);
        Assert.False(result.IsNewerOnDisk);
        Assert.False(result.HasError);
        Assert.Equal(DocumentStatusLevel.RecentlyReloaded, result.GetStatusLevel(reloadTime));
    }

    [Fact]
    public void ReloadFailedOnlySetsErrorAndDoesNotAdvanceTimestamps()
    {
        var state = Initial();

        var result = FileStateTransitions.WithError(state, "Access denied.");

        Assert.Equal("Access denied.", result.ErrorMessage);
        Assert.Equal(state.RenderedTimestampUtc, result.RenderedTimestampUtc);
        Assert.Equal(state.DiskTimestampUtc, result.DiskTimestampUtc);
        Assert.Equal(state.LastReloadTimestampUtc, result.LastReloadTimestampUtc);
        Assert.Equal(DocumentStatusLevel.Error, result.GetStatusLevel(Rendered));
    }

    [Fact]
    public void WithReloadModeOnlyChangesTheMode()
    {
        var state = Initial();

        var result = FileStateTransitions.WithReloadMode(state, ReloadMode.Confirm);

        Assert.Equal(ReloadMode.Confirm, result.ReloadMode);
        Assert.Equal(state.RenderedTimestampUtc, result.RenderedTimestampUtc);
        Assert.Equal(state.DiskTimestampUtc, result.DiskTimestampUtc);
    }
}
