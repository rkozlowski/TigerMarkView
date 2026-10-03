namespace TigerMarkView.Pdf;

/// <summary>
/// Keeps TigerMarkView's WebView2 hosts from leaving a browsing trail: every engine runs InPrivate,
/// and the persistent profile earlier versions kept is removed.
/// </summary>
/// <remarks>
/// <para>
/// A WebView2 engine in a persistent profile records what it shows the way Edge does — a History
/// database, Top Sites, favicons, sessions, a disk cache — under the host's user data folder. For a
/// document viewer that is a second, hidden record of every document read, kept beside settings the
/// reader can see and clear. An InPrivate engine keeps that state in memory only, for the life of the
/// browser process, so closing the last window — or a crash — leaves nothing behind. It is the
/// controller option WebView2 provides for exactly this, and needs no cleanup to be correct.
/// </para>
/// <para>
/// No persistent browser state is useful to TigerMarkView: it signs in nowhere, its pages are
/// generated afresh on every navigation, and its web images are fetched by the request boundary
/// rather than the engine. The one thing InPrivate cannot do is undo what an earlier version already
/// recorded. That lives in the folder's <c>EBWebView\Default</c> profile, which no InPrivate engine
/// reads, so <see cref="RemovePersistentProfile"/> deletes it — once per folder, marked by a file so a
/// later start does not touch the folder again. The engine-wide data beside it (component updates,
/// shader caches, crash reports) holds nothing about documents and is left alone.
/// </para>
/// </remarks>
public static class InPrivateBrowsing
{
    /// <summary>Written into a user data folder once its persistent profile has been removed.</summary>
    public const string MarkerFileName = "TigerMarkView.InPrivate";

    /// <summary>
    /// Removes the persistent profile from <paramref name="userDataFolder"/> unless that has already
    /// been done. Best effort: a profile an earlier version still holds open stays, and removal is
    /// tried again on the next start, because the marker is written only after a complete removal.
    /// Call it before an engine is created in the folder.
    /// </summary>
    public static void RemovePersistentProfile(string userDataFolder)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(userDataFolder);

        var marker = Path.Combine(userDataFolder, MarkerFileName);
        try
        {
            if (File.Exists(marker))
            {
                return;
            }

            // Directory.Delete removes a junction or symbolic link inside the profile without
            // following it, so nothing outside the folder can be reached through one.
            var profile = Path.Combine(userDataFolder, "EBWebView", "Default");
            if (Directory.Exists(profile))
            {
                Directory.Delete(profile, recursive: true);
            }

            Directory.CreateDirectory(userDataFolder);
            File.WriteAllText(
                marker,
                "TigerMarkView runs WebView2 InPrivate; the persistent profile earlier versions kept here was removed.\r\n");
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            // Held open by a window of an earlier version, most likely. The engine still runs
            // InPrivate, so nothing new is recorded, and the next start tries again.
        }
    }
}
