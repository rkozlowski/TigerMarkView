using System.Runtime.ExceptionServices;
using ItTiger.TigerCli.Commands;
using ItTiger.TigerCli.Enums;
using ItTiger.TigerCli.Exceptions;
using ItTiger.TigerCli.Tui;
using ItTiger.TigerCli.Tui.Activity;

namespace TigerMarkView.Cli;

/// <summary>
/// <c>tiger-mark</c>'s only command: the default one, so a bare <c>tiger-mark notes.md</c> runs it.
/// </summary>
/// <remarks>
/// It is orchestration and nothing else — the conversion is <see cref="PdfConversion"/>'s, and every
/// decision about how a document renders or how HTML becomes a PDF belongs to
/// <c>TigerMarkView.Core</c> and <c>TigerMarkView.Pdf</c>. What lives here is the translation between
/// the two worlds: a page setup out of the bound settings, an activity around the long half, and an
/// outcome turned into a <see cref="TigerMarkExitCode"/>.
/// </remarks>
internal sealed class ConvertCommand : TigerCliAsyncCommandHandler<ConvertSettings, TigerMarkExitCode>
{
    /// <summary>
    /// The shape of the progress dialog the activity would show. The conversion runs inside a real
    /// activity rather than a bare <c>await</c> because that is TigerCli's one execution path for work
    /// that takes a while: the framework picks the presentation — a dialog when it has a console, no UI
    /// at all when it does not — and the same operation body runs either way.
    /// </summary>
    /// <remarks>
    /// The dialog is never actually drawn today: the application declares itself non-interactive, so the
    /// activity always takes the headless path (see <see cref="TigerMarkApp"/>) and the text is here
    /// because a spec needs a row, not as output. Its <c>NonInteractiveMessage</c> is deliberately left
    /// unset, and that is why the spec is built explicitly instead of using the convenience overload that
    /// takes a plain message: that overload prints the message to <em>stdout</em> when headless, and a
    /// successful conversion must stay exactly one <c>Created:</c> line for whatever is reading it.
    /// </remarks>
    private static ActivityDialogSpec ProgressDialog() =>
        ActivityDialogSpec.Create()
            .AddColumn()
            .AddRow(null, row => row.Cell(0).Text("Creating the PDF..."))
            .Build();

    public override async Task<TigerMarkExitCode> ExecuteAsync(ConvertSettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);

        // The one clock reading of the whole run, taken before anything is read or written. Every date
        // a header prints and the suffix of any fallback file come from it, so the PDF is dated once
        // and cannot contradict itself — a run that crosses midnight still prints one date on every
        // page, and the file it leaves behind is named for the same moment.
        var request = new PdfConversionRequest(
            settings.Input,
            settings.Output,
            settings.PageSetup,
            settings.TimestampedFallback,
            DateTimeOffset.Now);

        var activity = await TigerTui.RunActivityAsync(
            ProgressDialog(),
            (_, cancellationToken) => PdfConversion.RunAsync(request, cancellationToken),
            // The run token, threaded in explicitly — an activity does not pick it up implicitly, and
            // without it a headless run is stoppable by nothing at all. TigerCliSettings.CancellationToken
            // combines the token TigerCliApp.RunAsync was given with TigerCli's own Ctrl-C/Ctrl-Break
            // handling, so this one argument is what makes an interrupted conversion end as exit 3
            // instead of Windows tearing the process down. See TigerMarkApp.
            ct: settings.CancellationToken);

        if (activity.Outcome == ActivityOutcome.Completed && activity.Value is { } conversion)
        {
            // The one line a script reads, and it always names a PDF that exists. Nothing else is ever
            // written to stdout — including the notice below, because a fallback still produced a file
            // and a script parsing stdout must not have to tell the two cases apart by reading prose.
            Console.Out.WriteLine($"Created: {conversion.OutputPath}");

            if (conversion.UnreplacedTarget is not { } target)
            {
                return TigerMarkExitCode.Success;
            }

            Console.Error.WriteLine(
                $"Could not replace {target} — it may be open in another application. " +
                $"The PDF was kept as {conversion.OutputPath}.");

            return TigerMarkExitCode.TargetNotReplaced;
        }

        if (WasInterrupted(activity.Outcome, activity.Exception))
        {
            return TigerMarkExitCode.Cancelled;
        }

        // Rethrown rather than reformatted: PdfConversion already phrased the failure, and TigerCli
        // renders it and maps the exit code. The dispatch info keeps the original stack, which matters
        // for the one kind of exception nobody planned for.
        if (activity.Exception is { } failure)
        {
            ExceptionDispatchInfo.Capture(failure).Throw();
        }

        throw new TigerCliCommandException($"The PDF could not be created ({activity.Outcome}).");
    }

    /// <summary>
    /// Whether the run stopped because it was asked to. A stop reaches us two ways: as a stop outcome
    /// when the activity itself observed it, or — because an interrupted operation reports as a failure
    /// like any other — as a failure carrying an <see cref="OperationCanceledException"/>. Both are the
    /// reader's doing and neither is an error, so both become
    /// <see cref="TigerMarkExitCode.Cancelled"/> rather than a conversion failure.
    /// </summary>
    private static bool WasInterrupted(ActivityOutcome outcome, Exception? exception) =>
        outcome is ActivityOutcome.Cancelled or ActivityOutcome.Aborted or ActivityOutcome.SystemCancelled
        || exception is OperationCanceledException;
}
