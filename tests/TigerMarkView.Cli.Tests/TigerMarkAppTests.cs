using ItTiger.TigerCli.Testing;

namespace TigerMarkView.Cli.Tests;

/// <summary>
/// The application boundary: what a reader types, and what the process says and returns. These run the
/// real app <see cref="TigerMarkApp.Create"/> builds — the one <c>Program</c> runs — through TigerCli's
/// own test host, so they exercise the real parsing, help, error rendering and exit-code policy.
/// </summary>
/// <remarks>
/// <para>
/// What is <em>not</em> here is a parser test suite. TigerCli's grammar is TigerCli's, tested there;
/// what these assert is this application's contract: the options it declares, the exit code each kind
/// of outcome returns, and that a failure never lands on stdout.
/// </para>
/// <para>
/// Every case stops before a browser starts — a successful conversion needs the WebView2 runtime and
/// writes a real PDF, and belongs in end-to-end validation of the built command.
/// </para>
/// </remarks>
public class TigerMarkAppTests : IDisposable
{
    private readonly string _dir;

    public TigerMarkAppTests()
    {
        _dir = Path.Combine(Path.GetTempPath(), "TigerMarkViewCliTests_" + Guid.NewGuid());
        Directory.CreateDirectory(_dir);
    }

    public void Dispose() => Directory.Delete(_dir, recursive: true);

    private static Task<TigerCliAppRunResult> RunAsync(params string[] args) =>
        RunAsync(CancellationToken.None, args);

    private static Task<TigerCliAppRunResult> RunAsync(CancellationToken cancellationToken, params string[] args) =>
        TigerCliAppTestHost.For(TigerMarkApp.Create())
            .WithArgs(args)
            // Wide enough that a declared option's own line is not wrapped away from it.
            .WithViewport(160, 60)
            .RunAsync(cancellationToken);

    private string WriteDocument(string name = "notes.md")
    {
        var path = Path.Combine(_dir, name);
        File.WriteAllText(path, "# Hello");
        return path;
    }

    private static void AssertFailed(TigerCliAppRunResult run, TigerMarkExitCode expected)
    {
        Assert.Equal((int)expected, run.ExitCode);
        Assert.Empty(run.StdOut);
        Assert.False(string.IsNullOrWhiteSpace(run.StdErr));
    }

    [Fact]
    public async Task HelpDocumentsEveryOptionTheCommandDeclares()
    {
        var run = await RunAsync("--help");

        Assert.Equal((int)TigerMarkExitCode.Success, run.ExitCode);
        Assert.Empty(run.StdErr);

        Assert.Contains("<input>", run.StdOut, StringComparison.Ordinal);
        Assert.Contains("--output", run.StdOut, StringComparison.Ordinal);
        Assert.Contains("--paper", run.StdOut, StringComparison.Ordinal);
        Assert.Contains("--orientation", run.StdOut, StringComparison.Ordinal);
        Assert.Contains("--margins", run.StdOut, StringComparison.Ordinal);
        Assert.Contains("--page-numbers", run.StdOut, StringComparison.Ordinal);

        // The framework's own options are part of what this application offers, too.
        Assert.Contains("--non-interactive", run.StdOut, StringComparison.Ordinal);
        Assert.Contains("--help-errors", run.StdOut, StringComparison.Ordinal);
    }

    /// <summary>Help says what the tool is, in its own words rather than the desktop application's.</summary>
    [Fact]
    public async Task HelpDescribesTheCommandRatherThanTheDesktopApplication()
    {
        var run = await RunAsync("--help");

        Assert.Contains("PDF", run.StdOut, StringComparison.Ordinal);
        Assert.DoesNotContain("viewer", run.StdOut, StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// One version, from Version.props through assembly metadata — asserted as "a version is
    /// reported", never against a literal, which would be the second place to edit on every release.
    /// </summary>
    [Fact]
    public async Task VersionReportsTheBuiltVersion()
    {
        var run = await RunAsync("--version");

        Assert.Equal((int)TigerMarkExitCode.Success, run.ExitCode);
        Assert.Matches(@"\d+\.\d+", run.StdOut);
    }

    /// <summary>The exit-code contract is documented by the framework from one enum declaration.</summary>
    [Fact]
    public async Task HelpErrorsDocumentsTheExitCodes()
    {
        var run = await RunAsync("--help-errors");

        Assert.Equal((int)TigerMarkExitCode.Success, run.ExitCode);

        foreach (var code in Enum.GetValues<TigerMarkExitCode>())
        {
            Assert.Contains(((int)code).ToString(), run.StdOut, StringComparison.Ordinal);
            Assert.Contains(code.ToString(), run.StdOut, StringComparison.Ordinal);
        }
    }

    [Fact]
    public async Task AMissingInputFileIsAConversionFailureNotAUsageError()
    {
        AssertFailed(await RunAsync(Path.Combine(_dir, "does-not-exist.md")), TigerMarkExitCode.ConversionFailed);
    }

    [Fact]
    public async Task AFolderGivenAsTheInputIsRefused()
    {
        AssertFailed(await RunAsync(_dir), TigerMarkExitCode.ConversionFailed);
    }

    [Fact]
    public async Task WritingThePdfOverTheInputFileIsRefused()
    {
        var input = WriteDocument();

        AssertFailed(await RunAsync(input, "--output", input), TigerMarkExitCode.ConversionFailed);
    }

    [Fact]
    public async Task AnOutputPathNoFileCouldHaveIsRefused()
    {
        AssertFailed(await RunAsync(WriteDocument(), "-o", "C:\\bad\0path\\out.pdf"), TigerMarkExitCode.ConversionFailed);
    }

    [Fact]
    public async Task AMissingOutputFolderIsRefused()
    {
        var run = await RunAsync(WriteDocument(), "-o", Path.Combine(_dir, "no-such-folder", "out.pdf"));

        AssertFailed(run, TigerMarkExitCode.ConversionFailed);
        Assert.Contains("folder", run.StdErr, StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// A malformed command line is its own exit code: only this one is worth re-reading the usage text
    /// over. Every case is refused by TigerCli's grammar before the command runs, which is why none of
    /// them needs the named document to exist.
    /// </summary>
    [Fact]
    public async Task NoInputFileIsAUsageError()
    {
        AssertFailed(await RunAsync(), TigerMarkExitCode.UsageError);
    }

    /// <inheritdoc cref="NoInputFileIsAUsageError"/>
    [Theory]
    [InlineData("notes.md", "--colour-me-surprised")]
    [InlineData("notes.md", "more.md")]
    [InlineData("notes.md", "--output")]
    [InlineData("notes.md", "-o")]
    [InlineData("notes.md", "--paper", "A6")]
    [InlineData("notes.md", "--orientation", "sideways")]
    [InlineData("notes.md", "--margins", "generous")]
    public async Task AMalformedCommandLineIsAUsageError(params string[] arguments)
    {
        AssertFailed(await RunAsync(arguments), TigerMarkExitCode.UsageError);
    }

    /// <summary>
    /// A page option that parses gets as far as the document, which is how a boundary test can tell
    /// "the option was accepted" from "the option was rejected" without needing a browser: a missing
    /// input file is a conversion failure, and an unusable option value never reaches it.
    /// </summary>
    [Theory]
    [InlineData("--paper", "A5")]
    [InlineData("--paper", "letter")]
    [InlineData("--paper", "LEGAL")]
    [InlineData("--orientation", "landscape")]
    [InlineData("--margins", "narrow")]
    [InlineData("--margins", "Wide")]
    public async Task APageOptionIsAcceptedByNameAndIsNotCaseSensitive(string option, string value)
    {
        AssertFailed(
            await RunAsync(Path.Combine(_dir, "does-not-exist.md"), option, value),
            TigerMarkExitCode.ConversionFailed);
    }

    [Fact]
    public async Task PageNumbersIsAFlagAndTheWholeCombinationIsAccepted()
    {
        var run = await RunAsync(
            Path.Combine(_dir, "does-not-exist.md"),
            "--paper", "Letter",
            "--orientation", "landscape",
            "--margins", "wide",
            "--page-numbers");

        AssertFailed(run, TigerMarkExitCode.ConversionFailed);
    }

    /// <summary>
    /// Both spellings of the output option, and the `=` form TigerCli also accepts. All three are
    /// refused for the same reason — the document does not exist — which is the point: the option itself
    /// bound in every spelling.
    /// </summary>
    [Theory]
    [InlineData("-o")]
    [InlineData("--output")]
    public async Task TheOutputOptionBindsInBothSpellings(string option)
    {
        AssertFailed(
            await RunAsync(Path.Combine(_dir, "does-not-exist.md"), option, Path.Combine(_dir, "out.pdf")),
            TigerMarkExitCode.ConversionFailed);
    }

    [Fact]
    public async Task TheOutputOptionBindsWithAnEqualsSign()
    {
        AssertFailed(
            await RunAsync(Path.Combine(_dir, "does-not-exist.md"), $"--output={Path.Combine(_dir, "out.pdf")}"),
            TigerMarkExitCode.ConversionFailed);
    }

    /// <summary>
    /// An interrupted run is its own exit code, and neither an error nor a conversion failure. The
    /// framework's run token is what carries an interruption — a Ctrl-C in a terminal and the token
    /// <c>RunAsync</c> was given arrive through the one <c>TigerCliSettings.CancellationToken</c> — so
    /// running with a token that is already cancelled exercises the same path a real Ctrl-C takes,
    /// without needing a console signal.
    /// </summary>
    /// <remarks>
    /// The document is a real one, so nothing else could have failed the run; what it must not do is
    /// report the interruption as <see cref="TigerMarkExitCode.ConversionFailed"/>, or write anything
    /// to stdout, or leave a PDF behind.
    /// </remarks>
    [Fact]
    public async Task AnInterruptedRunIsCancelledRatherThanFailed()
    {
        var input = WriteDocument();
        using var cancellation = new CancellationTokenSource();
        await cancellation.CancelAsync();

        var run = await RunAsync(cancellation.Token, input);

        Assert.Equal((int)TigerMarkExitCode.Cancelled, run.ExitCode);
        Assert.Empty(run.StdOut);
        Assert.False(File.Exists(Path.ChangeExtension(input, ".pdf")));
    }

    /// <summary>
    /// `--non-interactive` is what a script would reach for and must be accepted, even though the app
    /// already declares that mode and so needs nothing from it.
    /// </summary>
    [Fact]
    public async Task NonInteractiveIsAcceptedAndChangesNothing()
    {
        var withFlag = await RunAsync(Path.Combine(_dir, "does-not-exist.md"), "--non-interactive");
        var without = await RunAsync(Path.Combine(_dir, "does-not-exist.md"));

        Assert.Equal(without.ExitCode, withFlag.ExitCode);
        Assert.Equal(without.StdErr, withFlag.StdErr);
    }
}
