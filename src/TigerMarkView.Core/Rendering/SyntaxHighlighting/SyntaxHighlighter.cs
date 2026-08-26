using System.Net;
using System.Text;
using ColorCode;
using ColorCode.Common;
using ColorCode.Parsing;

namespace TigerMarkView.Core.Rendering.SyntaxHighlighting;

/// <summary>
/// Colours one block of source code, producing the <em>inner</em> HTML of a <c>&lt;code&gt;</c> element:
/// escaped text with TigerMarkView's own <c>syn-*</c> spans around it, and nothing else.
/// </summary>
/// <remarks>
/// <para>
/// Built on <see cref="CodeColorizerBase"/>, ColorCode's documented extension point, rather than on its
/// <c>HtmlClassFormatter</c>. The stock formatter wraps its output in <c>&lt;div class="csharp"&gt;&lt;pre&gt;</c>
/// and drops the <c>&lt;code&gt;</c> element entirely, which would silently fall out of every
/// <c>pre code</c> rule this project's screen and print stylesheets are written against. Producing only
/// the span-level markup leaves <see cref="HighlightedCodeBlockRenderer"/> free to emit exactly the
/// <c>&lt;pre&gt;&lt;code class="language-x"&gt;</c> wrapper Markdig has always emitted.
/// </para>
/// <para>
/// <strong>Every character of source code is HTML-encoded.</strong> The only markup in the output is
/// spans this class wrote, so a code block containing <c>&lt;/code&gt;&lt;/pre&gt;&lt;script&gt;</c> is
/// displayed as that text and can never close the element it sits in. This is the one property worth
/// re-checking if this file is ever touched.
/// </para>
/// <para>
/// Not thread-safe, and does not need to be: one instance belongs to one
/// <see cref="HighlightedCodeBlockRenderer"/>, and Markdig builds a fresh renderer per render.
/// </para>
/// </remarks>
internal sealed class SyntaxHighlighter : CodeColorizerBase
{
    private readonly StringBuilder _output = new();

    /// <summary>
    /// Both arguments left to ColorCode's own defaults. The style dictionary is genuinely unused —
    /// TigerMarkView owns syntax colour, and the palette lives in <see cref="DocumentShell"/> as CSS
    /// custom properties, not in a library table of hard-coded hex values.
    /// </summary>
    public SyntaxHighlighter() : base(null, null)
    {
    }

    public string Highlight(string sourceCode, ILanguage language)
    {
        _output.Clear();
        languageParser.Parse(sourceCode, language, (parsedSourceCode, scopes) => Write(parsedSourceCode, scopes));

        return _output.ToString();
    }

    /// <summary>
    /// Called back by the parser once per parsed chunk, with the scopes covering it.
    /// </summary>
    /// <remarks>
    /// Scopes nest and overlap, so they are flattened into an ordered list of insertion points — an
    /// opening span at each scope's start, a closing span at its end — and the text between two
    /// insertions is encoded and emitted verbatim. The sort has to be <em>stable</em>: sibling scopes
    /// starting at the same index would otherwise be reordered and their spans interleaved.
    /// </remarks>
    protected override void Write(string parsedSourceCode, IList<Scope> scopes)
    {
        var insertions = new List<TextInsertion>();

        foreach (var scope in scopes)
        {
            CollectInsertions(scope, insertions);
        }

        insertions.SortStable((left, right) => left.Index.CompareTo(right.Index));

        var offset = 0;

        foreach (var insertion in insertions)
        {
            AppendEncoded(parsedSourceCode, offset, insertion.Index - offset);

            if (string.IsNullOrEmpty(insertion.Text))
            {
                AppendOpeningSpan(insertion.Scope?.Name);
            }
            else
            {
                _output.Append(insertion.Text);
            }

            offset = insertion.Index;
        }

        AppendEncoded(parsedSourceCode, offset, parsedSourceCode.Length - offset);
    }

    private static void CollectInsertions(Scope scope, ICollection<TextInsertion> insertions)
    {
        insertions.Add(new TextInsertion { Index = scope.Index, Scope = scope });

        foreach (var child in scope.Children)
        {
            CollectInsertions(child, insertions);
        }

        insertions.Add(new TextInsertion { Index = scope.Index + scope.Length, Text = "</span>" });
    }

    /// <summary>
    /// A scope this project has no class for still gets its <c>&lt;span&gt;</c>, because its closing tag
    /// is already queued. An unclassed span is inert, which is the right rendering for a construct with
    /// no opinion attached to it.
    /// </summary>
    private void AppendOpeningSpan(string? scopeName)
    {
        var cssClass = SyntaxScopes.ClassFor(scopeName);

        if (cssClass is null)
        {
            _output.Append("<span>");
            return;
        }

        _output.Append("<span class=\"").Append(cssClass).Append("\">");
    }

    private void AppendEncoded(string source, int start, int length)
    {
        if (length <= 0)
        {
            return;
        }

        _output.Append(WebUtility.HtmlEncode(source.Substring(start, length)));
    }
}
