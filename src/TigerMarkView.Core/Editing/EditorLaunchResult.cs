namespace TigerMarkView.Core.Editing;

/// <summary>Outcome of resolving an <see cref="EditorConfiguration"/> into a launch plan — never throws, always tells the caller what happened.</summary>
public sealed record EditorLaunchResult(bool IsSuccess, EditorLaunchPlan? Plan, string? ErrorMessage)
{
    public static EditorLaunchResult Success(EditorLaunchPlan plan) => new(true, plan, null);

    public static EditorLaunchResult Failure(string errorMessage) => new(false, null, errorMessage);
}
