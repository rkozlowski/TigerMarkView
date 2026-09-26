namespace TigerMarkView.Core.Navigation;

/// <summary>Where a document WebView stands with respect to its request boundary.</summary>
public enum ViewerBoundaryState
{
    /// <summary>The WebView does not exist yet, so nothing may be shown in it.</summary>
    Pending,

    /// <summary>The boundary is installed; navigation goes straight through.</summary>
    Protected,

    /// <summary>The boundary could not be installed; no document will be shown.</summary>
    Unavailable,
}

/// <summary>
/// Decides when a document WebView may be navigated: only once its request boundary is installed,
/// and never again after installing it failed.
/// </summary>
/// <remarks>
/// <para>
/// The engine is created lazily, and a window usually asks to show its first document before that has
/// happened, so the latest request is held and released once the boundary is in. Only the latest:
/// anything asked for in between has already been superseded.
/// </para>
/// <para>
/// Failure closes the gate for good. The request boundary is the only layer that can keep a page off
/// a network share — the page's Content Security Policy cannot tell a local file from a remote one,
/// and a relative image in a document that lives on a share only becomes a network path once
/// resolved — so showing documents without it would silently drop a protection rather than degrade
/// gracefully. The failure is reported instead, and the reason kept for the window to show.
/// </para>
/// </remarks>
public sealed class ViewerNavigationGate
{
    private Uri? _held;

    public ViewerBoundaryState State { get; private set; } = ViewerBoundaryState.Pending;

    /// <summary>Why the boundary could not be installed, once it could not.</summary>
    public string? UnavailableReason { get; private set; }

    /// <summary>
    /// Asks to show <paramref name="target"/>. Returns it when the WebView may navigate there now, and
    /// <c>null</c> when the request is held (boundary pending) or refused (boundary unavailable).
    /// </summary>
    public Uri? Request(Uri target)
    {
        ArgumentNullException.ThrowIfNull(target);

        switch (State)
        {
            case ViewerBoundaryState.Protected:
                return target;

            case ViewerBoundaryState.Pending:
                _held = target;
                return null;

            default:
                return null;
        }
    }

    /// <summary>
    /// Records that the boundary is installed on a (possibly re-created) engine, and returns the held
    /// request, if any, for the caller to navigate to now.
    /// </summary>
    public Uri? BoundaryInstalled()
    {
        if (State == ViewerBoundaryState.Unavailable)
        {
            return null;
        }

        State = ViewerBoundaryState.Protected;

        var held = _held;
        _held = null;
        return held;
    }

    /// <summary>
    /// Records that the boundary could not be installed. Every request from now on is refused, including
    /// one already held.
    /// </summary>
    public void BoundaryUnavailable(string reason)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(reason);

        State = ViewerBoundaryState.Unavailable;
        UnavailableReason = reason;
        _held = null;
    }
}
