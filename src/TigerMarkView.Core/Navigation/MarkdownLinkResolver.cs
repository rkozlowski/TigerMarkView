namespace TigerMarkView.Core.Navigation;

/// <summary>
/// Decides whether a link target is "another local Markdown document" — the one question that
/// separates a navigation TigerMarkView must handle itself from one the WebView may keep.
/// </summary>
/// <remarks>
/// Kept in Core, and expressed over plain strings/<see cref="Uri"/> rather than any WebView type, so
/// the rule is unit-testable without a browser and reusable by the CLI. The viewer applies it in
/// <c>MainWindow.OnNavigationStarted</c>.
/// </remarks>
public static class MarkdownLinkResolver
{
    /// <summary>
    /// Extensions treated as TigerMarkView documents. Matches the File &gt; Open picker filter and the
    /// drag/drop filter, so every entry point agrees on what "a Markdown file" is.
    /// </summary>
    public static readonly IReadOnlyList<string> MarkdownExtensions = [".md", ".markdown"];

    /// <summary>True if <paramref name="path"/> names a file this application renders as Markdown.</summary>
    public static bool IsMarkdownPath(string? path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return false;
        }

        string extension;
        try
        {
            extension = Path.GetExtension(path);
        }
        catch (ArgumentException)
        {
            // Path contains characters that cannot appear in a file name at all.
            return false;
        }

        return MarkdownExtensions.Any(candidate =>
            string.Equals(extension, candidate, StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>
    /// Resolves <paramref name="href"/> as written in a Markdown document at
    /// <paramref name="currentDocumentPath"/>, and reports the absolute local path when — and only
    /// when — it designates another local Markdown file.
    /// </summary>
    /// <remarks>
    /// <para>
    /// Handles relative links (<c>foo.md</c>, <c>docs/foo.md</c>, <c>../foo.md</c>), absolute local
    /// paths, and <c>file:</c> URIs. Deliberately returns <see langword="false"/> for fragment-only
    /// links (<c>#anchor</c> stays in the document), for <c>http</c>/<c>https</c>/<c>mailto</c> and
    /// every other non-file scheme, and for any target that is not a Markdown file — TigerMarkView is
    /// a Markdown reader, not a general browser.
    /// </para>
    /// <para>
    /// In the running viewer the WebView has already resolved the link and the
    /// <see cref="TryResolveLocalMarkdown(Uri, out string)"/> overload is what runs; this one states
    /// the same rule for callers holding a raw <c>href</c> (and is where it is tested).
    /// </para>
    /// </remarks>
    public static bool TryResolveLocalMarkdown(
        string currentDocumentPath,
        string? href,
        out string resolvedPath)
    {
        resolvedPath = "";

        if (string.IsNullOrWhiteSpace(href) || href.StartsWith('#'))
        {
            return false;
        }

        Uri baseUri;
        try
        {
            baseUri = new Uri(Path.GetFullPath(currentDocumentPath));
        }
        catch (Exception ex) when (ex is ArgumentException or NotSupportedException or PathTooLongException)
        {
            return false;
        }

        // An href in HTML is percent-encoded (Markdig writes `my%20notes.md` for a file name with a
        // space), but combining a *string* onto a base Uri escapes it again — `%20` would become
        // `%2520` and resolve to a file that does not exist. Decoding first hands Uri the raw
        // reference it expects and lets it do the escaping once, which is what a browser ends up with.
        var reference = Unescape(href);

        return Uri.TryCreate(baseUri, reference, out var target) && TryResolveLocalMarkdown(target, out resolvedPath);
    }

    private static string Unescape(string href)
    {
        try
        {
            return Uri.UnescapeDataString(href);
        }
        catch (UriFormatException)
        {
            // A stray '%' that is not an escape sequence: use the href exactly as written.
            return href;
        }
    }

    /// <summary>
    /// The already-absolute form of <see cref="TryResolveLocalMarkdown(string, string?, out string)"/>,
    /// for a navigation the WebView has already resolved against the document's <c>&lt;base href&gt;</c>.
    /// </summary>
    public static bool TryResolveLocalMarkdown(Uri? target, out string resolvedPath)
    {
        resolvedPath = "";

        if (target is null || !target.IsAbsoluteUri || !target.IsFile)
        {
            return false;
        }

        // A UNC path is still a local file path as far as opening it goes; a file: URI naming some
        // other host is not something File.ReadAllText can do anything useful with.
        string localPath;
        try
        {
            localPath = target.LocalPath;
        }
        catch (InvalidOperationException)
        {
            return false;
        }

        if (!IsMarkdownPath(localPath))
        {
            return false;
        }

        try
        {
            resolvedPath = Path.GetFullPath(localPath);
            return true;
        }
        catch (Exception ex) when (ex is ArgumentException or NotSupportedException or PathTooLongException)
        {
            return false;
        }
    }
}
