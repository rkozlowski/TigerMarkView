using System;
using System.Runtime.InteropServices;

namespace TigerMarkView.Windowing;

/// <summary>
/// Whether the window the reader is looking at is one of TigerMarkView's.
/// </summary>
/// <remarks>
/// The application half of <see cref="Core.Printing.PrintActivation"/>: Core decides whether
/// activation should be taken back, this answers the one question that decision needs. Deliberately
/// the smallest possible reading of "is it ours" — the owning <em>process</em>, so the main window, a
/// modal dialog of ours, and the Help window all count, and nothing else does. Best-effort: on any
/// failure it answers <c>false</c>, which only ever means "do not take the foreground".
/// </remarks>
internal static class ForegroundWindow
{
    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);

    public static bool BelongsToThisProcess()
    {
        try
        {
            var foreground = GetForegroundWindow();
            if (foreground == IntPtr.Zero)
            {
                return false;
            }

            return GetWindowThreadProcessId(foreground, out var processId) != 0
                   && processId == (uint)Environment.ProcessId;
        }
        catch (DllNotFoundException)
        {
            return false;
        }
        catch (EntryPointNotFoundException)
        {
            return false;
        }
    }
}
