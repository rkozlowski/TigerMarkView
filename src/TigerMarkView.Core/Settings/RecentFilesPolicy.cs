using TigerMarkView.Core.Navigation;

namespace TigerMarkView.Core.Settings;

/// <summary>
/// The single rule that decides what File &gt; Open Recent is a list <em>of</em>.
/// </summary>
/// <remarks>
/// Open Recent holds explicit entry points only — documents the reader named from outside the one they
/// were reading. Documents merely arrived at (a local Markdown link, Back/Forward, a pick from the
/// history list) belong to the session's navigation trail and nowhere else.
/// <para>
/// It is a one-line rule and it lives here, rather than inline in the viewer, for two reasons: the
/// viewer is an Avalonia window and cannot be unit tested, and this is exactly the rule that was wrong
/// before — worth pinning down where it can be asserted. See <see cref="DocumentOpenOrigin"/>.
/// </para>
/// </remarks>
public static class RecentFilesPolicy
{
    /// <summary>
    /// Whether opening a document with this origin should add it to (or promote it within) the
    /// persisted recent-files list.
    /// </summary>
    public static bool ShouldRemember(DocumentOpenOrigin origin) => origin == DocumentOpenOrigin.ExplicitOpen;
}
