using TigerMarkView.Core.Exporting;

namespace TigerMarkView.Cli;

/// <summary>
/// The way round a PDF that is open in somebody's reader: write the new one under a name nothing can
/// possibly be holding, then move it over the one that was asked for.
/// </summary>
/// <remarks>
/// <para>
/// The problem it solves is that a locked target is discovered <em>at the end</em>. The export engine
/// writes straight to the destination, so a reader with last week's <c>Report.pdf</c> still open loses
/// the whole conversion — several seconds of browser, layout and print — and is left with nothing.
/// Writing to <c>Report-20260830142530.pdf</c> first turns that into a rename that either works or
/// does not, with a perfectly good PDF on disk either way.
/// </para>
/// <para>
/// It is opt-in because the two outcomes are not the same file. A script that always writes
/// <c>Report.pdf</c> and then publishes it must not silently start publishing last week's version
/// while a new one sits beside it under a name nobody looked for; asking for the mode is asking to
/// handle exit <see cref="TigerMarkExitCode.TargetNotReplaced"/>.
/// </para>
/// <para>
/// Nothing here retries, waits for a lock to clear, or deletes anything. A kept file is the whole
/// recovery: it is beside the file the reader asked for, its name says when it was made, and moving it
/// into place is something they can do once they have closed whatever was holding the target.
/// </para>
/// </remarks>
internal static class LockedTargetFallback
{
    /// <summary>Where the PDF is written before the move — beside <paramref name="requestedPath"/>.</summary>
    public static string PathFor(string requestedPath, DateTimeOffset timestamp) =>
        PdfFileNaming.TimestampedVariant(requestedPath, timestamp);

    /// <summary>
    /// Moves <paramref name="writtenPath"/> onto <paramref name="requestedPath"/>, replacing whatever
    /// is there.
    /// </summary>
    /// <returns>
    /// <c>true</c> when the requested file is now the new PDF; <c>false</c> when it could not be
    /// replaced, in which case <paramref name="writtenPath"/> is left exactly where it is.
    /// </returns>
    /// <remarks>
    /// A move rather than a copy-and-delete: on one volume it is atomic, so there is no moment in which
    /// the requested path holds a half-written PDF. The caught exceptions are the ways Windows says
    /// "something is holding that file" — a sharing violation, a denied access, a read-only target.
    /// </remarks>
    public static bool TryReplace(string writtenPath, string requestedPath, out string error)
    {
        error = string.Empty;

        try
        {
            File.Move(writtenPath, requestedPath, overwrite: true);
            return true;
        }
        catch (Exception exception) when (
            exception is IOException or UnauthorizedAccessException or NotSupportedException)
        {
            error = exception.Message;
            return false;
        }
    }
}
