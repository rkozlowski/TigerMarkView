using Markdig;
using Markdig.Syntax;
using Markdig.Syntax.Inlines;
using System.Text;

namespace TigerMarkView.Core.Rendering;

/// <summary>
/// What a document calls itself: the title a running head or foot prints when a template asks for
/// <c>{Title}</c>.
/// </summary>
/// <remarks>
/// <para>
/// Three sources, in order, because each is a weaker statement of the same thing: a
/// <c>title:</c> key in the document's own YAML front matter is the author saying it outright; the
/// first level-one heading is the author saying it in the document; and the file name is what is left
/// when the author said nothing at all. The file name is never empty, so resolution always answers.
/// </para>
/// <para>
/// The heading is found by parsing with Markdig — the very pipeline
/// <see cref="MarkdownRenderer"/> renders with — rather than by matching a <c>#</c> at the start of a
/// line. A <c>#</c> inside a fenced code block is a comment in somebody's shell script, not the title
/// of the document that quotes it, and only a real parse can tell the two apart.
/// </para>
/// <para>
/// Front matter is read here rather than by an extension because the shipped pipeline deliberately
/// does not include Markdig's YAML front matter extension: adding it would change how every document
/// with front matter <em>renders</em>, which is a product decision and not this feature's to make.
/// So the block is recognised, read for one key, and — importantly — skipped before the heading
/// search, so a <c>title:</c>-less front matter cannot be mistaken for the document's first heading.
/// </para>
/// </remarks>
public static class MarkdownDocumentTitle
{
    /// <summary>
    /// The title of <paramref name="markdown"/>, falling back to <paramref name="fallback"/> (the
    /// file name without its extension) when the document states none.
    /// </summary>
    public static string Resolve(string? markdown, string? fallback)
    {
        var (frontMatterTitle, body) = ReadFrontMatter(markdown ?? string.Empty);

        if (!string.IsNullOrWhiteSpace(frontMatterTitle))
        {
            return frontMatterTitle;
        }

        if (FirstTopLevelHeading(body) is { } heading && !string.IsNullOrWhiteSpace(heading))
        {
            return heading;
        }

        return fallback?.Trim() ?? string.Empty;
    }

    /// <summary>
    /// Splits a leading YAML front matter block off <paramref name="markdown"/>, returning its
    /// <c>title:</c> value (when it has one) and the Markdown that follows it.
    /// </summary>
    /// <remarks>
    /// Deliberately minimal: a front matter block is a <c>---</c> line at the very top and everything
    /// up to the next <c>---</c> or <c>...</c> line, and the one key that is read is an unindented
    /// <c>title</c>. This is not a YAML parser and must not grow into one — anything richer belongs in
    /// a real front matter feature with rendering behaviour of its own.
    /// </remarks>
    private static (string? Title, string Body) ReadFrontMatter(string markdown)
    {
        var lines = markdown.Split('\n');

        if (lines.Length == 0 || lines[0].TrimEnd('\r').TrimEnd() != "---")
        {
            return (null, markdown);
        }

        string? title = null;

        for (var index = 1; index < lines.Length; index++)
        {
            var line = lines[index].TrimEnd('\r');
            var trimmed = line.TrimEnd();

            if (trimmed is "---" or "...")
            {
                var body = string.Join('\n', lines.Skip(index + 1));
                return (title, body);
            }

            if (title is null && TryReadTitleKey(line) is { } value)
            {
                title = value;
            }
        }

        // An unterminated block is not front matter at all; the document is Markdown from the top.
        return (null, markdown);
    }

    /// <summary>Reads <c>title: value</c> from one unindented front matter line.</summary>
    private static string? TryReadTitleKey(string line)
    {
        if (line.Length == 0 || char.IsWhiteSpace(line[0]))
        {
            return null;
        }

        var colon = line.IndexOf(':');
        if (colon < 0 || !line[..colon].Trim().Equals("title", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        var value = line[(colon + 1)..].Trim();

        if (value.Length >= 2 && value[0] == value[^1] && value[0] is '"' or '\'')
        {
            value = value[1..^1];
        }

        return value.Length == 0 ? null : Normalize(value);
    }

    /// <summary>The text of the first level-one heading, or <c>null</c> when there is none.</summary>
    private static string? FirstTopLevelHeading(string markdown)
    {
        // Rendering options are irrelevant to a heading's text, so the default pipeline is used — and
        // it is MarkdownRenderer's own cached one, never a pipeline assembled here.
        var document = Markdown.Parse(markdown, MarkdownRenderer.PipelineFor(default));

        foreach (var block in document)
        {
            if (block is HeadingBlock { Level: 1 } heading)
            {
                return PlainText(heading.Inline);
            }
        }

        return null;
    }

    /// <summary>
    /// A heading's inline content as plain text: emphasis, links and code spans contribute their
    /// text and nothing else, because a running head is a line of type, not a fragment of HTML.
    /// </summary>
    private static string PlainText(ContainerInline? inline)
    {
        if (inline is null)
        {
            return string.Empty;
        }

        var text = new StringBuilder();

        foreach (var descendant in inline.Descendants())
        {
            switch (descendant)
            {
                case LiteralInline literal:
                    text.Append(literal.Content.AsSpan());
                    break;
                case CodeInline code:
                    text.Append(code.Content);
                    break;
                case LineBreakInline:
                    text.Append(' ');
                    break;
            }
        }

        return Normalize(text.ToString());
    }

    /// <summary>Collapses runs of whitespace, so a wrapped heading prints as one line.</summary>
    private static string Normalize(string text)
    {
        var normalized = new StringBuilder(text.Length);
        var pendingSpace = false;

        foreach (var character in text)
        {
            if (char.IsWhiteSpace(character))
            {
                pendingSpace = normalized.Length > 0;
                continue;
            }

            if (pendingSpace)
            {
                normalized.Append(' ');
                pendingSpace = false;
            }

            normalized.Append(character);
        }

        return normalized.ToString();
    }
}
