using System.Globalization;
using TigerMarkView.Core.Exporting;

namespace TigerMarkView.Core.Rendering;

/// <summary>
/// The CSS that turns Markdig's HTML fragment into a readable document.
/// </summary>
/// <remarks>
/// Deliberately structured as <em>one</em> layout/structure stylesheet (<see cref="Css"/>) written
/// entirely against CSS custom properties, plus a small per-theme block that supplies nothing but
/// colour values (<see cref="ThemeCss"/>). Adding a theme is therefore a new token block, not a second
/// copy of the whole shell. <see cref="PrintCss"/> is the third, independent layer: it re-declares the
/// light token values inside <c>@media print</c>, which is what keeps PDF output readable regardless
/// of the theme the viewer happens to be using.
/// </remarks>
internal static class DocumentShell
{
    public static string ThemeCss(MarkdownTheme theme) => theme switch
    {
        MarkdownTheme.Dark => DarkThemeCss,
        _ => LightThemeCss,
    };

    /// <summary>Colour tokens only — every structural rule lives in <see cref="Css"/>.</summary>
    public const string LightThemeCss = """
        :root {
          color-scheme: light;
          --page-bg: #ffffff;
          --text: #1f2328;
          --text-muted: #57606a;
          --heading: #1f2328;
          --link: #0969da;
          --border: #d0d7de;
          --code-bg: #f6f8fa;
          --code-text: #1f2328;
          /* Transparent rather than absent so the dark theme can add a code-block outline without
             the light theme's appearance changing from earlier phases. */
          --code-border: transparent;
          --table-header-bg: #f6f8fa;
          --quote-border: #d0d7de;
          /* Syntax colours, used only when the Syntax Highlighting rendering option is on. Eight
             semantic tokens rather than one per language construct — see SyntaxScopes. */
          --syn-keyword: #cf222e;
          --syn-comment: #6e7781;
          --syn-string: #0a3069;
          --syn-number: #0550ae;
          --syn-type: #116329;
          --syn-function: #8250df;
          --syn-variable: #953800;
          --syn-operator: #24292f;
        }
        """;

    public const string DarkThemeCss = """
        :root {
          color-scheme: dark;
          --page-bg: #0d1117;
          --text: #e6edf3;
          --text-muted: #9198a1;
          --heading: #f0f6fc;
          --link: #4493f8;
          --border: #30363d;
          --code-bg: #161b22;
          --code-text: #e6edf3;
          --code-border: #30363d;
          --table-header-bg: #161b22;
          --quote-border: #3d444d;
          /* The same eight roles, lifted for a #161b22 code background. */
          --syn-keyword: #ff7b72;
          --syn-comment: #8b949e;
          --syn-string: #a5d6ff;
          --syn-number: #79c0ff;
          --syn-type: #7ee787;
          --syn-function: #d2a8ff;
          --syn-variable: #ffa657;
          --syn-operator: #c9d1d9;
        }
        """;

    public const string Css = """
        html { background: var(--page-bg); }
        body {
          font-family: -apple-system, "Segoe UI", Helvetica, Arial, sans-serif;
          line-height: 1.6;
          color: var(--text);
          background: var(--page-bg);
          /* Adaptive reading column. A fixed 800px left a maximized window mostly empty margin, and
             dropping the constraint entirely would run prose to the full width of a 4K display. The
             clamp keeps ordinary windows close to the familiar width (a 1000px window still renders
             at ~800px), lets wider ones grow with the viewport, and stops at 64rem — sized for a
             maximized 1080p display as the point past which prose lines start reading as too long.
             Beyond that the extra space stays as margin. Tables, code blocks, and images all inherit
             the gain. */
          max-width: clamp(46rem, 80vw, 64rem);
          margin: 2rem auto;
          padding: 0 1.5rem;
        }
        h1, h2, h3, h4, h5, h6 { color: var(--heading); }
        h1, h2, h3 { line-height: 1.25; margin-top: 1.6em; }
        h1, h2 { border-bottom: 1px solid var(--border); padding-bottom: .3em; }
        a { color: var(--link); text-decoration: none; }
        a:hover { text-decoration: underline; }
        code, pre {
          font-family: ui-monospace, "Cascadia Code", Consolas, monospace;
          background: var(--code-bg);
          color: var(--code-text);
          border-radius: 6px;
        }
        /* Scale an oversized image down to the reading column instead of forcing the whole page to
           scroll sideways. `height: auto` overrides any intrinsic height so the aspect ratio is kept,
           and `max-width` (not `width`) leaves images narrower than the column at their natural size
           rather than blowing them up. Print has its own copy of this rule — see PrintCss. */
        img { max-width: 100%; height: auto; }
        code { padding: .2em .4em; font-size: 85%; }
        pre { padding: 1em; overflow: auto; border: 1px solid var(--code-border); }
        pre code { padding: 0; background: none; border: 0; }
        /* Syntax spans. Present in every document and inert in almost all of them: they only ever
           match markup HighlightedCodeBlockRenderer wrote, which happens when the Syntax Highlighting
           rendering option is on and the fence named a language ColorCode knows. Colour only — no
           italics, no weights, no backgrounds: a listing being reviewed should read as code with some
           structure picked out, not as a paint chart. */
        pre code .syn-keyword { color: var(--syn-keyword); }
        pre code .syn-comment { color: var(--syn-comment); }
        pre code .syn-string { color: var(--syn-string); }
        pre code .syn-number { color: var(--syn-number); }
        pre code .syn-type { color: var(--syn-type); }
        pre code .syn-function { color: var(--syn-function); }
        pre code .syn-variable { color: var(--syn-variable); }
        pre code .syn-operator { color: var(--syn-operator); }
        table { border-collapse: collapse; width: 100%; margin: 1em 0; }
        th, td { border: 1px solid var(--border); padding: 6px 13px; }
        th { background: var(--table-header-bg); }
        blockquote { border-left: 4px solid var(--quote-border); margin: 1em 0; padding: 0 1em; color: var(--text-muted); }
        hr { border: 0; border-top: 1px solid var(--border); margin: 1.5em 0; }
        """;

    /// <summary>
    /// Keeps in-document <c>#anchor</c> links inside the document.
    /// </summary>
    /// <remarks>
    /// Needed because the generated HTML carries a <c>&lt;base href&gt;</c> pointing at the Markdown
    /// file's own directory (that is what makes relative images resolve). Per the URL spec a
    /// fragment-only link resolves against the <em>base</em> URL, not the current document's, so
    /// <c>[Tables](#tables)</c> becomes a navigation to <c>file:///…/source-dir/#tables</c> and leaves
    /// the page entirely. Intercepting the click and scrolling manually restores the behaviour a
    /// reader expects, without giving up the base href. Inert during printing, so PDF output is
    /// unaffected — page-internal link destinations still come from the <c>href</c> attributes.
    /// </remarks>
    public const string AnchorScript = """
        document.addEventListener('click', function (event) {
          var anchor = event.target && event.target.closest ? event.target.closest('a') : null;
          if (!anchor) { return; }
          var href = anchor.getAttribute('href');
          if (!href || href.charAt(0) !== '#') { return; }
          event.preventDefault();
          var id = decodeURIComponent(href.slice(1));
          var target = document.getElementById(id) || document.getElementsByName(id)[0];
          if (target) { target.scrollIntoView(); }
        });
        """;

    /// <summary>
    /// Forwards the Alt+Left / Alt+Right navigation shortcuts from the page to the host.
    /// </summary>
    /// <remarks>
    /// The WebView is a native child window that keeps its own keyboard input, so a shortcut handled
    /// on the Avalonia side only works while focus is on the menu bar or status bar — which is almost
    /// never, since the reader is in the document. Listening in the page and posting a message back is
    /// what makes Back/Forward reachable from the keyboard where it is actually wanted. The guard
    /// leaves the script inert anywhere the host object is absent, so nothing breaks during PDF export.
    /// The host's message name is prefixed to keep it distinguishable from any future channel.
    /// </remarks>
    public const string NavigationShortcutScript = """
        document.addEventListener('keydown', function (event) {
          if (!event.altKey || event.ctrlKey || event.shiftKey || event.metaKey) { return; }
          var command = event.key === 'ArrowLeft' ? 'back'
                      : event.key === 'ArrowRight' ? 'forward' : null;
          if (!command) { return; }
          event.preventDefault();
          if (window.chrome && window.chrome.webview) {
            window.chrome.webview.postMessage('tigermarkview:navigate:' + command);
          }
        });
        """;

    /// <summary>
    /// Forwards F1 from the page to the host, so the standard help shortcut works where the reader is.
    /// </summary>
    /// <remarks>
    /// The same native-child-window problem <see cref="NavigationShortcutScript"/> solves: a key
    /// handled on the Avalonia side only fires while focus is on the menu bar or status bar, which for
    /// a reader scrolling a document is almost never. Guarded on the host object exactly as the
    /// navigation script is, so it is inert during PDF export and in any page rendered without a host.
    /// </remarks>
    public const string HelpShortcutScript = """
        document.addEventListener('keydown', function (event) {
          if (event.key !== 'F1' || event.altKey || event.ctrlKey || event.shiftKey || event.metaKey) { return; }
          event.preventDefault();
          if (window.chrome && window.chrome.webview) {
            window.chrome.webview.postMessage('tigermarkview:help');
          }
        });
        """;

    /// <summary>
    /// Forwards Ctrl+P from the page to the host, and — just as importantly — stops Chromium handling
    /// it itself.
    /// </summary>
    /// <remarks>
    /// The native-child-window problem the other two shortcut scripts solve, plus one this key has on
    /// its own: WebView2 treats Ctrl+P as a browser accelerator and would open Edge's print preview
    /// over the document. That preview knows nothing of the paper, margins, or page numbers
    /// TigerMarkView laid the document out for, so it is not an alternative route to the same result —
    /// it is a second, wrong one. <c>preventDefault</c> runs before the host check, so the browser UI
    /// stays suppressed even in a page rendered without a host (during PDF export, where no key is
    /// pressed anyway).
    /// </remarks>
    public const string PrintShortcutScript = """
        document.addEventListener('keydown', function (event) {
          if (event.key !== 'p' && event.key !== 'P') { return; }
          if (!event.ctrlKey || event.altKey || event.shiftKey || event.metaKey) { return; }
          event.preventDefault();
          if (window.chrome && window.chrome.webview) {
            window.chrome.webview.postMessage('tigermarkview:print');
          }
        });
        """;

    /// <summary>
    /// Print/PDF layer over <see cref="Css"/>. Emitted into the same &lt;style&gt; block as the screen
    /// CSS so a single generated HTML document drives both the on-screen viewer and PDF export — there
    /// is no parallel "PDF document" rendering path. Everything here is scoped to <c>@media print</c>
    /// (plus the page box itself via <c>@page</c>) so it has no effect on-screen.
    /// </summary>
    /// <remarks>
    /// The only part that varies is the <c>@page</c> rule, which is written from
    /// <paramref name="page"/>; every rule inside <c>@media print</c> is fixed. So a change of paper,
    /// orientation, margins, or page numbering is a different page box around the same typography,
    /// never a different stylesheet.
    /// </remarks>
    public static string PrintCss(PdfPageSetup page) => PageRule(page) + Environment.NewLine + PrintRules;

    /// <summary>
    /// The page box: physical sheet, printable inset, and — when asked for — the page number.
    /// </summary>
    /// <remarks>
    /// <para>
    /// The sheet size is stated here as well as being handed to the print engine. The engine's value
    /// governs the PDF's MediaBox, while the CSS declaration ensures any other print consumer also
    /// uses the paper the document was laid out for.
    /// </para>
    /// <para>
    /// Page numbers are a CSS margin box supported by the WebView2 Chromium engine. That keeps
    /// numbering inside the one
    /// rendering pipeline — no second PDF renderer, no JavaScript pagination, no post-processing.
    /// Because a margin box lives in the <em>margin</em>, the printable area shrinks to make room for
    /// it and document content can never be overprinted or clipped by a number; the deterministic
    /// widening of a too-small bottom margin is <see cref="PdfPageSetup.PrintMargins"/>.
    /// </para>
    /// </remarks>
    private static string PageRule(PdfPageSetup page)
    {
        var margins = page.PrintMargins;

        var pageNumber = page.ShowPageNumbers
            ? """

                @bottom-center {
                  content: counter(page);
                  font-family: -apple-system, "Segoe UI", Helvetica, Arial, sans-serif;
                  font-size: 9pt;
                  /* The light theme's muted text colour, stated literally: a margin box sits outside
                     the document tree, so it does not inherit the :root custom properties. */
                  color: #57606a;
                }
              """
            : string.Empty;

        return string.Create(
            CultureInfo.InvariantCulture,
            $$"""
              @page {
                size: {{Mm(page.WidthMillimetres)}} {{Mm(page.HeightMillimetres)}};
                margin: {{Mm(margins.TopMillimetres)}} {{Mm(margins.RightMillimetres)}} {{Mm(margins.BottomMillimetres)}} {{Mm(margins.LeftMillimetres)}};{{pageNumber}}
              }
              """);
    }

    /// <summary>
    /// A CSS length in millimetres. Invariant culture, because a decimal comma (Letter is 215.9 mm
    /// wide) would be a syntax error the stylesheet silently drops.
    /// </summary>
    private static string Mm(double millimetres) =>
        millimetres.ToString("0.####", CultureInfo.InvariantCulture) + "mm";

    private const string PrintRules = """
        @media print {
          /* Paper is white whatever the viewer is set to. Re-declaring the tokens here (rather than
             overriding every individual rule) is what makes a Dark-mode viewer still export a normal,
             readable, ink-sensible PDF — the structural rules in Css need no print-specific variants. */
          :root {
            color-scheme: light;
            --page-bg: #ffffff;
            --text: #000000;
            --text-muted: #3d444d;
            --heading: #000000;
            --link: #0b4f9e;
            --border: #c8ced4;
            --code-bg: #f6f8fa;
            --code-text: #000000;
            --code-border: #d8dee4;
            --table-header-bg: #f1f3f5;
            --quote-border: #c8ced4;
            /* A print palette of its own, not a copy of either screen palette. Everything here sits in
               a narrow dark band on white: the light theme's #6e7781 comment and #8250df function read
               fine backlit but wash out on paper, and the dark theme's colours are unusable on it. Each
               token stays dark enough to survive a greyscale printer, and the operator colour is very
               nearly the body text — colouring every bracket is what makes a printed listing look
               noisy. */
            --syn-keyword: #0b3d91;
            --syn-comment: #4f5b66;
            --syn-string: #8b1a1a;
            --syn-number: #7a4100;
            --syn-type: #0f5c5a;
            --syn-function: #5b2a86;
            --syn-variable: #0a5c2e;
            --syn-operator: #2f3a45;
          }
          html, body { background: #fff; }
          body {
            max-width: none;
            margin: 0;
            padding: 0;
            font-size: 10.5pt;
            line-height: 1.5;
            color: #000;
          }
          /* Links stay visually distinct, including in-document anchors: WebView2 keeps both external
             and internal links live in the PDF, so styling them as plain text would hide that. */
          a { color: var(--link); text-decoration: none; }

          h1, h2, h3, h4, h5, h6 {
            /* Keep a heading with the content it introduces instead of stranding it at a page foot.
               Chromium ignores `avoid` when the following block cannot fit anywhere, so this cannot
               produce a runaway blank page. */
            break-after: avoid;
            page-break-after: avoid;
            break-inside: avoid;
            page-break-inside: avoid;
            margin: 1.1em 0 .5em;
          }
          h1 { font-size: 19pt; margin-top: 0; }
          h2 { font-size: 15pt; }
          h3 { font-size: 12.5pt; }
          h4, h5, h6 { font-size: 11pt; }
          h1, h2 { border-bottom: 1px solid var(--border); padding-bottom: .2em; }

          p, ul, ol, dl { orphans: 3; widows: 3; margin: .6em 0; }
          li { break-inside: avoid; page-break-inside: avoid; }

          pre {
            background: var(--code-bg);
            border: 1px solid var(--code-border);
            padding: .7em .9em;
            font-size: 9pt;
            line-height: 1.4;
            /* Paper has no horizontal scrollbar, so long lines must wrap rather than be clipped. */
            white-space: pre-wrap;
            overflow-wrap: anywhere;
            overflow: visible;
            /* Deliberately left breakable: a listing longer than the remaining space would otherwise
               be pushed whole to the next page and leave most of a page blank. */
            break-inside: auto;
            page-break-inside: auto;
            orphans: 2;
            widows: 2;
          }
          code { font-size: 9pt; background: #f2f4f6; color: #000; overflow-wrap: anywhere; }
          pre code { font-size: inherit; background: none; }

          table {
            /* Fixed layout keeps wide tables inside the page box; automatic layout lets them run off
               the right edge, and print has no way to scroll to the clipped columns. */
            table-layout: fixed;
            width: 100%;
            font-size: 9pt;
            break-inside: auto;
            page-break-inside: auto;
          }
          th, td { padding: 4px 7px; overflow-wrap: anywhere; }
          thead { display: table-header-group; }
          tr { break-inside: avoid; page-break-inside: avoid; }

          blockquote { break-inside: avoid; page-break-inside: avoid; color: #3d444d; }

          img { max-width: 100%; height: auto; break-inside: avoid; page-break-inside: avoid; }

          hr { border: 0; border-top: 1px solid var(--border); margin: 1.2em 0; }

          input[type="checkbox"] { margin-right: .35em; }
        }
        """;
}
