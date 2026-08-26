namespace TigerMarkView.Core.Printing;

/// <summary>
/// When TigerMarkView may take the foreground back after a print, and when it must not.
/// </summary>
/// <remarks>
/// <para>
/// Printing hands the screen to two windows that are not TigerMarkView's: the Windows print dialog,
/// which is out-of-process on Windows 11, and whatever the chosen printer driver puts up (Microsoft
/// Print to PDF asks where to save). When those close, Windows may restore activation to the
/// application the reader printed from or to another application. This decision keeps TigerMarkView
/// from taking focus unexpectedly.
/// </para>
/// <para>
/// <strong>Two conditions, and the first is the one that matters.</strong> Activation is only ever
/// taken back if TigerMarkView <em>had</em> it when the print began: a reader who started a print and
/// deliberately went to another application must not have a window pulled in front of them when the
/// job finishes. The second condition is simply that Windows has not already done it.
/// </para>
/// <para>
/// This is a decision, not an action — the window is activated by the application project, which is
/// where windows live. It is here so it can be stated once and unit-tested, in the same spirit as
/// <c>Settings.RecentFilesPolicy</c>.
/// </para>
/// </remarks>
public static class PrintActivation
{
    /// <summary>
    /// Whether the main window should be activated now that a print flow has ended.
    /// </summary>
    /// <param name="ownedForegroundBefore">
    /// Whether TigerMarkView owned the foreground window when the print was invoked.
    /// </param>
    /// <param name="ownsForegroundNow">
    /// Whether it owns the foreground window now, after the print dialog and any driver dialog have
    /// closed.
    /// </param>
    public static bool ShouldRestoreForeground(bool ownedForegroundBefore, bool ownsForegroundNow) =>
        ownedForegroundBefore && !ownsForegroundNow;
}
