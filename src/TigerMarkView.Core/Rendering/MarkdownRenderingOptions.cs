namespace TigerMarkView.Core.Rendering;

/// <summary>
/// The optional rendering behaviours a document can be rendered with. Both are off by default, so
/// <c>default(MarkdownRenderingOptions)</c> reproduces the output TigerMarkView produced before either
/// feature existed.
/// </summary>
/// <remarks>
/// <para>
/// Deliberately separate from <see cref="MarkdownTheme"/> (a palette) and
/// <see cref="Exporting.PdfPageSetup"/> (physical paper): this is about <em>what the Markdown becomes</em>,
/// not how it is coloured or what sheet it lands on. It is a value, and the pipelines built from it are
/// immutable and cached — there is no global renderer state to configure, and no caller anywhere
/// assembles a Markdig pipeline of its own.
/// </para>
/// <para>
/// A struct with four representable combinations is the whole point: <see cref="MarkdownRenderer"/>
/// keeps one pipeline per combination, so asking for options is a lookup rather than a build.
/// </para>
/// </remarks>
/// <param name="EmojiShortcodes">
/// Whether <c>:rocket:</c>-style shortcodes expand to their Unicode emoji. Raw Unicode emoji are
/// ordinary text and never depend on this.
/// </param>
/// <param name="SyntaxHighlighting">
/// Whether fenced code blocks with a recognised language are coloured. Unrecognised and absent
/// languages fall back to the plain code block, so turning this on can never make a document render
/// worse than it did.
/// </param>
public readonly record struct MarkdownRenderingOptions(
    bool EmojiShortcodes = false,
    bool SyntaxHighlighting = false)
{
    /// <summary>Both features off — what Help and <c>tiger-mark</c> render with.</summary>
    public static MarkdownRenderingOptions Default => default;

    public MarkdownRenderingOptions WithEmojiShortcodes(bool enabled) => this with { EmojiShortcodes = enabled };

    public MarkdownRenderingOptions WithSyntaxHighlighting(bool enabled) => this with { SyntaxHighlighting = enabled };
}
