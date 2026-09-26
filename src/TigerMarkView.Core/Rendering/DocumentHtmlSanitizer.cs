using AngleSharp.Dom;
using Ganss.Xss;

namespace TigerMarkView.Core.Rendering;

/// <summary>
/// Reduces the HTML Markdig produced for a document to passive, formatting-oriented markup.
/// </summary>
/// <remarks>
/// <para>
/// A Markdown document can come from anywhere, and Markdown passes raw HTML straight through — so a
/// document could otherwise carry <c>&lt;script&gt;</c>, inline event handlers, <c>javascript:</c> links,
/// frames, plugins, or a <c>&lt;meta&gt;</c> refresh into a WebView that has local-file access and a
/// channel to the host. This is the first of three independent layers against that: the generated
/// page also carries a hash-pinned Content Security Policy (<see cref="DocumentContentSecurityPolicy"/>),
/// and both WebView2 hosts enforce <see cref="WebResourcePolicy"/> on every request. Each layer is meant
/// to hold on its own.
/// </para>
/// <para>
/// It runs over Markdig's <em>whole</em> output, not just the raw-HTML nodes, because Markdown itself
/// can write active markup: <c>[x](javascript:…)</c> is a valid link, and the generic-attributes
/// extension accepts <c>{onclick=…}</c>. It parses with a browser-grade HTML5 parser (AngleSharp, via
/// HtmlSanitizer) rather than matching text, because every hand-written filter loses to parser
/// differentials such as entity-encoded schemes or mis-nested tags.
/// </para>
/// <para>
/// The lists below are an explicit allowlist rather than the library's defaults, so the policy is
/// reviewable here and does not move when the package is updated. What is kept is what Markdig emits
/// plus the raw HTML people actually use for layout — <c>details</c>, <c>kbd</c>, <c>sup</c>, sized and
/// aligned images, tables. Forms and form controls are dropped: a reader has nothing to submit, and a
/// form is a way to turn a click into a data-bearing request. The one control that survives is the
/// disabled checkbox a task list renders as.
/// </para>
/// </remarks>
internal static class DocumentHtmlSanitizer
{
    private static readonly string[] AllowedTags =
    [
        "a", "abbr", "acronym", "address", "area", "article", "aside", "b", "bdi", "bdo", "big",
        "blockquote", "br", "caption", "center", "cite", "code", "col", "colgroup", "data", "dd", "del",
        "details", "dfn", "dir", "div", "dl", "dt", "em", "figcaption", "figure", "font", "footer", "h1",
        "h2", "h3", "h4", "h5", "h6", "header", "hr", "i", "img", "input", "ins", "kbd", "label", "li",
        "main", "map", "mark", "menu", "meter", "nav", "ol", "p", "pre", "progress", "q", "rp", "rt",
        "ruby", "s", "samp", "section", "small", "span", "strike", "strong", "sub", "summary", "sup",
        "table", "tbody", "td", "tfoot", "th", "thead", "time", "tr", "tt", "u", "ul", "var", "wbr",

        // Plain vector shapes: Markdig draws the icon in an alert block's title this way. Only the
        // drawing elements are admitted — none of SVG's script, link, animation, <use>, or
        // <foreignObject> machinery.
        "svg", "path",
    ];

    /// <remarks>
    /// <c>id</c> and <c>class</c> are not in the library's defaults and are needed here: Markdig writes
    /// heading ids that in-document links target, and classes for code languages, task lists,
    /// footnotes, and syntax-highlighting spans. Every event-handler attribute is absent by
    /// construction — nothing beginning with <c>on</c> is listed.
    /// </remarks>
    private static readonly string[] AllowedAttributes =
    [
        "abbr", "align", "alt", "axis", "bgcolor", "border", "cellpadding", "cellspacing", "char",
        "charoff", "checked", "cite", "class", "clear", "color", "colspan", "compact", "coords",
        "datetime", "dir", "disabled", "face", "headers", "height", "high", "href", "hreflang", "hspace",
        "id", "ismap", "label", "lang", "longdesc", "low", "max", "min", "name", "noshade", "nowrap",
        "open", "optimum", "rel", "rev", "reversed", "rowspan", "rules", "scope", "shape", "size", "span",
        "src", "start", "style", "summary", "target", "title", "type", "usemap", "valign", "value",
        "vspace", "width",

        // Geometry for the vector shapes above; no href-bearing SVG attribute is listed.
        "aria-hidden", "d", "fill", "version", "viewbox",
    ];

    /// <summary>Attributes whose value a browser resolves as a URL and may fetch or navigate to.</summary>
    private static readonly string[] UriAttributes = ["cite", "href", "longdesc", "src"];

    /// <remarks>
    /// <c>file</c> keeps absolute local links and images working — the viewer resolves them through
    /// its own navigation rules, and <see cref="WebResourcePolicy"/> decides what may be fetched.
    /// <c>data</c> is admitted here only so that <see cref="OnFilterUrl"/> can keep it for inline
    /// images and nowhere else. Relative URLs are kept as written; the document's <c>&lt;base&gt;</c>
    /// resolves them.
    /// </remarks>
    private static readonly string[] AllowedSchemes = ["http", "https", "mailto", "file", "data"];

    /// <summary>
    /// Configured once, then shared: HtmlSanitizer documents <c>Sanitize</c> as thread-safe on a shared
    /// instance whose settings are no longer being changed, which is exactly this use.
    /// </summary>
    private static readonly HtmlSanitizer Sanitizer = Create();

    /// <summary>
    /// Returns <paramref name="html"/> with every active construct removed and every passive one kept.
    /// </summary>
    public static string Sanitize(string html) => Sanitizer.Sanitize(html);

    private static HtmlSanitizer Create()
    {
        var options = new HtmlSanitizerOptions
        {
            AllowedTags = new HashSet<string>(AllowedTags, StringComparer.OrdinalIgnoreCase),
            AllowedAttributes = new HashSet<string>(AllowedAttributes, StringComparer.OrdinalIgnoreCase),
            UriAttributes = new HashSet<string>(UriAttributes, StringComparer.OrdinalIgnoreCase),
            AllowedSchemes = new HashSet<string>(AllowedSchemes, StringComparer.OrdinalIgnoreCase),

            // Inline styles are how raw HTML sizes and aligns things, and Markdig writes them for
            // table alignment. The library's property list already excludes script-capable values
            // (expression(), behavior, -moz-binding); url() values are screened against the schemes
            // above like any other URL.
            AllowedCssProperties = new HashSet<string>(
                HtmlSanitizerDefaults.AllowedCssProperties, StringComparer.OrdinalIgnoreCase),
        };

        var sanitizer = new HtmlSanitizer(options);
        sanitizer.FilterUrl += OnFilterUrl;
        sanitizer.PostProcessNode += OnPostProcessNode;

        return sanitizer;
    }

    /// <summary>
    /// A <c>data:</c> URL survives only as the source of an image, which is the one place it is a
    /// picture rather than a document the WebView could be sent to.
    /// </summary>
    private static void OnFilterUrl(object? sender, FilterUrlEventArgs e)
    {
        if (e.SanitizedUrl is not { } url || !url.StartsWith("data:", StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        var isImageSource = e.Tag is { } tag
            && string.Equals(tag.LocalName, "img", StringComparison.OrdinalIgnoreCase)
            && url.StartsWith("data:image/", StringComparison.OrdinalIgnoreCase);

        if (!isImageSource)
        {
            e.SanitizedUrl = null;
        }
    }

    /// <summary>
    /// Keeps <c>input</c> only as the inert checkbox a Markdown task list renders.
    /// </summary>
    private static void OnPostProcessNode(object? sender, PostProcessNodeEventArgs e)
    {
        if (e.Node is not IElement element
            || !string.Equals(element.LocalName, "input", StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        if (!string.Equals(element.GetAttribute("type"), "checkbox", StringComparison.OrdinalIgnoreCase))
        {
            element.Remove();
            return;
        }

        element.SetAttribute("disabled", "disabled");
    }
}
