using System.Text;
using Markdig.Renderers;
using Markdig.Renderers.Html;
using Markdig.Syntax;

namespace TigerMarkView.Core.Rendering.SyntaxHighlighting;

/// <summary>
/// Markdig's code-block renderer with one behaviour added: a fenced block whose language ColorCode
/// recognises has its body coloured. Everything else — indented code, an unknown language, no language
/// at all — is handed straight back to the base renderer.
/// </summary>
/// <remarks>
/// <para>
/// The wrapper markup is deliberately identical to Markdig's own, down to writing the block's
/// attributes through <c>WriteAttributes</c>: the <c>language-csharp</c> class is put on the block by
/// the fenced-code <em>parser</em>, not by the renderer, so reusing that call is what keeps
/// <c>&lt;pre&gt;&lt;code class="language-csharp"&gt;</c> byte-for-byte what it always was. Only the
/// bytes between <c>&gt;</c> and <c>&lt;/code&gt;</c> differ, and only when a language resolved.
/// </para>
/// <para>
/// That matters beyond tidiness. Every screen and print rule this project has for code is written
/// against <c>pre</c> and <c>pre code</c> — including the <c>white-space: pre-wrap</c> that stops a long
/// line being clipped off the edge of a page. A renderer that invented its own element structure would
/// quietly drop out of all of them.
/// </para>
/// </remarks>
internal sealed class HighlightedCodeBlockRenderer : CodeBlockRenderer
{
    private readonly SyntaxHighlighter _highlighter = new();

    protected override void Write(HtmlRenderer renderer, CodeBlock obj)
    {
        ArgumentNullException.ThrowIfNull(renderer);
        ArgumentNullException.ThrowIfNull(obj);

        if (!TryHighlight(obj, renderer, out var highlighted))
        {
            base.Write(renderer, obj);
            return;
        }

        renderer.EnsureLine();

        if (renderer.EnableHtmlForBlock)
        {
            renderer.Write("<pre");

            if (OutputAttributesOnPre)
            {
                renderer.WriteAttributes(obj);
            }

            renderer.Write("><code");

            if (!OutputAttributesOnPre)
            {
                renderer.WriteAttributes(obj);
            }

            renderer.Write('>');
        }

        // Written unescaped because SyntaxHighlighter has already encoded every character of the
        // source; the only markup in the string is the spans it wrote itself.
        renderer.Write(highlighted);

        if (renderer.EnableHtmlForBlock)
        {
            renderer.WriteLine("</code></pre>");
        }

        renderer.EnsureLine();
    }

    private bool TryHighlight(CodeBlock block, HtmlRenderer renderer, out string highlighted)
    {
        highlighted = string.Empty;

        // Plain-text output has no spans to carry colour, and the base renderer is the only thing that
        // knows how to produce it.
        if (!renderer.EnableHtmlForBlock || !renderer.EnableHtmlEscape)
        {
            return false;
        }

        if (block is not FencedCodeBlock fenced)
        {
            return false;
        }

        // Blocks the host has redirected to a <div> or another element are not ours to take over — the
        // base renderer owns that shape. Neither collection is configured by TigerMarkView; this is a
        // guard against a future caller that does configure one.
        if (fenced.Info is { } info && (BlocksAsDiv.Contains(info) || BlockMapping.ContainsKey(info)))
        {
            return false;
        }

        if (!SyntaxLanguages.TryResolve(fenced.Info, out var language))
        {
            return false;
        }

        highlighted = _highlighter.Highlight(ReadCode(fenced), language);
        return true;
    }

    /// <summary>
    /// The block's source lines, each followed by a newline — the same text Markdig's own
    /// <c>WriteLeafRawLines(obj, writeEndOfLines: true, …)</c> emits, so a highlighted block and a plain
    /// one contain the same characters and differ only in the spans around them.
    /// </summary>
    private static string ReadCode(LeafBlock block)
    {
        var lines = block.Lines.Lines;

        if (lines is null || block.Lines.Count == 0)
        {
            return string.Empty;
        }

        var builder = new StringBuilder();

        for (var i = 0; i < block.Lines.Count; i++)
        {
            builder.Append(lines[i].Slice.AsSpan());
            builder.Append('\n');
        }

        return builder.ToString();
    }
}
