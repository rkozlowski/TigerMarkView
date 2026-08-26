using ColorCode.Common;

namespace TigerMarkView.Core.Rendering.SyntaxHighlighting;

/// <summary>
/// Folds ColorCode's ~60 language-specific scope names down to the small set of semantic classes
/// TigerMarkView's stylesheet actually colours.
/// </summary>
/// <remarks>
/// <para>
/// This is where the project takes ownership of syntax colour. ColorCode names scopes after the
/// language construct that produced them ("SQL System Function", "PowerShell Variable", "Json Key"),
/// which would mean a palette that grew every time a language was added and looked different in every
/// language. Eight buckets is what a reader actually distinguishes at a glance, and it is what keeps
/// the token list in <see cref="DocumentShell"/> short enough to hand-tune for Light, Dark, <em>and</em>
/// paper.
/// </para>
/// <para>
/// An unmapped scope returns <c>null</c>, and the highlighter emits an unclassed <c>&lt;span&gt;</c> for
/// it: the tag has to be written either way to stay balanced with its closing tag, and unstyled text is
/// the right answer for a construct this project has no opinion about.
/// </para>
/// </remarks>
internal static class SyntaxScopes
{
    public const string Keyword = "syn-keyword";
    public const string Comment = "syn-comment";
    public const string String = "syn-string";
    public const string Number = "syn-number";
    public const string Type = "syn-type";
    public const string Function = "syn-function";
    public const string Variable = "syn-variable";
    public const string Operator = "syn-operator";

    /// <summary>Every class this project emits, for the stylesheet test to hold the two in step.</summary>
    public static readonly string[] All =
        [Keyword, Comment, String, Number, Type, Function, Variable, Operator];

    private static readonly Dictionary<string, string> ClassByScope = new(StringComparer.Ordinal)
    {
        // Anything the language reserves for itself.
        [ScopeName.Keyword] = Keyword,
        [ScopeName.ControlKeyword] = Keyword,
        [ScopeName.PreprocessorKeyword] = Keyword,
        [ScopeName.PseudoKeyword] = Keyword,
        [ScopeName.Predefined] = Keyword,
        [ScopeName.Intrinsic] = Keyword,
        [ScopeName.Continuation] = Keyword,
        [ScopeName.MarkdownListItem] = Keyword,
        [ScopeName.MarkdownEmph] = Keyword,
        [ScopeName.MarkdownBold] = Keyword,

        // Prose the compiler ignores — including XML doc comments and their tags, which read as one
        // block of commentary to a reviewer rather than as two different things.
        [ScopeName.Comment] = Comment,
        [ScopeName.XmlComment] = Comment,
        [ScopeName.HtmlComment] = Comment,
        [ScopeName.XmlDocComment] = Comment,
        [ScopeName.XmlDocTag] = Comment,

        // Literal text, wherever it appears — including attribute values and CDATA, which are text in
        // every sense that matters when reading a diff of one.
        [ScopeName.String] = String,
        [ScopeName.StringCSharpVerbatim] = String,
        [ScopeName.StringEscape] = String,
        [ScopeName.JsonString] = String,
        [ScopeName.XmlAttributeValue] = String,
        [ScopeName.HtmlAttributeValue] = String,
        [ScopeName.CssPropertyValue] = String,
        [ScopeName.XmlCDataSection] = String,
        [ScopeName.MarkdownCode] = String,

        // Numeric and other bare literals. `true`/`null` land here rather than with keywords because
        // they are values being read, not control flow.
        [ScopeName.Number] = Number,
        [ScopeName.JsonNumber] = Number,
        [ScopeName.JsonConst] = Number,
        [ScopeName.BuiltinValue] = Number,

        // Names of things: types, namespaces, element names, selectors.
        [ScopeName.Type] = Type,
        [ScopeName.TypeVariable] = Type,
        [ScopeName.ClassName] = Type,
        [ScopeName.NameSpace] = Type,
        [ScopeName.Constructor] = Type,
        [ScopeName.PowerShellType] = Type,
        [ScopeName.XmlName] = Type,
        [ScopeName.HtmlElementName] = Type,
        [ScopeName.CssSelector] = Type,
        [ScopeName.MarkdownHeader] = Type,

        // Things being invoked.
        [ScopeName.BuiltinFunction] = Function,
        [ScopeName.SqlSystemFunction] = Function,
        [ScopeName.PowerShellCommand] = Function,
        [ScopeName.HtmlServerSideScript] = Function,

        // Things being named or passed: variables, parameters, keys, attribute names.
        [ScopeName.PowerShellVariable] = Variable,
        [ScopeName.PowerShellParameter] = Variable,
        [ScopeName.PowerShellAttribute] = Variable,
        [ScopeName.Attribute] = Variable,
        [ScopeName.JsonKey] = Variable,
        [ScopeName.XmlAttribute] = Variable,
        [ScopeName.HtmlAttributeName] = Variable,
        [ScopeName.CssPropertyName] = Variable,

        // Punctuation and glue. Deliberately near-plain in every palette — colouring every bracket is
        // the fastest way to make a listing unreadable.
        [ScopeName.Operator] = Operator,
        [ScopeName.PowerShellOperator] = Operator,
        [ScopeName.HtmlOperator] = Operator,
        [ScopeName.Delimiter] = Operator,
        [ScopeName.Brackets] = Operator,
        [ScopeName.XmlDelimiter] = Operator,
        [ScopeName.XmlAttributeQuotes] = Operator,
        [ScopeName.HtmlTagDelimiter] = Operator,
        [ScopeName.HtmlEntity] = Operator,
        [ScopeName.SpecialCharacter] = Operator,
    };

    /// <summary>
    /// The CSS class for a ColorCode scope, or <c>null</c> when this project has no opinion about it
    /// (including <see cref="ScopeName.PlainText"/>, which is exactly the case where none is wanted).
    /// </summary>
    public static string? ClassFor(string? scopeName) =>
        scopeName is not null && ClassByScope.TryGetValue(scopeName, out var cssClass) ? cssClass : null;
}
