using ColorCode;

namespace TigerMarkView.Core.Rendering.SyntaxHighlighting;

/// <summary>
/// Turns a fenced block's info string into a language ColorCode can colour, or nothing at all.
/// </summary>
/// <remarks>
/// <para>
/// The fenced language identifier is the <em>only</em> input. There is deliberately no automatic
/// language detection: this is a viewer for reviewing documents, and a listing coloured as the wrong
/// language is worse than a listing left plain. A reader who wants highlighting says so in the fence.
/// </para>
/// <para>
/// Aliases come from ColorCode's own repository rather than a table here, so <c>csharp</c>, <c>cs</c>,
/// <c>c#</c> and <c>CSharp</c> all resolve to one language, as do <c>js</c>, <c>ts</c>, <c>py</c> and
/// <c>md</c>. Lookup is case-insensitive.
/// </para>
/// <para>
/// ColorCode ships 25 languages, and the gaps are real — there is no Bash/shell, YAML, diff, Rust, Go,
/// TOML or INI. That is survivable precisely because an unresolved language falls back to the plain
/// code block TigerMarkView has always rendered, so enabling highlighting can never make a document
/// look worse than it did with the feature off.
/// </para>
/// </remarks>
internal static class SyntaxLanguages
{
    /// <summary>
    /// Resolves the language for a fenced block's info string, or reports that there is none.
    /// </summary>
    /// <param name="info">
    /// The fence's info string. Only the first whitespace-delimited token is considered, so a fence
    /// carrying extra words after the language still resolves on the language.
    /// </param>
    public static bool TryResolve(string? info, out ILanguage language)
    {
        language = null!;

        var id = FirstToken(info);
        if (id.Length == 0)
        {
            return false;
        }

        var found = Languages.FindById(id);
        if (found is null)
        {
            return false;
        }

        language = found;
        return true;
    }

    private static string FirstToken(string? info)
    {
        if (string.IsNullOrWhiteSpace(info))
        {
            return string.Empty;
        }

        var span = info.AsSpan().TrimStart();
        var end = span.IndexOfAny(' ', '\t');

        return (end < 0 ? span : span[..end]).ToString();
    }
}
