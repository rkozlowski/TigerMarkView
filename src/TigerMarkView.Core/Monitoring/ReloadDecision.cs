namespace TigerMarkView.Core.Monitoring;

/// <summary>What a reload-mode should do in response to a detected external file change.</summary>
public enum ReloadDecision
{
    /// <summary>Manual: do nothing automatically; status bar reflects the newer-on-disk state.</summary>
    NoAction,

    /// <summary>Confirm: surface an unobtrusive reload prompt; wait for the user to act.</summary>
    AwaitConfirmation,

    /// <summary>Automatic: reload right away.</summary>
    ReloadNow,
}
