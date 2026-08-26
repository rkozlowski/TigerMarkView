using System;
using System.Runtime.InteropServices;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Styling;
using TigerMarkView.Core.Rendering;

namespace TigerMarkView.Windowing;

/// <summary>
/// Makes the <em>native</em> Windows title bar follow the selected theme, so a Dark-mode window is not
/// a dark application wearing a white caption.
/// </summary>
/// <remarks>
/// <para>
/// Avalonia's theme variant restyles everything Avalonia draws, but the caption is drawn by the window
/// manager and Avalonia 12.1 exposes no property for it — there is no <c>Win32Properties</c> title-bar
/// API and the Win32 backend never sets the attribute itself. The supported native route is DWM's
/// <c>DWMWA_USE_IMMERSIVE_DARK_MODE</c>, which is what this is; a custom-drawn title bar was rejected
/// because it would mean re-implementing minimize/maximize/close, resizing, the system menu, and Snap.
/// </para>
/// <para>
/// The attribute number changed during Windows 10's life: 20 from build 18985 (20H1) onward, 19 on
/// 1809–1903. Both are tried, newest first. Everything here is best-effort — an older Windows, a
/// future one that drops the attribute, or a non-Windows host simply leaves the caption as the system
/// draws it, which is cosmetic. It must never be able to stop the window from opening.
/// </para>
/// </remarks>
internal static class NativeTitleBar
{
    private const int UseImmersiveDarkMode = 20;
    private const int UseImmersiveDarkModeBefore20H1 = 19;

    private const uint WmNcActivate = 0x0086;

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    /// <summary>Applies the viewer theme to <paramref name="window"/>'s caption.</summary>
    public static void Apply(Window window, MarkdownTheme theme) => Apply(window, theme == MarkdownTheme.Dark);

    /// <summary>
    /// Applies whatever theme the application is currently in. Used by the dialogs, which are opened
    /// from several places and have no theme of their own to consult.
    /// </summary>
    public static void ApplyCurrentTheme(Window window) =>
        Apply(window, Application.Current?.ActualThemeVariant == ThemeVariant.Dark);

    private static void Apply(Window window, bool dark)
    {
        ArgumentNullException.ThrowIfNull(window);

        // The caption only exists once the window has a native handle, so callers apply this from
        // Opened (and again on every theme switch).
        if (window.TryGetPlatformHandle()?.Handle is not { } hwnd || hwnd == IntPtr.Zero)
        {
            return;
        }

        var value = dark ? 1 : 0;

        try
        {
            if (DwmSetWindowAttribute(hwnd, UseImmersiveDarkMode, ref value, sizeof(int)) != 0)
            {
                DwmSetWindowAttribute(hwnd, UseImmersiveDarkModeBefore20H1, ref value, sizeof(int));
            }

            RepaintCaption(hwnd);
        }
        catch (Exception ex) when (ex is DllNotFoundException or EntryPointNotFoundException)
        {
            // No dwmapi (or no such export): the caption stays as the system draws it.
        }
    }

    /// <summary>
    /// Makes an already-visible window repaint its caption in the colour just set.
    /// </summary>
    /// <remarks>
    /// Setting the attribute takes effect at the caption's next repaint, and on Windows 10 nothing
    /// schedules one: the attribute call can return <c>S_OK</c> while the title bar
    /// stays light indefinitely. <c>SetWindowPos</c> with <c>SWP_FRAMECHANGED</c> and
    /// <c>RedrawWindow</c> with <c>RDW_FRAME</c> were both tried and neither repaints it; a
    /// minimize/restore and a one-pixel resize do, but a theme switch must not make the window jump.
    /// Toggling <c>WM_NCACTIVATE</c> away from the window's real activation state and straight back
    /// repaints it, moves and resizes nothing, and works the same maximized as it does normal.
    /// </remarks>
    private static void RepaintCaption(IntPtr hwnd)
    {
        // Flip to the opposite of what the window really is, then back, so a window that was inactive
        // is not left painted as the active one.
        var active = GetForegroundWindow() == hwnd;
        var real = active ? new IntPtr(1) : IntPtr.Zero;
        var opposite = active ? IntPtr.Zero : new IntPtr(1);

        SendMessage(hwnd, WmNcActivate, opposite, IntPtr.Zero);
        SendMessage(hwnd, WmNcActivate, real, IntPtr.Zero);
    }
}
