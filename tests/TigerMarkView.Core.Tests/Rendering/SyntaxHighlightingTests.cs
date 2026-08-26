using TigerMarkView.Core.Rendering;

namespace TigerMarkView.Core.Tests.Rendering;

/// <summary>
/// The syntax highlighting option. Two properties matter more than the colours: the element structure
/// stays <c>pre &gt; code.language-x</c> so every existing screen and print rule keeps applying, and a
/// fence whose language is unknown retains the ordinary code-block rendering.
/// </summary>
public class SyntaxHighlightingTests
{
    private static readonly MarkdownRenderingOptions On = new(SyntaxHighlighting: true);

    private const string CSharpBlock = """
        ```csharp
        public sealed class Greeter // greets
        {
            private const int Max = 42;
        }
        ```
        """;

    [Fact]
    public void OffRendersThePlainCodeBlockUnchanged()
    {
        var html = MarkdownRenderer.ToHtmlFragment(CSharpBlock);

        Assert.Contains("""<pre><code class="language-csharp">public sealed class Greeter // greets""", html);
        Assert.DoesNotContain("syn-", html);
    }

    [Fact]
    public void OnHighlightsASupportedLanguage()
    {
        var html = MarkdownRenderer.ToHtmlFragment(CSharpBlock, On);

        Assert.Contains("""<span class="syn-keyword">public</span>""", html);
        Assert.Contains("""<span class="syn-comment">// greets</span>""", html);
        Assert.Contains("""<span class="syn-number">42</span>""", html);
    }

    /// <summary>
    /// The structural contract every code rule in <c>DocumentShell</c> is written against — including
    /// the print-only <c>white-space: pre-wrap</c> that stops a long line being clipped off a page.
    /// </summary>
    [Fact]
    public void HighlightedBlocksKeepThePreCodeStructureAndLanguageClass()
    {
        var html = MarkdownRenderer.ToHtmlFragment(CSharpBlock, On);

        Assert.Contains("""<pre><code class="language-csharp">""", html);
        Assert.Contains("</code></pre>", html);
        Assert.DoesNotContain("<div", html);
    }

    [Theory]
    [InlineData("csharp")]
    [InlineData("cs")]
    [InlineData("c#")]
    [InlineData("CSharp")]
    [InlineData("CS")]
    public void SupportedAliasesResolveToTheSameLanguage(string languageId)
    {
        var html = MarkdownRenderer.ToHtmlFragment($"```{languageId}\nvar x = 1;\n```", On);

        Assert.Contains("""<span class="syn-keyword">var</span>""", html);
        Assert.Contains($"""class="language-{languageId}" """.TrimEnd(), html);
    }

    /// <summary>
    /// One block per language TigerMarkView expects to meet in a real document and ColorCode supports.
    /// Deliberately asserts only that something was coloured — which token got which class is the
    /// grammar's business, and pinning it here would break on every upstream tweak.
    /// </summary>
    [Theory]
    [InlineData("sql", "SELECT TOP 10 [Name] FROM dbo.Users;")]
    [InlineData("powershell", "$items = Get-ChildItem -Path 'C:\\temp'")]
    [InlineData("javascript", "const f = () => { return 1; };")]
    [InlineData("typescript", "interface P { a: string }")]
    [InlineData("json", "{ \"a\": 1 }")]
    [InlineData("xml", "<root attr=\"1\" />")]
    [InlineData("html", "<div class=\"a\">hi</div>")]
    [InlineData("python", "def f(x):\n    return x")]
    public void RepresentativeLanguagesAreHighlighted(string languageId, string code)
    {
        var html = MarkdownRenderer.ToHtmlFragment($"```{languageId}\n{code}\n```", On);

        Assert.Contains("<span class=\"syn-", html);
        Assert.Contains($"""class="language-{languageId}" """.TrimEnd(), html);
    }

    /// <summary>
    /// The fallback that makes the feature strictly additive: enabling it can never make a document
    /// render worse than it did, because anything not recognised is left exactly as it was.
    /// </summary>
    [Theory]
    [InlineData("```bash\necho hi\n```")]          // a language ColorCode does not ship
    [InlineData("```yaml\nkey: value\n```")]       // ditto
    [InlineData("```nosuchlanguage\nplain\n```")]  // not a language at all
    [InlineData("```\nno language identifier\n```")]
    [InlineData("    four-space indented code\n")]
    public void UnsupportedAndAbsentLanguagesFallBackToTheExistingPlainBlock(string markdown)
    {
        Assert.Equal(
            MarkdownRenderer.ToHtmlFragment(markdown),
            MarkdownRenderer.ToHtmlFragment(markdown, On));
    }

    /// <summary>
    /// TigerMarkView owns syntax colour. ColorCode's own formatters emit hard-coded hex; this renderer
    /// emits classes only, so Light, Dark and print each supply their own values for the same markup.
    /// </summary>
    [Fact]
    public void HighlightedOutputCarriesSemanticClassesAndNoInlineColours()
    {
        var html = MarkdownRenderer.ToHtmlFragment(CSharpBlock, On);

        Assert.DoesNotContain("style=", html);
        Assert.DoesNotContain("color:", html);
    }

    /// <summary>
    /// The property worth re-checking whenever the highlighter is touched: source code is data, never
    /// markup. A block that closes its own element and opens a script tag must come out as visible text.
    /// </summary>
    [Fact]
    public void HostileCodeCannotEscapeTheCodeElement()
    {
        const string markdown = """
            ```csharp
            var s = "</code></pre><script>alert('xss')</script>";
            ```
            """;

        var html = MarkdownRenderer.ToHtmlFragment(markdown, On);

        Assert.Contains("&lt;/code&gt;&lt;/pre&gt;&lt;script&gt;", html);
        Assert.DoesNotContain("<script>", html);

        // Exactly one code element was opened and closed: the one Markdig asked for.
        Assert.Equal(1, CountOccurrences(html, "</code></pre>"));
    }

    [Theory]
    [InlineData("<img onerror=alert(1)>")]
    [InlineData("</span></code><b>bold</b>")]
    [InlineData("& < > \" '")]
    public void EveryCharacterOfSourceIsEncoded(string code)
    {
        var html = MarkdownRenderer.ToHtmlFragment($"```csharp\n{code}\n```", On);

        Assert.DoesNotContain("<img", html);
        Assert.DoesNotContain("<b>", html);

        // The only tags between <code> and </code> are the highlighter's own spans.
        var body = Between(html, """<code class="language-csharp">""", "</code></pre>");
        foreach (var tag in Tags(body))
        {
            Assert.True(
                tag is "</span>" || tag == "<span>" || tag.StartsWith("<span class=\"syn-", StringComparison.Ordinal),
                $"Unexpected tag in highlighted output: {tag}");
        }
    }

    [Fact]
    public void HighlightingDoesNotDependOnTheEmojiOption()
    {
        var both = MarkdownRenderer.ToHtmlFragment(
            CSharpBlock,
            new MarkdownRenderingOptions(EmojiShortcodes: true, SyntaxHighlighting: true));

        Assert.Contains("""<span class="syn-keyword">public</span>""", both);
    }

    private static int CountOccurrences(string haystack, string needle)
    {
        var count = 0;
        var index = haystack.IndexOf(needle, StringComparison.Ordinal);

        while (index >= 0)
        {
            count++;
            index = haystack.IndexOf(needle, index + needle.Length, StringComparison.Ordinal);
        }

        return count;
    }

    private static string Between(string text, string start, string end)
    {
        var from = text.IndexOf(start, StringComparison.Ordinal);
        Assert.True(from >= 0, $"Expected to find '{start}'.");
        from += start.Length;

        var to = text.IndexOf(end, from, StringComparison.Ordinal);
        Assert.True(to >= 0, $"Expected to find '{end}'.");

        return text[from..to];
    }

    private static IEnumerable<string> Tags(string html)
    {
        var index = html.IndexOf('<');

        while (index >= 0)
        {
            var close = html.IndexOf('>', index);
            if (close < 0)
            {
                yield break;
            }

            yield return html[index..(close + 1)];
            index = html.IndexOf('<', close + 1);
        }
    }
}
