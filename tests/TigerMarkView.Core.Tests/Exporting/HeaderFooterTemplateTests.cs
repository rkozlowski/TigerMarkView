using System.Globalization;
using TigerMarkView.Core.Exporting;

namespace TigerMarkView.Core.Tests.Exporting;

/// <summary>
/// The template language a running head or foot is written in: what a reader may type, what is
/// refused, and what each accepted template becomes as the CSS <c>content</c> value of a margin box.
/// </summary>
/// <remarks>
/// The two paging placeholders are asserted as <em>counters</em> rather than as text, because that is
/// the whole reason they exist: nothing here can know how many pages there will be, so they have to
/// survive into the stylesheet unresolved and be evaluated per page while the document paginates.
/// </remarks>
public class HeaderFooterTemplateTests
{
    private static readonly DateTimeOffset Moment =
        new(2026, 8, 30, 14, 25, 30, TimeSpan.FromHours(2));

    private static readonly PdfDocumentFacts Document = new(
        "Quarterly Review",
        "quarterly-review",
        "quarterly-review.md",
        @"C:\Reports\quarterly-review.md",
        Moment);

    private static string? Css(string? template, PdfDocumentFacts? document = null) =>
        HeaderFooterTemplate.ToCssContent(template, document ?? Document);

    [Fact]
    public void PlainTextBecomesOneQuotedString()
    {
        Assert.Equal("\"Confidential draft\"", Css("Confidential draft"));
    }

    /// <summary>Only the print engine knows where the pages fell, so these stay counters.</summary>
    [Fact]
    public void ThePagingPlaceholdersBecomeCssCounters()
    {
        Assert.Equal("counter(page)", Css("{Page}"));
        Assert.Equal("counter(pages)", Css("{TotalPages}"));
        Assert.Equal("\"Page \" counter(page) \" of \" counter(pages)", Css("Page {Page} of {TotalPages}"));
    }

    [Theory]
    [InlineData("{Title}", "\"Quarterly Review\"")]
    [InlineData("{FileName}", "\"quarterly-review\"")]
    [InlineData("{FileNameWithExt}", "\"quarterly-review.md\"")]
    [InlineData("{FilePath}", "\"C:\\\\Reports\\\\quarterly-review.md\"")]
    public void EachDocumentPlaceholderPrintsItsOwnFact(string template, string expected)
    {
        Assert.Equal(expected, Css(template));
    }

    /// <summary>The three documented defaults, which are what a template without a format gets.</summary>
    [Theory]
    [InlineData("{Date}", "\"2026-08-30\"")]
    [InlineData("{Time}", "\"14:25:30\"")]
    [InlineData("{DateTime}", "\"2026-08-30 14:25:30\"")]
    public void ADatePlaceholderWithoutAFormatUsesTheDocumentedDefault(string template, string expected)
    {
        Assert.Equal(expected, Css(template));
    }

    /// <summary>A format is a .NET format string, and may itself contain colons.</summary>
    [Theory]
    [InlineData("{Date:dd MMM yyyy}", "\"30 Aug 2026\"")]
    [InlineData("{Time:HH:mm}", "\"14:25\"")]
    [InlineData("{DateTime:yyyy-MM-ddTHH:mm:ssK}", "\"2026-08-30T14:25:30+02:00\"")]
    public void ADatePlaceholderTakesADotNetFormat(string template, string expected)
    {
        Assert.Equal(expected, Css(template));
    }

    /// <summary>
    /// A decimal comma cannot creep into a stylesheet, and neither can a Polish month name: the same
    /// command has to produce the same PDF on a colleague's machine.
    /// </summary>
    [Fact]
    public void DatesAreFormattedInvariantlyWhateverTheMachinesCulture()
    {
        var previous = Thread.CurrentThread.CurrentCulture;
        Thread.CurrentThread.CurrentCulture = new CultureInfo("pl-PL");

        try
        {
            Assert.Equal("\"30 Aug 2026\"", Css("{Date:dd MMM yyyy}"));
        }
        finally
        {
            Thread.CurrentThread.CurrentCulture = previous;
        }
    }

    [Theory]
    [InlineData("{{Page}}", "\"{Page}\"")]
    [InlineData("{{", "\"{\"")]
    [InlineData("}}", "\"}\"")]
    [InlineData("{{{Page}}}", "\"{\" counter(page) \"}\"")]
    public void DoubledBracesAreLiteralBraces(string template, string expected)
    {
        Assert.Equal(expected, Css(template));
    }

    /// <summary>
    /// Mixed text and placeholders collapse into as few CSS values as they can: adjacent literals are
    /// one string, and a counter is what breaks them apart.
    /// </summary>
    [Fact]
    public void AdjacentLiteralsAreMergedIntoOneString()
    {
        Assert.Equal(
            "\"Quarterly Review — 2026-08-30, page \" counter(page)",
            Css("{Title} — {Date}, page {Page}"));
    }

    /// <summary>
    /// Placeholder names are matched without regard to case, for the same reason <c>--paper letter</c>
    /// works.
    /// </summary>
    [Theory]
    [InlineData("{page}")]
    [InlineData("{PAGE}")]
    [InlineData("{PaGe}")]
    public void PlaceholderNamesAreNotCaseSensitive(string template)
    {
        Assert.Equal("counter(page)", Css(template));
    }

    /// <summary>
    /// A box that would print nothing is no box at all — otherwise a template that resolves to an
    /// empty string would silently reserve a band of page margin for a blank line.
    /// </summary>
    [Theory]
    [InlineData(null)]
    [InlineData("")]
    public void ATemplateWithNothingInItWritesNoBox(string? template)
    {
        Assert.Null(Css(template));
    }

    [Fact]
    public void APlaceholderThatResolvesToNothingWritesNoBox()
    {
        // No document: {Title} has nothing to say, and nothing else in the template does either.
        Assert.Null(HeaderFooterTemplate.ToCssContent("{Title}", document: null));
    }

    /// <summary>
    /// Without a document the paging placeholders still work, which is what lets the page-number
    /// shorthand exist before a file has been read.
    /// </summary>
    [Fact]
    public void PageNumberingNeedsNoDocument()
    {
        Assert.Equal("counter(page)", HeaderFooterTemplate.ToCssContent(HeaderFooterTemplate.PageNumber, null));
    }

    /// <summary>
    /// The stylesheet is emitted inside a &lt;style&gt; element and CSS strings are delimited by
    /// quotes, so a template must not be able to end either one.
    /// </summary>
    [Fact]
    public void TextThatCouldEndTheStringOrTheStyleElementIsEscaped()
    {
        var css = Css("""a "quote", a \backslash and </style>""");

        Assert.NotNull(css);
        Assert.DoesNotContain("</style>", css, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("\\\"quote\\\"", css);
        Assert.Contains("\\\\backslash", css);
        Assert.Contains("\\3C ", css);
    }

    [Theory]
    [InlineData("{Nope}")]
    [InlineData("Page {Pages}")]
    [InlineData("{Title")]
    [InlineData("Title}")]
    [InlineData("{Title:x}")]
    [InlineData("{Page:0}")]
    [InlineData("{Date:}")]
    [InlineData("{Date:q}")]
    public void AMalformedTemplateIsRefusedWithAReasonRatherThanPrinted(string template)
    {
        var error = HeaderFooterTemplate.Validate(template);

        Assert.False(string.IsNullOrWhiteSpace(error));

        // And it is dropped rather than printed as text: rendering a document must not fail over its
        // page furniture, and half-understood markup must not reach the page.
        Assert.Null(Css(template));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("Page {Page} of {TotalPages} — {Title} ({Date:yyyy}) {{literal}}")]
    public void AUsableTemplateValidatesWithoutAnError(string? template)
    {
        Assert.Null(HeaderFooterTemplate.Validate(template));
    }

    /// <summary>An unknown placeholder's message names the placeholders that do exist.</summary>
    [Fact]
    public void TheErrorForAnUnknownPlaceholderListsTheKnownOnes()
    {
        var error = HeaderFooterTemplate.Validate("{Autor}");

        Assert.Contains("{Autor}", error);
        Assert.Contains("{Title}", error);
        Assert.Contains("{TotalPages}", error);
    }
}
