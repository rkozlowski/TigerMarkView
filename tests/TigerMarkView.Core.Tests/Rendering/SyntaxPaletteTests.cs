using TigerMarkView.Core.Rendering;

namespace TigerMarkView.Core.Tests.Rendering;

/// <summary>
/// The syntax palette's place in the existing three-layer stylesheet: structural rules written against
/// tokens, one set of token values per screen theme, and a third set re-declared for paper. Asserted at
/// the level of "each layer supplies every token" rather than by pinning hex values, which are a design
/// decision and not a contract.
/// </summary>
public class SyntaxPaletteTests
{
    private static readonly string[] Tokens =
    [
        "--syn-keyword",
        "--syn-comment",
        "--syn-string",
        "--syn-number",
        "--syn-type",
        "--syn-function",
        "--syn-variable",
        "--syn-operator",
    ];

    /// <summary>
    /// The structural half: every syntax class is coloured through a variable, never a literal, which
    /// is what lets one copy of the rules serve Light, Dark and print alike.
    /// </summary>
    [Theory]
    [InlineData(MarkdownTheme.Light)]
    [InlineData(MarkdownTheme.Dark)]
    public void SyntaxClassesAreStyledThroughTokensInTheScreenStylesheet(MarkdownTheme theme)
    {
        var html = MarkdownRenderer.ToHtmlDocument("# Hello", "Doc", theme: theme);
        var screenSection = html[..html.IndexOf("@page", StringComparison.Ordinal)];

        foreach (var token in Tokens)
        {
            var cssClass = ".syn-" + token["--syn-".Length..];
            Assert.Contains($"pre code {cssClass} {{ color: var({token}); }}", screenSection);
        }
    }

    [Theory]
    [InlineData(MarkdownTheme.Light)]
    [InlineData(MarkdownTheme.Dark)]
    public void EveryThemeSuppliesEverySyntaxToken(MarkdownTheme theme)
    {
        var html = MarkdownRenderer.ToHtmlDocument("# Hello", "Doc", theme: theme);
        var screenSection = html[..html.IndexOf("@media print", StringComparison.Ordinal)];

        foreach (var token in Tokens)
        {
            Assert.Contains(token + ":", screenSection);
        }
    }

    /// <summary>
    /// The rule that matters for PDF: print re-declares every syntax token itself, so a document read in
    /// Dark mode still prints from the paper palette. Same guarantee the page and text colours already
    /// have, extended rather than excepted.
    /// </summary>
    [Theory]
    [InlineData(MarkdownTheme.Light)]
    [InlineData(MarkdownTheme.Dark)]
    public void PrintRedeclaresEverySyntaxTokenWhateverTheViewerTheme(MarkdownTheme theme)
    {
        var html = MarkdownRenderer.ToHtmlDocument("# Hello", "Doc", theme: theme);
        var printSection = html[html.IndexOf("@media print", StringComparison.Ordinal)..];

        foreach (var token in Tokens)
        {
            Assert.Contains(token + ":", printSection);
        }
    }

    /// <summary>
    /// The print palette is its own design, not a copy of either screen palette: the light theme's
    /// colours are tuned for a backlit display and the dark theme's are unusable on white.
    /// </summary>
    [Fact]
    public void ThePrintSyntaxPaletteIsNeitherScreenPalette()
    {
        var html = MarkdownRenderer.ToHtmlDocument("# Hello", "Doc", theme: MarkdownTheme.Dark);
        var printIndex = html.IndexOf("@media print", StringComparison.Ordinal);
        var screenSection = html[..printIndex];
        var printSection = html[printIndex..];

        foreach (var token in Tokens)
        {
            var screenValue = ValueOf(screenSection, token);
            var printValue = ValueOf(printSection, token);

            Assert.NotEqual(screenValue, printValue);
        }

        // A spot check that the dark values genuinely do not leak onto paper.
        Assert.DoesNotContain("#ff7b72", printSection);
        Assert.DoesNotContain("#a5d6ff", printSection);
    }

    /// <summary>
    /// Paper has no backlight and may be printed in greyscale, so every print syntax colour has to be
    /// genuinely dark ink on white — not a pastel that survives only on a screen.
    /// </summary>
    [Fact]
    public void EveryPrintSyntaxColourIsDarkEnoughForWhitePaper()
    {
        var html = MarkdownRenderer.ToHtmlDocument("# Hello", "Doc");
        var printSection = html[html.IndexOf("@media print", StringComparison.Ordinal)..];

        foreach (var token in Tokens)
        {
            var luminance = RelativeLuminance(ValueOf(printSection, token));

            // 0.4 is comfortably below mid-grey: enough contrast against white to stay readable once
            // the colour is flattened by a greyscale printer.
            Assert.True(luminance < 0.4, $"{token} is too light for paper (relative luminance {luminance:F2}).");
        }
    }

    private static string ValueOf(string css, string token)
    {
        var index = css.IndexOf(token + ":", StringComparison.Ordinal);
        Assert.True(index >= 0, $"Expected {token} to be declared.");

        var start = index + token.Length + 1;
        var end = css.IndexOf(';', start);

        return css[start..end].Trim();
    }

    /// <summary>WCAG relative luminance of a <c>#rrggbb</c> colour.</summary>
    private static double RelativeLuminance(string hex)
    {
        Assert.StartsWith("#", hex);
        Assert.Equal(7, hex.Length);

        static double Channel(string hex, int offset)
        {
            var value = Convert.ToInt32(hex.Substring(offset, 2), 16) / 255.0;
            return value <= 0.03928 ? value / 12.92 : Math.Pow((value + 0.055) / 1.055, 2.4);
        }

        return (0.2126 * Channel(hex, 1)) + (0.7152 * Channel(hex, 3)) + (0.0722 * Channel(hex, 5));
    }
}
