using TigerMarkView.Core.Settings;

namespace TigerMarkView.Core.Tests.Settings;

/// <summary>
/// Load Remote Images as already-open windows apply it. Each test plays windows against one settings
/// file the way separate processes do: separate <see cref="ApplicationSettingsFile"/> instances and
/// separate <see cref="SharedRemoteImagesSetting"/>s, each created before the other window's change.
/// </summary>
public sealed class SharedRemoteImagesSettingTests : IDisposable
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
    public void AnOpenWindowFollowsRemoteImagesTurnedOffAndBackOnInAnotherWindow()
    {
        var fileA = new ApplicationSettingsFile(FilePath);
        var windowA = new SharedRemoteImagesSetting(fileA.TryLoad);
        var windowB = new SharedRemoteImagesSetting(new ApplicationSettingsFile(FilePath).TryLoad);
        Assert.True(windowA.AllowedNow());
        Assert.True(windowB.AllowedNow());

        windowA.Chosen(false, fileA.Update(settings => settings.LoadRemoteImages = false) is not null);
        Assert.False(windowA.AllowedNow());
        Assert.False(windowB.AllowedNow());

        windowA.Chosen(true, fileA.Update(settings => settings.LoadRemoteImages = true) is not null);
        Assert.True(windowA.AllowedNow());
        Assert.True(windowB.AllowedNow());
    }

    [Fact]
    public void ASettingsFileThatCannotBeReadRefusesWebImages()
    {
        Assert.NotNull(new ApplicationSettingsFile(FilePath).Update(settings => settings.LoadRemoteImages = true));
        var window = new SharedRemoteImagesSetting(new ApplicationSettingsFile(FilePath).TryLoad);

        using (new FileStream(FilePath, FileMode.Open, FileAccess.Read, FileShare.None))
        {
            Assert.False(window.AllowedNow());
        }

        Assert.True(window.AllowedNow());
    }

    /// <summary>
    /// A read-only profile: the reader turns remote images off, the shared file cannot take it and
    /// still says on. The window that was told must not go on loading them.
    /// </summary>
    [Fact]
    public void ATurnOffThatCouldNotBeSharedStillHoldsInTheWindowThatMadeIt()
    {
        var shared = ApplicationSettings.CreateDefault();
        var window = new SharedRemoteImagesSetting(() => shared);

        window.Chosen(enabled: false, shared: false);
        Assert.False(window.AllowedNow());

        window.Chosen(enabled: true, shared: true);
        Assert.True(window.AllowedNow());
    }

    [Fact]
    public void TurningOnCannotOverruleTheSharedFileThatSaysOff()
    {
        var shared = ApplicationSettings.CreateDefault();
        shared.LoadRemoteImages = false;
        var window = new SharedRemoteImagesSetting(() => shared);

        window.Chosen(enabled: true, shared: false);

        Assert.False(window.AllowedNow());
    }

    [Fact]
    public void WithNoSettingsFileRemoteImagesAreOnByDefault()
    {
        Assert.True(new SharedRemoteImagesSetting(new ApplicationSettingsFile(FilePath).TryLoad).AllowedNow());
        Assert.False(File.Exists(FilePath));
    }
}
