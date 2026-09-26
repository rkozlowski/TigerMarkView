using System.Security.Cryptography;
using System.Text;
using AngleSharp.Dom;
using AngleSharp.Html.Parser;
using TigerMarkView.Core.Rendering;

namespace TigerMarkView.Core.Tests.Rendering;

/// <summary>
/// Source code in a fenced block is data, with or without syntax highlighting: every character comes
/// out as visible text inside the one <c>pre &gt; code</c> element, the only markup around it is the
/// highlighter's own <c>syn-*</c> spans, and the whole-document sanitizer after it leaves that markup
/// alone.
/// </summary>
/// <remarks>
/// The central assertion is that the code element's text equals the source exactly. That proves more
/// than "nothing active survived": had the highlighter emitted any of the source as markup, the
/// sanitizer backstop would have removed it and the text would no longer match. So it shows the source
/// was encoded by ColorCode's path itself, not merely cleaned up afterwards.
/// </remarks>
public class HostileCodeBlockTests
{
    private static readonly MarkdownRenderingOptions Highlighted = new(EmojiShortcodes: false, SyntaxHighlighting: true);

    public static readonly string[] Payloads =
    [
        "<script>alert(1)</script>",
        "</span><script>alert(1)</script>",
        "<img src=x onerror=alert(1)>",
        "<a href=\"javascript:alert(1)\">x</a>",
        "</code></pre><script>alert(1)</script><pre><code>",
        "<span class=\"syn-keyword\" onclick=\"alert(1)\">var</span>",
        "\"><svg onload=alert(1)>",
        "<!--</span>--><script>alert(1)</script>",
        "<![CDATA[</span>]]><img src=x onerror=alert(1)>",
        "&lt;script&gt; &amp; &#60;img&#62;",
    ];

    /// <summary>The languages TigerMarkView highlights that a hostile payload is most at home in.</summary>
    public static readonly string[] Languages = ["csharp", "javascript", "html", "xml", "sql", "powershell", "python", "css"];

    public static TheoryData<string, string> HighlightedCases()
    {
        var data = new TheoryData<string, string>();
        foreach (var language in Languages)
        {
            foreach (var payload in Payloads)
            {
                data.Add(language, payload);
            }
        }

        return data;
    }

    [Theory]
    [MemberData(nameof(HighlightedCases))]
    public void AHighlightedPayloadStaysLiteralCode(string language, string payload)
    {
        var source = $"var value = 1; // {payload}\n{payload}\n";

        var code = RenderSingleCodeBlock($"```{language}\n{source}```", Highlighted);

        Assert.Equal(source, code.TextContent);
        AssertOnlyHighlighterMarkup(code);
    }

    [Theory]
    [MemberData(nameof(PlainCases))]
    public void AnUnhighlightedPayloadStaysLiteralCode(string fence, string payload)
    {
        var source = $"{payload}\n";

        var code = RenderSingleCodeBlock($"{fence}\n{source}```", Highlighted);

        Assert.Equal(source, code.TextContent);
        Assert.Empty(code.Children);
    }

    public static TheoryData<string, string> PlainCases()
    {
        var data = new TheoryData<string, string>();
        foreach (var payload in Payloads)
        {
            data.Add("```", payload);          // no language
            data.Add("```text", payload);      // a language ColorCode does not know
        }

        return data;
    }

    public static TheoryData<string> HostileInfoStrings => new()
    {
        "csharp\"><script>alert(1)</script>",
        "csharp\" onmouseover=\"alert(1)",
        "\"><img src=x onerror=alert(1)>",
        "javascript:alert(1)",
    };

    /// <summary>
    /// The fence's info string becomes the <c>language-x</c> class. It is written through Markdig's
    /// escaping attribute writer and then sanitized, so it can name a class and nothing more.
    /// </summary>
    [Theory]
    [MemberData(nameof(HostileInfoStrings))]
    public void AHostileInfoStringCanOnlyBecomeAClassName(string info)
    {
        var body = Render($"```{info}\nvar x = 1;\n```", Highlighted);

        var code = Assert.Single(body.QuerySelectorAll("pre > code"));
        Assert.Equal("var x = 1;\n", code.TextContent);
        Assert.Empty(body.QuerySelectorAll("script, img, svg"));
        Assert.All(body.QuerySelectorAll("*"), element =>
            Assert.DoesNotContain(element.Attributes, attribute =>
                attribute.Name.StartsWith("on", StringComparison.OrdinalIgnoreCase)));
    }

    /// <summary>
    /// The backstop must not cost the feature: the spans the highlighter writes survive sanitizing with
    /// their classes, for every representative language, and carry no inline style for the page's
    /// policy to have an opinion about.
    /// </summary>
    [Theory]
    [InlineData("csharp", "public sealed class Greeter { private const int Max = 42; } // note")]
    [InlineData("javascript", "const f = () => { return \"x\"; }; // note")]
    [InlineData("sql", "SELECT TOP 10 [Name] FROM dbo.Users WHERE Id = 1; -- note")]
    [InlineData("powershell", "$items = Get-ChildItem -Path 'C:\\temp' # note")]
    [InlineData("html", "<div class=\"a\">hi</div> <!-- note -->")]
    [InlineData("python", "def f(x):\n    return 'x'  # note")]
    public void HighlightingSurvivesTheSanitizerWithClassesAndNoInlineStyle(string language, string source)
    {
        var code = RenderSingleCodeBlock($"```{language}\n{source}\n```", Highlighted);

        Assert.Equal($"language-{language}", code.GetAttribute("class"));
        Assert.Equal(source + "\n", code.TextContent);

        var spans = code.QuerySelectorAll("span[class^='syn-']");
        Assert.NotEmpty(spans);
        Assert.Contains(spans, span => span.ClassName == "syn-comment");
        Assert.Empty(code.QuerySelectorAll("[style]"));
    }

    /// <summary>
    /// Highlighting is coloured by the shell stylesheet, and that stylesheet is the one the page's
    /// policy admits by hash — so the policy cannot switch the colours off, and the page the viewer
    /// shows is the page GUI export prints.
    /// </summary>
    [Fact]
    public void AHighlightedPageStylesItsSpansThroughThePolicyAdmittedStylesheet()
    {
        var html = MarkdownRenderer.ToHtmlDocument(
            "```csharp\nvar x = 1; // <script>alert(1)</script>\n```",
            "code.md",
            "file:///C:/Docs/",
            renderingOptions: Highlighted);

        var document = new HtmlParser().ParseDocument(html);
        var style = Assert.Single(document.QuerySelectorAll("style")).TextContent;
        var policy = document.QuerySelector("meta[http-equiv='Content-Security-Policy']")!.GetAttribute("content")!;

        Assert.Contains($"style-src-elem '{Hash(style)}'", policy, StringComparison.Ordinal);
        Assert.Contains("pre code .syn-keyword", style, StringComparison.Ordinal);
        Assert.Contains("pre code .syn-comment", style, StringComparison.Ordinal);
        Assert.NotEmpty(document.QuerySelectorAll("pre > code span.syn-keyword"));
        Assert.Single(document.QuerySelectorAll("script"));
    }

    private static IElement RenderSingleCodeBlock(string markdown, MarkdownRenderingOptions options) =>
        Assert.Single(Render(markdown, options).QuerySelectorAll("pre > code"));

    private static IElement Render(string markdown, MarkdownRenderingOptions options) =>
        new HtmlParser()
            .ParseDocument($"<!doctype html><html><body>{MarkdownRenderer.ToHtmlFragment(markdown, options)}</body></html>")
            .Body!;

    private static void AssertOnlyHighlighterMarkup(IElement code)
    {
        Assert.All(code.QuerySelectorAll("*"), element =>
        {
            Assert.Equal("span", element.LocalName);

            var names = element.Attributes.Select(attribute => attribute.Name).ToArray();
            Assert.True(names.Length == 0 || names is ["class"], $"A span carries {string.Join(", ", names)}.");

            if (element.GetAttribute("class") is { } cssClass)
            {
                Assert.StartsWith("syn-", cssClass, StringComparison.Ordinal);
            }
        });
    }

    private static string Hash(string text) =>
        "sha256-" + Convert.ToBase64String(SHA256.HashData(Encoding.UTF8.GetBytes(text)));
}
