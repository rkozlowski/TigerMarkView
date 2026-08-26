using TigerMarkView.Core.Navigation;
using TigerMarkView.Core.Rendering;

namespace TigerMarkView.Core.Tests.Navigation;

/// <summary>
/// The page-to-host channel that carries Alt+Left/Alt+Right out of the WebView. The script builds its
/// message names by concatenation, so the important test is that the two halves still agree.
/// </summary>
public class ViewerMessagesTests
{
    [Fact]
    public void TheScriptPostsExactlyTheCommandsTheHostParses()
    {
        var html = MarkdownRenderer.ToHtmlDocument("# Hello", "Doc");

        Assert.Contains("'tigermarkview:navigate:' + command", html);
        Assert.Equal("tigermarkview:navigate:back", ViewerMessages.BackCommand);
        Assert.Equal("tigermarkview:navigate:forward", ViewerMessages.ForwardCommand);

        // ...and the two commands the script can build are the two the host understands.
        Assert.Contains("'back'", html);
        Assert.Contains("'forward'", html);
    }

    /// <summary>
    /// F1 travels the same channel and needs the same guarantee: the script's literal and the host's
    /// constant are written in two files and have to stay the same string.
    /// </summary>
    [Fact]
    public void TheScriptPostsExactlyTheHelpCommandTheHostRecognises()
    {
        var html = MarkdownRenderer.ToHtmlDocument("# Hello", "Doc");

        Assert.Contains($"postMessage('{ViewerMessages.HelpCommand}')", html);
        Assert.Equal("tigermarkview:help", ViewerMessages.HelpCommand);
        Assert.True(ViewerMessages.IsHelpCommand(ViewerMessages.HelpCommand));
    }

    /// <summary>
    /// The two surfaces with no document behind them carry the help shortcut too. Without it F1 is
    /// inert for a reader who has clicked into an empty or failed viewer — the WebView keeps its own
    /// keyboard input, so the host-side handler never sees the key.
    /// </summary>
    [Fact]
    public void TheEmptyAndErrorViewersCarryTheHelpShortcutToo()
    {
        Assert.Contains(ViewerMessages.HelpCommand, MarkdownRenderer.ToEmptyDocument());
        Assert.Contains(ViewerMessages.HelpCommand, MarkdownRenderer.ToErrorDocument("x.md", "boom"));
    }

    /// <summary>
    /// Ctrl+P travels the same channel, and its script has a second job the other two do not: cancelling
    /// the key so Chromium does not open Edge's own print preview — a print path that knows nothing of
    /// the paper the document was laid out for.
    /// </summary>
    [Fact]
    public void TheScriptPostsExactlyThePrintCommandTheHostRecognises()
    {
        var html = MarkdownRenderer.ToHtmlDocument("# Hello", "Doc");

        Assert.Contains($"postMessage('{ViewerMessages.PrintCommand}')", html);
        Assert.Equal("tigermarkview:print", ViewerMessages.PrintCommand);
        Assert.True(ViewerMessages.IsPrintCommand(ViewerMessages.PrintCommand));
    }

    /// <summary>
    /// Nothing here is printable, which is precisely why the script has to be here: without it Ctrl+P
    /// in an empty or failed viewer opens the browser's print preview over it.
    /// </summary>
    [Fact]
    public void TheEmptyAndErrorViewersCarryThePrintShortcutToo()
    {
        Assert.Contains(ViewerMessages.PrintCommand, MarkdownRenderer.ToEmptyDocument());
        Assert.Contains(ViewerMessages.PrintCommand, MarkdownRenderer.ToErrorDocument("x.md", "boom"));
    }

    /// <summary>The suppression itself, which is what keeps Edge's print UI out of the viewer.</summary>
    [Fact]
    public void ThePrintScriptCancelsTheKeyBeforeItReachesTheBrowser()
    {
        var html = MarkdownRenderer.ToHtmlDocument("# Hello", "Doc");
        var script = html[html.IndexOf("event.key !== 'p'", StringComparison.Ordinal)..];

        // preventDefault comes before the host check, so the browser is stopped even in a page with no
        // host attached to post the message to.
        Assert.True(
            script.IndexOf("event.preventDefault();", StringComparison.Ordinal) <
            script.IndexOf("window.chrome", StringComparison.Ordinal));
    }

    /// <summary>The three vocabularies must not answer for each other.</summary>
    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("print")]
    [InlineData("tigermarkview:help")]
    [InlineData("tigermarkview:navigate:back")]
    public void AnythingElseIsNotAPrintCommand(string? message)
    {
        Assert.False(ViewerMessages.IsPrintCommand(message));
        Assert.Null(ViewerMessages.ParseNavigationCommand(ViewerMessages.PrintCommand));
        Assert.False(ViewerMessages.IsHelpCommand(ViewerMessages.PrintCommand));
    }

    [Theory]
    [InlineData("\"tigermarkview:print\"")]
    [InlineData("  tigermarkview:print  ")]
    public void ThePrintCommandIsRecognisedQuotedOrPadded(string message)
    {
        Assert.True(ViewerMessages.IsPrintCommand(message));
    }

    [Theory]
    [InlineData("\"tigermarkview:help\"")]
    [InlineData("  tigermarkview:help  ")]
    public void TheHelpCommandIsRecognisedQuotedOrPadded(string message)
    {
        Assert.True(ViewerMessages.IsHelpCommand(message));
    }

    /// <summary>
    /// The two vocabularies must not answer for each other: a navigation command is not a help request,
    /// and Help is not a navigation the viewer should record.
    /// </summary>
    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("help")]
    [InlineData("tigermarkview:navigate:back")]
    public void AnythingElseIsNotAHelpCommand(string? message)
    {
        Assert.False(ViewerMessages.IsHelpCommand(message));
    }

    [Fact]
    public void TheHelpCommandIsNotParsedAsANavigation()
    {
        Assert.Null(ViewerMessages.ParseNavigationCommand(ViewerMessages.HelpCommand));
    }

    [Theory]
    [InlineData("tigermarkview:navigate:back", ViewerNavigationCommand.Back)]
    [InlineData("tigermarkview:navigate:forward", ViewerNavigationCommand.Forward)]
    [InlineData("  tigermarkview:navigate:back  ", ViewerNavigationCommand.Back)]
    public void KnownCommandsAreRecognised(string message, ViewerNavigationCommand expected)
    {
        Assert.Equal(expected, ViewerMessages.ParseNavigationCommand(message));
    }

    /// <summary>
    /// A WebView host may hand a posted string over JSON-encoded depending on which accessor it uses,
    /// so the quoted form has to be understood too.
    /// </summary>
    [Fact]
    public void AJsonEncodedCommandIsRecognised()
    {
        Assert.Equal(
            ViewerNavigationCommand.Back,
            ViewerMessages.ParseNavigationCommand("\"tigermarkview:navigate:back\""));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("back")]
    [InlineData("tigermarkview:navigate:")]
    [InlineData("tigermarkview:navigate:sideways")]
    [InlineData("some other page message")]
    public void AnythingElseIsIgnoredRatherThanGuessedAt(string? message)
    {
        Assert.Null(ViewerMessages.ParseNavigationCommand(message));
    }
}
