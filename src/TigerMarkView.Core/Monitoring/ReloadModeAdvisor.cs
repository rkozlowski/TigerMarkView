namespace TigerMarkView.Core.Monitoring;

/// <summary>Pure mapping from a reload mode to what should happen when an external change is detected.</summary>
public static class ReloadModeAdvisor
{
    public static ReloadDecision Decide(ReloadMode mode) => mode switch
    {
        ReloadMode.Manual => ReloadDecision.NoAction,
        ReloadMode.Confirm => ReloadDecision.AwaitConfirmation,
        ReloadMode.Automatic => ReloadDecision.ReloadNow,
        _ => ReloadDecision.NoAction,
    };
}
