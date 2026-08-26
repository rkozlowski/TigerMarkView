namespace TigerMarkView.Editing;

public sealed record LaunchOutcome(bool Success, string? ErrorMessage)
{
    public static LaunchOutcome Ok() => new(true, null);

    public static LaunchOutcome Failed(string errorMessage) => new(false, errorMessage);
}
