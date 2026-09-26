using System.Security.Cryptography;
using System.Text;
using AngleSharp.Dom;
using AngleSharp.Html.Parser;
using TigerMarkView.Core.Rendering;

namespace TigerMarkView.Core.Tests.Rendering;

/// <summary>
/// The policy layer: every page TigerMarkView generates tells the engine to run exactly its own shell
/// script and stylesheet, to fetch nothing but images, and to ignore a document-supplied base.
/// </summary>
/// <remarks>
/// The hashes are recomputed here from the page as a browser would parse it, independently of the
/// production code that wrote them — a policy whose hash does not match its own script would block the
/// host shortcuts, and a policy that admitted more than its own script would not be a policy.
/// </remarks>
public class ContentSecurityPolicyTests
{
    public static TheoryData<string, string> GeneratedPages => new()
    {
        { "document", MarkdownRenderer.ToHtmlDocument("# Title\n\n| A |\n|--:|\n| 1 |", "notes.md", "file:///C:/Docs/") },
        { "dark document", MarkdownRenderer.ToHtmlDocument("# Title", "notes.md", "file:///C:/Docs/", MarkdownTheme.Dark) },
        { "empty viewer", MarkdownRenderer.ToEmptyDocument(MarkdownTheme.Dark) },
        { "error page", MarkdownRenderer.ToErrorDocument("notes.md", "Access denied.") },
    };

    [Theory]
    [MemberData(nameof(GeneratedPages))]
    public void EveryGeneratedPageDeclaresItsPolicyBeforeAnyOtherContent(string page, string html)
    {
        var head = Parse(html).Head!;

        var policy = PolicyElement(head);
        Assert.True(policy is not null, $"{page}: no Content-Security-Policy meta element.");

        // Only the charset declaration may precede it: a policy applies to what comes after it,
        // including the <base> element its base-uri rule governs.
        var index = Array.IndexOf(head.Children.ToArray(), policy);
        Assert.True(index == 1, $"{page}: the policy is element {index} of the head, not the first after charset.");
    }

    [Theory]
    [MemberData(nameof(GeneratedPages))]
    public void ThePolicyAdmitsExactlyThePagesOwnScriptAndStylesheet(string page, string html)
    {
        var document = Parse(html);
        var directives = Directives(document);

        var script = Assert.Single(document.QuerySelectorAll("script"));
        var style = Assert.Single(document.QuerySelectorAll("style"));

        Assert.True(
            $"'{Hash(script.TextContent)}'" == directives["script-src"],
            $"{page}: script-src '{directives["script-src"]}' does not admit exactly the page's own script.");
        Assert.True(
            $"'{Hash(style.TextContent)}'" == directives["style-src-elem"],
            $"{page}: style-src-elem '{directives["style-src-elem"]}' does not admit exactly the page's own stylesheet.");
    }

    [Theory]
    [MemberData(nameof(GeneratedPages))]
    public void ThePolicyClosesEveryRequestChannelButImages(string page, string html)
    {
        var directives = Directives(Parse(html));

        Assert.True("'none'" == directives["default-src"], $"{page}: default-src is not 'none'.");
        Assert.True("'none'" == directives["form-action"], $"{page}: form-action is not 'none'.");
        Assert.True("file:" == directives["base-uri"], $"{page}: base-uri is not limited to local folders.");
        Assert.Equal(["file:", "data:", "http:", "https:"], directives["img-src"].Split(' '));
        Assert.Equal("'unsafe-inline'", directives["style-src-attr"]);

        // Nothing that would reopen what default-src closes, and no inline-script escape hatch.
        Assert.DoesNotContain(directives.Keys, name => name is "connect-src" or "frame-src" or "child-src"
            or "object-src" or "media-src" or "font-src" or "worker-src" or "script-src-attr" or "script-src-elem");
        Assert.DoesNotContain("unsafe", directives["script-src"], StringComparison.Ordinal);
        Assert.DoesNotContain("unsafe", directives["style-src-elem"], StringComparison.Ordinal);
    }

    /// <summary>
    /// The engine hashes script text after HTML parsing has turned CR LF into LF, so the emitted text
    /// must already be LF-only or a Windows checkout would produce pages that block their own script.
    /// </summary>
    [Theory]
    [MemberData(nameof(GeneratedPages))]
    public void TheHashedBlocksAreEmittedWithLineFeedEndingsOnly(string page, string html)
    {
        var document = Parse(html.Replace("\r\n", "\n"));
        var raw = Parse(html);

        Assert.True(
            raw.QuerySelector("script")!.TextContent == document.QuerySelector("script")!.TextContent,
            $"{page}: the script block contains carriage returns.");
        Assert.True(
            raw.QuerySelector("style")!.TextContent == document.QuerySelector("style")!.TextContent,
            $"{page}: the style block contains carriage returns.");
    }

    [Fact]
    public void ADocumentsOwnPolicyOrScriptCannotJoinThePagesHead()
    {
        var html = MarkdownRenderer.ToHtmlDocument(
            "<meta http-equiv=\"Content-Security-Policy\" content=\"script-src 'unsafe-inline'\">\n\n<script>alert(1)</script>",
            "hostile.md");

        var document = Parse(html);

        Assert.Single(document.QuerySelectorAll("meta[http-equiv]"));
        Assert.Single(document.QuerySelectorAll("script"));
        Assert.DoesNotContain("unsafe-inline", Directives(document)["script-src"], StringComparison.Ordinal);
    }

    private static IDocument Parse(string html) => new HtmlParser().ParseDocument(html);

    private static IElement? PolicyElement(IElement head) =>
        head.QuerySelector("meta[http-equiv='Content-Security-Policy']");

    private static Dictionary<string, string> Directives(IDocument document) =>
        PolicyElement(document.Head!)!.GetAttribute("content")!
            .Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(directive => directive.Split(' ', 2))
            .ToDictionary(parts => parts[0], parts => parts.Length > 1 ? parts[1] : string.Empty);

    private static string Hash(string text) =>
        "sha256-" + Convert.ToBase64String(SHA256.HashData(Encoding.UTF8.GetBytes(text)));
}
