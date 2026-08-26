using TigerMarkView.Core.Rendering;

namespace TigerMarkView.Core.Tests.Rendering;

/// <summary>
/// The emoji shortcode option. The point of every test here is that expansion happens in the Markdown
/// <em>inline parser</em>, not by rewriting source text or generated HTML — which is why code, URLs and
/// escapes are safe, and why they are worth asserting rather than assuming.
/// </summary>
public class EmojiShortcodeTests
{
    private static readonly MarkdownRenderingOptions On = new(EmojiShortcodes: true);

    [Fact]
    public void OffLeavesShortcodesExactlyAsWritten()
    {
        var html = MarkdownRenderer.ToHtmlFragment("Ship it :rocket: now.");

        Assert.Contains(":rocket:", html);
        Assert.DoesNotContain("🚀", html);
    }

    [Fact]
    public void DefaultOptionsAreOff()
    {
        Assert.Equal(
            MarkdownRenderer.ToHtmlFragment("Ship it :rocket: now."),
            MarkdownRenderer.ToHtmlFragment("Ship it :rocket: now.", MarkdownRenderingOptions.Default));
    }

    [Theory]
    [InlineData(":rocket:", "🚀")]
    [InlineData(":warning:", "⚠️")]
    [InlineData(":smile:", "😄")]
    [InlineData(":tiger:", "🐯")]
    public void OnExpandsRecognisedShortcodes(string shortcode, string emoji)
    {
        var html = MarkdownRenderer.ToHtmlFragment($"Status: {shortcode} here.", On);

        Assert.Contains(emoji, html);
        Assert.DoesNotContain(shortcode, html);
    }

    [Fact]
    public void UnknownShortcodesStayLiteral()
    {
        var html = MarkdownRenderer.ToHtmlFragment("A :not_an_emoji: token.", On);

        Assert.Contains(":not_an_emoji:", html);
    }

    /// <summary>
    /// The same Markdig extension also maps ASCII smileys. It is switched off on purpose: in a document
    /// full of code, paths and ratios, <c>:)</c> and <c>:/</c> turning into pictures is a false positive,
    /// not a feature.
    /// </summary>
    [Theory]
    [InlineData(":)")]
    [InlineData("8-)")]
    [InlineData(":-(")]
    [InlineData(":/")]
    public void SmileysAreNotConverted(string smiley)
    {
        var html = MarkdownRenderer.ToHtmlFragment($"Feeling {smiley} today.", On);

        Assert.Contains(smiley, html);
    }

    [Fact]
    public void EscapedShortcodesStayLiteral()
    {
        var html = MarkdownRenderer.ToHtmlFragment(@"Literally \:rocket\: please.", On);

        Assert.Contains(":rocket:", html);
        Assert.DoesNotContain("🚀", html);
    }

    /// <summary>
    /// Raw Unicode emoji are ordinary text and must render identically whether the option is on or off —
    /// they do not depend on this feature and never will.
    /// </summary>
    [Fact]
    public void UnicodeEmojiRenderTheSameWithTheOptionOnOrOff()
    {
        const string markdown = "Direct: 🚀 ⚠️ 😄 stay put.";

        var off = MarkdownRenderer.ToHtmlFragment(markdown);
        var on = MarkdownRenderer.ToHtmlFragment(markdown, On);

        Assert.Equal(off, on);
        Assert.Contains("🚀 ⚠️ 😄", on);
    }

    [Fact]
    public void InlineCodeIsNotExpanded()
    {
        var html = MarkdownRenderer.ToHtmlFragment("Type `:rocket:` to get one.", On);

        Assert.Contains("<code>:rocket:</code>", html);
        Assert.DoesNotContain("🚀", html);
    }

    [Fact]
    public void FencedCodeIsNotExpanded()
    {
        const string markdown = """
            ```text
            :rocket: :warning:
            ```
            """;

        var html = MarkdownRenderer.ToHtmlFragment(markdown, On);

        Assert.Contains(":rocket: :warning:", html);
        Assert.DoesNotContain("🚀", html);
    }

    [Fact]
    public void LinkDestinationsAreNotRewritten()
    {
        var html = MarkdownRenderer.ToHtmlFragment("[docs](https://example.com/:rocket:/guide)", On);

        Assert.Contains("""href="https://example.com/:rocket:/guide" """.TrimEnd(), html);
        Assert.DoesNotContain("https://example.com/🚀", html);
    }

    [Fact]
    public void AutolinkUrlsAreNotRewritten()
    {
        var html = MarkdownRenderer.ToHtmlFragment("See https://example.com/a:rocket:b for details.", On);

        Assert.Contains("""href="https://example.com/a:rocket:b" """.TrimEnd(), html);
        Assert.DoesNotContain("🚀", html);
    }

    /// <summary>
    /// Link <em>text</em> is ordinary inline content and does expand, which is what GitHub does too.
    /// Asserted so the boundary between text and destination stays a deliberate one.
    /// </summary>
    [Fact]
    public void LinkTextIsExpanded()
    {
        var html = MarkdownRenderer.ToHtmlFragment("[:rocket: launch](https://example.com/)", On);

        Assert.Contains(">🚀 launch</a>", html);
    }

    /// <summary>
    /// Raw HTML keeps whatever behaviour the existing Markdown policy gives it: a raw HTML block is
    /// passed through as written, and enabling emoji does not start reaching inside it.
    /// </summary>
    [Fact]
    public void RawHtmlBlocksAreUnchanged()
    {
        const string markdown = "<div class=\"note\">:rocket:</div>";

        var off = MarkdownRenderer.ToHtmlFragment(markdown);
        var on = MarkdownRenderer.ToHtmlFragment(markdown, On);

        Assert.Equal(off, on);
        Assert.Contains(":rocket:", on);
    }

    [Fact]
    public void ShortcodesReachTheFullDocumentAndItsTitleIsUntouched()
    {
        var document = MarkdownRenderer.ToHtmlDocument(
            "# Launch :rocket:",
            "notes:rocket:.md",
            renderingOptions: On);

        Assert.Contains("🚀", document);
        Assert.Contains("<title>notes:rocket:.md</title>", document);
    }
}
