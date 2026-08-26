using System.Text.Json.Serialization;
using TigerMarkView.Core.Editing;
using TigerMarkView.Core.Exporting;
using TigerMarkView.Core.Monitoring;
using TigerMarkView.Core.Rendering;
using EditorKind = TigerMarkView.Core.Editing.EditorType;

namespace TigerMarkView.Core.Settings;

/// <summary>
/// Everything TigerMarkView remembers between runs. Platform-neutral by design: this type knows the
/// <em>shape</em> of the settings, never where they live — locating and writing the file is the app's
/// job (see <c>TigerMarkView.Settings.SettingsStore</c>).
/// </summary>
/// <remarks>
/// Property initialisers are the single source of truth for first-run defaults, so a missing file, a
/// partial file, and a fresh install all produce identical behaviour.
/// </remarks>
public sealed class ApplicationSettings
{
    /// <summary>
    /// Identifies the persisted shape. Not a migration framework — just a marker so a future version
    /// can recognise what it is looking at instead of guessing from which properties are present.
    /// </summary>
    public const int CurrentVersion = 1;

    public int Version { get; set; } = CurrentVersion;

    [JsonConverter(typeof(TolerantEnumConverter<MarkdownTheme>))]
    public MarkdownTheme Theme { get; set; } = MarkdownTheme.Light;

    [JsonConverter(typeof(TolerantReloadModeConverter))]
    public ReloadMode ReloadMode { get; set; } = ReloadMode.Confirm;

    [JsonConverter(typeof(TolerantEnumConverter<EditorKind>))]
    public EditorKind EditorType { get; set; } = EditorKind.SystemDefault;

    public string? CustomEditorPath { get; set; }

    public string? CustomEditorArguments { get; set; }

    public List<string> RecentFiles { get; set; } = [];

    /// <summary>
    /// Chrome the reader can hide from the View menu. All three default to visible, and a settings
    /// file written before any of them existed simply omits it — which lands on exactly that default,
    /// so the persisted shape stays additive and no version bump is involved.
    /// </summary>
    /// <remarks>
    /// The menu bar and the toolbar are the two <em>command</em> surfaces, and are constrained by
    /// <see cref="CommandSurfaces"/>: a file claiming both are hidden is repaired by
    /// <see cref="Normalized"/> rather than restoring a window with no way to reach a command.
    /// </remarks>
    public bool MenuBarVisible { get; set; } = true;

    /// <inheritdoc cref="MenuBarVisible"/>
    public bool ToolbarVisible { get; set; } = true;

    /// <inheritdoc cref="MenuBarVisible"/>
    public bool StatusBarVisible { get; set; } = true;

    /// <summary>
    /// Whether the toolbar carries the <c>☰</c> menu button. Visible by default — it is the toolbar
    /// this application has always shown — and hideable only while the menu bar is there to take over,
    /// which is <see cref="CommandSurfaces"/>' second invariant rather than a check made here.
    /// </summary>
    /// <remarks>
    /// Additive like the flags above: a settings file written before it existed omits it and lands on
    /// <see langword="true"/>, so nothing a reader saved changes shape. Deliberately <em>not</em>
    /// carrying <c>TolerantBooleanConverter</c>, unlike the optional toolbar buttons: that converter
    /// reads an unusable value as <see langword="false"/>, which for this flag means hiding a surface
    /// nobody asked to hide, and falling back to the whole default file is the better recovery.
    /// </remarks>
    public bool ToolbarMenuVisible { get; set; } = true;

    /// <summary>
    /// The toolbar's two optional commands — the Open Recent dropdown and Export to PDF — each off
    /// unless the reader turns it on under <c>View &gt; Toolbar Buttons</c>. Off is the default because
    /// both are already on the menu bar and in the hamburger mirror, so the compact toolbar this
    /// application has always shown stays what a reader gets.
    /// </summary>
    /// <remarks>
    /// <para>
    /// Two more additive properties: a settings file written before they existed omits them and
    /// lands on <see langword="false"/> — no <see cref="Version"/> bump and no migration, exactly as
    /// the chrome flags, the PDF preferences and the rendering options were added. They carry no
    /// invariant of their own; see <see cref="ToolbarActions"/> for why not.
    /// </para>
    /// Unknown members are ignored by <see cref="System.Text.Json"/>, which keeps settings files
    /// forward-compatible with properties this version does not recognise.
    /// </remarks>
    [JsonConverter(typeof(TolerantBooleanConverter))]
    public bool ToolbarOpenRecentVisible { get; set; }

    /// <inheritdoc cref="ToolbarOpenRecentVisible"/>
    [JsonConverter(typeof(TolerantBooleanConverter))]
    public bool ToolbarExportPdfVisible { get; set; }

    /// <summary>
    /// How PDF export lays a document out. Global preferences rather than per-export choices, so
    /// File &gt; Export to PDF stays one dialog — the save dialog — and never becomes a page-setup
    /// form the reader has to answer every time.
    /// </summary>
    /// <remarks>
    /// Four more additive properties, so a settings file written before they existed simply omits
    /// them and each lands on the default below. That is why this needed no version bump and no
    /// migration: <see cref="Version"/> still identifies the same shape, additively grown, exactly as
    /// it was for <see cref="ToolbarVisible"/>.
    /// </remarks>
    [JsonConverter(typeof(TolerantPaperSizeConverter))]
    public PdfPaperSize PdfPaperSize { get; set; } = PdfPaperSize.A4;

    /// <inheritdoc cref="PdfPaperSize"/>
    [JsonConverter(typeof(TolerantEnumConverter<PdfOrientation>))]
    public PdfOrientation PdfOrientation { get; set; } = PdfOrientation.Portrait;

    /// <inheritdoc cref="PdfPaperSize"/>
    [JsonConverter(typeof(TolerantMarginPresetConverter))]
    public PdfMarginPreset PdfMargins { get; set; } = PdfMarginPreset.Normal;

    /// <inheritdoc cref="PdfPaperSize"/>
    public bool PdfPageNumbers { get; set; }

    /// <summary>
    /// The two optional rendering behaviours, both off unless the reader turns them on under
    /// <c>View &gt; Rendering</c>. Off is the default because they change how a document <em>looks</em>
    /// rather than what TigerMarkView can do with it: a reader who has never heard of either gets the
    /// rendering this application has always produced.
    /// </summary>
    /// <remarks>
    /// Two more additive properties, so a settings file written before they existed simply omits them
    /// and lands on <see langword="false"/> — no <see cref="Version"/> bump, no migration, exactly as
    /// the PDF preferences and the chrome flags were added.
    /// </remarks>
    [JsonConverter(typeof(TolerantBooleanConverter))]
    public bool EmojiShortcodes { get; set; }

    /// <inheritdoc cref="EmojiShortcodes"/>
    [JsonConverter(typeof(TolerantBooleanConverter))]
    public bool SyntaxHighlighting { get; set; }

    public WindowPlacement Window { get; set; } = new();

    public static ApplicationSettings CreateDefault() => new();

    /// <summary>
    /// Rebuilds the in-memory <see cref="EditorConfiguration"/>. A Custom entry with no executable
    /// path (a hand-broken or half-written file) degrades to System Default rather than restoring a
    /// configuration that can only fail at launch time.
    /// </summary>
    public EditorConfiguration ToEditorConfiguration() => EditorType switch
    {
        EditorKind.VisualStudioCode => EditorConfiguration.VisualStudioCode(),
        EditorKind.Notepad3 => EditorConfiguration.Notepad3(),
        EditorKind.Custom when !string.IsNullOrWhiteSpace(CustomEditorPath) =>
            EditorConfiguration.Custom(CustomEditorPath, CustomEditorArguments),
        _ => EditorConfiguration.SystemDefault(),
    };

    /// <summary>
    /// Records the user's editor choice. Selecting a preset deliberately leaves the remembered Custom
    /// executable/arguments untouched, so switching to VS Code and back does not discard what the user
    /// configured.
    /// </summary>
    public void ApplyEditorConfiguration(EditorConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);

        EditorType = configuration.Type;

        if (configuration.Type == EditorKind.Custom)
        {
            CustomEditorPath = configuration.ExecutablePath;
            CustomEditorArguments = configuration.ArgumentsTemplate;
        }
    }

    /// <summary>
    /// Turns the four remembered preferences into the physical page geometry the renderer and the
    /// exporter both work in. The one place the translation happens, so the menu, the rendered
    /// document, and the print engine cannot end up describing three different pages.
    /// </summary>
    public PdfPageSetup ToPdfPageSetup() =>
        PdfPageSetup.For(PdfPaperSize, PdfOrientation, PdfMargins, PdfPageNumbers);

    /// <summary>
    /// The remembered rendering options, as the value the renderer works in. The one translation point,
    /// for the same reason <see cref="ToPdfPageSetup"/> is: the menu, the document on screen, and the
    /// HTML an export prints must not be able to describe three different things.
    /// </summary>
    public MarkdownRenderingOptions ToRenderingOptions() => new(EmojiShortcodes, SyntaxHighlighting);

    /// <summary>
    /// The remembered command-surface visibility, as a value that cannot express the illegal
    /// combination. <see cref="Normalized"/> has already repaired the fields, so this is a read of
    /// what was loaded rather than a second chance to fix it.
    /// </summary>
    public CommandSurfaces ToCommandSurfaces() =>
        CommandSurfaces.Of(MenuBarVisible, ToolbarVisible, ToolbarMenuVisible);

    /// <summary>Records the reader's current chrome choice, which is legal by construction.</summary>
    public void ApplyCommandSurfaces(CommandSurfaces surfaces)
    {
        MenuBarVisible = surfaces.MenuBarVisible;
        ToolbarVisible = surfaces.ToolbarVisible;
        ToolbarMenuVisible = surfaces.ToolbarMenuButtonVisible;
    }

    /// <summary>
    /// The toolbar's optional commands, as the value the window lays itself out from. The one
    /// translation point, for the same reason <see cref="ToPdfPageSetup"/> and
    /// <see cref="ToCommandSurfaces"/> are: the View menu's check marks, the buttons on screen, and
    /// the separator between them must not be able to describe three different toolbars.
    /// </summary>
    public ToolbarActions ToToolbarActions() =>
        new(ToolbarOpenRecentVisible, ToolbarExportPdfVisible);

    /// <inheritdoc cref="ToToolbarActions"/>
    public void ApplyToolbarActions(ToolbarActions actions)
    {
        ToolbarOpenRecentVisible = actions.OpenRecent;
        ToolbarExportPdfVisible = actions.ExportPdf;
    }

    public void AddRecentFile(string path) =>
        RecentFiles = RecentFilesList.Add(RecentFiles, path);

    /// <summary>
    /// Repairs anything a partial, hand-edited, or older settings file could contain, so callers never
    /// have to null-check or range-check what they loaded. Unknown enum values are already handled
    /// during deserialization by <see cref="TolerantEnumConverter{TEnum}"/>.
    /// </summary>
    public ApplicationSettings Normalized()
    {
        Version = CurrentVersion;
        RecentFiles = RecentFilesList.Normalize(RecentFiles);

        // A file claiming both command surfaces are hidden — or a compact window with no menu button
        // to reach the menu from — would otherwise produce a window with no way to reach a command at
        // all. CommandSurfaces decides what each of those recovers to.
        ApplyCommandSurfaces(ToCommandSurfaces());

        if (Window is null)
        {
            Window = new WindowPlacement();
        }

        Window.Normalized();

        return this;
    }
}
