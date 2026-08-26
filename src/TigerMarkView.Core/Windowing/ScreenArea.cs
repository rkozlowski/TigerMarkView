namespace TigerMarkView.Core.Windowing;

/// <summary>
/// A rectangle in physical screen pixels — either a monitor's usable area or a window's outer bounds.
/// </summary>
/// <remarks>
/// A deliberately plain value type rather than Avalonia's <c>PixelRect</c>: the clamping rules in
/// <see cref="WindowPlacementCalculator"/> are ordinary geometry and should be testable without a
/// windowing system. The app project converts to and from Avalonia's types at the boundary.
/// </remarks>
public readonly record struct ScreenArea(int X, int Y, int Width, int Height)
{
    public int Right => X + Width;

    public int Bottom => Y + Height;

    public bool IsEmpty => Width <= 0 || Height <= 0;

    public bool Contains(int pointX, int pointY) =>
        pointX >= X && pointX < Right && pointY >= Y && pointY < Bottom;

    /// <summary>Area of the overlap with <paramref name="other"/>; zero when they do not intersect.</summary>
    public long IntersectionArea(ScreenArea other)
    {
        var width = Math.Min(Right, other.Right) - Math.Max(X, other.X);
        var height = Math.Min(Bottom, other.Bottom) - Math.Max(Y, other.Y);

        return width <= 0 || height <= 0 ? 0 : (long)width * height;
    }
}
