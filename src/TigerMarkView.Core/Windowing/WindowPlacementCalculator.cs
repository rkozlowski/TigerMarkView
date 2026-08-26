namespace TigerMarkView.Core.Windowing;

/// <summary>
/// Keeps a non-maximized window inside a monitor's <em>working area</em>, so its title bar is always
/// on screen and reachable with the mouse.
/// </summary>
/// <remarks>
/// <para>
/// Working area, not full monitor bounds — clamping to raw bounds would happily tuck the bottom of a
/// window behind the Windows taskbar.
/// </para>
/// <para>
/// The rectangles here are the window's <em>outer</em> bounds (frame included) in physical pixels,
/// because that is what has to fit on the monitor. Converting a client size into outer bounds, and
/// device-independent units into pixels, is the caller's job — see <c>MainWindow.RestoreWindowPlacement</c>.
/// </para>
/// </remarks>
public static class WindowPlacementCalculator
{
    /// <summary>
    /// Fits a desired geometry to the available monitors.
    /// </summary>
    /// <param name="x">Desired left edge, or null to let the window manager place the window.</param>
    /// <param name="y">Desired top edge, or null to let the window manager place the window.</param>
    /// <param name="width">Desired outer width in physical pixels.</param>
    /// <param name="height">Desired outer height in physical pixels.</param>
    /// <param name="workingAreas">
    /// Every connected monitor's working area. The first entry is treated as the fallback ("primary")
    /// monitor. An empty list means no screen information is available, in which case nothing is
    /// clamped and placement is left entirely to the platform.
    /// </param>
    /// <remarks>
    /// The monitor is chosen by largest overlap with the desired rectangle, which is what the user
    /// would call "the monitor the window is on". A rectangle that overlaps <em>no</em> monitor — the
    /// display it was saved on has been unplugged, or the layout changed — keeps its size (clamped to
    /// the fallback monitor) but loses its position, so the window manager can place it somewhere
    /// visible instead of the caller reinstating coordinates that no longer exist.
    /// </remarks>
    public static WindowPlacementFit Fit(
        int? x,
        int? y,
        int width,
        int height,
        IReadOnlyList<ScreenArea> workingAreas)
    {
        ArgumentNullException.ThrowIfNull(workingAreas);

        var usable = workingAreas.Where(area => !area.IsEmpty).ToList();
        if (usable.Count == 0)
        {
            return new WindowPlacementFit(x, y, width, height, Changed: false);
        }

        var desired = x is { } left && y is { } top
            ? new ScreenArea(left, top, width, height)
            : (ScreenArea?)null;

        var monitor = desired is { } rect ? ChooseMonitor(rect, usable) : usable[0];

        var fallback = monitor ?? usable[0];
        var fittedWidth = Math.Min(width, fallback.Width);
        var fittedHeight = Math.Min(height, fallback.Height);

        if (desired is null || monitor is null)
        {
            // No position to preserve (first run), or the saved one belongs to a monitor that is no
            // longer there: clamp the size only and let the platform choose where the window goes.
            return new WindowPlacementFit(
                X: null,
                Y: null,
                fittedWidth,
                fittedHeight,
                Changed: fittedWidth != width || fittedHeight != height || desired is not null);
        }

        var fittedX = Clamp(desired.Value.X, fallback.X, fallback.Right - fittedWidth);
        var fittedY = Clamp(desired.Value.Y, fallback.Y, fallback.Bottom - fittedHeight);

        var changed = fittedX != desired.Value.X || fittedY != desired.Value.Y
            || fittedWidth != width || fittedHeight != height;

        return new WindowPlacementFit(fittedX, fittedY, fittedWidth, fittedHeight, changed);
    }

    /// <summary>
    /// The monitor a window at <paramref name="desired"/> is most on, or null when it is on none of
    /// them. Overlap area rather than the top-left corner: a window straddling two displays belongs to
    /// whichever shows more of it, and a window whose corner is off-screen is still "on" the monitor
    /// showing its body.
    /// </summary>
    private static ScreenArea? ChooseMonitor(ScreenArea desired, IReadOnlyList<ScreenArea> workingAreas)
    {
        ScreenArea? best = null;
        long bestOverlap = 0;

        foreach (var area in workingAreas)
        {
            var overlap = area.IntersectionArea(desired);
            if (overlap > bestOverlap)
            {
                bestOverlap = overlap;
                best = area;
            }
        }

        return best;
    }

    /// <summary>
    /// Clamps into <c>[min, max]</c>, tolerating an inverted range. The range inverts whenever the
    /// window is exactly as wide (or tall) as the monitor minus rounding, and <see cref="Math.Clamp(int, int, int)"/>
    /// throws rather than coping with that.
    /// </summary>
    private static int Clamp(int value, int min, int max) => max <= min ? min : Math.Min(Math.Max(value, min), max);
}
