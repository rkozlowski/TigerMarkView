using ItTiger.TigerCli.Commands;
using TigerMarkView.Core.Exporting;

namespace TigerMarkView.Cli;

/// <summary>
/// The whole command surface of <c>tiger-mark</c>: one Markdown file in, one PDF out, plus the page
/// setup the desktop application offers under <c>Tools &gt; PDF Export</c>.
/// </summary>
/// <remarks>
/// <para>
/// There are no subcommands. Converting to PDF is the only thing the tool does, and a mandatory verb
/// naming the only operation would be noise the reader has to type every time. TigerCli's default
/// command is what makes <c>tiger-mark notes.md</c> the whole invocation.
/// </para>
/// <para>
/// Every property is <see cref="TigerCliPromptable.No"/>: <c>tiger-mark</c> is invoked by scripts far
/// more often than by hand, so a missing input file must fail rather than open a picker. The app is
/// non-interactive anyway (see <see cref="TigerMarkApp"/>) — this states the intent per value, so it
/// survives an interaction-mode change.
/// </para>
/// <para>
/// The paper, orientation and margin choices are the GUI's enums from <c>TigerMarkView.Core</c>, bound
/// by name (case-insensitively) by TigerCli. They are named here and translated in one place,
/// <see cref="PageSetup"/> — the CLI states no dimension and no margin value of its own.
/// </para>
/// </remarks>
internal sealed class ConvertSettings : TigerCliSettings
{
    [TigerCliArgument(
        0,
        Name = "input",
        Description = "The Markdown file to convert.",
        Promptable = TigerCliPromptable.No)]
    public string Input { get; set; } = string.Empty;

    [TigerCliOption(
        "-o|--output",
        ValueName = "file",
        Description = "Write the PDF to this file. The default is the Markdown file's own name with a .pdf extension, in its own folder.",
        Promptable = TigerCliPromptable.No)]
    public string? Output { get; set; }

    [TigerCliOption(
        "--paper",
        ValueName = "size",
        Description = "Paper size: A3, A4, A5, Letter or Legal.",
        Promptable = TigerCliPromptable.No)]
    public PdfPaperSize Paper { get; set; } = PdfPaperSize.A4;

    [TigerCliOption(
        "--orientation",
        ValueName = "mode",
        Description = "Page orientation: Portrait or Landscape.",
        Promptable = TigerCliPromptable.No)]
    public PdfOrientation Orientation { get; set; } = PdfOrientation.Portrait;

    [TigerCliOption(
        "--margins",
        ValueName = "preset",
        Description = "Margin preset: Narrow, Normal or Wide.",
        Promptable = TigerCliPromptable.No)]
    public PdfMarginPreset Margins { get; set; } = PdfMarginPreset.Normal;

    [TigerCliOption(
        "--page-numbers",
        Description = "Print a page number at the foot of every page. Off unless asked for.",
        Promptable = TigerCliPromptable.No)]
    public bool PageNumbers { get; set; }

    /// <summary>
    /// The four choices as physical page geometry, through the same <see cref="PdfPageSetup.For"/> the
    /// GUI's preferences go through — so the same answers produce the same page, to the millimetre,
    /// whichever front end was asked. Nothing here knows a paper's dimensions or a preset's margins.
    /// </summary>
    /// <remarks>
    /// The defaults above are <see cref="PdfPageSetup.Default"/> spelled out as choices: A4 portrait,
    /// Normal margins, unnumbered. They are stated explicitly because both <see cref="PdfPaperSize"/>
    /// and <see cref="PdfMarginPreset"/> have a different first member, and a plain
    /// <c>tiger-mark notes.md</c> must keep producing the PDF it always did.
    /// </remarks>
    public PdfPageSetup PageSetup => PdfPageSetup.For(Paper, Orientation, Margins, PageNumbers);
}
