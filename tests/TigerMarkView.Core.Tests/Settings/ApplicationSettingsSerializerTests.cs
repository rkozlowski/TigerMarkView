using TigerMarkView.Core.Editing;
using TigerMarkView.Core.Exporting;
using TigerMarkView.Core.Monitoring;
using TigerMarkView.Core.Rendering;
using TigerMarkView.Core.Settings;

namespace TigerMarkView.Core.Tests.Settings;

/// <summary>
/// Serialization is tested independently of where the file lives, so none of this touches the
/// filesystem or a Windows-specific path.
/// </summary>
public class ApplicationSettingsSerializerTests
{
    [Fact]
    public void EveryPersistedFieldSurvivesARoundTrip()
    {
        var original = new ApplicationSettings
        {
            Theme = MarkdownTheme.Dark,
            ReloadMode = ReloadMode.Automatic,
            EditorType = EditorType.Custom,
            CustomEditorPath = @"C:\Tools\My Editor\edit.exe",
            CustomEditorArguments = "--wait \"{file}\"",
            RecentFiles = new List<string> { @"C:\docs\a.md", @"C:\docs\b.md" },
            MenuBarVisible = false,
            ToolbarVisible = true,
            StatusBarVisible = false,
            PdfPaperSize = PdfPaperSize.Legal,
            PdfOrientation = PdfOrientation.Landscape,
            PdfMargins = PdfMarginPreset.Wide,
            PdfPageNumbers = true,
            EmojiShortcodes = true,
            SyntaxHighlighting = true,
            ToolbarOpenRecentVisible = true,
            ToolbarExportPdfVisible = true,
            Window = new WindowPlacement { Width = 1234, Height = 567, X = 40, Y = 80, Maximized = true },
        };

        var restored = ApplicationSettingsSerializer.Deserialize(
            ApplicationSettingsSerializer.Serialize(original));

        Assert.Equal(ApplicationSettings.CurrentVersion, restored.Version);
        Assert.Equal(MarkdownTheme.Dark, restored.Theme);
        Assert.Equal(ReloadMode.Automatic, restored.ReloadMode);
        Assert.Equal(EditorType.Custom, restored.EditorType);
        Assert.Equal(original.CustomEditorPath, restored.CustomEditorPath);
        Assert.Equal(original.CustomEditorArguments, restored.CustomEditorArguments);
        Assert.Equal(original.RecentFiles, restored.RecentFiles);
        Assert.False(restored.MenuBarVisible);
        Assert.True(restored.ToolbarVisible);
        Assert.False(restored.StatusBarVisible);
        Assert.Equal(PdfPaperSize.Legal, restored.PdfPaperSize);
        Assert.Equal(PdfOrientation.Landscape, restored.PdfOrientation);
        Assert.Equal(PdfMarginPreset.Wide, restored.PdfMargins);
        Assert.True(restored.PdfPageNumbers);
        Assert.True(restored.EmojiShortcodes);
        Assert.True(restored.SyntaxHighlighting);
        Assert.True(restored.ToolbarOpenRecentVisible);
        Assert.True(restored.ToolbarExportPdfVisible);
        Assert.Equal(1234, restored.Window.Width);
        Assert.Equal(567, restored.Window.Height);
        Assert.Equal(40, restored.Window.X);
        Assert.Equal(80, restored.Window.Y);
        Assert.True(restored.Window.Maximized);
    }

    /// <summary>Enums are written as names so the file stays legible and reordering members is safe.</summary>
    [Fact]
    public void EnumsAreWrittenAsNamesAndTheVersionIsStamped()
    {
        var json = ApplicationSettingsSerializer.Serialize(
            new ApplicationSettings { Theme = MarkdownTheme.Dark, ReloadMode = ReloadMode.Manual });

        Assert.Contains("\"version\": 1", json);
        Assert.Contains("\"theme\": \"Dark\"", json);
        Assert.Contains("\"reloadMode\": \"Manual\"", json);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("this is not json")]
    [InlineData("{ \"theme\": ")]
    [InlineData("[1, 2, 3]")]
    public void MalformedContentFallsBackToDefaultsWithoutThrowing(string json)
    {
        Assert.False(ApplicationSettingsSerializer.TryDeserialize(json, out var settings));

        Assert.Equal(MarkdownTheme.Light, settings.Theme);
        Assert.Equal(ReloadMode.Confirm, settings.ReloadMode);
        Assert.Equal(EditorType.SystemDefault, settings.EditorType);
        Assert.Empty(settings.RecentFiles);
    }

    [Fact]
    public void ExplicitJsonNullDeserializesToDefaults()
    {
        var settings = ApplicationSettingsSerializer.Deserialize("null");

        Assert.Equal(MarkdownTheme.Light, settings.Theme);
        Assert.Equal(ReloadMode.Confirm, settings.ReloadMode);
    }

    /// <summary>
    /// A file written by a future TigerMarkView (or hand-edited) costs the user that one setting, not
    /// the rest of the file — this is the whole point of the tolerant enum converter.
    /// </summary>
    [Fact]
    public void AnUnrecognisedEnumValueFallsBackWithoutDiscardingTheOtherSettings()
    {
        const string json = """
            {
              "version": 1,
              "theme": "Solarized",
              "reloadMode": "Automatic",
              "recentFiles": [ "C:\\docs\\a.md" ]
            }
            """;

        Assert.True(ApplicationSettingsSerializer.TryDeserialize(json, out var settings));

        Assert.Equal(MarkdownTheme.Light, settings.Theme);
        Assert.Equal(ReloadMode.Automatic, settings.ReloadMode);
        Assert.Equal(new[] { @"C:\docs\a.md" }, settings.RecentFiles);
    }

    [Fact]
    public void AnEnumOfTheWrongJsonShapeFallsBackWithoutDiscardingTheOtherSettings()
    {
        const string json = """
            {
              "theme": { "name": "Dark" },
              "reloadMode": null,
              "editorType": 99,
              "recentFiles": [ "C:\\docs\\a.md" ]
            }
            """;

        Assert.True(ApplicationSettingsSerializer.TryDeserialize(json, out var settings));

        Assert.Equal(MarkdownTheme.Light, settings.Theme);
        // Not the enum's zero member (Manual) — the fallback is the application's documented default.
        Assert.Equal(ReloadMode.Confirm, settings.ReloadMode);
        Assert.Equal(EditorType.SystemDefault, settings.EditorType);
        Assert.Equal(new[] { @"C:\docs\a.md" }, settings.RecentFiles);
    }

    /// <summary>
    /// The rendering options are the file's only named on/off <em>features</em>, so they are the ones
    /// most likely to be reached for by hand. A value of the wrong shape costs that one option rather
    /// than the whole file.
    /// </summary>
    [Fact]
    public void AMalformedRenderingOptionFallsBackWithoutDiscardingTheOtherSettings()
    {
        const string json = """
            {
              "theme": "Dark",
              "emojiShortcodes": "on",
              "syntaxHighlighting": { "enabled": true },
              "recentFiles": [ "C:\\docs\\a.md" ]
            }
            """;

        Assert.True(ApplicationSettingsSerializer.TryDeserialize(json, out var settings));

        Assert.False(settings.EmojiShortcodes);
        Assert.False(settings.SyntaxHighlighting);

        Assert.Equal(MarkdownTheme.Dark, settings.Theme);
        Assert.Equal(new[] { @"C:\docs\a.md" }, settings.RecentFiles);
    }

    /// <summary>
    /// The additive-growth guarantee: a settings file written before the rendering options existed is
    /// still valid, and lands on both being off.
    /// </summary>
    [Fact]
    public void ASettingsFileWrittenBeforeTheRenderingOptionsExistedStillLoads()
    {
        const string json = """
            {
              "version": 1,
              "theme": "Dark",
              "reloadMode": "Automatic",
              "pdfPaperSize": "Letter",
              "recentFiles": [ "C:\\docs\\a.md" ]
            }
            """;

        Assert.True(ApplicationSettingsSerializer.TryDeserialize(json, out var settings));

        Assert.Equal(ApplicationSettings.CurrentVersion, settings.Version);
        Assert.False(settings.EmojiShortcodes);
        Assert.False(settings.SyntaxHighlighting);
        Assert.Equal(MarkdownRenderingOptions.Default, settings.ToRenderingOptions());

        Assert.Equal(MarkdownTheme.Dark, settings.Theme);
        Assert.Equal(ReloadMode.Automatic, settings.ReloadMode);
        Assert.Equal(PdfPaperSize.Letter, settings.PdfPaperSize);
    }

    /// <summary>
    /// The same additive-growth guarantee for the toolbar's optional commands. A file written before
    /// they existed — which is every file anyone has today — must load as the compact toolbar its
    /// owner already had, keeping everything else it holds.
    /// </summary>
    [Fact]
    public void ASettingsFileWrittenBeforeTheOptionalToolbarCommandsKeepsTheCompactToolbar()
    {
        const string json = """
            {
              "version": 1,
              "theme": "Dark",
              "reloadMode": "Automatic",
              "toolbarVisible": true,
              "statusBarVisible": false,
              "recentFiles": [ "C:\\docs\\a.md" ]
            }
            """;

        Assert.True(ApplicationSettingsSerializer.TryDeserialize(json, out var settings));

        Assert.Equal(ApplicationSettings.CurrentVersion, settings.Version);
        Assert.False(settings.ToolbarOpenRecentVisible);
        Assert.False(settings.ToolbarExportPdfVisible);
        Assert.Equal(ToolbarActions.Default, settings.ToToolbarActions());

        Assert.Equal(MarkdownTheme.Dark, settings.Theme);
        Assert.Equal(ReloadMode.Automatic, settings.ReloadMode);
        Assert.True(settings.ToolbarVisible);
        Assert.False(settings.StatusBarVisible);
        Assert.Equal(new[] { @"C:\docs\a.md" }, settings.RecentFiles);
    }

    /// <summary>
    /// A hand-written value of the wrong shape costs that one button rather than the whole file, and
    /// costs it in the safe direction: the button is simply not on the toolbar.
    /// </summary>
    [Fact]
    public void AMalformedToolbarButtonSettingFallsBackWithoutDiscardingTheOtherSettings()
    {
        const string json = """
            {
              "theme": "Dark",
              "toolbarOpenRecentVisible": "yes",
              "toolbarExportPdfVisible": true
            }
            """;

        Assert.True(ApplicationSettingsSerializer.TryDeserialize(json, out var settings));

        Assert.False(settings.ToolbarOpenRecentVisible);
        Assert.True(settings.ToolbarExportPdfVisible);
        Assert.Equal(MarkdownTheme.Dark, settings.Theme);
    }

    [Fact]
    public void APartialFileKeepsTheDefaultsForEverythingItOmits()
    {
        Assert.True(ApplicationSettingsSerializer.TryDeserialize("""{ "theme": "Dark" }""", out var settings));

        Assert.Equal(MarkdownTheme.Dark, settings.Theme);
        Assert.Equal(ReloadMode.Confirm, settings.ReloadMode);
        Assert.Equal(EditorType.SystemDefault, settings.EditorType);
        Assert.Empty(settings.RecentFiles);
        Assert.NotNull(settings.Window);
        Assert.Null(settings.Window.Width);
    }

    /// <summary>
    /// A settings file written before the toolbar existed. The chrome-visibility fields are simply
    /// absent, and must come back visible without the file being treated as invalid or losing anything
    /// else it holds — which is why adding them needed no version bump.
    /// </summary>
    [Fact]
    public void ASettingsFileWrittenBeforeTheToolbarKeepsItsContentAndShowsAllChrome()
    {
        const string json = """
            {
              "version": 1,
              "theme": "Dark",
              "reloadMode": "Automatic",
              "editorType": "Notepad3",
              "recentFiles": [ "C:\\docs\\a.md" ],
              "window": { "width": 900, "height": 700, "maximized": false }
            }
            """;

        Assert.True(ApplicationSettingsSerializer.TryDeserialize(json, out var settings));

        Assert.True(settings.MenuBarVisible);
        Assert.True(settings.ToolbarVisible);
        Assert.True(settings.StatusBarVisible);

        Assert.Equal(MarkdownTheme.Dark, settings.Theme);
        Assert.Equal(ReloadMode.Automatic, settings.ReloadMode);
        Assert.Equal(EditorType.Notepad3, settings.EditorType);
        Assert.Equal(new[] { @"C:\docs\a.md" }, settings.RecentFiles);
        Assert.Equal(900, settings.Window.Width);
    }

    /// <summary>
    /// A settings file written while the menu bar was still permanent — it has a
    /// <c>toolbarVisible</c> but no <c>menuBarVisible</c>, and its owner had a menu bar. The absent
    /// field must therefore land on visible, including for the reader who had already hidden the
    /// toolbar; anything else would hide the only command surface such a file describes.
    /// </summary>
    [Fact]
    public void ASettingsFileWrittenBeforeTheMenuBarCouldBeHiddenKeepsItsMenuBar()
    {
        const string json = """
            {
              "version": 1,
              "theme": "Light",
              "toolbarVisible": false,
              "statusBarVisible": true
            }
            """;

        Assert.True(ApplicationSettingsSerializer.TryDeserialize(json, out var settings));

        Assert.True(settings.MenuBarVisible);
        Assert.False(settings.ToolbarVisible);
        Assert.True(settings.StatusBarVisible);
    }

    /// <summary>
    /// A file that hides every command surface — hand-edited, or written by something that did not
    /// know the rule. It is repaired on load rather than producing a window with no way to reach a
    /// command; see <see cref="CommandSurfaces"/>.
    /// </summary>
    [Fact]
    public void ASettingsFileHidingEveryCommandSurfaceIsRepairedOnLoad()
    {
        const string json = """
            {
              "version": 1,
              "menuBarVisible": false,
              "toolbarVisible": false,
              "statusBarVisible": false,
              "theme": "Dark"
            }
            """;

        Assert.True(ApplicationSettingsSerializer.TryDeserialize(json, out var settings));

        Assert.True(settings.MenuBarVisible);
        Assert.False(settings.ToolbarVisible);

        // Only the illegal pair is touched: the status bar and everything else stay as written.
        Assert.False(settings.StatusBarVisible);
        Assert.Equal(MarkdownTheme.Dark, settings.Theme);
    }

    /// <summary>
    /// The second command-surface rule, on a file that could only have been hand-written: a compact
    /// window (no menu bar) whose toolbar has had its menu button taken off, which leaves nothing on
    /// screen that reaches Tools, Help, or the menu bar itself. The menu button comes back; the
    /// reader's compact window stays compact.
    /// </summary>
    [Fact]
    public void ASettingsFileHidingBothTheMenuBarAndTheMenuButtonIsRepairedOnLoad()
    {
        const string json = """
            {
              "version": 1,
              "menuBarVisible": false,
              "toolbarVisible": true,
              "toolbarMenuVisible": false,
              "statusBarVisible": false,
              "theme": "Dark"
            }
            """;

        Assert.True(ApplicationSettingsSerializer.TryDeserialize(json, out var settings));

        Assert.True(settings.ToolbarMenuVisible);

        // The menu bar is not brought back to solve it, and nothing else is touched either.
        Assert.False(settings.MenuBarVisible);
        Assert.True(settings.ToolbarVisible);
        Assert.False(settings.StatusBarVisible);
        Assert.Equal(MarkdownTheme.Dark, settings.Theme);
    }

    /// <summary>
    /// The additive-growth guarantee for the newest field of all: a file written before the menu
    /// button could be hidden must load with it showing, which is the toolbar its owner had.
    /// </summary>
    [Fact]
    public void ASettingsFileWrittenBeforeTheMenuButtonCouldBeHiddenKeepsIt()
    {
        const string json = """
            {
              "version": 1,
              "menuBarVisible": false,
              "toolbarVisible": true,
              "toolbarOpenRecentVisible": true
            }
            """;

        Assert.True(ApplicationSettingsSerializer.TryDeserialize(json, out var settings));

        Assert.True(settings.ToolbarMenuVisible);
        Assert.True(settings.ToCommandSurfaces().ToolbarMenuButtonVisible);
        Assert.True(settings.ToolbarOpenRecentVisible);
    }

    [Fact]
    public void ChromeVisibilityIsWrittenForEverySurface()
    {
        var json = ApplicationSettingsSerializer.Serialize(
            new ApplicationSettings
            {
                MenuBarVisible = true,
                ToolbarVisible = true,
                StatusBarVisible = false,
                ToolbarMenuVisible = false,
            });

        Assert.Contains("\"menuBarVisible\": true", json);
        Assert.Contains("\"toolbarVisible\": true", json);
        Assert.Contains("\"statusBarVisible\": false", json);
        Assert.Contains("\"toolbarMenuVisible\": false", json);
    }

    /// <summary>
    /// The same question for the PDF preferences, which are the newest additive fields: a settings
    /// file written before they existed must load as A4 portrait, Normal margins, no page numbers —
    /// i.e. exactly the export behaviour that file's owner had — without a version bump or migration.
    /// </summary>
    [Fact]
    public void ASettingsFileWrittenBeforePdfPreferencesKeepsTheOldExportBehaviour()
    {
        const string json = """
            {
              "version": 1,
              "theme": "Dark",
              "reloadMode": "Manual",
              "editorType": "VisualStudioCode",
              "recentFiles": [ "C:\\docs\\a.md" ],
              "toolbarVisible": false,
              "statusBarVisible": true,
              "window": { "width": 900, "height": 700, "maximized": false }
            }
            """;

        Assert.True(ApplicationSettingsSerializer.TryDeserialize(json, out var settings));

        Assert.Equal(PdfPaperSize.A4, settings.PdfPaperSize);
        Assert.Equal(PdfOrientation.Portrait, settings.PdfOrientation);
        Assert.Equal(PdfMarginPreset.Normal, settings.PdfMargins);
        Assert.False(settings.PdfPageNumbers);
        Assert.Equal(PdfPageSetup.Default, settings.ToPdfPageSetup());

        // And nothing the file did say was lost in the process.
        Assert.Equal(MarkdownTheme.Dark, settings.Theme);
        Assert.Equal(ReloadMode.Manual, settings.ReloadMode);
        Assert.Equal(EditorType.VisualStudioCode, settings.EditorType);
        Assert.False(settings.ToolbarVisible);
        Assert.Equal(ApplicationSettings.CurrentVersion, settings.Version);
    }

    /// <summary>
    /// Both PDF enums have a default that is <em>not</em> their zero member (A3 and Narrow sort
    /// first), so an unreadable value must fall back to the application's default rather than to
    /// whatever happens to be declared first.
    /// </summary>
    [Fact]
    public void UnrecognisedPdfPreferencesFallBackToTheApplicationDefaults()
    {
        const string json = """
            {
              "pdfPaperSize": "A0",
              "pdfOrientation": "Sideways",
              "pdfMargins": { "left": 5 },
              "pdfPageNumbers": true,
              "theme": "Dark"
            }
            """;

        Assert.True(ApplicationSettingsSerializer.TryDeserialize(json, out var settings));

        Assert.Equal(PdfPaperSize.A4, settings.PdfPaperSize);
        Assert.Equal(PdfOrientation.Portrait, settings.PdfOrientation);
        Assert.Equal(PdfMarginPreset.Normal, settings.PdfMargins);

        // The settings that were readable are kept, including the one alongside the broken ones.
        Assert.True(settings.PdfPageNumbers);
        Assert.Equal(MarkdownTheme.Dark, settings.Theme);
    }

    [Fact]
    public void PdfPreferencesAreWrittenAsNames()
    {
        var json = ApplicationSettingsSerializer.Serialize(new ApplicationSettings
        {
            PdfPaperSize = PdfPaperSize.A5,
            PdfOrientation = PdfOrientation.Landscape,
            PdfMargins = PdfMarginPreset.Narrow,
            PdfPageNumbers = true,
        });

        Assert.Contains("\"pdfPaperSize\": \"A5\"", json);
        Assert.Contains("\"pdfOrientation\": \"Landscape\"", json);
        Assert.Contains("\"pdfMargins\": \"Narrow\"", json);
        Assert.Contains("\"pdfPageNumbers\": true", json);
    }

    [Fact]
    public void UnknownPropertiesFromAFutureVersionAreIgnored()
    {
        const string json = """
            { "version": 99, "theme": "Dark", "somethingNewInVersion99": { "nested": [1, 2] } }
            """;

        Assert.True(ApplicationSettingsSerializer.TryDeserialize(json, out var settings));

        Assert.Equal(MarkdownTheme.Dark, settings.Theme);
        // Whatever the file said, what this build writes back is the shape this build understands.
        Assert.Equal(ApplicationSettings.CurrentVersion, settings.Version);
    }

    [Fact]
    public void LoadedRecentFilesAreNormalized()
    {
        const string json = """
            { "recentFiles": [ "C:\\a.md", "", "C:\\A.MD", "C:\\b.md" ] }
            """;

        Assert.True(ApplicationSettingsSerializer.TryDeserialize(json, out var settings));

        Assert.Equal(new[] { @"C:\a.md", @"C:\b.md" }, settings.RecentFiles);
    }

    [Fact]
    public void ANullObjectGraphInTheFileIsRepairedOnLoad()
    {
        Assert.True(ApplicationSettingsSerializer.TryDeserialize(
            """{ "window": null, "recentFiles": null }""", out var settings));

        Assert.NotNull(settings.Window);
        Assert.Empty(settings.RecentFiles);
    }
}
