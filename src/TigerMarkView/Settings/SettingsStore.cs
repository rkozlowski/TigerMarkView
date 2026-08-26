using System;
using System.IO;
using System.Security;
using TigerMarkView.Core.Settings;

namespace TigerMarkView.Settings;

/// <summary>
/// Reads and writes <see cref="ApplicationSettings"/> as a single JSON file under
/// <c>%LocalAppData%\TigerMarkView</c>. This is the only place that knows where settings live —
/// <see cref="TigerMarkView.Core.Settings"/> owns their shape, this owns their location.
/// </summary>
/// <remarks>
/// <para>
/// LocalAppData rather than the registry (never) or roaming AppData: the persisted values —
/// window geometry, a local editor's executable path, local recent-file paths — are machine
/// specific, so roaming them to another PC would restore geometry and paths that do not apply there.
/// </para>
/// <para>
/// Neither <see cref="Load"/> nor <see cref="Save"/> ever throws. Settings are convenience data;
/// losing them is a minor annoyance, while failing to start (or crashing on exit) because of a
/// bad file or a read-only profile directory would not be.
/// </para>
/// </remarks>
public sealed class SettingsStore
{
    public const string FileName = "settings.json";

    /// <summary>Suffix given to a file that could not be parsed, so the user can inspect or restore it.</summary>
    private const string InvalidSuffix = ".invalid";

    private const string TempSuffix = ".tmp";

    private readonly string _filePath;

    public SettingsStore() : this(DefaultFilePath())
    {
    }

    public SettingsStore(string filePath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(filePath);
        _filePath = filePath;
    }

    public string FilePath => _filePath;

    public static string DefaultDirectory() => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "TigerMarkView");

    public static string DefaultFilePath() => Path.Combine(DefaultDirectory(), FileName);

    /// <summary>
    /// Returns the persisted settings, or defaults if there are none or they cannot be used. An
    /// unparseable file is moved aside (best effort) so the next save starts from a clean slate
    /// without destroying whatever the user had.
    /// </summary>
    public ApplicationSettings Load()
    {
        string json;

        try
        {
            if (!File.Exists(_filePath))
            {
                return ApplicationSettings.CreateDefault();
            }

            json = File.ReadAllText(_filePath);
        }
        catch (Exception ex) when (IsExpectedFileFailure(ex))
        {
            return ApplicationSettings.CreateDefault();
        }

        if (ApplicationSettingsSerializer.TryDeserialize(json, out var settings))
        {
            return settings;
        }

        QuarantineInvalidFile();
        return settings;
    }

    /// <summary>
    /// Writes <paramref name="settings"/> via a temporary file and a single replace, so a crash or
    /// power loss mid-write leaves the previous settings intact rather than a truncated file.
    /// </summary>
    public void Save(ApplicationSettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);

        try
        {
            var json = ApplicationSettingsSerializer.Serialize(settings.Normalized());

            var directory = Path.GetDirectoryName(_filePath);
            if (!string.IsNullOrEmpty(directory))
            {
                Directory.CreateDirectory(directory);
            }

            var temporaryPath = _filePath + TempSuffix;
            File.WriteAllText(temporaryPath, json);
            File.Move(temporaryPath, _filePath, overwrite: true);
        }
        catch (Exception ex) when (IsExpectedFileFailure(ex))
        {
            // Read-only profile, roaming folder unavailable, antivirus lock, disk full: the user keeps
            // working with the settings they have in memory for this session.
        }
    }

    private void QuarantineInvalidFile()
    {
        try
        {
            File.Move(_filePath, _filePath + InvalidSuffix, overwrite: true);
        }
        catch (Exception ex) when (IsExpectedFileFailure(ex))
        {
            // Best effort only. If the bad file cannot be moved it will simply be overwritten by the
            // next successful save — that is an acceptable outcome for a file we already cannot read.
        }
    }

    private static bool IsExpectedFileFailure(Exception exception) => exception
        is IOException
        or UnauthorizedAccessException
        or SecurityException
        or NotSupportedException
        or ArgumentException;
}
