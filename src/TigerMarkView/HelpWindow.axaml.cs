using System;
using System.Globalization;
using System.IO;
using System.Threading.Tasks;
using Avalonia.Controls;
using Avalonia.Threading;
using TigerMarkView.Core.Navigation;
using TigerMarkView.Core.Rendering;
using TigerMarkView.Documentation;
using TigerMarkView.Hosting;
using TigerMarkView.Navigation;
using TigerMarkView.Windowing;

namespace TigerMarkView;

/// <summary>
/// The bundled offline documentation, rendered by TigerMarkView's own Markdown pipeline in a window of
/// its own.
/// </summary>
/// <remarks>
/// <para>
/// <strong>Help is an application-owned context, not a document the reader opened.</strong> That is the
/// whole reason it is a separate window rather than something shown in the viewer: a reader partway
/// through <c>A.md → B.md → C.md</c> must get all of it back untouched when Help closes. Nothing here
/// goes near <see cref="MainWindow.OpenFile"/>, so opening Help cannot add to Open Recent, cannot
/// append to the navigation trail, attaches no <see cref="Monitoring.DocumentWatcher"/>, does not
/// change what Open in Editor or Export to PDF act on, and leaves the reading position where it was.
/// The main window is not navigated at all.
/// </para>
/// <para>
/// It renders through <see cref="MarkdownDocumentLoader"/> exactly as the viewer does — same Markdig
/// pipeline, same stylesheet, same themes, same in-page anchor script — so help looks like any other
/// TigerMarkView document, and there is no second help system to keep in step with the first.
/// </para>
/// </remarks>
public partial class HelpWindow : Window
{
    /// <summary>
    /// Help's own generated page. Deliberately <em>not</em> the viewer's <c>preview.html</c>: sharing
    /// one file would have Help and the document overwrite each other's rendering, which is the session
    /// interference this window exists to avoid.
    /// </summary>
    private static readonly string PreviewHtmlPath =
        Path.Combine(Path.GetTempPath(), "TigerMarkView", "help.html");

    /// <summary>
    /// The one Help window, if it is open. F1 is easy to lean on, and a help window per keypress is
    /// nobody's idea of help — a second request re-uses this one and brings it forward.
    /// </summary>
    private static HelpWindow? _instance;

    private readonly ExternalLinkLauncher _linkLauncher = new();

    private BundledDocument _document = BundledDocuments.Help;
    private MarkdownTheme _theme;
    private double? _pendingScrollY;

    public HelpWindow() : this(MarkdownTheme.Light)
    {
    }

    public HelpWindow(MarkdownTheme theme)
    {
        _theme = theme;

        InitializeComponent();

        // Same reason as the viewer: the default WebView2 profile location is the application
        // directory, which an all-users install makes read-only. See WebViewProfile.
        WebViewProfile.Attach(Browser);

        Browser.NavigationCompleted += OnNavigationCompleted;

        // Same rule as the viewer, for the same reason: the WebView is a native child window that
        // follows links and takes drops on its own, so every navigation away from the generated page is
        // intercepted rather than trusted.
        Browser.NavigationStarted += OnNavigationStarted;
        Browser.NewWindowRequested += OnNewWindowRequested;
    }

    /// <summary>
    /// Shows <paramref name="document"/> in the Help window, opening it if it is not already open and
    /// bringing it forward if it is.
    /// </summary>
    /// <remarks>
    /// Modeless and owned by <paramref name="owner"/>: the reader can carry on with their document
    /// while help is open, and an owned window cannot get lost behind the application it explains.
    /// </remarks>
    public static void ShowDocument(Window owner, MarkdownTheme theme, BundledDocument document)
    {
        ArgumentNullException.ThrowIfNull(owner);
        ArgumentNullException.ThrowIfNull(document);

        if (_instance is { } existing)
        {
            existing.LoadDocument(document);
            existing.Activate();
            return;
        }

        var window = new HelpWindow(theme);
        _instance = window;
        window.Closed += (_, _) =>
        {
            if (ReferenceEquals(_instance, window))
            {
                _instance = null;
            }
        };

        window.LoadDocument(document);
        window.Show(owner);
    }

    /// <summary>
    /// Repaints an open Help window in <paramref name="theme"/>. Called from the main window's theme
    /// switch, so the two windows never disagree about which theme the application is in.
    /// </summary>
    public static void ApplyTheme(MarkdownTheme theme) => _instance?.SetTheme(theme);

    protected override void OnOpened(EventArgs e)
    {
        base.OnOpened(e);

        // The native caption is the one surface Avalonia's theme variant does not reach — same DWM
        // nudge the main window and the dialogs get.
        NativeTitleBar.Apply(this, _theme);
    }

    private void LoadDocument(BundledDocument document)
    {
        _document = document;

        // Same shape as the viewer's "README.md — TigerMarkView", so the two windows read as one
        // application rather than two products.
        Title = $"{document.Title} — TigerMarkView";

        Render(scrollY: null);
    }

    private async void SetTheme(MarkdownTheme theme)
    {
        if (_theme == theme)
        {
            return;
        }

        _theme = theme;
        NativeTitleBar.Apply(this, theme);

        // Re-rendering is a fresh navigation, so the reader's place has to be carried across it — the
        // same capture/restore the viewer uses for a theme switch.
        Render(await TryCaptureScrollYAsync());
    }

    /// <summary>
    /// Renders the current bundled document and puts it on screen.
    /// </summary>
    /// <remarks>
    /// A missing or unreadable help file is reported on the error page rather than thrown: documentation
    /// that failed to install is a disappointment, not a crash, and the reader still has the rest of the
    /// application.
    /// </remarks>
    private void Render(double? scrollY)
    {
        string html;

        try
        {
            var text = File.ReadAllText(_document.Path);
            html = MarkdownDocumentLoader.RenderHtmlDocument(_document.Path, AsMarkdown(_document.Path, text), _theme);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException
                                       or NotSupportedException or System.Security.SecurityException)
        {
            html = MarkdownRenderer.ToErrorDocument(_document.Path, ex.Message, _theme);
        }

        WritePreviewHtml(html);
        _pendingScrollY = scrollY;
        NavigateBrowser();
    }

    /// <summary>
    /// Markdown is rendered as Markdown; anything else — in practice the repository's extensionless
    /// LICENSE, copied to the output as a <c>.txt</c> — is shown verbatim in a code block. Reflowing a
    /// licence into prose paragraphs would silently reformat a legal text, and keeping a second,
    /// Markdown copy of it in the repository is how the two would come to disagree.
    /// </summary>
    private static string AsMarkdown(string path, string text) =>
        MarkdownLinkResolver.IsMarkdownPath(path) ? text : $"```text\n{text}\n```";

    private static void WritePreviewHtml(string html)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(PreviewHtmlPath)!);
        File.WriteAllText(PreviewHtmlPath, html);
    }

    /// <summary>
    /// Help re-uses one generated file, so a re-render would otherwise navigate to an equal
    /// <see cref="Uri"/> and might not refresh at all. The per-navigation cache-buster the viewer uses
    /// solves it here for the same reason — a theme switch has to actually repaint.
    /// </summary>
    private void NavigateBrowser()
    {
        var builder = new UriBuilder(new Uri(PreviewHtmlPath)) { Query = $"t={DateTime.UtcNow.Ticks}" };
        Browser.Source = builder.Uri;
    }

    private async void OnNavigationCompleted(object? sender, WebViewNavigationCompletedEventArgs e)
    {
        var scrollY = _pendingScrollY;
        _pendingScrollY = null;

        if (e.IsSuccess && scrollY is { } y)
        {
            try
            {
                await Browser.InvokeScript($"window.scrollTo(0, {y.ToString(CultureInfo.InvariantCulture)});");
            }
            catch
            {
                // Best-effort, exactly as in the viewer: losing the reading position is not a failure.
            }
        }
    }

    private async Task<double?> TryCaptureScrollYAsync()
    {
        try
        {
            var result = await Browser.InvokeScript("window.scrollY");
            return double.TryParse(result, NumberStyles.Float, CultureInfo.InvariantCulture, out var y) ? y : null;
        }
        catch
        {
            return null;
        }
    }

    private void OnNavigationStarted(object? sender, WebViewNavigationStartingEventArgs e)
    {
        if (e.Request is { } target && !IsOwnPreviewNavigation(target) && TryHandleNavigation(target))
        {
            e.Cancel = true;
        }
    }

    private void OnNewWindowRequested(object? sender, WebViewNewWindowRequestedEventArgs e)
    {
        e.Handled = true;

        if (e.Request is { } target)
        {
            TryHandleNavigation(target);
        }
    }

    /// <summary>
    /// Where a link in the help documentation is allowed to go.
    /// </summary>
    /// <remarks>
    /// Three answers, and the third is the important one. A link to another <em>bundled</em> document
    /// stays in this window, so help can cross-reference itself without ever reaching the viewer's
    /// recent-files or history machinery. An <c>http</c>/<c>https</c>/<c>mailto</c> link leaves for the
    /// system browser or mail client, the same launcher the viewer uses. Everything else — any other
    /// local file, including a Markdown file elsewhere on the disk — is refused: help is documentation
    /// that ships with the application, not a second way to open documents.
    /// </remarks>
    private bool TryHandleNavigation(Uri target)
    {
        if (MarkdownLinkResolver.TryResolveLocalMarkdown(target, out var markdownPath) &&
            BundledDocuments.Contains(markdownPath))
        {
            // Posted rather than called directly: this runs inside the WebView's own navigation
            // callback, and starting the replacement navigation from there re-enters it.
            Dispatcher.UIThread.Post(() =>
                LoadDocument(new BundledDocument(markdownPath, Path.GetFileName(markdownPath))));
            return true;
        }

        if (ExternalLinkLauncher.IsLaunchableScheme(target))
        {
            var outcome = _linkLauncher.Open(target);
            if (!outcome.Success)
            {
                // No status bar to report into here, and the failure is worth saying out loud rather
                // than leaving a link that appears to do nothing. Posted for the same re-entrancy
                // reason as the branch above.
                Dispatcher.UIThread.Post(() =>
                    _ = MessageDialog.ShowAsync(this, "Could not open the link", outcome.ErrorMessage ?? "Unknown error."));
            }

            return true;
        }

        return target.IsFile;
    }

    private static bool IsOwnPreviewNavigation(Uri target)
    {
        if (!target.IsAbsoluteUri || !target.IsFile)
        {
            return false;
        }

        try
        {
            return string.Equals(
                Path.GetFullPath(target.LocalPath),
                PreviewHtmlPath,
                StringComparison.OrdinalIgnoreCase);
        }
        catch (Exception ex) when (ex is ArgumentException or NotSupportedException or PathTooLongException)
        {
            return false;
        }
    }
}
