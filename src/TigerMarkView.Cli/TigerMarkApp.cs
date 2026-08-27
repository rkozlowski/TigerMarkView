using ItTiger.TigerCli.Commands;
using ItTiger.TigerCli.Enums;

namespace TigerMarkView.Cli;

/// <summary>
/// Builds the <c>tiger-mark</c> application. One factory, called by <see cref="Program"/> and by the
/// tests, so what the tests exercise is the command line readers actually type.
/// </summary>
/// <remarks>
/// <para>
/// <c>tiger-mark</c> is a plain TigerCli application: the framework owns parsing, help, version,
/// error rendering, exit-code mapping and interaction policy, and this project owns nothing but its own
/// domain. There is no hand-written parser, no usage text, and no interception of framework options —
/// where the old command line collided with a TigerCli convention, the command line changed.
/// </para>
/// <para>
/// <strong>Non-interactive on purpose.</strong> Nothing here prompts: a missing input file must fail
/// rather than open a picker, because the tool is invoked by scripts far more often than by hand.
/// Declaring the mode says that once, for every environment, so a script needs no flag to be told what
/// it already is; <c>--non-interactive</c> is still accepted and costs nothing when passed anyway. The
/// mode also decides how the progress activity presents itself — a dialog with a console, nothing at
/// all without one — but not what it does: the same operation body runs either way, so there is one
/// execution path here and no headless branch of our own.
/// </para>
/// <para>
/// <strong>Ctrl+C reaches the conversion.</strong> TigerCli registers cooperative process/system
/// cancellation (Ctrl-C / Ctrl-Break on Windows) in both interaction modes and combines it with the
/// token <c>RunAsync</c> was given into one handler-visible
/// <see cref="TigerCliSettings.CancellationToken"/>. <see cref="ConvertCommand"/> passes that token to
/// its activity explicitly — an activity never picks it up implicitly — so an interrupted export
/// unwinds through <see cref="PdfConversion"/> and ends as <see cref="TigerMarkExitCode.Cancelled"/>,
/// with no half-written PDF and no abrupt <c>STATUS_CONTROL_C_EXIT</c>. A second signal escalates to
/// default termination, which is TigerCli's, not ours. Nothing here owns a cancellation mechanism of
/// its own, and nothing should: the framework's token is the whole implementation.
/// </para>
/// </remarks>
internal static class TigerMarkApp
{
    public static TigerCliApp Create() =>
        TigerCliApp.CreateBuilder()
            // Name, description, version and copyright off the built assembly, which is where
            // Version.props put them. No version string exists in this project and there must
            // never be one; the application name comes from the assembly, which is `tiger-mark`.
            .UseAssemblyMetadata<ConvertCommand>()
            .SetInteractionMode(TigerCliInteractionMode.NonInteractive)
            // The published numeric contract, resolved by TigerCli and documented by --help-errors.
            // Everything TigerCli classifies as Execution or Unexpected — including every
            // TigerCliCommandException PdfConversion raises — falls to the error baseline.
            .UseExitCodes(TigerMarkExitCode.Success, TigerMarkExitCode.ConversionFailed)
            .ExitCategory(TigerCliExitCategory.Usage, TigerMarkExitCode.UsageError)
            .ExitCategory(TigerCliExitCategory.Validation, TigerMarkExitCode.UsageError)
            .ExitCategory(TigerCliExitCategory.Cancelled, TigerMarkExitCode.Cancelled)
            .SetDefaultCommand<ConvertCommand>()
            .Build();
}
