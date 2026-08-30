using System.Globalization;
using System.Text;

namespace TigerMarkView.Core.Exporting;

/// <summary>
/// The little template language a running head or foot is written in, and the one thing it compiles
/// to: the CSS <c>content</c> value of a <c>@page</c> margin box.
/// </summary>
/// <remarks>
/// <para>
/// A template is ordinary text with <c>{Placeholder}</c> substitutions and <c>{{</c>/<c>}}</c> for
/// literal braces. Two placeholders — <c>{Page}</c> and <c>{TotalPages}</c> — cannot be resolved here
/// at all, because only the print engine knows where the pages fell; they become CSS counters and are
/// evaluated per page while the document paginates. Every other placeholder is resolved once, from
/// <see cref="PdfDocumentFacts"/>, so every page carries identical text.
/// </para>
/// <para>
/// Compiling to a margin box rather than to markup is what keeps headers and footers inside the one
/// rendering pipeline: no second PDF renderer, no JavaScript pagination, no post-processing, and
/// nothing added to the document flow that the text could collide with.
/// </para>
/// <para>
/// Dates and times are formatted with <see cref="CultureInfo.InvariantCulture"/> and .NET format
/// strings. Invariant deliberately: the same command must produce the same PDF on a colleague's
/// machine, and a template that wants some other rendering can say so in its format string.
/// </para>
/// </remarks>
public static class HeaderFooterTemplate
{
    /// <summary>
    /// The template <c>--page-numbers</c> is shorthand for. Page numbering is not a mechanism of its
    /// own with rules of its own; it is the footer-centre slot with the simplest possible template in
    /// it.
    /// </summary>
    public const string PageNumber = "{Page}";

    /// <summary>The format <c>{Date}</c> uses when a template names none.</summary>
    public const string DefaultDateFormat = "yyyy-MM-dd";

    /// <summary>The format <c>{Time}</c> uses when a template names none.</summary>
    public const string DefaultTimeFormat = "HH:mm:ss";

    /// <summary>The format <c>{DateTime}</c> uses when a template names none.</summary>
    public const string DefaultDateTimeFormat = "yyyy-MM-dd HH:mm:ss";

    private const string KnownPlaceholders =
        "{Page}, {TotalPages}, {Title}, {FileName}, {FileNameWithExt}, {FilePath}, " +
        "{Date}, {Time} and {DateTime}";

    /// <summary>
    /// Checks <paramref name="template"/>, without needing a document.
    /// </summary>
    /// <returns>
    /// An error a reader can act on, or <c>null</c> when the template is usable. An empty template is
    /// usable and prints nothing.
    /// </returns>
    public static string? Validate(string? template) =>
        TryParse(template, out _, out var error) ? null : error;

    /// <summary>
    /// Compiles <paramref name="template"/> into the CSS <c>content</c> value of one margin box.
    /// </summary>
    /// <param name="document">
    /// The document being printed. When <c>null</c> every placeholder that describes a document
    /// resolves to nothing, which still leaves page numbering working — that is what lets the
    /// page-number shorthand be built with no document in hand.
    /// </param>
    /// <returns>
    /// A CSS value such as <c>"Page " counter(page) " of " counter(pages)</c>, or <c>null</c> when the
    /// box would print nothing at all: an empty template, an unusable one, or one whose every
    /// placeholder resolved to nothing. <c>null</c> means no margin box is written, so no page space
    /// is reserved for text that was never going to appear.
    /// </returns>
    public static string? ToCssContent(string? template, PdfDocumentFacts? document)
    {
        // An unusable template is dropped rather than thrown: it is refused at the command line, where
        // the reader can fix it, and rendering a document must never fail over its page furniture.
        if (!TryParse(template, out var parts, out _))
        {
            return null;
        }

        var values = new List<string>();
        var literal = new StringBuilder();
        var printsSomething = false;

        foreach (var part in parts)
        {
            var counter = part.Kind switch
            {
                Placeholder.Page => "counter(page)",
                Placeholder.TotalPages => "counter(pages)",
                _ => null,
            };

            if (counter is not null)
            {
                Flush(literal, values);
                values.Add(counter);
                printsSomething = true;
                continue;
            }

            var text = Resolve(part, document);
            printsSomething |= text.Length > 0;
            literal.Append(text);
        }

        Flush(literal, values);

        return printsSomething ? string.Join(' ', values) : null;

        static void Flush(StringBuilder literal, List<string> values)
        {
            if (literal.Length > 0)
            {
                values.Add(Quote(literal.ToString()));
                literal.Clear();
            }
        }
    }

    /// <summary>One resolved placeholder's text, or the empty string when it has nothing to say.</summary>
    private static string Resolve(Part part, PdfDocumentFacts? document) => part.Kind switch
    {
        Placeholder.Literal => part.Text,
        _ when document is null => string.Empty,
        Placeholder.Title => document.Title,
        Placeholder.FileName => document.FileName,
        Placeholder.FileNameWithExtension => document.FileNameWithExtension,
        Placeholder.FilePath => document.FilePath,
        Placeholder.Date => Format(document.GeneratedAt, part.Text, DefaultDateFormat),
        Placeholder.Time => Format(document.GeneratedAt, part.Text, DefaultTimeFormat),
        Placeholder.DateTime => Format(document.GeneratedAt, part.Text, DefaultDateTimeFormat),
        _ => string.Empty,
    };

    private static string Format(DateTimeOffset moment, string format, string fallback) =>
        moment.ToString(format.Length == 0 ? fallback : format, CultureInfo.InvariantCulture);

    /// <summary>
    /// A CSS string literal. The escapes are not decoration: the stylesheet is emitted inside an HTML
    /// <c>style</c> element, where an unescaped <c>&lt;</c> could end that element early, and a raw
    /// quote or backslash would end or corrupt the string itself.
    /// </summary>
    private static string Quote(string text)
    {
        var quoted = new StringBuilder(text.Length + 2).Append('"');

        foreach (var character in text)
        {
            switch (character)
            {
                case '\\':
                    quoted.Append("\\\\");
                    break;
                case '"':
                    quoted.Append("\\\"");
                    break;
                // A hex escape ends at the space, which is consumed with it: nothing extra is printed.
                case '<':
                    quoted.Append("\\3C ");
                    break;
                case '\r':
                case '\n':
                    quoted.Append("\\A ");
                    break;
                default:
                    quoted.Append(character);
                    break;
            }
        }

        return quoted.Append('"').ToString();
    }

    private enum Placeholder
    {
        Literal,
        Page,
        TotalPages,
        Title,
        FileName,
        FileNameWithExtension,
        FilePath,
        Date,
        Time,
        DateTime,
    }

    /// <param name="Text">The literal text, or — for a date placeholder — its format string.</param>
    private readonly record struct Part(Placeholder Kind, string Text);

    private static bool TryParse(string? template, out List<Part> parts, out string error)
    {
        parts = [];
        error = string.Empty;

        if (string.IsNullOrEmpty(template))
        {
            return true;
        }

        var literal = new StringBuilder();

        for (var index = 0; index < template.Length; index++)
        {
            var character = template[index];

            if (character is '{' or '}' && index + 1 < template.Length && template[index + 1] == character)
            {
                literal.Append(character);
                index++;
                continue;
            }

            if (character == '}')
            {
                error = "an unmatched closing brace. Write it twice for a literal one.";
                return false;
            }

            if (character != '{')
            {
                literal.Append(character);
                continue;
            }

            var close = template.IndexOf('}', index + 1);
            if (close < 0)
            {
                error = "an unmatched opening brace. Write it twice for a literal one.";
                return false;
            }

            if (!TryReadPlaceholder(template[(index + 1)..close], out var placeholder, out error))
            {
                return false;
            }

            AppendLiteral(literal, parts);
            parts.Add(placeholder);
            index = close;
        }

        AppendLiteral(literal, parts);
        return true;

        static void AppendLiteral(StringBuilder literal, List<Part> parts)
        {
            if (literal.Length > 0)
            {
                parts.Add(new Part(Placeholder.Literal, literal.ToString()));
                literal.Clear();
            }
        }
    }

    private static bool TryReadPlaceholder(string body, out Part part, out string error)
    {
        part = default;
        error = string.Empty;

        var colon = body.IndexOf(':');
        var name = (colon < 0 ? body : body[..colon]).Trim();
        var format = colon < 0 ? null : body[(colon + 1)..];

        // Matched without regard to case, for the same reason --paper accepts "letter": a reader
        // typing into a shell should not have to remember which words are capitalised.
        var kind = name.ToLowerInvariant() switch
        {
            "page" => Placeholder.Page,
            "totalpages" => Placeholder.TotalPages,
            "title" => Placeholder.Title,
            "filename" => Placeholder.FileName,
            "filenamewithext" => Placeholder.FileNameWithExtension,
            "filepath" => Placeholder.FilePath,
            "date" => Placeholder.Date,
            "time" => Placeholder.Time,
            "datetime" => Placeholder.DateTime,
            _ => Placeholder.Literal,
        };

        if (kind == Placeholder.Literal)
        {
            error = $"the unknown placeholder {Brace(body)}. The placeholders are {KnownPlaceholders}.";
            return false;
        }

        if (format is null)
        {
            part = new Part(kind, string.Empty);
            return true;
        }

        if (kind is not (Placeholder.Date or Placeholder.Time or Placeholder.DateTime))
        {
            error = $"a format on {Brace(name)}, which takes none. Only {{Date}}, {{Time}} and {{DateTime}} do.";
            return false;
        }

        if (format.Length == 0)
        {
            error = $"an empty format on {Brace(name)}. Give a .NET date and time format, or drop the colon.";
            return false;
        }

        try
        {
            // Proved usable now, against a real moment, so a bad format is a command-line error the
            // reader is told about rather than a surprise in the middle of a printed page.
            _ = DateTimeOffset.UnixEpoch.ToString(format, CultureInfo.InvariantCulture);
        }
        catch (FormatException)
        {
            error = $"'{format}' is not a usable .NET date and time format.";
            return false;
        }

        part = new Part(kind, format);
        return true;
    }

    private static string Brace(string name) => "{" + name + "}";
}
