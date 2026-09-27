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
/// channel to the host. This is the first of three layers against that: the generated
/// page also carries a hash-pinned Content Security Policy (<see cref="DocumentContentSecurityPolicy"/>),
/// and both WebView2 hosts enforce <see cref="WebResourcePolicy"/> on every request. These are
/// complementary contracts: the image allowlist alone cannot stop executable code from putting
/// computed data in an image URL, so script prevention must also hold.
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
    /// its own navigation rules, and <see cref="WebResourcePolicy"/> decides what may be fetched;
    /// <see cref="OnFilterUrl"/> drops the ones that name another host.
    /// <c>data</c> is rejected by <see cref="OnFilterUrl"/> and restored by
    /// <see cref="OnRemovingAttribute"/> only for inline image sources. Relative URLs are kept as written; the document's <c>&lt;base&gt;</c>
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
        sanitizer.RemovingAttribute += OnRemovingAttribute;
        sanitizer.PostProcessNode += OnPostProcessNode;

        return sanitizer;
    }

    /// <summary>
    /// Drops a URL that would reach a file on another host, and keeps a <c>data:</c> URL only as the
    /// source of an image.
    /// </summary>
    /// <remarks>
    /// <para>
    /// A network file is dropped wherever the page would fetch it — an image source, a CSS
    /// <c>url()</c> — because fetching it opens an SMB connection that carries the reader's Windows
    /// credentials (see <see cref="WebResourcePolicy"/>). A hyperlink keeps its target: nothing is
    /// fetched until the reader follows it, and following it is the reader's own action.
    /// </para>
    /// <para>
    /// A <c>data:</c> URL is a picture only as an image source; anywhere else it is a document the
    /// WebView could be sent to.
    /// </para>
    /// </remarks>
    private static void OnFilterUrl(object? sender, FilterUrlEventArgs e)
    {
        if (e.SanitizedUrl is not { } url)
        {
            return;
        }

        if (WebResourcePolicy.IsNetworkFileReference(url)
            || url.StartsWith("data:", StringComparison.OrdinalIgnoreCase))
        {
            e.SanitizedUrl = null;
        }
    }

    private static void OnRemovingAttribute(object? sender, RemovingAttributeEventArgs e)
    {
        if (e.Reason != RemoveReason.NotAllowedUrlValue)
        {
            return;
        }

        // FilterUrl supplies the element, not the attribute/CSS property being checked. Comparing
        // its URL to href also authorizes background:url(the-same-href). Grant these two exceptions
        // only here, where the library identifies the actual attribute it would remove.
        e.Cancel = (e.Tag.LocalName is "a" or "area"
                    && e.Attribute.Name == "href"
                    && WebResourcePolicy.IsNetworkFileReference(e.Attribute.Value))
            || (e.Tag.LocalName == "img"
                && e.Attribute.Name == "src"
                && e.Attribute.Value.Trim().StartsWith("data:image/", StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>
    /// Keeps <c>input</c> only as the inert checkbox a Markdown task list renders.
    /// </summary>
    private static void OnPostProcessNode(object? sender, PostProcessNodeEventArgs e)
    {
        if (e.Node is not IElement element)
        {
            return;
        }

        // SVG presentation attributes are not CSS declarations to HtmlSanitizer. Keep solid paint
        // only, including the currentColor used by alert icons; never external paint-server URLs.
        if (element.GetAttribute("fill") is { } fill
            && !System.Text.RegularExpressions.Regex.IsMatch(fill.Trim(),
                @"\A(?:[a-zA-Z]+|#[0-9a-fA-F]{3,8}|(?:rgb|rgba|hsl|hsla)\([0-9.,%+\- /]+\))\z"))
        {
            element.RemoveAttribute("fill");
        }

        if (element.LocalName != "input")
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
