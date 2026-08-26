using System.Text.Json;
using System.Text.Json.Serialization;
using TigerMarkView.Core.Exporting;
using TigerMarkView.Core.Monitoring;

namespace TigerMarkView.Core.Settings;

/// <summary>
/// Writes enums as names (so the settings file stays readable and survives enum members being
/// reordered) and, on reading, falls back to a nominated value for anything it does not recognise
/// instead of throwing.
/// </summary>
/// <remarks>
/// The point is graceful degradation of a convenience file: a settings file written by a newer
/// TigerMarkView — or hand-edited to <c>"theme": "Solarized"</c> — must cost the user that one
/// setting, not the whole file and certainly not the launch. The fallback is explicit rather than
/// simply <c>default(TEnum)</c> because an enum's zero member is not always the application's chosen
/// default (<see cref="ReloadMode.Manual"/> is zero, but the app defaults to
/// <see cref="ReloadMode.Confirm"/>).
/// </remarks>
internal class TolerantEnumConverter<TEnum> : JsonConverter<TEnum>
    where TEnum : struct, Enum
{
    private readonly TEnum _fallback;

    public TolerantEnumConverter() : this(default)
    {
    }

    protected TolerantEnumConverter(TEnum fallback) => _fallback = fallback;

    public override TEnum Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        switch (reader.TokenType)
        {
            case JsonTokenType.String:
                var name = reader.GetString();
                return Enum.TryParse<TEnum>(name, ignoreCase: true, out var parsed) && Enum.IsDefined(parsed)
                    ? parsed
                    : _fallback;

            case JsonTokenType.Number:
                // Tolerated for hand-edited files; the app itself always writes names.
                return reader.TryGetInt32(out var number) && Enum.IsDefined(typeof(TEnum), number)
                    ? (TEnum)Enum.ToObject(typeof(TEnum), number)
                    : _fallback;

            default:
                // Null, or a shape that could never be an enum (object/array). Consume it whole so
                // the rest of the document still parses, and take the fallback.
                reader.Skip();
                return _fallback;
        }
    }

    public override void Write(Utf8JsonWriter writer, TEnum value, JsonSerializerOptions options) =>
        writer.WriteStringValue(value.ToString());
}

/// <summary>
/// <see cref="ReloadMode"/> is one of the settings whose default is not the enum's zero member, so it
/// needs its fallback stated explicitly. See <see cref="ApplicationSettings.ReloadMode"/>.
/// </summary>
internal sealed class TolerantReloadModeConverter()
    : TolerantEnumConverter<ReloadMode>(ReloadMode.Confirm);

/// <summary>
/// The paper list is ordered by name, so its zero member is <see cref="PdfPaperSize.A3"/> while the
/// application's default paper is <see cref="PdfPaperSize.A4"/>. The enum keeps the order a reader
/// would expect in a menu; the fallback is stated here instead.
/// </summary>
internal sealed class TolerantPaperSizeConverter()
    : TolerantEnumConverter<PdfPaperSize>(PdfPaperSize.A4);

/// <summary>
/// Same shape of problem: the presets read Narrow → Normal → Wide, so the middle one — the default —
/// is not the zero member.
/// </summary>
internal sealed class TolerantMarginPresetConverter()
    : TolerantEnumConverter<PdfMarginPreset>(PdfMarginPreset.Normal);

/// <summary>
/// The same graceful degradation for a boolean: anything that is not a JSON <c>true</c>/<c>false</c>
/// costs that one setting rather than the whole file.
/// </summary>
/// <remarks>
/// Applied to the two rendering options, which are the settings most likely to be reached for by hand
/// (they are the file's only named on/off <em>features</em>, so <c>"syntaxHighlighting": "on"</c> is a
/// plausible thing for someone to type). Both fall back to <see langword="false"/>, which is also their
/// property initialiser, so a bad value lands exactly where a missing one would.
/// </remarks>
internal sealed class TolerantBooleanConverter : JsonConverter<bool>
{
    public override bool Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        switch (reader.TokenType)
        {
            case JsonTokenType.True:
                return true;

            case JsonTokenType.False:
                return false;

            default:
                // Consume whatever it is whole, so the rest of the document still parses.
                reader.Skip();
                return false;
        }
    }

    public override void Write(Utf8JsonWriter writer, bool value, JsonSerializerOptions options) =>
        writer.WriteBooleanValue(value);
}
