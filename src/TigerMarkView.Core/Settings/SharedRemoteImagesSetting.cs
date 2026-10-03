namespace TigerMarkView.Core.Settings;

/// <summary>
/// The reader's Load Remote Images choice as one window must apply it: the value in the settings file
/// every TigerMarkView window shares, read at the moment a web image would be requested.
/// </summary>
/// <remarks>
/// <para>
/// Every window is its own process with its own copy of the settings, taken when it started. Turning
/// remote images off promises that no window fetches them any more, so that copy must never be what
/// authorizes a web image: a window still open from before another window turned them off would go on
/// fetching them. <see cref="AllowedNow"/> therefore asks the shared file each time, and turning them
/// back on in any window applies to every window the same way.
/// </para>
/// <para>
/// It fails closed. A settings file that exists but cannot be read just now refuses web images rather
/// than falling back to the default, which is on. And a window whose own choice to turn them off could
/// not be written to the shared file keeps that choice for itself: the shared file still saying on must
/// not overrule what the reader just chose in this window.
/// </para>
/// </remarks>
public sealed class SharedRemoteImagesSetting
{
    private readonly Func<ApplicationSettings?> _readShared;
    private bool _unsharedOff;

    /// <param name="readShared">
    /// Reads the shared settings as they are now, <see langword="null"/> when they cannot be read —
    /// <see cref="ApplicationSettingsFile.TryLoad"/>.
    /// </param>
    public SharedRemoteImagesSetting(Func<ApplicationSettings?> readShared)
    {
        ArgumentNullException.ThrowIfNull(readShared);
        _readShared = readShared;
    }

    /// <summary>Whether <c>http</c>/<c>https</c> images may load now, in this window.</summary>
    public bool AllowedNow() => !_unsharedOff && (_readShared()?.LoadRemoteImages ?? false);

    /// <summary>
    /// Records the choice this window's reader made, once it has been written to the shared file or has
    /// failed to be.
    /// </summary>
    public void Chosen(bool enabled, bool shared) => _unsharedOff = !enabled && !shared;
}
