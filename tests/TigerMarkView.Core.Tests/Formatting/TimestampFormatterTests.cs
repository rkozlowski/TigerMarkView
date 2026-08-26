using TigerMarkView.Core.Formatting;

namespace TigerMarkView.Core.Tests.Formatting;

public class TimestampFormatterTests
{
    private static readonly DateTime Now = new(2026, 8, 8, 14, 30, 0);

    [Fact]
    public void TimestampFromTodayShowsTimeOnly()
    {
        var timestamp = new DateTime(2026, 8, 8, 10, 23, 7);

        Assert.Equal("10:23:07", TimestampFormatter.Format(timestamp, Now));
    }

    [Fact]
    public void TimestampFromYesterdayShowsDateAndTime()
    {
        var timestamp = new DateTime(2026, 8, 7, 22, 41, 8);

        Assert.Equal("7 Aug 2026 22:41:08", TimestampFormatter.Format(timestamp, Now));
    }

    [Fact]
    public void OlderTimestampShowsDateAndTime()
    {
        var timestamp = new DateTime(2025, 1, 3, 9, 5, 2);

        Assert.Equal("3 Jan 2025 09:05:02", TimestampFormatter.Format(timestamp, Now));
    }

    [Fact]
    public void DateBoundaryJustBeforeMidnightIsNotTreatedAsToday()
    {
        // Now is just after midnight; the timestamp is ~2 seconds earlier but on the previous
        // calendar day, so it must still be shown with a full date, not as "time only".
        var now = new DateTime(2026, 8, 8, 0, 0, 1);
        var timestamp = new DateTime(2026, 8, 7, 23, 59, 59);

        Assert.Equal("7 Aug 2026 23:59:59", TimestampFormatter.Format(timestamp, now));
    }

    [Fact]
    public void DateBoundaryJustAfterMidnightOnTheSameDayIsToday()
    {
        var now = new DateTime(2026, 8, 8, 0, 0, 5);
        var timestamp = new DateTime(2026, 8, 8, 0, 0, 1);

        Assert.Equal("00:00:01", TimestampFormatter.Format(timestamp, now));
    }
}
