using Markdig;
using TigerMarkView.Core.Exporting;
using TigerMarkView.Core.Rendering.SyntaxHighlighting;

namespace TigerMarkView.Core.Rendering;

public static class MarkdownRenderer
{
    /// <summary>
    /// One built pipeline per <see cref="MarkdownRenderingOptions"/> combination, built on first use.
    /// </summary>
    /// <remarks>
    /// A Markdig pipeline is immutable and thread-safe once built, and there are only four combinations,
    /// so the whole "configuration" story is a four-slot lookup rather than mutable renderer state that
    /// callers take turns setting. Nothing outside this class ever assembles a pipeline, which is what
    /// stops the viewer, PDF export, Help, and <c>tiger-mark</c> from drifting into four dialects of
    /// Markdown.
    /// </remarks>
    private static readonly Lazy<MarkdownPipeline>[] Pipelines = CreatePipelines();

    public static string ToHtmlFragment(string markdown, MarkdownRenderingOptions options = default) =>
        Markdown.ToHtml(markdown, PipelineFor(options));

    private static Lazy<MarkdownPipeline>[] CreatePipelines()
    {
        var pipelines = new Lazy<MarkdownPipeline>[4];

        for (var index = 0; index < pipelines.Length; index++)
        {
            var options = new MarkdownRenderingOptions(
                EmojiShortcodes: (index & 1) != 0,
                SyntaxHighlighting: (index & 2) != 0);

            pipelines[index] = new Lazy<MarkdownPipeline>(() => BuildPipeline(options));
        }

        return pipelines;
    }

    /// <summary>
    /// The one pipeline built for <paramref name="options"/>. Internal rather than private only so
    /// that <see cref="MarkdownDocumentTitle"/> can <em>parse</em> with the very pipeline the document
    /// renders with; nothing outside this assembly assembles or obtains a pipeline.
    /// </summary>
    internal static MarkdownPipeline PipelineFor(MarkdownRenderingOptions options) =>
        Pipelines[(options.EmojiShortcodes ? 1 : 0) | (options.SyntaxHighlighting ? 2 : 0)].Value;

    private static MarkdownPipeline BuildPipeline(MarkdownRenderingOptions options)
    {
        var builder = new MarkdownPipelineBuilder().UseAdvancedExtensions();

        if (options.EmojiShortcodes)
        {
            // Markdig's own extension, so there is no second emoji implementation and no shortcode
            // table of ours to keep current. Smileys stay off deliberately: the same extension maps
            // `:)`, `8-)` and `:/` to emoji, which in a document full of code and paths is a
            // false-positive generator rather than a feature. Only explicit `:name:` shortcodes expand.
            builder = builder.UseEmojiAndSmiley(enableSmileys: false);
        }

        if (options.SyntaxHighlighting)
        {
            builder = builder.Use(new SyntaxHighlightingExtension());
        }

        return builder.Build();
    }

    /// <param name="baseHref">
    /// If set, emitted as a &lt;base href&gt; so image/link paths in the source Markdown
    /// resolve relative to the Markdown file's own directory rather than wherever the
    /// generated HTML happens to be written on disk.
    /// </param>
    /// <param name="theme">
    /// Screen palette only. The print rules are always emitted and always re-declare the light
    /// palette, so exporting a PDF from a Dark viewer still produces an ink-sensible document.
    /// </param>
    /// <param name="pageSetup">
    /// The paper this document's <c>@page</c> rule describes, defaulting to
    /// <see cref="PdfPageSetup.Default"/>. It has no effect on screen — the rule only applies to
    /// print — but it is what an export of this HTML will lay out on, so the same value must reach
    /// <see cref="Exporting.PdfExportRequest"/>.
    /// </param>
    /// <param name="renderingOptions">
    /// The optional rendering behaviours (emoji shortcodes, syntax highlighting) this document is
    /// rendered with. Defaults to <see cref="MarkdownRenderingOptions.Default"/> — both off — which is
    /// what Help and <c>tiger-mark</c> deliberately keep using.
    /// </param>
    public static string ToHtmlDocument(
        string markdown,
        string title,
        string? baseHref = null,
        MarkdownTheme theme = MarkdownTheme.Light,
        PdfPageSetup? pageSetup = null,
        MarkdownRenderingOptions renderingOptions = default)
    {
        var fragment = ToHtmlFragment(markdown, renderingOptions);
        var safeTitle = System.Net.WebUtility.HtmlEncode(title);
        var baseTag = baseHref is null ? "" : $"""<base href="{System.Net.WebUtility.HtmlEncode(baseHref)}" />""";

        return $"""
            <!doctype html>
            <html lang="en">
            <head>
            <meta charset="utf-8" />
            {baseTag}
            <title>{safeTitle}</title>
            <style>
            {DocumentShell.ThemeCss(theme)}
            {DocumentShell.Css}
            {DocumentShell.PrintCss(pageSetup ?? PdfPageSetup.Default)}
            </style>
            </head>
            <body>
            {fragment}
            <script>
            {DocumentShell.AnchorScript}
            {DocumentShell.NavigationShortcutScript}
            {DocumentShell.HelpShortcutScript}
            {DocumentShell.PrintShortcutScript}
            </script>
            </body>
            </html>
            """;
    }

    /// <summary>
    /// The viewer with no document in it: a page carrying nothing but the theme.
    /// </summary>
    /// <remarks>
    /// The WebView paints its own default white page when it has been navigated nowhere, so a Dark
    /// session with no document open showed a white slab where the document belongs. This gives the
    /// empty state a page of its own that follows the theme like every other viewer surface. It is
    /// deliberately blank — the status bar already says "No document open", and inventing a welcome
    /// screen to solve a background colour would be a product decision nobody asked for. The print
    /// rules are left off for the same reason the error page leaves them off: neither is exportable.
    /// </remarks>
    /// <remarks>
    /// The help shortcut is the one thing it does carry, and it is plumbing rather than content: the
    /// WebView keeps its own keyboard input, so without the script F1 does nothing at all for a reader
    /// who has clicked into an empty viewer — which is exactly the reader most likely to press it.
    /// Without the script, F1 is inert while the WebView has focus.
    /// </remarks>
    /// <remarks>
    /// The print shortcut is here for the opposite reason — not to make Ctrl+P do something, but to stop
    /// it doing something. There is nothing to print here, yet Chromium would still open Edge's print
    /// preview over the empty viewer; the script cancels the key, and the host ignores the message it
    /// posts because no document is open.
    /// </remarks>
    public static string ToEmptyDocument(MarkdownTheme theme = MarkdownTheme.Light) =>
        $"""
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8" />
        <title>TigerMarkView</title>
        <style>
        {DocumentShell.ThemeCss(theme)}
        {DocumentShell.Css}
        </style>
        </head>
        <body>
        <script>
        {DocumentShell.HelpShortcutScript}
        {DocumentShell.PrintShortcutScript}
        </script>
        </body>
        </html>
        """;

    /// <remarks>
    /// Carries the help shortcut for the same reason <see cref="ToEmptyDocument"/> does — a reader
    /// looking at "Could not open file" is another one with good cause to press F1 — and the print
    /// shortcut for the same reason too: an error page is not printable, so Ctrl+P must not summon the
    /// browser's own print UI over it.
    /// </remarks>
    public static string ToErrorDocument(string title, string message, MarkdownTheme theme = MarkdownTheme.Light)
    {
        var safeTitle = System.Net.WebUtility.HtmlEncode(title);
        var safeMessage = System.Net.WebUtility.HtmlEncode(message);

        return $"""
            <!doctype html>
            <html lang="en">
            <head>
            <meta charset="utf-8" />
            <title>TigerMarkView</title>
            <style>
            {DocumentShell.ThemeCss(theme)}
            {DocumentShell.Css}
            </style>
            </head>
            <body>
            <h1>Could not open file</h1>
            <p>{safeTitle}</p>
            <pre>{safeMessage}</pre>
            <script>
            {DocumentShell.HelpShortcutScript}
            {DocumentShell.PrintShortcutScript}
            </script>
            </body>
            </html>
            """;
    }
}
