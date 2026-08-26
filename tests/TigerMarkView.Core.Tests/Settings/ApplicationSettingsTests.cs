using TigerMarkView.Core.Editing;
using TigerMarkView.Core.Exporting;
using TigerMarkView.Core.Monitoring;
using TigerMarkView.Core.Rendering;
using TigerMarkView.Core.Settings;

namespace TigerMarkView.Core.Tests.Settings;

public class ApplicationSettingsTests
{
    /// <summary>The documented first-run behaviour.</summary>
    [Fact]
    public void DefaultsMatchTheDocumentedFirstRunBehaviour()
    {
        var settings = ApplicationSettings.CreateDefault();

        Assert.Equal(ApplicationSettings.CurrentVersion, settings.Version);
        Assert.Equal(MarkdownTheme.Light, settings.Theme);
        Assert.Equal(ReloadMode.Confirm, settings.ReloadMode);
        Assert.Equal(EditorType.SystemDefault, settings.EditorType);
        Assert.Null(settings.CustomEditorPath);
        Assert.Null(settings.CustomEditorArguments);
        Assert.Empty(settings.RecentFiles);

        // Chrome starts visible: a reader who has never opened the View menu gets the whole UI.
        Assert.True(settings.MenuBarVisible);
        Assert.True(settings.ToolbarVisible);
        Assert.True(settings.StatusBarVisible);

        // PDF export starts where it always was: A4 portrait, Normal margins, unnumbered.
        Assert.Equal(PdfPaperSize.A4, settings.PdfPaperSize);
        Assert.Equal(PdfOrientation.Portrait, settings.PdfOrientation);
        Assert.Equal(PdfMarginPreset.Normal, settings.PdfMargins);
        Assert.False(settings.PdfPageNumbers);

        // Both optional rendering behaviours start off: a reader who has never opened View > Rendering
        // gets the rendering TigerMarkView has always produced.
        Assert.False(settings.EmojiShortcodes);
        Assert.False(settings.SyntaxHighlighting);
        Assert.Equal(MarkdownRenderingOptions.Default, settings.ToRenderingOptions());

        Assert.Null(settings.Window.Width);
        Assert.Null(settings.Window.Height);
        Assert.Null(settings.Window.X);
        Assert.Null(settings.Window.Y);
        Assert.False(settings.Window.Maximized);
    }

    [Fact]
    public void DefaultSettingsProduceTheUnchangedPageSetup()
    {
        Assert.Equal(PdfPageSetup.Default, ApplicationSettings.CreateDefault().ToPdfPageSetup());
    }

    [Fact]
    public void ThePdfPreferencesTranslateIntoPhysicalPageGeometry()
    {
        var settings = new ApplicationSettings
        {
            PdfPaperSize = PdfPaperSize.A5,
            PdfOrientation = PdfOrientation.Landscape,
            PdfMargins = PdfMarginPreset.Narrow,
            PdfPageNumbers = true,
        };

        var page = settings.ToPdfPageSetup();

        Assert.Equal(210, page.WidthMillimetres, 6);
        Assert.Equal(148, page.HeightMillimetres, 6);
        Assert.Equal(PdfPageMargins.For(PdfMarginPreset.Narrow), page.Margins);
        Assert.True(page.ShowPageNumbers);
    }

    [Theory]
    [InlineData(false, false)]
    [InlineData(true, false)]
    [InlineData(false, true)]
    [InlineData(true, true)]
    public void TheRenderingPreferencesTranslateIntoRenderingOptions(bool emoji, bool syntax)
    {
        var settings = new ApplicationSettings { EmojiShortcodes = emoji, SyntaxHighlighting = syntax };

        Assert.Equal(new MarkdownRenderingOptions(emoji, syntax), settings.ToRenderingOptions());
    }

    [Fact]
    public void DefaultSettingsProduceTheSystemDefaultEditor()
    {
        var configuration = ApplicationSettings.CreateDefault().ToEditorConfiguration();

        Assert.Equal(EditorType.SystemDefault, configuration.Type);
    }

    [Theory]
    [InlineData(EditorType.VisualStudioCode)]
    [InlineData(EditorType.Notepad3)]
    public void PresetEditorSelectionsRoundTripThroughSettings(EditorType type)
    {
        var settings = ApplicationSettings.CreateDefault();
        var chosen = type == EditorType.VisualStudioCode
            ? EditorConfiguration.VisualStudioCode()
            : EditorConfiguration.Notepad3();

        settings.ApplyEditorConfiguration(chosen);

        Assert.Equal(chosen, settings.ToEditorConfiguration());
    }

    [Fact]
    public void ACustomEditorRoundTripsItsPathAndArguments()
    {
        var settings = ApplicationSettings.CreateDefault();

        settings.ApplyEditorConfiguration(
            EditorConfiguration.Custom(@"C:\Tools\My Editor\edit.exe", "--wait \"{file}\""));

        var restored = settings.ToEditorConfiguration();

        Assert.Equal(EditorType.Custom, restored.Type);
        Assert.Equal(@"C:\Tools\My Editor\edit.exe", restored.ExecutablePath);
        Assert.Equal("--wait \"{file}\"", restored.ArgumentsTemplate);
    }

    /// <summary>
    /// Switching to a preset and back must not lose what the user configured, so the Custom fields
    /// are remembered even while another editor is selected.
    /// </summary>
    [Fact]
    public void SelectingAPresetKeepsTheRememberedCustomEditor()
    {
        var settings = ApplicationSettings.CreateDefault();
        settings.ApplyEditorConfiguration(EditorConfiguration.Custom(@"C:\edit.exe", "{file}"));

        settings.ApplyEditorConfiguration(EditorConfiguration.VisualStudioCode());

        Assert.Equal(EditorType.VisualStudioCode, settings.EditorType);
        Assert.Equal(@"C:\edit.exe", settings.CustomEditorPath);
        Assert.Equal("{file}", settings.CustomEditorArguments);
    }

    /// <summary>A half-written or hand-broken Custom entry degrades instead of restoring a broken launch.</summary>
    [Fact]
    public void ACustomEditorWithNoExecutableFallsBackToSystemDefault()
    {
        var settings = ApplicationSettings.CreateDefault();
        settings.EditorType = EditorType.Custom;
        settings.CustomEditorPath = "   ";

        Assert.Equal(EditorType.SystemDefault, settings.ToEditorConfiguration().Type);
    }

    [Fact]
    public void NormalizedRepairsAPartiallyMissingObjectGraph()
    {
        var settings = ApplicationSettings.CreateDefault();
        settings.Version = 0;
        settings.RecentFiles = null!;
        settings.Window = null!;

        settings.Normalized();

        Assert.Equal(ApplicationSettings.CurrentVersion, settings.Version);
        Assert.Empty(settings.RecentFiles);
        Assert.NotNull(settings.Window);
    }

    /// <summary>
    /// The settings file is the one place the illegal combination can arrive from — nothing in the UI
    /// can produce it — so loading is where it has to be repaired.
    /// </summary>
    [Fact]
    public void NormalizedRepairsASettingsFileThatHidesEveryCommandSurface()
    {
        var settings = ApplicationSettings.CreateDefault();
        settings.MenuBarVisible = false;
        settings.ToolbarVisible = false;
        settings.StatusBarVisible = false;

        settings.Normalized();

        Assert.True(settings.MenuBarVisible);
        Assert.False(settings.ToolbarVisible);

        // The status bar is not a command surface and is left exactly as the reader had it.
        Assert.False(settings.StatusBarVisible);
    }

    [Theory]
    [InlineData(true, false)]
    [InlineData(false, true)]
    [InlineData(true, true)]
    public void NormalizedLeavesEveryLegalChromeCombinationAlone(bool menuBar, bool toolbar)
    {
        var settings = ApplicationSettings.CreateDefault();
        settings.MenuBarVisible = menuBar;
        settings.ToolbarVisible = toolbar;

        settings.Normalized();

        Assert.Equal(menuBar, settings.MenuBarVisible);
        Assert.Equal(toolbar, settings.ToolbarVisible);
    }

    [Fact]
    public void CommandSurfacesRoundTripThroughTheSettings()
    {
        var settings = ApplicationSettings.CreateDefault();

        settings.ApplyCommandSurfaces(CommandSurfaces.Default.WithToolbar(false));

        Assert.True(settings.MenuBarVisible);
        Assert.False(settings.ToolbarVisible);
        Assert.Equal(
            CommandSurfaces.Of(menuBarVisible: true, toolbarVisible: false, toolbarMenuButtonVisible: true),
            settings.ToCommandSurfaces());
    }

    /// <summary>
    /// The toolbar's menu button is the one <c>View &gt; Toolbar Buttons</c> entry that starts on: it is
    /// the toolbar this application has always shown, and hiding it is the reader's choice to make.
    /// </summary>
    [Fact]
    public void TheToolbarMenuButtonIsOnForAFirstRun()
    {
        var settings = ApplicationSettings.CreateDefault();

        Assert.True(settings.ToolbarMenuVisible);
        Assert.True(settings.ToCommandSurfaces().ToolbarMenuButtonVisible);
    }

    [Fact]
    public void TheToolbarMenuButtonRoundTripsThroughTheSettings()
    {
        var settings = ApplicationSettings.CreateDefault();

        settings.ApplyCommandSurfaces(CommandSurfaces.Default.WithToolbarMenuButton(false));

        Assert.False(settings.ToolbarMenuVisible);
        Assert.False(settings.ToCommandSurfaces().ToolbarMenuButtonVisible);
    }

    /// <summary>
    /// The state a hand-edited file can claim and a window cannot survive: no menu bar and no menu
    /// button, so nothing on screen reaches Tools, Help, or the menu bar itself. The menu button is
    /// what comes back — never the menu bar, which the reader chose to do without.
    /// </summary>
    [Fact]
    public void NormalizedRepairsACompactWindowWithNoMenuButton()
    {
        var settings = ApplicationSettings.CreateDefault();
        settings.MenuBarVisible = false;
        settings.ToolbarVisible = true;
        settings.ToolbarMenuVisible = false;

        settings.Normalized();

        Assert.False(settings.MenuBarVisible);
        Assert.True(settings.ToolbarVisible);
        Assert.True(settings.ToolbarMenuVisible);
    }

    /// <summary>
    /// A menu button hidden under a visible menu bar is a legal choice and is left exactly as it was —
    /// the repair above must not be a blanket "show the menu button".
    /// </summary>
    [Fact]
    public void NormalizedLeavesAHiddenMenuButtonAloneWhileTheMenuBarShows()
    {
        var settings = ApplicationSettings.CreateDefault();
        settings.ToolbarMenuVisible = false;

        settings.Normalized();

        Assert.False(settings.ToolbarMenuVisible);
    }

    /// <summary>
    /// The compact toolbar is what a first run gets: neither optional command is on it until the
    /// reader asks for it under <c>View &gt; Toolbar Buttons</c>.
    /// </summary>
    [Fact]
    public void TheOptionalToolbarCommandsAreOffOnAFirstRun()
    {
        var settings = ApplicationSettings.CreateDefault();

        Assert.False(settings.ToolbarOpenRecentVisible);
        Assert.False(settings.ToolbarExportPdfVisible);
        Assert.Equal(ToolbarActions.Default, settings.ToToolbarActions());
    }

    [Fact]
    public void ToolbarActionsRoundTripThroughTheSettings()
    {
        var settings = ApplicationSettings.CreateDefault();

        settings.ApplyToolbarActions(ToolbarActions.Default.WithOpenRecent(true).WithExportPdf(true));

        Assert.True(settings.ToolbarOpenRecentVisible);
        Assert.True(settings.ToolbarExportPdfVisible);
        Assert.Equal(
            new ToolbarActions(OpenRecent: true, ExportPdf: true),
            settings.ToToolbarActions());
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1200)]
    [InlineData(double.NaN)]
    [InlineData(50)]
    public void NormalizedDiscardsImpossibleWindowSizes(double width)
    {
        var settings = ApplicationSettings.CreateDefault();
        settings.Window.Width = width;
        settings.Window.Height = 900;

        settings.Normalized();

        Assert.Null(settings.Window.Width);
        Assert.Equal(900, settings.Window.Height);
    }

    /// <summary>A position is only meaningful as a pair; half of one is discarded rather than guessed at.</summary>
    [Fact]
    public void NormalizedDiscardsAHalfWrittenWindowPosition()
    {
        var settings = ApplicationSettings.CreateDefault();
        settings.Window.X = 120;

        settings.Normalized();

        Assert.Null(settings.Window.X);
        Assert.Null(settings.Window.Y);
    }
}
