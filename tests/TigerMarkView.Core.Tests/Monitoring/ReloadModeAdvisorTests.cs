using TigerMarkView.Core.Monitoring;

namespace TigerMarkView.Core.Tests.Monitoring;

public class ReloadModeAdvisorTests
{
    [Fact]
    public void ManualDoesNotRequestAnAutomaticReload()
    {
        Assert.Equal(ReloadDecision.NoAction, ReloadModeAdvisor.Decide(ReloadMode.Manual));
    }

    [Fact]
    public void ConfirmRequiresUserAction()
    {
        Assert.Equal(ReloadDecision.AwaitConfirmation, ReloadModeAdvisor.Decide(ReloadMode.Confirm));
    }

    [Fact]
    public void AutomaticRequestsReloadImmediately()
    {
        Assert.Equal(ReloadDecision.ReloadNow, ReloadModeAdvisor.Decide(ReloadMode.Automatic));
    }
}
