using System.Globalization;

namespace TigerMarkView.Core.Formatting;

/// <summary>
/// Single shared rule for displaying timestamps in the status bar (and anywhere else a
/// timestamp is shown): today's timestamps show time only, older ones show date and time.
/// Both <paramref name="timestamp"/> and <paramref name="now"/> are expected to already be
/// in local time — this class does not perform UTC conversion.
/// </summary>
public static class TimestampFormatter
{
    private const string TimeOnlyFormat = "HH:mm:ss";
    private const string DateAndTimeFormat = "d MMM yyyy HH:mm:ss";

    public static string Format(DateTime timestamp, DateTime now)
    {
        var format = timestamp.Date == now.Date ? TimeOnlyFormat : DateAndTimeFormat;
        return timestamp.ToString(format, CultureInfo.InvariantCulture);
    }

    public static string Format(DateTime timestamp) => Format(timestamp, DateTime.Now);
}
