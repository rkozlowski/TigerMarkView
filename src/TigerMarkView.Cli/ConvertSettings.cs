using ItTiger.TigerCli.Commands;
using TigerMarkView.Core.Exporting;

namespace TigerMarkView.Cli;

/// <summary>
/// The whole command surface of <c>tiger-mark</c>: one Markdown file in, one PDF out, plus the page
/// setup the desktop application offers under <c>Tools &gt; PDF Export</c>, the running heads and feet
/// only the command line offers, and how to behave when the target file will not budge.
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
        Description = "Print a page number at the foot of every page. Shorthand for --footer-center \"{Page}\". Off unless asked for.",
        Promptable = TigerCliPromptable.No)]
    public bool PageNumbers { get; set; }

    [TigerCliOption(
        "--header-left",
        ValueName = "template",
        Description = TemplateHelp,
        Promptable = TigerCliPromptable.No)]
    public string? HeaderLeft { get; set; }

    [TigerCliOption(
        "--header-center",
        ValueName = "template",
        Description = "The same, printed at the top centre of every page.",
        Promptable = TigerCliPromptable.No)]
    public string? HeaderCenter { get; set; }

    [TigerCliOption(
        "--header-right",
        ValueName = "template",
        Description = "The same, printed at the top right of every page.",
        Promptable = TigerCliPromptable.No)]
    public string? HeaderRight { get; set; }

    [TigerCliOption(
        "--footer-left",
        ValueName = "template",
        Description = "The same, printed at the foot left of every page.",
        Promptable = TigerCliPromptable.No)]
    public string? FooterLeft { get; set; }

    [TigerCliOption(
        "--footer-center",
        ValueName = "template",
        Description = "The same, printed at the foot centre of every page.",
        Promptable = TigerCliPromptable.No)]
    public string? FooterCenter { get; set; }

    [TigerCliOption(
        "--footer-right",
        ValueName = "template",
        Description = "The same, printed at the foot right of every page.",
        Promptable = TigerCliPromptable.No)]
    public string? FooterRight { get; set; }

    [TigerCliOption(
        "--timestamped-fallback",
        Description =
            "Write the PDF to a timestamped file beside the output first, then replace the output with it. "
            + "If the output cannot be replaced — it is open in a reader, say — the timestamped PDF is kept "
            + "and the command exits 4.",
        Promptable = TigerCliPromptable.No)]
    public bool TimestampedFallback { get; set; }

    /// <summary>
    /// The six slots, with <c>--page-numbers</c> resolved into the one it is shorthand for.
    /// </summary>
    /// <remarks>
    /// An explicit <c>--footer-center</c> wins, because it is the more specific instruction: a reader
    /// who has written their own centre footer has already said what belongs there, and silently
    /// replacing it with a bare page number would be the flag overruling the option. Documents are
    /// resolved later — see <see cref="PdfConversion"/> — because the title cannot be known until the
    /// file has been read.
    /// </remarks>
    public PdfHeaderFooter HeaderFooter => new(
        HeaderLeft,
        HeaderCenter,
        HeaderRight,
        FooterLeft,
        PageNumbers && string.IsNullOrWhiteSpace(FooterCenter) ? HeaderFooterTemplate.PageNumber : FooterCenter,
        FooterRight);

    /// <summary>
    /// The page choices as physical page geometry, through the same <see cref="PdfPageSetup.For"/> the
    /// GUI's preferences go through — so the same answers produce the same page, to the millimetre,
    /// whichever front end was asked. Nothing here knows a paper's dimensions or a preset's margins.
    /// </summary>
    /// <remarks>
    /// The defaults above are <see cref="PdfPageSetup.Default"/> spelled out as choices: A4 portrait,
    /// Normal margins, nothing in the margins. They are stated explicitly because both
    /// <see cref="PdfPaperSize"/> and <see cref="PdfMarginPreset"/> have a different first member, and a
    /// plain <c>tiger-mark notes.md</c> must keep producing the PDF it always did.
    /// </remarks>
    public PdfPageSetup PageSetup => PdfPageSetup.For(Paper, Orientation, Margins, HeaderFooter);

    /// <summary>
    /// Refuses a malformed header or footer template before anything is read, rendered or written.
    /// </summary>
    /// <remarks>
    /// A template with an unknown placeholder or a stray brace is a mistyped command line, not a failed
    /// conversion, so it belongs here: TigerCli reports the message and resolves it through the
    /// validation exit mapping, which <see cref="TigerMarkApp"/> points at
    /// <see cref="TigerMarkExitCode.UsageError"/>. The rule itself is Core's — this only asks.
    /// </remarks>
    public override TigerCliValidationResult Validate() =>
        HeaderFooter.Validate() is { } error
            ? TigerCliValidationResult.Error(error)
            : TigerCliValidationResult.Success();

    /// <summary>
    /// The template vocabulary, stated once. The other five slots say "the same, printed at ..." rather
    /// than repeating it: six copies of the same paragraph is a help page nobody reads to the end of.
    /// </summary>
    private const string TemplateHelp =
        "A running head printed at the top left of every page. Templates are text plus {Page}, "
        + "{TotalPages}, {Title}, {FileName}, {FileNameWithExt}, {FilePath}, {Date}, {Time} and "
        + "{DateTime}; each date placeholder takes an optional :format, and {{ and }} are literal braces.";
}
