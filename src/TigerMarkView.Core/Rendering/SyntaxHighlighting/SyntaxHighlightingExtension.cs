using Markdig;
using Markdig.Renderers;
using Markdig.Renderers.Html;

namespace TigerMarkView.Core.Rendering.SyntaxHighlighting;

/// <summary>
/// The Markdig extension that swaps the stock code-block renderer for
/// <see cref="HighlightedCodeBlockRenderer"/>.
/// </summary>
/// <remarks>
/// Nothing is added at the parser level: fenced code blocks already parse exactly as they need to, and
/// the language identifier already reaches the renderer as the block's info string. Highlighting is
/// purely a rendering decision, which is why it can be switched on and off by re-rendering retained
/// Markdown and never needs the file re-read.
/// </remarks>
internal sealed class SyntaxHighlightingExtension : IMarkdownExtension
{
    public void Setup(MarkdownPipelineBuilder pipeline)
    {
    }

    public void Setup(MarkdownPipeline pipeline, IMarkdownRenderer renderer)
    {
        if (renderer is HtmlRenderer htmlRenderer)
        {
            // A fresh renderer per Markdig render, which is what lets SyntaxHighlighter hold a buffer
            // without any thread-safety machinery.
            htmlRenderer.ObjectRenderers.Replace<CodeBlockRenderer>(new HighlightedCodeBlockRenderer());
        }
    }
}
