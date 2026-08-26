using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Media;
using Avalonia.Platform.Storage;
using Avalonia.Threading;
using System.Threading;
using TigerMarkView.Core.Editing;
using TigerMarkView.Core.Exporting;
using TigerMarkView.Core.Formatting;
using TigerMarkView.Core.Monitoring;
using TigerMarkView.Core.Navigation;
using TigerMarkView.Core.Rendering;
using TigerMarkView.Core.Settings;
using TigerMarkView.Core.Windowing;
using TigerMarkView.Documentation;
using TigerMarkView.Editing;
using TigerMarkView.Hosting;
using TigerMarkView.Menus;
using TigerMarkView.Monitoring;
using TigerMarkView.Navigation;
using TigerMarkView.Pdf;
using TigerMarkView.Settings;
using TigerMarkView.Shell;
using TigerMarkView.Windowing;

namespace TigerMarkView;

public partial class MainWindow : Window
{
    private static readonly TimeSpan StatusRefreshInterval = TimeSpan.FromSeconds(15);

    // How long a one-off note ("that link is not a Markdown document") stays in the status bar before
    // the normal freshness status takes it back.
    private static readonly TimeSpan TransientStatusDuration = TimeSpan.FromSeconds(6);

    // A successful export outlasts an ordinary note on purpose: it is not just an acknowledgement but
    // the only place the two export actions appear, so it has to survive being noticed, read, and
    // acted on — which a toast-length message does not allow for.
    private static readonly TimeSpan PdfExportSuccessDuration = TimeSpan.FromSeconds(12);

    private static readonly string PreviewHtmlPath =
        Path.Combine(Path.GetTempPath(), "TigerMarkView", "preview.html");


    // Fixed status-dot colours rather than theme resources: a 10px dot has to stay legible against
    // both a white and a near-black status bar, and these read correctly on both.
    private static readonly IBrush ErrorDotBrush = new SolidColorBrush(Color.FromRgb(0xE5, 0x48, 0x4D));
    private static readonly IBrush NewerOnDiskDotBrush = new SolidColorBrush(Color.FromRgb(0xF0, 0x88, 0x3E));
    private static readonly IBrush RecentlyReloadedDotBrush = new SolidColorBrush(Color.FromRgb(0x3F, 0xB9, 0x50));
    private static readonly IBrush NeutralDotBrush = new SolidColorBrush(Color.FromRgb(0x8B, 0x94, 0x9E));

    // Avalonia 12 exposes no frame size before a window is shown, so the caption and borders have to
    // be estimated when the restored geometry is fitted to a monitor. Erring generous is the safe
    // direction: a window a few units shorter than it could be is invisible to the user, whereas an
    // under-estimate is exactly the bug being fixed — a title bar pushed off the top of the screen.
    private const double EstimatedFrameWidth = 16;
    private const double EstimatedFrameHeight = 44;

    // Long enough for a drag to finish and — importantly — for WindowState to catch up with a
    // maximize, which fires size/move events *before* the property reports the new state.
    private static readonly TimeSpan WindowPlacementSettleDelay = TimeSpan.FromMilliseconds(400);

    private readonly DispatcherTimer _statusRefreshTimer;
    private readonly DispatcherTimer _statusOverrideTimer;
    private readonly DispatcherTimer _windowPlacementTimer;
    private readonly ExternalEditorLauncher _editorLauncher = new();
    private readonly ExternalLinkLauncher _linkLauncher = new();
    private readonly ShellLauncher _shellLauncher = new();

    /// <summary>
    /// The latest successful PDF export of each document, for this session only. Keyed by the Markdown
    /// document so the status bar's folder action can never point at some other document's PDF.
    /// </summary>
    private readonly ExportedPdfRegistry _exportedPdfs = new();

    /// <summary>
    /// Back/Forward over documents. Only <see cref="OpenDocumentAsync"/> and
    /// <see cref="NavigateHistoryAsync"/> touch it — reloads, theme switches, PDF export, and Open in
    /// Editor all act on the document already current and deliberately leave history alone.
    /// </summary>
    private readonly NavigationHistory _history = new();

    private readonly ApplicationSettings _settings;
    private readonly SettingsStore _settingsStore;
    private ReloadMode _currentReloadMode;
    private EditorConfiguration _editorConfiguration;
    private MarkdownTheme _theme;

    /// <summary>
    /// Which command surfaces are showing. Held as the Core value rather than as two booleans so the
    /// "at least one of them" rule is carried by the type: every change goes through
    /// <see cref="CommandSurfaces.WithMenuBar"/> / <see cref="CommandSurfaces.WithToolbar"/>, which
    /// cannot produce a window with no way to reach a command.
    /// </summary>
    private CommandSurfaces _commandSurfaces;

    /// <summary>
    /// Which of the toolbar's optional commands — Open Recent, Export to PDF — are on it.
    /// Held as the Core value for the same reason <see cref="_commandSurfaces"/> is: the layout rule
    /// that goes with it (whether the divider in front of the publishing group earns its place) belongs
    /// with the value, not scattered through the window.
    /// </summary>
    private ToolbarActions _toolbarActions;

    /// <summary>
    /// The paper every rendered document is laid out for, from the persisted PDF preferences. Held
    /// as resolved geometry rather than as the four menu choices, so nothing below this line has to
    /// know that presets exist.
    /// </summary>
    private PdfPageSetup _pdfPageSetup;

    /// <summary>
    /// The optional rendering behaviours every document is rendered with, from the persisted
    /// preferences under <c>View &gt; Rendering</c>. Held as the Core value so nothing below this line
    /// has to know there are two menu items behind it.
    /// </summary>
    private MarkdownRenderingOptions _renderingOptions;

    private DocumentWatcher? _watcher;
    private double? _pendingScrollY;

    // Last geometry the window had while *not* maximized — what a restore should reproduce. Tracked
    // in memory and written only on close, so dragging or resizing never touches the disk.
    private double? _normalWidth;
    private double? _normalHeight;
    private PixelPoint? _normalPosition;

    /// <summary>
    /// The version currently on screen. Retained (HTML included) rather than re-read on demand so
    /// PDF export reproduces exactly what the reader is looking at — see <see cref="OnExportPdfClick"/>.
    /// </summary>
    private RenderedDocument? _renderedDocument;

    /// <summary>
    /// The error page the viewer is showing, if it is showing one, kept in the form needed to redraw
    /// it. Never set at the same time as <see cref="_renderedDocument"/>: between them, and their both
    /// being null (the empty viewer), they say which of the three surfaces is on screen — which is all
    /// <see cref="RefreshViewerAsync"/> needs to redraw it.
    /// </summary>
    private ViewerErrorPage? _errorPage;

    private CancellationTokenSource? _pdfExportCancellation;
    private string? _statusOverride;

    /// <summary>
    /// The export the transient success message is about, and therefore what its Open-PDF action
    /// targets. Lives exactly as long as that message; the per-document memory in
    /// <see cref="_exportedPdfs"/> is what outlives it.
    /// </summary>
    private string? _recentExportPath;

    private bool _windowClosed;

    public MainWindow() : this(null, ApplicationSettings.CreateDefault(), new SettingsStore())
    {
    }

    public MainWindow(string? initialFilePath, ApplicationSettings settings, SettingsStore settingsStore)
    {
        ArgumentNullException.ThrowIfNull(settings);
        ArgumentNullException.ThrowIfNull(settingsStore);

        _settings = settings;
        _settingsStore = settingsStore;
        _currentReloadMode = settings.ReloadMode;
        _editorConfiguration = settings.ToEditorConfiguration();
        _theme = settings.Theme;
        _pdfPageSetup = settings.ToPdfPageSetup();
        _renderingOptions = settings.ToRenderingOptions();

        InitializeComponent();

        RestoreWindowPlacement(settings.Window);

        _windowPlacementTimer = new DispatcherTimer { Interval = WindowPlacementSettleDelay };
        _windowPlacementTimer.Tick += (_, _) => CaptureNormalPlacement();
        SizeChanged += (_, _) => ScheduleWindowPlacementCapture();
        PositionChanged += (_, _) => ScheduleWindowPlacementCapture();

        AddHandler(DragDrop.DropEvent, OnDrop);
        DragDrop.SetAllowDrop(this, true);

        // The History submenu is refilled when the Navigate menu opens — i.e. before the submenu
        // itself is shown. See BuildHistoryItems for why this is on-open rather than on-navigate, and
        // why it hangs off the parent menu rather than off the submenu's own opening.
        NavigateMenuItem.SubmenuOpened += (_, _) => HistoryMenuItem.ItemsSource = BuildHistoryItems();

        // Tunnelling, so Alt+Left/Right reach the shortcut before the menu bar's own Alt handling.
        AddHandler(KeyDownEvent, OnPreviewKeyDown, RoutingStrategies.Tunnel);

        // Before anything else touches the WebView: its browser profile must not default to the
        // application directory, which an all-users install makes read-only. See WebViewProfile.
        WebViewProfile.Attach(Browser);

        Browser.NavigationCompleted += OnNavigationCompleted;

        // The two events that keep the WebView from ever acting as a browser in its own right: every
        // navigation away from the generated preview, and every attempt to spawn a window, is routed
        // back through TigerMarkView's document pipeline instead. See OnNavigationStarted.
        Browser.NavigationStarted += OnNavigationStarted;
        Browser.NewWindowRequested += OnNewWindowRequested;
        Browser.WebMessageReceived += OnWebMessageReceived;

        SetReloadModeChecked(_currentReloadMode);
        SetEditorTypeMenuChecked(_editorConfiguration.Type);
        SetThemeMenuChecked(_theme);
        SetRenderingMenuChecked();
        SetPdfExportMenuChecked();
        App.ApplyThemeVariant(_theme);
        RebuildRecentFilesMenu();

        // Before ApplyCommandSurfaces, which greys the Toolbar Buttons submenu when the toolbar itself
        // is hidden and therefore has to run after the buttons it describes are on screen.
        ApplyToolbarActions(settings.ToToolbarActions(), persist: false);

        // Already repaired by ApplicationSettings.Normalized if the file claimed both were hidden, so
        // this restores a combination that is legal by construction.
        ApplyCommandSurfaces(settings.ToCommandSurfaces(), persist: false);
        SetStatusBarVisible(settings.StatusBarVisible, persist: false);

        UpdateNavigationCommandState();
        UpdateDocumentCommandState();

        _statusRefreshTimer = new DispatcherTimer { Interval = StatusRefreshInterval };
        _statusRefreshTimer.Tick += (_, _) => RefreshStatusBar();
        _statusRefreshTimer.Start();

        // Interval is set per message by SetStatusOverride — a link note and an export result do not
        // deserve the same dwell time.
        _statusOverrideTimer = new DispatcherTimer { Interval = TransientStatusDuration };
        _statusOverrideTimer.Tick += (_, _) => ClearStatusOverride();

        RefreshStatusBar();

        // Naming a file on the command line is the reader choosing a document, exactly as File > Open
        // is — so it is an entry point and belongs in Open Recent.
        if (initialFilePath is not null)
        {
            OpenFile(initialFilePath, DocumentOpenOrigin.ExplicitOpen);
        }
        else
        {
            // Started with nothing to read: the viewer still has to be *something*, and that something
            // has to follow the saved theme. Left unnavigated, the WebView shows its own white page,
            // which is a white slab in the middle of a Dark window.
            ShowEmptyViewer();
        }
    }

    /// <summary>
    /// The native caption is the one piece of the window Avalonia's theme variant does not reach, so it
    /// is themed here — once the window has a handle to theme, and again on every switch.
    /// </summary>
    protected override void OnOpened(EventArgs e)
    {
        base.OnOpened(e);
        NativeTitleBar.Apply(this, _theme);
    }

    /// <summary>
    /// File &gt; Open and the toolbar's Open button share this handler outright. Every toolbar command
    /// is wired to the same handler as its menu twin for the same reason: two entry points into one
    /// behaviour is the whole point of a toolbar, and a duplicated implementation would be free to
    /// drift.
    /// </summary>
    private async void OnOpenClick(object? sender, RoutedEventArgs e) => await OpenDocumentViaPickerAsync();

    private async Task OpenDocumentViaPickerAsync()
    {
        var files = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title = "Open Markdown File",
            AllowMultiple = false,
            FileTypeFilter = new[]
            {
                new FilePickerFileType("Markdown") { Patterns = new[] { "*.md", "*.markdown" } },
            },
        });

        var path = files.Count > 0 ? files[0].TryGetLocalPath() : null;
        if (path is not null)
        {
            OpenFile(path, DocumentOpenOrigin.ExplicitOpen);
        }
    }

    /// <summary>
    /// Exports the document <em>as currently viewed</em>, never whatever happens to be on disk at the
    /// moment of export. In Manual/Confirm mode the file may already be newer than the rendering on
    /// screen; for a review tool, silently publishing content the reviewer has not seen would be the
    /// worse failure. The status bar's "Newer version available" indicator is how the user knows to
    /// reload first.
    /// </summary>
    /// <remarks>
    /// The viewer theme does not leak into the PDF: the exported HTML always carries the print rules,
    /// which re-declare the light palette inside <c>@media print</c>. Exporting from Dark mode
    /// therefore yields the same ink-sensible document as exporting from Light.
    /// </remarks>
    private async void OnExportPdfClick(object? sender, RoutedEventArgs e)
    {
        if (_renderedDocument is not { } document || _pdfExportCancellation is not null)
        {
            return;
        }

        var outputPath = await AskForPdfDestinationAsync(document.FilePath);
        if (outputPath is null)
        {
            return;
        }

        using var cancellation = new CancellationTokenSource();
        _pdfExportCancellation = cancellation;

        // An earlier export's actions must not linger over the one now running: whatever this attempt
        // produces (or fails to) replaces them.
        _recentExportPath = null;
        SetStatusOverride("Exporting PDF…", duration: null);
        UpdateExportActionState();
        UpdateDocumentCommandState();

        try
        {
            // The document's own page setup, not the current preferences: the sheet handed to the
            // print engine has to be the one the retained HTML's @page rule was written for, and a
            // preference changed while this export was being set up must not split the two apart.
            var result = await PdfExporter.ExportAsync(
                new PdfExportRequest(document.Html, outputPath, document.PageSetup), cancellation.Token);

            if (_windowClosed)
            {
                // The user closed the window while the export was running (OnClosed cancelled it).
                // There is no longer a window to report to, and owning a dialog on it would throw.
                return;
            }

            if (result.Success)
            {
                // Recorded against the document that was printed, not against whatever is current by
                // the time this returns — the reader may have navigated on while the export ran.
                _exportedPdfs.Record(document.FilePath, result.OutputPath!);
                _recentExportPath = result.OutputPath!;

                SetStatusOverride($"PDF exported: {result.OutputPath}", PdfExportSuccessDuration);
                UpdateExportActionState();
            }
            else
            {
                // A failure leaves the previously recorded export for this document exactly as it was:
                // nothing but a success ever writes to the registry.
                ClearStatusOverride();
                await MessageDialog.ShowAsync(this, "Could not export PDF", result.ErrorMessage ?? "Unknown error.");
            }
        }
        finally
        {
            _pdfExportCancellation = null;
            UpdateDocumentCommandState();
        }
    }

    private async Task<string?> AskForPdfDestinationAsync(string markdownPath)
    {
        var suggestedDirectory = PdfFileNaming.SuggestDirectory(markdownPath);
        var startLocation = suggestedDirectory is null
            ? null
            : await StorageProvider.TryGetFolderFromPathAsync(suggestedDirectory);

        var target = await StorageProvider.SaveFilePickerAsync(new FilePickerSaveOptions
        {
            Title = "Export to PDF",
            SuggestedFileName = PdfFileNaming.SuggestFileName(markdownPath),
            SuggestedStartLocation = startLocation,
            DefaultExtension = "pdf",
            ShowOverwritePrompt = true,
            FileTypeChoices = new[]
            {
                new FilePickerFileType("PDF Document")
                {
                    Patterns = new[] { "*.pdf" },
                    MimeTypes = new[] { "application/pdf" },
                },
            },
        });

        return target?.TryGetLocalPath();
    }

    /// <summary>
    /// Opens the just-exported PDF in whatever application Windows associates with <c>.pdf</c>. The
    /// viewer is not navigated and the current document is not replaced — this is a second window on
    /// the reader's desktop, not a change of what TigerMarkView is showing.
    /// </summary>
    private async void OnOpenExportedPdfClick(object? sender, RoutedEventArgs e)
    {
        if (_recentExportPath is { } path)
        {
            await RunExportActionAsync(path, _shellLauncher.OpenFile, "Could not open the exported PDF");
        }
    }

    private async void OnOpenExportFolderClick(object? sender, RoutedEventArgs e)
    {
        if (ExportFolderActionTarget() is { } path)
        {
            await RunExportActionAsync(path, _shellLauncher.RevealFile, "Could not open the containing folder");
        }
    }

    /// <summary>
    /// Shared guard for both export actions: a remembered path is only a record of what was written,
    /// so the file may since have been deleted, moved, or renamed. That is reported plainly and the
    /// record dropped, rather than leaving a button that fails the same way every time it is pressed.
    /// </summary>
    private async Task RunExportActionAsync(string pdfPath, Func<string, LaunchOutcome> launch, string failureTitle)
    {
        if (!File.Exists(pdfPath))
        {
            ForgetExport(pdfPath);
            await MessageDialog.ShowAsync(
                this,
                "Exported PDF not found",
                $"The exported PDF is no longer at:\n\n{pdfPath}\n\nIt may have been moved, renamed, or deleted.");
            return;
        }

        var outcome = launch(pdfPath);
        if (!outcome.Success)
        {
            await MessageDialog.ShowAsync(this, failureTitle, outcome.ErrorMessage ?? "Unknown error.");
        }
    }

    /// <summary>
    /// What the folder action points at: the export just made, otherwise the latest one recorded for
    /// the document currently open. With no document open, or one that has not been exported this
    /// session, there is nothing to point at and the button is hidden.
    /// </summary>
    private string? ExportFolderActionTarget() => _recentExportPath ?? _exportedPdfs.Find(_watcher?.FilePath);

    /// <summary>
    /// The one place the two status-bar export actions are shown or hidden. Open PDF belongs to the
    /// transient success message; the folder action belongs to the document, so it survives the
    /// message and comes back when the reader returns to a document exported earlier in the session.
    /// </summary>
    private void UpdateExportActionState()
    {
        OpenExportedPdfButton.IsVisible = _recentExportPath is not null;
        OpenExportFolderButton.IsVisible = ExportFolderActionTarget() is not null;
    }

    private void ForgetExport(string pdfPath)
    {
        _exportedPdfs.ForgetExport(pdfPath);

        if (string.Equals(_recentExportPath, pdfPath, StringComparison.OrdinalIgnoreCase))
        {
            _recentExportPath = null;
        }

        UpdateExportActionState();
    }

    /// <summary>
    /// True while a PDF export is running.
    /// </summary>
    private bool PdfWorkInProgress => _pdfExportCancellation is not null;

    private void OnExitClick(object? sender, RoutedEventArgs e) => Close();

    private void OnHelpClick(object? sender, RoutedEventArgs e) => ShowHelp(BundledDocuments.Help);

    /// <summary>
    /// Opens a bundled document in the Help window.
    /// </summary>
    /// <remarks>
    /// Pointedly <em>not</em> <see cref="OpenFile"/>. The bundled documentation is not a document the
    /// reader opened, and routing it through the viewer would put HELP.md in Open Recent, append it to
    /// the navigation trail, attach a watcher to a file inside the installation folder, and make Export
    /// to PDF and Open in Editor act on it. Every one of those would be wrong, and the reading session
    /// the reader comes back to must be exactly the one they left.
    /// </remarks>
    private void ShowHelp(BundledDocument document) => HelpWindow.ShowDocument(this, _theme, document);

    private async void OnAboutClick(object? sender, RoutedEventArgs e)
    {
        // About's documentation links close the dialog and hand the choice back here, so a modal dialog
        // and a modeless Help window are never both on screen contending for the same owner.
        if (await AboutDialog.ShowAsync(this) is { } requested)
        {
            ShowHelp(requested);
        }
    }

    /// <summary>
    /// Handles a file dropped on the Avalonia chrome (menu bar, banner, status bar).
    /// </summary>
    /// <remarks>
    /// This is only half of drag/drop support. The WebView fills most of the window and is a native
    /// child window that takes OLE drops itself, so a file dropped on the document area never reaches
    /// this routed event at all — that case is caught in <see cref="OnNavigationStarted"/>, where the
    /// WebView's attempt to navigate to the dropped file is cancelled and rerouted. Both halves end up
    /// in <see cref="OpenFile"/>, so a drop behaves exactly like File &gt; Open wherever it lands.
    /// </remarks>
    private void OnDrop(object? sender, DragEventArgs e)
    {
        var path = e.DataTransfer.TryGetFiles()?
            .Select(file => file.TryGetLocalPath())
            .FirstOrDefault(MarkdownLinkResolver.IsMarkdownPath);

        if (path is not null)
        {
            // Dropping a file is the reader handing the viewer a document, so it is an entry point.
            OpenFile(path, DocumentOpenOrigin.ExplicitOpen);
        }
    }

    private async void OnReloadClick(object? sender, RoutedEventArgs e) => await ReloadCurrentFileAsync();

    private void OnReloadModeManualClick(object? sender, RoutedEventArgs e) => SetReloadMode(ReloadMode.Manual);
    private void OnReloadModeConfirmClick(object? sender, RoutedEventArgs e) => SetReloadMode(ReloadMode.Confirm);
    private void OnReloadModeAutomaticClick(object? sender, RoutedEventArgs e) => SetReloadMode(ReloadMode.Automatic);

    private void SetReloadMode(ReloadMode mode)
    {
        _currentReloadMode = mode;
        _watcher?.SetReloadMode(mode);
        SetReloadModeChecked(mode);
        RefreshStatusBar();

        _settings.ReloadMode = mode;
        SaveSettings();
    }

    /// <summary>
    /// Reflects the one reload mode (<see cref="_currentReloadMode"/>, persisted in settings) in both
    /// places that display it. The toolbar deliberately holds no state of its own: whichever surface
    /// the user changed the mode from, both are re-checked from the same value here, so they cannot
    /// disagree.
    /// </summary>
    private void SetReloadModeChecked(ReloadMode mode)
    {
        ManualModeItem.IsChecked = mode == ReloadMode.Manual;
        ConfirmModeItem.IsChecked = mode == ReloadMode.Confirm;
        AutomaticModeItem.IsChecked = mode == ReloadMode.Automatic;

        ManualModeToolbarItem.IsChecked = mode == ReloadMode.Manual;
        ConfirmModeToolbarItem.IsChecked = mode == ReloadMode.Confirm;
        AutomaticModeToolbarItem.IsChecked = mode == ReloadMode.Automatic;

        ReloadModeLabel.Text = ShortReloadModeName(mode);
        ToolTip.SetTip(ReloadModeButton, $"Reload mode: {mode}");
    }

    /// <summary>
    /// Toolbar label text. "Automatic" is shortened only because it is the one name wide enough to
    /// stretch the toolbar; the tooltip always spells the mode out in full.
    /// </summary>
    private static string ShortReloadModeName(ReloadMode mode) => mode switch
    {
        ReloadMode.Automatic => "Auto",
        _ => mode.ToString(),
    };

    private async void OnThemeLightClick(object? sender, RoutedEventArgs e) =>
        await SetThemeAsync(MarkdownTheme.Light);

    private async void OnThemeDarkClick(object? sender, RoutedEventArgs e) =>
        await SetThemeAsync(MarkdownTheme.Dark);

    /// <summary>
    /// Switches theme, and repaints every surface that shows it: the Avalonia chrome, the native
    /// caption, and the viewer — whatever the viewer happens to be showing.
    /// </summary>
    private async Task SetThemeAsync(MarkdownTheme theme)
    {
        // The radio MenuItem has already flipped itself; keep the group consistent either way.
        SetThemeMenuChecked(theme);

        if (_theme == theme)
        {
            return;
        }

        _theme = theme;
        App.ApplyThemeVariant(theme);
        NativeTitleBar.Apply(this, theme);

        // Help is a separate window, so nothing repaints it for us.
        HelpWindow.ApplyTheme(theme);

        _settings.Theme = theme;
        SaveSettings();

        await RefreshViewerAsync();
    }

    /// <summary>
    /// Re-renders the viewer under the current theme and rendering options, whichever of its three
    /// surfaces is on screen: the rendered document, the error page, or the empty viewer.
    /// </summary>
    /// <remarks>
    /// <para>
    /// One path for all three. A theme switch only ever
    /// re-rendered <see cref="_renderedDocument"/>, so with no document open the central area stayed
    /// in the old theme until the app was restarted or a document was loaded, and the error page had
    /// the same gap. The rule is that the viewer is a themed surface like the menus and the status
    /// bar — not something only a document can carry a theme into.
    /// </para>
    /// <para>
    /// It is also the one path for <em>every</em> presentation change, not just theme. Emoji shortcodes
    /// and syntax highlighting change what the document looks like on screen exactly as a theme does,
    /// so they refresh through here rather than through a second, nearly identical method. (The PDF
    /// preferences deliberately do not: everything they change is inert on screen, so
    /// <see cref="ApplyPdfExportSettings"/> updates the retained HTML without navigating at all.)
    /// </para>
    /// <para>
    /// The document case keeps every guarantee it had: the Markdown is re-rendered from the text
    /// retained in <see cref="RenderedDocument"/>, so the file is <em>not</em> re-read, a change here
    /// can never pull in a newer version the reader has not seen, the status bar's three timestamps
    /// stay exactly as they were, no history entry is created, the watcher is untouched, and the
    /// reading position is restored by the same capture/restore mechanism reloads use. What PDF export
    /// would publish is the same document version, re-rendered the way it is now being read.
    /// </para>
    /// </remarks>
    private async Task RefreshViewerAsync()
    {
        if (_renderedDocument is { } document)
        {
            var scrollY = await TryCaptureScrollYAsync();

            // One re-render even when both changed, which is why this is WithPresentation rather than
            // WithTheme followed by WithRenderingOptions.
            var refreshed = document.WithPresentation(_theme, _renderingOptions);

            WritePreviewHtml(refreshed.Html);
            _pendingScrollY = scrollY;
            NavigateBrowser();

            _renderedDocument = refreshed;
            return;
        }

        if (_errorPage is { } error)
        {
            ShowErrorPage(error.Path, error.Message);
            return;
        }

        ShowEmptyViewer();
    }

    /// <summary>
    /// Puts the error page on screen and remembers it, so a later theme switch can redraw it.
    /// </summary>
    private void ShowErrorPage(string path, string message)
    {
        _errorPage = new ViewerErrorPage(path, message);

        WritePreviewHtml(MarkdownRenderer.ToErrorDocument(path, message, _theme));
        Title = "TigerMarkView";
        NavigateBrowser();
    }

    /// <summary>
    /// Shows the viewer with no document in it.
    /// </summary>
    /// <remarks>
    /// Navigating to a deliberately blank themed page rather than leaving the WebView unnavigated: it
    /// is a native child window that paints its own default white page, so a Dark session with no
    /// document open showed a white slab down the middle of the window until something was loaded.
    /// </remarks>
    private void ShowEmptyViewer()
    {
        _errorPage = null;

        WritePreviewHtml(MarkdownRenderer.ToEmptyDocument(_theme));
        NavigateBrowser();
    }

    private void SetThemeMenuChecked(MarkdownTheme theme)
    {
        LightThemeItem.IsChecked = theme == MarkdownTheme.Light;
        DarkThemeItem.IsChecked = theme == MarkdownTheme.Dark;
    }

    /// <summary>
    /// The two rendering options. Each derives its new value from the persisted setting rather than
    /// from the menu item's own <c>IsChecked</c>, because a click forwarded from the toolbar's menu
    /// mirror runs this handler without flipping it — see <see cref="Menus.MenuMirror"/>.
    /// <see cref="SetRenderingMenuChecked"/> then writes the check mark back from the setting, so both
    /// surfaces leave the same state behind.
    /// </summary>
    private async void OnEmojiShortcodesClick(object? sender, RoutedEventArgs e)
    {
        _settings.EmojiShortcodes = !_settings.EmojiShortcodes;
        await ApplyRenderingOptionsAsync();
    }

    /// <inheritdoc cref="OnEmojiShortcodesClick"/>
    private async void OnSyntaxHighlightingClick(object? sender, RoutedEventArgs e)
    {
        _settings.SyntaxHighlighting = !_settings.SyntaxHighlighting;
        await ApplyRenderingOptionsAsync();
    }

    /// <summary>
    /// The one place a changed rendering option takes effect: re-resolve the options, re-check the
    /// menu, persist, and re-render what is on screen.
    /// </summary>
    /// <remarks>
    /// Unlike a PDF preference, these change the pixels, so the viewer really is re-navigated — through
    /// <see cref="RefreshViewerAsync"/>, the same path a theme switch takes, with the same guarantees:
    /// no file is read, the reading position is restored, and the document's identity, timestamps,
    /// navigation trail, recent-files list, and watcher are all left alone.
    /// </remarks>
    private async Task ApplyRenderingOptionsAsync()
    {
        _renderingOptions = _settings.ToRenderingOptions();
        SetRenderingMenuChecked();
        SaveSettings();

        await RefreshViewerAsync();
    }

    private void SetRenderingMenuChecked()
    {
        EmojiShortcodesItem.IsChecked = _settings.EmojiShortcodes;
        SyntaxHighlightingItem.IsChecked = _settings.SyntaxHighlighting;
    }

    private void OnPdfPaperA3Click(object? sender, RoutedEventArgs e) => SetPdfPaperSize(PdfPaperSize.A3);
    private void OnPdfPaperA4Click(object? sender, RoutedEventArgs e) => SetPdfPaperSize(PdfPaperSize.A4);
    private void OnPdfPaperA5Click(object? sender, RoutedEventArgs e) => SetPdfPaperSize(PdfPaperSize.A5);
    private void OnPdfPaperLetterClick(object? sender, RoutedEventArgs e) => SetPdfPaperSize(PdfPaperSize.Letter);
    private void OnPdfPaperLegalClick(object? sender, RoutedEventArgs e) => SetPdfPaperSize(PdfPaperSize.Legal);

    private void OnPdfPortraitClick(object? sender, RoutedEventArgs e) =>
        SetPdfOrientation(PdfOrientation.Portrait);

    private void OnPdfLandscapeClick(object? sender, RoutedEventArgs e) =>
        SetPdfOrientation(PdfOrientation.Landscape);

    private void OnPdfMarginsNarrowClick(object? sender, RoutedEventArgs e) =>
        SetPdfMargins(PdfMarginPreset.Narrow);

    private void OnPdfMarginsNormalClick(object? sender, RoutedEventArgs e) =>
        SetPdfMargins(PdfMarginPreset.Normal);

    private void OnPdfMarginsWideClick(object? sender, RoutedEventArgs e) =>
        SetPdfMargins(PdfMarginPreset.Wide);

    private void OnPdfPageNumbersClick(object? sender, RoutedEventArgs e)
    {
        // The remembered setting is the question, not the menu item's own toggle: a click forwarded
        // from the toolbar's menu mirror never flips it. SetPdfExportMenuChecked writes the check mark
        // back from the setting, so both surfaces leave the same state behind — see MenuMirror.
        _settings.PdfPageNumbers = !_settings.PdfPageNumbers;
        ApplyPdfExportSettings();
    }

    private void SetPdfPaperSize(PdfPaperSize paper)
    {
        _settings.PdfPaperSize = paper;
        ApplyPdfExportSettings();
    }

    private void SetPdfOrientation(PdfOrientation orientation)
    {
        _settings.PdfOrientation = orientation;
        ApplyPdfExportSettings();
    }

    private void SetPdfMargins(PdfMarginPreset margins)
    {
        _settings.PdfMargins = margins;
        ApplyPdfExportSettings();
    }

    /// <summary>
    /// The one place a changed PDF preference takes effect: re-resolve the page geometry, persist the
    /// choice, re-check the menu, and re-render the retained document's HTML so the next export uses
    /// the new paper.
    /// </summary>
    /// <remarks>
    /// <para>
    /// The viewer is deliberately <em>not</em> navigated. Everything these preferences change lives in
    /// the <c>@page</c> rule and is inert on screen, so re-navigating would cost a visible reload and a
    /// scroll restoration to display exactly the same pixels. What has to change is the HTML PDF export
    /// will print, and that is held in <see cref="_renderedDocument"/>.
    /// </para>
    /// <para>
    /// Like a theme switch, the re-render comes from the Markdown retained in
    /// <see cref="RenderedDocument"/>. No file is read, so changing a PDF preference cannot promote the
    /// reader's view to a newer version on disk, and the status bar's three timestamps, the navigation
    /// trail, and the reload state are all untouched.
    /// </para>
    /// </remarks>
    private void ApplyPdfExportSettings()
    {
        _pdfPageSetup = _settings.ToPdfPageSetup();
        SetPdfExportMenuChecked();
        SaveSettings();

        _renderedDocument = _renderedDocument?.WithPageSetup(_pdfPageSetup);
    }

    /// <summary>
    /// Reflects the persisted PDF preferences in the menu — all four groups from the one settings
    /// object, so a radio item that checked itself on click cannot leave the group disagreeing with
    /// what was actually saved.
    /// </summary>
    private void SetPdfExportMenuChecked()
    {
        PdfPaperA3Item.IsChecked = _settings.PdfPaperSize == PdfPaperSize.A3;
        PdfPaperA4Item.IsChecked = _settings.PdfPaperSize == PdfPaperSize.A4;
        PdfPaperA5Item.IsChecked = _settings.PdfPaperSize == PdfPaperSize.A5;
        PdfPaperLetterItem.IsChecked = _settings.PdfPaperSize == PdfPaperSize.Letter;
        PdfPaperLegalItem.IsChecked = _settings.PdfPaperSize == PdfPaperSize.Legal;

        PdfPortraitItem.IsChecked = _settings.PdfOrientation == PdfOrientation.Portrait;
        PdfLandscapeItem.IsChecked = _settings.PdfOrientation == PdfOrientation.Landscape;

        PdfMarginsNarrowItem.IsChecked = _settings.PdfMargins == PdfMarginPreset.Narrow;
        PdfMarginsNormalItem.IsChecked = _settings.PdfMargins == PdfMarginPreset.Normal;
        PdfMarginsWideItem.IsChecked = _settings.PdfMargins == PdfMarginPreset.Wide;

        PdfPageNumbersItem.IsChecked = _settings.PdfPageNumbers;
    }

    private async void OnOpenInEditorClick(object? sender, RoutedEventArgs e) =>
        await OpenCurrentDocumentInEditorAsync();

    private async Task OpenCurrentDocumentInEditorAsync()
    {
        if (_watcher is null)
        {
            return;
        }

        var outcome = _editorLauncher.Launch(_editorConfiguration, _watcher.FilePath);
        if (!outcome.Success)
        {
            await MessageDialog.ShowAsync(this, "Could not open editor", outcome.ErrorMessage ?? "Unknown error.");
        }
        // Success: viewer state is untouched. The watcher keeps monitoring the same path,
        // so any edit made in the external editor is picked up by the existing reload machinery.
    }

    private void OnEditorTypeSystemDefaultClick(object? sender, RoutedEventArgs e) =>
        SetEditorConfiguration(EditorConfiguration.SystemDefault());

    private void OnEditorTypeVsCodeClick(object? sender, RoutedEventArgs e) =>
        SetEditorConfiguration(EditorConfiguration.VisualStudioCode());

    private void OnEditorTypeNotepad3Click(object? sender, RoutedEventArgs e) =>
        SetEditorConfiguration(EditorConfiguration.Notepad3());

    private async void OnEditorTypeCustomClick(object? sender, RoutedEventArgs e)
    {
        var previousType = _editorConfiguration.Type;

        var result = await CustomEditorDialog.ShowAsync(this, _editorConfiguration);
        if (result is null)
        {
            // Avalonia's radio MenuItem already flipped IsChecked to Custom on click; revert it
            // since the dialog was cancelled and the configuration did not actually change.
            SetEditorTypeMenuChecked(previousType);
            return;
        }

        SetEditorConfiguration(result);
    }

    private void SetEditorConfiguration(EditorConfiguration configuration)
    {
        _editorConfiguration = configuration;
        SetEditorTypeMenuChecked(configuration.Type);

        _settings.ApplyEditorConfiguration(configuration);
        SaveSettings();
    }

    private void SetEditorTypeMenuChecked(EditorType type)
    {
        SystemDefaultEditorItem.IsChecked = type == EditorType.SystemDefault;
        VsCodeEditorItem.IsChecked = type == EditorType.VisualStudioCode;
        Notepad3EditorItem.IsChecked = type == EditorType.Notepad3;
        CustomEditorItem.IsChecked = type == EditorType.Custom;
    }

    /// <summary>
    /// <strong>The</strong> way a document is opened. File &gt; Open, Open Recent, the command-line
    /// argument, a drop, and a click on a local Markdown link all come through here, so none of them
    /// can drift into behaving differently from the others.
    /// </summary>
    /// <param name="origin">
    /// How the reader got here. Required rather than defaulted: the caller is the only thing that
    /// knows, it is what separates an Open Recent entry point from a link the reader merely followed,
    /// and a default would let a new route silently inherit the wrong answer.
    /// </param>
    public void OpenFile(string path, DocumentOpenOrigin origin) => _ = OpenDocumentAsync(path, origin);

    /// <summary>
    /// Opens <paramref name="path"/> as a <em>new</em> navigation: it becomes the current history
    /// entry, and anything the reader had navigated forward to is discarded (ordinary browser
    /// semantics). Reloads never come through here — they are the same document, not a navigation.
    /// </summary>
    private async Task OpenDocumentAsync(string path, DocumentOpenOrigin origin)
    {
        if (!TryResolveDocumentPath(path, out var fullPath, out var problem))
        {
            ShowUnopenableDocument(path, problem);
            return;
        }

        _history.RecordScrollPosition(await TryCaptureScrollYAsync());
        _history.Navigate(fullPath);

        await ShowCurrentHistoryEntryAsync(scrollY: null, origin);
    }

    /// <summary>
    /// Moves one document back or forward and shows it, restoring where the reader had scrolled to.
    /// </summary>
    /// <remarks>
    /// The historical document is re-opened through the same pipeline as any other open — file re-read,
    /// watcher attached, timestamps established fresh — rather than being restored from a stored
    /// rendering. Going Back to a document someone has edited in the meantime should show what the file
    /// says now, and a document with a live watcher behind it is the only kind the status bar, reload
    /// modes, and PDF export are built to reason about.
    /// </remarks>
    private async Task NavigateHistoryAsync(bool forward)
    {
        if (forward ? !_history.CanGoForward : !_history.CanGoBack)
        {
            return;
        }

        _history.RecordScrollPosition(await TryCaptureScrollYAsync());

        var entry = forward ? _history.GoForward() : _history.GoBack();
        if (entry is null)
        {
            return;
        }

        await ShowCurrentHistoryEntryAsync(entry.ScrollY, DocumentOpenOrigin.HistoryTraversal);
    }

    /// <summary>
    /// Jumps to an entry the reader picked out of the history list, from either surface.
    /// </summary>
    /// <remarks>
    /// The distinction that matters is in <see cref="NavigationHistory.GoTo"/>, not here: this
    /// <em>moves the cursor</em> over the existing trail, so with A → B → C → D picking B leaves C and
    /// D reachable with Forward instead of appending a second B and discarding them. Everything after
    /// that is the ordinary Back/Forward path, which is why the reading position comes back the same
    /// way — the entry's own <see cref="NavigationEntry.ScrollY"/>.
    /// </remarks>
    private async Task GoToHistoryEntryAsync(int index)
    {
        if (index == _history.CurrentIndex)
        {
            // Picking the document already on screen is not a navigation. Re-opening it would be a
            // reload the reader did not ask for, and would throw away the scroll position they are
            // looking at right now.
            return;
        }

        _history.RecordScrollPosition(await TryCaptureScrollYAsync());

        if (_history.GoTo(index) is not { } entry)
        {
            return;
        }

        await ShowCurrentHistoryEntryAsync(entry.ScrollY, DocumentOpenOrigin.HistoryTraversal);
    }

    private async Task ShowCurrentHistoryEntryAsync(double? scrollY, DocumentOpenOrigin origin)
    {
        if (_history.Current is not { } entry)
        {
            return;
        }

        AttachDocument(entry.FilePath, origin);
        UpdateNavigationCommandState();

        await LoadAndRenderAsync(entry.FilePath, scrollY);
    }

    /// <summary>
    /// Points the watcher, the recent-files list, and the document-scoped menu items at a new current
    /// file. Every action that targets "the current document" — Open in Editor, Reload, PDF export —
    /// follows from this one place, which is what keeps them consistent after a link navigation.
    /// </summary>
    /// <remarks>
    /// The recent-files list is the one thing here that is <em>not</em> unconditional, and
    /// <paramref name="origin"/> is why: everything that reaches a document repoints the watcher, but
    /// only an explicit open is an entry point worth remembering across sessions. The rule itself is
    /// <see cref="RecentFilesPolicy"/>, in Core where it can be tested.
    /// </remarks>
    private void AttachDocument(string fullPath, DocumentOpenOrigin origin)
    {
        _watcher?.Dispose();
        _watcher = new DocumentWatcher(fullPath, _currentReloadMode);
        _watcher.StateChanged += OnWatcherStateChanged;
        _watcher.ReloadRequested += async (_, _) => await ReloadCurrentFileAsync();

        // Nothing of the new document is on screen yet; don't let Export to PDF emit the previous
        // document (or the error page) if this open fails.
        _renderedDocument = null;
        UpdateDocumentCommandState();

        // A message (and Open-PDF action) about the document being left behind must not carry over to
        // this one. The folder action is then recomputed for the new document: it appears only if this
        // document was itself exported earlier in the session, which is how Back/Forward and Open
        // Recent get it back without ever offering an unrelated PDF.
        ClearStatusOverride();

        if (RecentFilesPolicy.ShouldRemember(origin))
        {
            RememberRecentFile(_watcher.FilePath);
        }
    }

    /// <summary>
    /// Rejects a path no document could ever be loaded from (illegal characters, no containing
    /// folder) before <see cref="DocumentWatcher"/> is handed it, since its constructor would throw on
    /// exactly those. A path that is merely <em>missing</em> is not rejected here — that is a normal
    /// error the viewer reports through the usual error page and status bar.
    /// </summary>
    private static bool TryResolveDocumentPath(string path, out string fullPath, out string problem)
    {
        fullPath = "";
        problem = "";

        if (string.IsNullOrWhiteSpace(path))
        {
            problem = "No file path was supplied.";
            return false;
        }

        try
        {
            fullPath = Path.GetFullPath(path);
        }
        catch (Exception ex) when (ex is ArgumentException or NotSupportedException or PathTooLongException
                                       or System.Security.SecurityException)
        {
            problem = ex.Message;
            return false;
        }

        if (string.IsNullOrEmpty(Path.GetDirectoryName(fullPath)))
        {
            problem = "That path has no containing folder.";
            return false;
        }

        return true;
    }

    private void ShowUnopenableDocument(string path, string problem)
    {
        _watcher?.Dispose();
        _watcher = null;
        _renderedDocument = null;
        UpdateDocumentCommandState();
        ClearStatusOverride();

        ShowErrorPage(path, problem);
        RefreshStatusBar();
    }

    /// <summary>
    /// Adds a genuinely existing path to the recent list. Guarding on existence keeps typos and dead
    /// command-line arguments out of the menu; an entry that goes missing <em>later</em> is left in
    /// place, since a network share being offline for an afternoon is not a reason to forget a file.
    /// </summary>
    private void RememberRecentFile(string path)
    {
        try
        {
            if (!File.Exists(path))
            {
                return;
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException)
        {
            return;
        }

        _settings.AddRecentFile(path);
        RebuildRecentFilesMenu();
        SaveSettings();
    }

    /// <summary>
    /// Refills File &gt; Open Recent and re-states whether either Open Recent surface has anything to
    /// offer. The toolbar dropdown fills itself at open time (see
    /// <see cref="OnOpenRecentToolbarClick"/>) but its enabled state is written here, so the menu item
    /// and the button say the same thing about the same list.
    /// </summary>
    private void RebuildRecentFilesMenu()
    {
        var items = BuildRecentFileItems();

        OpenRecentMenuItem.ItemsSource = items;
        OpenRecentMenuItem.IsEnabled = items.Count > 0;
        OpenRecentToolbarButton.IsEnabled = items.Count > 0;
    }

    /// <summary>
    /// Fills an Open Recent surface — the File menu's submenu or the toolbar's dropdown — from the one
    /// persisted list. Entries show the file name alone, unless two entries share one, in which case
    /// the containing folder's name is appended so they can be told apart — the folder's <em>name</em>,
    /// not its full path, because a deep path makes the menu unreadable. The full path is always
    /// available as a tooltip.
    /// </summary>
    /// <remarks>
    /// Two lists of <see cref="MenuItem"/> exist because a control belongs to one menu at a time, but
    /// they are built here, from <c>_settings.RecentFiles</c>, by the same code — exactly as
    /// <see cref="BuildHistoryItems"/> feeds the two history surfaces. There is no second recent-files
    /// list anywhere, so ordering, labels, tooltips and open semantics cannot differ between the two.
    /// </remarks>
    private List<MenuItem> BuildRecentFileItems()
    {
        var paths = _settings.RecentFiles;
        var labels = BuildDocumentLabels(paths);
        var items = new List<MenuItem>(paths.Count);

        for (var i = 0; i < paths.Count; i++)
        {
            var target = paths[i];
            var item = new MenuItem { Header = EscapeMenuMnemonics(labels[i]) };
            ToolTip.SetTip(item, target);

            // Choosing an entry point again is still choosing it, so this is an explicit open and
            // moves the document back to the top of the list — the ordinary MRU behaviour. Identical
            // whichever surface the entry was picked from, because there is one route in.
            item.Click += (_, _) => OpenFile(target, DocumentOpenOrigin.ExplicitOpen);

            items.Add(item);
        }

        return items;
    }

    /// <summary>
    /// The toolbar's Open Recent dropdown, filled and shown here rather than declared as the button's
    /// <see cref="Button.Flyout"/> — the same reason as <see cref="OnHistoryToolbarClick"/>: a
    /// <see cref="MenuFlyout"/> builds its presenter once and then ignores a reassigned
    /// <see cref="MenuFlyout.ItemsSource"/>, so a retained flyout would keep showing the list as it was
    /// the first time it opened. A new one per opening cannot go stale.
    /// </summary>
    private void OnOpenRecentToolbarClick(object? sender, RoutedEventArgs e) =>
        ShowToolbarFlyout(BuildRecentFileItems(), OpenRecentToolbarButton);

    /// <summary>
    /// The toolbar history dropdown, filled and shown here rather than declared as the button's
    /// <see cref="Button.Flyout"/>.
    /// </summary>
    /// <remarks>
    /// A new <see cref="MenuFlyout"/> per opening, which is not wastefulness but the only thing that
    /// works: a MenuFlyout builds its presenter the first time it is shown and then reuses it, so a
    /// reassigned <see cref="MenuFlyout.ItemsSource"/> never reaches the screen. A retained
    /// flyout kept showing the trail from its first opening, and because a clicked
    /// <see cref="MenuItemToggleType.CheckBox"/> item ticks itself, picking an entry out of that stale
    /// list produced a menu with two documents ticked at once. Building the items and the menu
    /// together, immediately before showing them, cannot go stale.
    /// </remarks>
    private void OnHistoryToolbarClick(object? sender, RoutedEventArgs e) =>
        ShowToolbarFlyout(BuildHistoryItems(), HistoryToolbarButton);

    /// <summary>
    /// Shows <paramref name="items"/> as a fresh menu hanging off <paramref name="anchor"/>.
    /// </summary>
    /// <remarks>
    /// The placement is stated, never left to the default, for the reason <see cref="MenuMirror"/>
    /// records: Avalonia's default <see cref="PlacementMode.Bottom"/> <em>centres</em> the popup on its
    /// anchor, so a menu several times wider than a 40px icon button hangs to the left of the button
    /// that opened it and reads as an unrelated floating panel.
    /// <see cref="PlacementMode.BottomEdgeAlignedLeft"/> lines the two left edges up, which is what
    /// makes the list look attached to the chevron the reader clicked.
    /// </remarks>
    private static void ShowToolbarFlyout(List<MenuItem> items, Control anchor)
    {
        var flyout = new MenuFlyout
        {
            ItemsSource = items,
            Placement = PlacementMode.BottomEdgeAlignedLeft,
        };

        flyout.ShowAt(anchor);
    }

    /// <summary>
    /// The toolbar's application menu — the whole menu bar, as a flyout, and the reason the menu bar
    /// can be hidden at all.
    /// </summary>
    /// <remarks>
    /// It holds no commands of its own: <see cref="MenuMirror"/> generates the flyout from the live
    /// <see cref="MainMenu"/> on every opening, and every click is forwarded to the menu bar's own
    /// item. The one thing that has to happen first is the same refresh <c>Navigate</c> performs when
    /// it opens — the history submenu is filled from the trail on demand, and mirroring it before
    /// filling it would mirror the previous trail.
    /// </remarks>
    private void OnMenuToolbarClick(object? sender, RoutedEventArgs e)
    {
        HistoryMenuItem.ItemsSource = BuildHistoryItems();

        MenuMirror.Create(MainMenu).ShowAt(MenuToolbarButton);
    }

    /// <summary>
    /// Whether there is a trail worth offering. One document is a trail with nowhere else to go, so
    /// both history surfaces stay disabled rather than showing a list with a single unusable item.
    /// </summary>
    private void UpdateHistoryCommandState()
    {
        var hasChoice = _history.Entries.Count > 1;

        HistoryMenuItem.IsEnabled = hasChoice;
        HistoryToolbarButton.IsEnabled = hasChoice;
    }

    /// <summary>
    /// Fills a history surface — <c>Navigate &gt; History</c> or the toolbar dropdown — from the one
    /// <see cref="NavigationHistory"/>, at the moment it is opened.
    /// </summary>
    /// <remarks>
    /// <para>
    /// Two lists of <see cref="MenuItem"/> exist because a control belongs to one menu at a time, but
    /// they are built here, from the same trail, by the same code: one history model, and no surface
    /// holding state of its own. That is the toolbar rule one level up — a second surface is a second
    /// view of a command, never a second implementation.
    /// </para>
    /// <para>
    /// Built on open rather than on every navigation, which is not merely lazier but <em>correct</em>:
    /// re-assigning <see cref="MenuFlyout.ItemsSource"/> does not refresh a flyout that has already
    /// been populated, so a rebuild-on-navigate left the previous items on screen — and since a
    /// clicked <see cref="MenuItemToggleType.CheckBox"/> item toggles itself, picking an entry from a
    /// stale list produced a menu with two documents ticked at once. Building at open time means the
    /// list is always drawn from the trail as it is now, and a stray toggle cannot survive.
    /// </para>
    /// </remarks>
    private List<MenuItem> BuildHistoryItems()
    {
        var entries = _history.Entries;
        var labels = BuildDocumentLabels(entries.Select(entry => entry.FilePath).ToList());
        var currentIndex = _history.CurrentIndex;
        var items = new List<MenuItem>(entries.Count);

        for (var i = 0; i < entries.Count; i++)
        {
            var index = i;
            var item = new MenuItem
            {
                Header = EscapeMenuMnemonics(labels[index]),

                // A check mark rather than a decorated label: "you are here" is a state, so it is
                // drawn the way the platform draws states and reaches accessibility tooling as one.
                ToggleType = MenuItemToggleType.CheckBox,
                IsChecked = index == currentIndex,
            };

            ToolTip.SetTip(item, entries[index].FilePath);
            item.Click += (_, _) => _ = GoToHistoryEntryAsync(index);

            items.Add(item);
        }

        return items;
    }

    /// <summary>
    /// Labels for a set of documents listed together in one menu. The file name alone, unless two
    /// entries share one, in which case the containing folder's <em>name</em> is appended so they can
    /// be told apart — the folder's name, not its full path, because a deep path makes the menu
    /// unreadable. Callers attach the full path as a tooltip.
    /// </summary>
    private static List<string> BuildDocumentLabels(IReadOnlyList<string> paths)
    {
        var ambiguousNames = paths
            .GroupBy(FileNameOf, StringComparer.OrdinalIgnoreCase)
            .Where(group => group.Count() > 1)
            .Select(group => group.Key)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        return paths
            .Select(path =>
            {
                var fileName = FileNameOf(path);
                var folderName = ambiguousNames.Contains(fileName) ? ParentFolderNameOf(path) : null;
                return folderName is null ? fileName : $"{fileName} — {folderName}";
            })
            .ToList();
    }

    private static string FileNameOf(string path)
    {
        try
        {
            var name = Path.GetFileName(path);
            return string.IsNullOrEmpty(name) ? path : name;
        }
        catch (ArgumentException)
        {
            return path;
        }
    }

    private static string? ParentFolderNameOf(string path)
    {
        try
        {
            var directory = Path.GetDirectoryName(path);
            if (string.IsNullOrEmpty(directory))
            {
                return null;
            }

            // A drive root ("C:\") has no name of its own; show the root itself in that case.
            var name = Path.GetFileName(directory);
            return string.IsNullOrEmpty(name) ? directory : name;
        }
        catch (ArgumentException)
        {
            return null;
        }
    }

    /// <summary>An underscore in a menu header is an access-key marker; doubling it shows a literal one.</summary>
    private static string EscapeMenuMnemonics(string header) => header.Replace("_", "__", StringComparison.Ordinal);

    private async Task ReloadCurrentFileAsync()
    {
        if (_watcher is null)
        {
            return;
        }

        var scrollY = await TryCaptureScrollYAsync();
        await LoadAndRenderAsync(_watcher.FilePath, scrollY);
    }

    /// <summary>
    /// Shared load/render/display path used for both the initial file open and every reload (Manual,
    /// Confirm, and Automatic all funnel through here), so there is only one Markdown loading pipeline.
    /// </summary>
    private async Task LoadAndRenderAsync(string path, double? scrollY)
    {
        try
        {
            var document = RenderedDocument.Load(path, _theme, _pdfPageSetup, _renderingOptions);

            WritePreviewHtml(document.Html);
            Title = $"{Path.GetFileName(document.FilePath)} — TigerMarkView";
            _pendingScrollY = scrollY;
            NavigateBrowser();

            // Same HTML the WebView is about to display is what PDF export will print.
            _renderedDocument = document;
            _errorPage = null;
            UpdateDocumentCommandState();

            _watcher?.NotifyReloadSucceeded(document.SourceTimestampUtc, DateTime.UtcNow);
        }
        catch (Exception ex)
        {
            if (_watcher is null || _watcher.State.RenderedTimestampUtc is null)
            {
                // Nothing has ever rendered successfully for this document, so show the error page.
                ShowErrorPage(path, ex.Message);
            }
            // Otherwise: keep showing the previously rendered content and just surface the error state.

            _watcher?.NotifyReloadFailed(ex.Message);
        }

        RefreshStatusBar();
    }

    private static void WritePreviewHtml(string html)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(PreviewHtmlPath)!);
        File.WriteAllText(PreviewHtmlPath, html);
    }

    /// <summary>
    /// Every file open/reload reuses the same on-disk preview path, so re-assigning
    /// <see cref="Avalonia.Controls.NativeWebView.Source"/> to an equal <see cref="Uri"/> would not
    /// necessarily trigger a fresh navigation. A per-navigation cache-busting query string guarantees
    /// a distinct Uri every time, independent of Avalonia's property-change/WebView2 caching behavior.
    /// The existing &lt;base href&gt; tag inside the generated HTML is unaffected by this, so relative
    /// image/link resolution keeps working.
    /// </summary>
    private void NavigateBrowser()
    {
        var builder = new UriBuilder(new Uri(PreviewHtmlPath)) { Query = $"t={DateTime.UtcNow.Ticks}" };
        Browser.Source = builder.Uri;
    }

    private async Task<double?> TryCaptureScrollYAsync()
    {
        try
        {
            // InvokeScript (CoreWebView2.ExecuteScriptAsync under the hood) returns its result as a
            // JSON-encoded string. A JS *number* comes back as bare digits ("123.5"); a JS *string*
            // would come back with literal quote characters ("\"123.5\""), which double.TryParse
            // would silently fail on — so the script must evaluate to a number, not call .toString().
            var result = await Browser.InvokeScript("window.scrollY");
            return double.TryParse(result, NumberStyles.Float, CultureInfo.InvariantCulture, out var y) ? y : null;
        }
        catch
        {
            // Best-effort: if the page can't be queried yet, just skip position preservation.
            return null;
        }
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
                // Best-effort: scroll restoration is not critical to correctness.
            }
        }
    }

    /// <summary>
    /// Keeps the WebView showing nothing but TigerMarkView's own generated preview.
    /// </summary>
    /// <remarks>
    /// <para>
    /// Two very different-looking bugs turned out to be the same one: a <c>.md</c> dropped on the
    /// document area, and a click on a relative <c>[link](other.md)</c>, both ended with the WebView
    /// navigating straight to the Markdown file and showing its raw source. Cancelling here and
    /// re-entering <see cref="OpenFile"/> fixes both at the single point where the WebView announces
    /// what it is about to do.
    /// </para>
    /// <para>
    /// Navigations to the preview file itself — including the <c>?t=</c> cache-buster and any
    /// in-page fragment — are the application's own and pass through untouched.
    /// </para>
    /// </remarks>
    private void OnNavigationStarted(object? sender, WebViewNavigationStartingEventArgs e)
    {
        if (e.Request is { } target && !IsOwnPreviewNavigation(target) && TryHandleNavigation(target))
        {
            e.Cancel = true;
        }
    }

    /// <summary>
    /// A link that asks for a new window (a dropped file, <c>target="_blank"</c>, a middle click) is
    /// always handled in place. TigerMarkView is a single-document reader: an extra WebView window
    /// showing raw Markdown was the most visible symptom of the drag/drop bug.
    /// </summary>
    private void OnNewWindowRequested(object? sender, WebViewNewWindowRequestedEventArgs e)
    {
        e.Handled = true;

        if (e.Request is { } target)
        {
            TryHandleNavigation(target);
        }
    }

    /// <summary>
    /// Routes a navigation target TigerMarkView is responsible for, and reports whether it took
    /// ownership — i.e. whether the WebView must be stopped from navigating there itself.
    /// </summary>
    /// <remarks>
    /// Local Markdown opens in the viewer; <c>http</c>/<c>https</c>/<c>mailto</c> leaves for the
    /// system browser or mail client. Any <em>other</em> local file is refused rather than opened with
    /// its shell association: a Markdown document can come from anywhere, and "click a link, launch
    /// whatever the file is" is not a power a document should have. Schemes the viewer has no opinion
    /// about (<c>about:</c>, <c>data:</c>) are left to the WebView.
    /// </remarks>
    private bool TryHandleNavigation(Uri target)
    {
        if (MarkdownLinkResolver.TryResolveLocalMarkdown(target, out var markdownPath))
        {
            // Posted rather than called directly: this runs inside the WebView's own navigation
            // callback, and starting the replacement navigation from there re-enters it.
            //
            // Navigation, not ExplicitOpen: the reader followed a link out of the document they were
            // already reading. It joins the session's trail and is reachable with Back, but it is not
            // an entry point and must not appear in Open Recent.
            Dispatcher.UIThread.Post(() => OpenFile(markdownPath, DocumentOpenOrigin.Navigation));
            return true;
        }

        if (ExternalLinkLauncher.IsLaunchableScheme(target))
        {
            var outcome = _linkLauncher.Open(target);
            if (!outcome.Success)
            {
                SetStatusOverride(outcome.ErrorMessage!, TransientStatusDuration);
            }

            return true;
        }

        if (target.IsFile)
        {
            SetStatusOverride("That link does not point to a Markdown document.", TransientStatusDuration);
            return true;
        }

        return false;
    }

    /// <summary>
    /// True for the generated preview file the viewer navigates to itself. Compared by path so the
    /// per-navigation <c>?t=</c> cache-buster (and any <c>#fragment</c>) does not matter.
    /// </summary>
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

    private async void OnBackClick(object? sender, RoutedEventArgs e) => await NavigateHistoryAsync(forward: false);

    private async void OnForwardClick(object? sender, RoutedEventArgs e) => await NavigateHistoryAsync(forward: true);

    /// <summary>
    /// Handles Alt+Left / Alt+Right pressed <em>inside the document</em>.
    /// </summary>
    /// <remarks>
    /// The WebView is a native child window and keeps its own keyboard input, so while the reader is
    /// in the document — which is nearly always — Avalonia never sees the shortcut. The rendered page
    /// therefore listens for it and posts it back here; see
    /// <c>DocumentShell.NavigationShortcutScript</c>. Together with
    /// <see cref="OnPreviewKeyDown"/> (which covers focus on the chrome) this makes the shortcut work
    /// wherever focus happens to be.
    /// </remarks>
    private async void OnWebMessageReceived(object? sender, WebMessageReceivedEventArgs e)
    {
        // F1 arrives the same way and for the same reason as Alt+Left/Right: the reader is in the
        // document, so Avalonia never sees the key.
        if (ViewerMessages.IsHelpCommand(e.Body))
        {
            ShowHelp(BundledDocuments.Help);
            return;
        }

        // Ctrl+P arrives the same way. Printing is not part of the shipped UI, so this is intentionally
        // a no-op — but the page script still has
        // to cancel the key and post it here, because without that WebView2 treats Ctrl+P as a browser
        // accelerator and opens Edge's own print preview over the document. Swallowing the message here
        // is what keeps that from happening; it is not a route to TigerMarkView printing.
        if (ViewerMessages.IsPrintCommand(e.Body))
        {
            return;
        }

        switch (ViewerMessages.ParseNavigationCommand(e.Body))
        {
            case ViewerNavigationCommand.Back:
                await NavigateHistoryAsync(forward: false);
                break;

            case ViewerNavigationCommand.Forward:
                await NavigateHistoryAsync(forward: true);
                break;
        }
    }

    /// <summary>
    /// F1, Ctrl+P, and Alt+Left / Alt+Right while focus is on Avalonia's chrome (menu bar, status bar,
    /// banner), handled here rather than as key bindings so the menu bar's own Alt handling does not
    /// swallow them first. The in-document case — which is nearly always — is handled by
    /// <see cref="OnWebMessageReceived"/>.
    /// </summary>
    private void OnPreviewKeyDown(object? sender, KeyEventArgs e)
    {
        if (e.Key == Key.F1 && e.KeyModifiers == KeyModifiers.None)
        {
            e.Handled = true;
            ShowHelp(BundledDocuments.Help);
            return;
        }

        // Ctrl+P from the chrome. Printing is not part of the shipped UI; the key is still marked
        // handled so it does nothing rather than falling through to
        // some other accelerator. The in-document case — which is nearly always — comes through
        // OnWebMessageReceived, because the WebView keeps its own keyboard input.
        if (e.Key == Key.P && e.KeyModifiers == KeyModifiers.Control)
        {
            e.Handled = true;
            return;
        }

        if (e.KeyModifiers != KeyModifiers.Alt)
        {
            return;
        }

        switch (e.Key)
        {
            case Key.Left:
                e.Handled = true;
                _ = NavigateHistoryAsync(forward: false);
                break;

            case Key.Right:
                e.Handled = true;
                _ = NavigateHistoryAsync(forward: true);
                break;
        }
    }

    /// <summary>
    /// The single place navigation availability is expressed, for the Navigate menu and the toolbar
    /// alike — every surface reads <see cref="NavigationHistory"/> rather than tracking anything
    /// itself. The history list is rebuilt from here too, since the trail and the cursor's place in it
    /// change together with what Back and Forward can do.
    /// </summary>
    private void UpdateNavigationCommandState()
    {
        BackMenuItem.IsEnabled = _history.CanGoBack;
        ForwardMenuItem.IsEnabled = _history.CanGoForward;

        BackToolbarButton.IsEnabled = _history.CanGoBack;
        ForwardToolbarButton.IsEnabled = _history.CanGoForward;

        UpdateHistoryCommandState();
    }

    /// <summary>
    /// Enables the commands that only mean something with a document open, in menu and toolbar
    /// together. Reload and Open in Editor need a watched file; Export to PDF needs a rendered document
    /// as well.
    /// </summary>
    private void UpdateDocumentCommandState()
    {
        var hasDocument = _watcher is not null;

        ReloadMenuItem.IsEnabled = hasDocument;
        ReloadToolbarButton.IsEnabled = hasDocument;

        OpenInEditorMenuItem.IsEnabled = hasDocument;
        OpenInEditorToolbarButton.IsEnabled = hasDocument;

        // Export needs something actually rendered — a file that failed to load has a watcher but
        // nothing to export — and is held back while an export is already running.
        var canPublish = _renderedDocument is not null && !PdfWorkInProgress;

        ExportPdfMenuItem.IsEnabled = canPublish;

        // Written here rather than anywhere it is shown or hidden: whether the command is *available*
        // and whether the reader has put it on the toolbar are separate questions, and only this one
        // belongs to the document.
        ExportPdfToolbarButton.IsEnabled = canPublish;
    }

    /// <summary>
    /// The two toolbar-button toggles under <c>View &gt; Toolbar Buttons</c>. Each derives its new
    /// value from <see cref="_toolbarActions"/>, never from the clicked item's own
    /// <see cref="MenuItem.IsChecked"/> — a real click flips it, a click forwarded from the hamburger
    /// mirror does not, and reading it would make one command mean opposite things on the two
    /// surfaces. Same rule, and the same reason, as <see cref="OnToggleMenuBarClick"/>.
    /// </summary>
    private void OnToggleToolbarOpenRecentClick(object? sender, RoutedEventArgs e) =>
        ApplyToolbarActions(_toolbarActions.WithOpenRecent(!_toolbarActions.OpenRecent), persist: true);

    /// <inheritdoc cref="OnToggleToolbarOpenRecentClick"/>
    private void OnToggleToolbarExportPdfClick(object? sender, RoutedEventArgs e) =>
        ApplyToolbarActions(_toolbarActions.WithExportPdf(!_toolbarActions.ExportPdf), persist: true);

    /// <summary>
    /// Shows and hides the toolbar's optional commands, and writes the View menu's check marks back
    /// from the same value — so a mirrored click, which does not tick the item it was made on, still
    /// leaves both surfaces agreeing about what is on the toolbar.
    /// </summary>
    /// <remarks>
    /// <para>
    /// Only visibility is decided here. Whether Export to PDF is <em>enabled</em> stays
    /// <see cref="UpdateDocumentCommandState"/>'s, alongside its File-menu twin, and Open Recent's
    /// stays <see cref="RebuildRecentFilesMenu"/>'s alongside the File menu's submenu; a hidden button
    /// keeps whatever state its command has, so showing one never reveals a stale plate.
    /// </para>
    /// <para>
    /// The divider in front of the publishing group is hidden with it
    /// (<see cref="ToolbarActions.PublishGroupVisible"/>), which is the whole of the layout care these
    /// need: a <see cref="StackPanel"/> gives a hidden child no space, so every other combination
    /// closes up on its own with no gap and no doubled separator.
    /// </para>
    /// </remarks>
    /// <param name="persist">
    /// False while restoring saved settings at startup, so reinstating what was loaded does not write
    /// the file straight back out again.
    /// </param>
    private void ApplyToolbarActions(ToolbarActions actions, bool persist)
    {
        _toolbarActions = actions;

        OpenRecentToolbarButton.IsVisible = actions.OpenRecent;
        ExportPdfToolbarButton.IsVisible = actions.ExportPdf;
        PublishToolbarSeparator.IsVisible = actions.PublishGroupVisible;

        ToolbarOpenRecentItem.IsChecked = actions.OpenRecent;
        ToolbarExportPdfItem.IsChecked = actions.ExportPdf;

        if (persist)
        {
            _settings.ApplyToolbarActions(actions);
            SaveSettings();
        }
    }

    /// <summary>
    /// The two command-surface toggles, and the one thing about them worth stating: the new value is
    /// derived from <see cref="_commandSurfaces"/>, never from the clicked item's own
    /// <see cref="MenuItem.IsChecked"/>.
    /// </summary>
    /// <remarks>
    /// A real click on a checkbox <see cref="MenuItem"/> flips it before the handler runs; a click
    /// forwarded from the toolbar's menu mirror does not (see <see cref="MenuMirror"/>).
    /// Reading the item would therefore make the same command mean opposite things on the two
    /// surfaces. Taking the application's own state as the question and writing the check mark back in
    /// <see cref="ApplyCommandSurfaces"/> makes them identical.
    /// </remarks>
    private void OnToggleMenuBarClick(object? sender, RoutedEventArgs e) =>
        ApplyCommandSurfaces(_commandSurfaces.WithMenuBar(!_commandSurfaces.MenuBarVisible), persist: true);

    /// <inheritdoc cref="OnToggleMenuBarClick"/>
    private void OnToggleToolbarClick(object? sender, RoutedEventArgs e) =>
        ApplyCommandSurfaces(_commandSurfaces.WithToolbar(!_commandSurfaces.ToolbarVisible), persist: true);

    /// <summary>
    /// The toolbar's <c>☰</c> menu button, under <c>View &gt; Toolbar Buttons &gt; Menu</c>. It sits
    /// with <see cref="ToolbarActions"/>' two optional commands in the menu because that is where a
    /// reader looks for "which buttons does my toolbar have", but it belongs to
    /// <see cref="CommandSurfaces"/> because it is the only one of the four that can be the last route
    /// to a command — see <see cref="CommandSurfaces.CanHideToolbarMenuButton"/>.
    /// </summary>
    /// <inheritdoc cref="OnToggleMenuBarClick" path="/remarks"/>
    private void OnToggleToolbarMenuClick(object? sender, RoutedEventArgs e) =>
        ApplyCommandSurfaces(
            _commandSurfaces.WithToolbarMenuButton(!_commandSurfaces.ToolbarMenuButtonVisible),
            persist: true);

    private void OnToggleStatusBarClick(object? sender, RoutedEventArgs e) =>
        SetStatusBarVisible(!StatusBar.IsVisible, persist: true);

    /// <summary>
    /// Shows and hides the menu bar, the toolbar, and the toolbar's menu button together, from the one
    /// value that knows which of them may not go. All three View items are rewritten from it: checked
    /// to match what is on screen, and disabled when the surface they control is the last route to a
    /// command — so the invariants are visible in the menu rather than being clicks that quietly do
    /// nothing.
    /// </summary>
    /// <remarks>
    /// <see cref="Visual.IsVisible"/> rather than opacity or a zero height, so the
    /// <see cref="DockPanel"/> stops reserving the row entirely and the document takes the space back
    /// with no residual gap. Nothing about the document is touched — no reload, no history entry, no
    /// timestamp — the WebView simply relayouts.
    /// </remarks>
    /// <param name="persist">
    /// False while restoring saved settings at startup, so reinstating what was loaded does not write
    /// the file straight back out again.
    /// </param>
    private void ApplyCommandSurfaces(CommandSurfaces surfaces, bool persist)
    {
        _commandSurfaces = surfaces;

        MainMenu.IsVisible = surfaces.MenuBarVisible;
        Toolbar.IsVisible = surfaces.ToolbarVisible;

        // Visibility only, and nothing else about the button: a StackPanel gives a hidden child no
        // space, so Open simply becomes the leftmost action with no gap and no placeholder left behind.
        MenuToolbarButton.IsVisible = surfaces.ToolbarMenuButtonVisible;

        MenuBarVisibleItem.IsChecked = surfaces.MenuBarVisible;
        ToolbarVisibleItem.IsChecked = surfaces.ToolbarVisible;
        ToolbarMenuItem.IsChecked = surfaces.ToolbarMenuButtonVisible;

        // CanHide* is false only for a surface whose loss would leave no way to reach a command, so a
        // hidden one is always re-showable: hiding the toolbar leaves the menu bar's item disabled,
        // hiding the menu bar leaves both the toolbar's and the menu button's disabled, and hiding the
        // menu button leaves the menu bar's disabled.
        MenuBarVisibleItem.IsEnabled = surfaces.CanHideMenuBar;
        ToolbarVisibleItem.IsEnabled = surfaces.CanHideToolbar;
        ToolbarMenuItem.IsEnabled = surfaces.CanHideToolbarMenuButton;

        // Nothing to put a button on while the toolbar is hidden, so the submenu that adds them greys
        // out rather than offering four choices with no visible effect. Reachable either way: hiding
        // the toolbar means the menu bar is showing, which CommandSurfaces guarantees.
        ToolbarButtonsMenuItem.IsEnabled = surfaces.ToolbarVisible;

        if (persist)
        {
            _settings.ApplyCommandSurfaces(surfaces);
            SaveSettings();
        }
    }

    /// <summary>
    /// The status bar, which is chrome but not a command surface: it reports state and offers two
    /// optional actions, so hiding it costs information rather than access and it carries no
    /// invariant. Same mechanism and the same reasons as <see cref="ApplyCommandSurfaces"/>.
    /// </summary>
    private void SetStatusBarVisible(bool visible, bool persist)
    {
        StatusBar.IsVisible = visible;
        StatusBarVisibleItem.IsChecked = visible;

        if (persist)
        {
            _settings.StatusBarVisible = visible;
            SaveSettings();
        }
    }

    private void OnWatcherStateChanged(object? sender, FileViewState state) => RefreshStatusBar();

    /// <summary>
    /// Replaces the freshness <em>text</em> with a one-off message for <paramref name="duration"/>, or
    /// until cleared explicitly when that is <c>null</c> (a busy state).
    /// </summary>
    /// <remarks>
    /// This is presentation only, layered over the file state — it never touches
    /// <see cref="FileViewState"/>. The status dot keeps showing the real document state throughout,
    /// the three timestamps keep advancing behind the message, and when it expires the status bar
    /// shows whatever became true meanwhile: a file that went stale under an export message comes
    /// back as "Newer version available", not as the state it had when the message appeared.
    /// </remarks>
    private void SetStatusOverride(string message, TimeSpan? duration)
    {
        _statusOverride = message;
        _statusOverrideTimer.Stop();

        if (duration is { } interval)
        {
            _statusOverrideTimer.Interval = interval;
            _statusOverrideTimer.Start();
        }

        RefreshStatusBar();
    }

    private void ClearStatusOverride()
    {
        _statusOverrideTimer.Stop();
        _statusOverride = null;

        // Open PDF belongs to the success message and goes when it does. What the registry remembers
        // per document is deliberately untouched — the folder action outlives the message.
        _recentExportPath = null;

        UpdateExportActionState();
        RefreshStatusBar();
    }

    /// <summary>
    /// Status text always carries itself as its own tooltip: the line is ellipsised when the window is
    /// narrow, and an exported PDF's full path is exactly the sort of thing that gets cut off and is
    /// then wanted in full.
    /// </summary>
    private void SetStatusText(string text)
    {
        StatusText.Text = text;
        ToolTip.SetTip(StatusText, text);
    }

    private void RefreshStatusBar()
    {
        if (_watcher is null)
        {
            StatusDot.Fill = NeutralDotBrush;
            SetStatusText("No document open");
            ReloadButton.IsVisible = false;
            ConfirmBanner.IsVisible = false;
            return;
        }

        var state = _watcher.State;
        var nowUtc = DateTime.UtcNow;
        var level = state.GetStatusLevel(nowUtc);

        StatusDot.Fill = level switch
        {
            DocumentStatusLevel.Error => ErrorDotBrush,
            DocumentStatusLevel.NewerOnDisk => NewerOnDiskDotBrush,
            DocumentStatusLevel.RecentlyReloaded => RecentlyReloadedDotBrush,
            _ => NeutralDotBrush,
        };

        var nowLocal = DateTime.Now;
        string FormatLocal(DateTime? utc) =>
            utc is { } value ? TimestampFormatter.Format(value.ToLocalTime(), nowLocal) : "—";

        SetStatusText(_statusOverride ?? level switch
        {
            DocumentStatusLevel.Error => $"Error — {state.ErrorMessage}",
            DocumentStatusLevel.NewerOnDisk =>
                $"Newer version available    Viewed: {FormatLocal(state.RenderedTimestampUtc)}    File: {FormatLocal(state.DiskTimestampUtc)}",
            _ =>
                $"Up to date    File: {FormatLocal(state.DiskTimestampUtc)}    Reloaded: {FormatLocal(state.LastReloadTimestampUtc)}",
        });

        ReloadButton.IsVisible = true;
        ConfirmBanner.IsVisible = state.ReloadMode == ReloadMode.Confirm && level == DocumentStatusLevel.NewerOnDisk;
    }

    /// <summary>
    /// Reinstates the saved size, position, and maximized state — but never outside the monitor
    /// working area a non-maximized window has to live in.
    /// </summary>
    /// <remarks>
    /// <para>
    /// The observed failure was a restored window taller than the screen, whose title bar ended up
    /// above the top edge and out of reach. Size and position are therefore both clamped, not merely
    /// validated: the saved geometry is honoured where it fits and shrunk/nudged where it does not,
    /// which is far friendlier than discarding it. This equally covers a first run whose default
    /// 1100×850 is too big for the display, a monitor that changed resolution or DPI since the last
    /// run, and coordinates saved on a monitor that is no longer connected.
    /// </para>
    /// <para>
    /// Working area rather than full monitor bounds, so the Windows taskbar is respected. The
    /// arithmetic itself lives in <see cref="WindowPlacementCalculator"/> in Core, where it is unit
    /// tested; this method only converts between Avalonia's units and its own.
    /// </para>
    /// </remarks>
    private void RestoreWindowPlacement(WindowPlacement placement)
    {
        var width = placement.Width ?? Width;
        var height = placement.Height ?? Height;

        var workingAreas = TryGetWorkingAreas();
        if (workingAreas.Count == 0)
        {
            // No screen information (headless or an unusual platform): restore verbatim, as before.
            ApplyRestoredPlacement(width, height, placement.X, placement.Y, placement.Maximized);
            return;
        }

        // Sizes are device-independent units and positions are physical pixels, so the fit has to be
        // computed in pixels using the scaling of the display the window is actually headed for.
        var scaling = ScalingFor(placement.X, placement.Y);
        var frameWidth = EstimatedFrameWidth * scaling;
        var frameHeight = EstimatedFrameHeight * scaling;

        var fit = WindowPlacementCalculator.Fit(
            placement.X,
            placement.Y,
            (int)Math.Round(width * scaling + frameWidth),
            (int)Math.Round(height * scaling + frameHeight),
            workingAreas);

        ApplyRestoredPlacement(
            Math.Max((fit.Width - frameWidth) / scaling, WindowPlacement.MinimumSize),
            Math.Max((fit.Height - frameHeight) / scaling, WindowPlacement.MinimumSize),
            fit.X,
            fit.Y,
            placement.Maximized);
    }

    private void ApplyRestoredPlacement(double width, double height, int? x, int? y, bool maximized)
    {
        Width = width;
        Height = height;

        if (x is { } left && y is { } top)
        {
            WindowStartupLocation = WindowStartupLocation.Manual;
            Position = new PixelPoint(left, top);
        }

        // Restore the maximized state last, and only after the normal size has been set, so
        // un-maximizing returns to the geometry that was saved rather than to a default.
        if (maximized)
        {
            WindowState = WindowState.Maximized;
        }
    }

    private IReadOnlyList<ScreenArea> TryGetWorkingAreas()
    {
        try
        {
            // Primary first: WindowPlacementCalculator treats the head of the list as the fallback
            // monitor for geometry it cannot place anywhere else.
            return Screens.All
                .OrderByDescending(screen => screen.IsPrimary)
                .Select(screen => new ScreenArea(
                    screen.WorkingArea.X,
                    screen.WorkingArea.Y,
                    screen.WorkingArea.Width,
                    screen.WorkingArea.Height))
                .ToList();
        }
        catch (Exception ex) when (ex is InvalidOperationException or NotSupportedException)
        {
            return [];
        }
    }

    /// <summary>
    /// Scaling of the display the saved position lands on, falling back to the primary display's.
    /// A window saved on a 150% monitor and restored with only a 100% one connected would otherwise be
    /// fitted using the wrong pixel size.
    /// </summary>
    private double ScalingFor(int? x, int? y)
    {
        try
        {
            var screen = x is { } left && y is { } top
                ? Screens.ScreenFromPoint(new PixelPoint(left, top)) ?? Screens.Primary
                : Screens.Primary;

            return screen?.Scaling is { } scaling && scaling > 0 ? scaling : 1.0;
        }
        catch (Exception ex) when (ex is InvalidOperationException or NotSupportedException)
        {
            return 1.0;
        }
    }

    /// <summary>
    /// Defers the geometry snapshot until movement has stopped. Reading it directly from the size and
    /// move events would be wrong as well as wasteful: a maximize raises both <em>before</em>
    /// <see cref="Window.WindowState"/> reports the new state, so the maximized bounds would be
    /// recorded as the window's normal size and a later un-maximize would restore a screen-sized
    /// window at the screen's origin.
    /// </summary>
    private void ScheduleWindowPlacementCapture()
    {
        _windowPlacementTimer.Stop();
        _windowPlacementTimer.Start();
    }

    private void CaptureNormalPlacement()
    {
        _windowPlacementTimer.Stop();

        if (WindowState != WindowState.Normal)
        {
            return;
        }

        _normalWidth = ClientSize.Width;
        _normalHeight = ClientSize.Height;
        _normalPosition = Position;
    }

    /// <summary>
    /// Copies the tracked geometry into the settings object. Called once, on close: window move and
    /// resize events fire continuously while dragging, and writing a file on each of them would be
    /// both wasteful and a good way to corrupt it.
    /// </summary>
    private void PersistWindowPlacement()
    {
        var placement = _settings.Window;
        placement.Maximized = WindowState == WindowState.Maximized;

        if (_normalWidth is { } width && _normalHeight is { } height)
        {
            placement.Width = width;
            placement.Height = height;
        }

        if (_normalPosition is { } position)
        {
            placement.X = position.X;
            placement.Y = position.Y;
        }
    }

    private void SaveSettings() => _settingsStore.Save(_settings);

    protected override void OnClosed(EventArgs e)
    {
        _windowClosed = true;
        _statusRefreshTimer.Stop();
        _statusOverrideTimer.Stop();
        _windowPlacementTimer.Stop();
        _pdfExportCancellation?.Cancel();
        _watcher?.Dispose();

        PersistWindowPlacement();
        SaveSettings();

        base.OnClosed(e);
    }

    /// <summary>
    /// An error page as the viewer is showing it, retained only so a theme switch can redraw it. Not
    /// a <see cref="RenderedDocument"/>: there is no source text, no version, and nothing to export.
    /// </summary>
    private sealed record ViewerErrorPage(string Path, string Message);
}

