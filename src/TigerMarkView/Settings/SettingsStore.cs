using System;
using System.IO;
using TigerMarkView.Core.Settings;

namespace TigerMarkView.Settings;

/// <summary>
/// Where <see cref="ApplicationSettings"/> live: a single JSON file under
/// <c>%LocalAppData%\TigerMarkView</c>. This is the only place that knows the location —
/// <see cref="TigerMarkView.Core.Settings"/> owns the settings' shape and how the shared file is
/// changed (<see cref="ApplicationSettingsFile"/>), this owns where it is.
/// </summary>
/// <remarks>
/// <para>
/// LocalAppData rather than the registry (never) or roaming AppData: the persisted values —
/// window geometry, a local editor's executable path, local recent-file paths — are machine
/// specific, so roaming them to another PC would restore geometry and paths that do not apply there.
/// </para>
/// <para>
/// There is deliberately no "save these settings" member. Every window is a separate process sharing
/// this one file, so a window records each change it makes through <see cref="Update"/>, which merges
/// that change into what is on disk now instead of writing back the window's whole, possibly stale,
/// copy. Neither member ever throws.
/// </para>
/// </remarks>
public sealed class SettingsStore
{
    public const string FileName = "settings.json";

    private readonly ApplicationSettingsFile _file;

    public SettingsStore() : this(DefaultFilePath())
    {
    }

    public SettingsStore(string filePath)
    {
        _file = new ApplicationSettingsFile(filePath);
    }

    public string FilePath => _file.FilePath;

    public static string DefaultDirectory() => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "TigerMarkView");

    public static string DefaultFilePath() => Path.Combine(DefaultDirectory(), FileName);

    /// <inheritdoc cref="ApplicationSettingsFile.Load"/>
    public ApplicationSettings Load() => _file.Load();

    /// <inheritdoc cref="ApplicationSettingsFile.Update"/>
    public ApplicationSettings? Update(Action<ApplicationSettings> change) => _file.Update(change);
}
