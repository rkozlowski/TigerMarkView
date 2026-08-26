namespace TigerMarkView.Core.Settings;

/// <summary>
/// Last-known main-window geometry. Sizes are in device-independent units (Avalonia's own
/// <c>ClientSize</c> units); <see cref="X"/>/<see cref="Y"/> are physical screen pixels, matching
/// Avalonia's <c>Window.Position</c>. All fields are optional: a first run — or a run where the size
/// could not be determined — simply leaves the OS/XAML defaults in place.
/// </summary>
public sealed class WindowPlacement
{
    /// <summary>Anything smaller is treated as corrupt rather than as a deliberately tiny window.</summary>
    public const double MinimumSize = 200;

    public double? Width { get; set; }

    public double? Height { get; set; }

    public int? X { get; set; }

    public int? Y { get; set; }

    public bool Maximized { get; set; }

    /// <summary>
    /// Drops values that could not have come from a real window (negative, zero, absurdly small, or
    /// non-finite after a hand-edit of the JSON). Screen-visibility of <see cref="X"/>/<see cref="Y"/>
    /// is deliberately <em>not</em> checked here — monitor layout is a platform concern and belongs
    /// with the code that actually restores the window.
    /// </summary>
    public WindowPlacement Normalized()
    {
        if (Width is { } width && (!double.IsFinite(width) || width < MinimumSize))
        {
            Width = null;
        }

        if (Height is { } height && (!double.IsFinite(height) || height < MinimumSize))
        {
            Height = null;
        }

        // A position is only meaningful as a pair.
        if (X is null || Y is null)
        {
            X = null;
            Y = null;
        }

        return this;
    }
}
