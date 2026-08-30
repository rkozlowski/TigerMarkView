namespace TigerMarkView.Core.Exporting;

/// <summary>
/// The six running head and foot slots of a page, as templates, plus the document they describe.
/// </summary>
/// <remarks>
/// <para>
/// Six independent slots, because that is the shape of the page: something on the left, something in
/// the middle and something on the right, at the head and at the foot. Each holds a
/// <see cref="HeaderFooterTemplate"/> — plain text with <c>{Page}</c>, <c>{Title}</c>, <c>{Date}</c>
/// and the rest — and each compiles to one <c>@page</c> margin box. A slot that is empty is not a
/// blank box; it is no box, and reserves no space.
/// </para>
/// <para>
/// <paramref name="Document"/> travels with the templates rather than being supplied at rendering
/// time, so that the values a header prints are fixed once, before the first page is laid out. That is
/// what makes <c>{Date}</c> the same date on every page of a PDF generated at midnight, and what lets
/// the whole thing be resolved and tested without a browser.
/// </para>
/// <para>
/// Page numbering is <em>not</em> a seventh setting: <see cref="PageNumbers"/> is this record with
/// <see cref="HeaderFooterTemplate.PageNumber"/> in the footer-centre slot, which is why
/// <c>--page-numbers</c> and <c>--footer-center "{Page}"</c> produce the same page, and why the space
/// a number needs is reserved by the one rule that reserves space for any foot.
/// </para>
/// </remarks>
/// <param name="Document">
/// The document the non-paging placeholders describe, or <c>null</c> when there is none yet — in which
/// case those placeholders resolve to nothing and only <c>{Page}</c> and <c>{TotalPages}</c> print.
/// </param>
public sealed record PdfHeaderFooter(
    string? HeaderLeft = null,
    string? HeaderCenter = null,
    string? HeaderRight = null,
    string? FooterLeft = null,
    string? FooterCenter = null,
    string? FooterRight = null,
    PdfDocumentFacts? Document = null)
{
    /// <summary>No running heads or feet: what every PDF this project produced before templates.</summary>
    public static PdfHeaderFooter None { get; } = new();

    /// <summary>
    /// A page number at the foot, centred — the whole of what the desktop application's Page Numbers
    /// setting and the CLI's <c>--page-numbers</c> flag mean.
    /// </summary>
    public static PdfHeaderFooter PageNumbers { get; } = new(FooterCenter: HeaderFooterTemplate.PageNumber);

    /// <summary>Whether any head slot has a template in it.</summary>
    public bool HasHeader => IsSet(HeaderLeft) || IsSet(HeaderCenter) || IsSet(HeaderRight);

    /// <summary>Whether any foot slot has a template in it.</summary>
    public bool HasFooter => IsSet(FooterLeft) || IsSet(FooterCenter) || IsSet(FooterRight);

    /// <summary>Whether nothing at all is printed outside the text area.</summary>
    public bool IsEmpty => !HasHeader && !HasFooter;

    /// <summary>
    /// Whether this is (or contains) the page-number shorthand, so the desktop application's Page
    /// Numbers state can still be read back off a page setup as the single true/false it is.
    /// </summary>
    public bool ShowsPageNumbers =>
        string.Equals(FooterCenter?.Trim(), HeaderFooterTemplate.PageNumber, StringComparison.OrdinalIgnoreCase);

    /// <summary>The same templates, resolved against <paramref name="document"/>.</summary>
    public PdfHeaderFooter For(PdfDocumentFacts document)
    {
        ArgumentNullException.ThrowIfNull(document);

        return this with { Document = document };
    }

    /// <summary>
    /// The first error in any of the six templates, or <c>null</c> when they are all usable. Reported
    /// slot by slot, because "one of your headers is wrong" is not something a reader can act on.
    /// </summary>
    public string? Validate() =>
        Validate("header-left", HeaderLeft)
        ?? Validate("header-center", HeaderCenter)
        ?? Validate("header-right", HeaderRight)
        ?? Validate("footer-left", FooterLeft)
        ?? Validate("footer-center", FooterCenter)
        ?? Validate("footer-right", FooterRight);

    private static string? Validate(string slot, string? template) =>
        HeaderFooterTemplate.Validate(template) is { } error
            ? $"The {slot} template contains {error}"
            : null;

    private static bool IsSet(string? template) => !string.IsNullOrWhiteSpace(template);
}
