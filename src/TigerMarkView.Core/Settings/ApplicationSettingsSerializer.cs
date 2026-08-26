using System.Text.Json;

namespace TigerMarkView.Core.Settings;

/// <summary>
/// JSON shape of the settings file, kept separate from where that file lives so it can be tested
/// without touching the filesystem or any Windows-specific path.
/// </summary>
public static class ApplicationSettingsSerializer
{
    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        // A settings file is something a user may reasonably open and tweak by hand.
        AllowTrailingCommas = true,
        ReadCommentHandling = JsonCommentHandling.Skip,
    };

    public static string Serialize(ApplicationSettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);

        return JsonSerializer.Serialize(settings, Options);
    }

    /// <summary>
    /// Parses <paramref name="json"/>, returning defaults for anything missing. Never throws: settings
    /// are convenience data and must not be able to stop the application from starting.
    /// </summary>
    public static ApplicationSettings Deserialize(string? json)
    {
        TryDeserialize(json, out var settings);
        return settings;
    }

    /// <summary>
    /// As <see cref="Deserialize"/>, but reports whether the text was usable. <see langword="false"/>
    /// means the content was not valid JSON at all (and <paramref name="settings"/> is the defaults) —
    /// which is what lets the caller set the bad file aside instead of silently overwriting it.
    /// </summary>
    public static bool TryDeserialize(string? json, out ApplicationSettings settings)
    {
        if (string.IsNullOrWhiteSpace(json))
        {
            settings = ApplicationSettings.CreateDefault();
            return false;
        }

        try
        {
            settings = (JsonSerializer.Deserialize<ApplicationSettings>(json, Options)
                        ?? ApplicationSettings.CreateDefault()).Normalized();
            return true;
        }
        catch (JsonException)
        {
            settings = ApplicationSettings.CreateDefault();
            return false;
        }
        catch (NotSupportedException)
        {
            // A value of a shape the converters cannot map at all (e.g. an object where a string
            // belongs). Same outcome as malformed JSON: fall back rather than fail.
            settings = ApplicationSettings.CreateDefault();
            return false;
        }
    }
}
