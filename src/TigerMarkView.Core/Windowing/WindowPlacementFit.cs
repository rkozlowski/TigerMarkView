namespace TigerMarkView.Core.Windowing;

/// <summary>
/// The result of fitting a desired window geometry to the monitors actually available.
/// </summary>
/// <param name="X">
/// Clamped left edge, or null when no usable position could be derived — the caller should then leave
/// placement to the window manager (TigerMarkView's XAML default is centre-screen) rather than force
/// coordinates the user cannot reach.
/// </param>
/// <param name="Y">Clamped top edge; null under the same conditions as <paramref name="X"/>.</param>
/// <param name="Width">Outer width, never wider than the chosen monitor's working area.</param>
/// <param name="Height">Outer height, never taller than the chosen monitor's working area.</param>
/// <param name="Changed">
/// True when anything was actually adjusted. Lets the caller distinguish "this geometry was already
/// fine" from "this had to be rescued", which is the interesting case to log or test.
/// </param>
public readonly record struct WindowPlacementFit(int? X, int? Y, int Width, int Height, bool Changed)
{
    public bool HasPosition => X is not null && Y is not null;
}
