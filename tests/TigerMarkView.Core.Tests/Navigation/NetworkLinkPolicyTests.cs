using TigerMarkView.Core.Navigation;

namespace TigerMarkView.Core.Tests.Navigation;

/// <summary>
/// A link in a document must not make the viewer open a file on another host — which signs in to that
/// host over SMB with the reader's Windows credentials — however the document spells it, while a share
/// the reader opened deliberately stays openable. Each case goes through the same two steps the viewer
/// takes: the WebView's resolved URL becomes a path (<see cref="MarkdownLinkResolver"/>), then the
/// policy decides by origin.
/// </summary>
public class NetworkLinkPolicyTests
{
    private const string LocalDocument = @"C:\Docs\guide.md";

    public static TheoryData<string> NetworkHrefs => new()
    {
        @"\\server\share\notes.md",
        @"\\server\share\folder with spaces\notes.md",
        "//server/share/notes.md",
        "file://server/share/notes.md",
        "file:////server/share/notes.md",
        "file://///server/share/notes.md",
        "file://127.0.0.1/c$/notes.md",
        "file://localhost/c$/notes.md",
        "file://[::1]/share/notes.md",
        "file://server.example.com@SSL/DavWWWRoot/notes.md",
        @"\\server@SSL@443\DavWWWRoot\notes.md",
        "%5C%5Cserver%5Cshare%5Cnotes.md",
        "file:%5C%5Cserver%5Cshare%5Cnotes.md",
        @"\\?\UNC\server\share\notes.md",
        @"\\.\UNC\server\share\notes.md",
        @"\\?\C:\Docs\notes.md",
        "/\\server/share/notes.markdown",
    };

    [Theory]
    [MemberData(nameof(NetworkHrefs))]
    public void ALinkToAShareIsNeverFollowed(string href)
    {
        if (!MarkdownLinkResolver.TryResolveLocalMarkdown(LocalDocument, href, out var resolved))
        {
            // Not even a Markdown target the viewer would open: nothing to follow.
            return;
        }

        Assert.True(NetworkLinkPolicy.Refuses(resolved, documentOnScreen: true), resolved);
    }

    /// <summary>
    /// The resolved-URL route — what the WebView actually reports after applying the page's base — in
    /// spellings System.Uri and Windows read differently.
    /// </summary>
    [Theory]
    [InlineData("file://server/share/notes.md")]
    [InlineData("file:////server/share/notes.md")]
    [InlineData("file:///%5C%5Cserver%5Cshare%5Cnotes.md")]
    [InlineData("file://127.0.0.1/share/notes.md")]
    [InlineData("file://localhost/C:/Docs/notes.md")]
    public void AResolvedNetworkUrlIsNeverFollowed(string url)
    {
        if (!MarkdownLinkResolver.TryResolveLocalMarkdown(new Uri(url), out var resolved))
        {
            return;
        }

        Assert.True(NetworkLinkPolicy.Refuses(resolved, documentOnScreen: true), resolved);
    }

    /// <summary>
    /// A relative link inside a document that was itself opened from a share still leads to the share:
    /// the document chose that target, not the reader.
    /// </summary>
    [Theory]
    [InlineData("next.md")]
    [InlineData("../other/next.md")]
    [InlineData("/root.md")]
    public void ARelativeLinkInADocumentOnAShareIsNotFollowed(string href)
    {
        Assert.True(MarkdownLinkResolver.TryResolveLocalMarkdown(@"\\server\share\docs\guide.md", href, out var resolved));

        Assert.True(NetworkLinkPolicy.Refuses(resolved, documentOnScreen: true));
    }

    [Theory]
    [InlineData("other.md")]
    [InlineData("sub/other.md")]
    [InlineData("../other.md")]
    [InlineData(@"C:\Elsewhere\other.md")]
    [InlineData("file:///C:/Elsewhere/other.md")]
    [InlineData("my%20notes.md")]
    [InlineData("a%23b.md")]
    public void ALinkToALocalDocumentIsFollowed(string href)
    {
        Assert.True(MarkdownLinkResolver.TryResolveLocalMarkdown(LocalDocument, href, out var resolved));

        Assert.False(NetworkLinkPolicy.Refuses(resolved, documentOnScreen: true), resolved);
    }

    /// <summary>
    /// With no document on screen (the empty or error page links to nothing) a request can only be a
    /// file the reader dropped, so a share stays openable that way.
    /// </summary>
    [Fact]
    public void AShareDroppedOnTheEmptyViewerStaysOpenable()
    {
        Assert.False(NetworkLinkPolicy.Refuses(@"\\server\share\notes.md", documentOnScreen: false));
    }

    /// <summary>
    /// The refusal does not depend on recognising the request as one of the page's own links: a target
    /// the page's hrefs do not match — however the browser arrived at it — is refused all the same while
    /// a document is on screen.
    /// </summary>
    [Fact]
    public void AShareRequestThePageDoesNotVisiblyLinkToIsStillRefused()
    {
        const string html = "<p><a href=\"other.md\">Other</a></p>";
        const string share = @"\\server\share\notes.md";

        Assert.Equal(DocumentOpenOrigin.ExplicitOpen, ViewerRequestOrigin.Classify(share, LocalDocument, html));
        Assert.True(NetworkLinkPolicy.Refuses(share, documentOnScreen: true));
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("relative.md")]
    [InlineData("C:relative.md")]
    [InlineData(@"\\server\share\notes.md")]
    [InlineData(@"\\?\UNC\server\share\notes.md")]
    [InlineData(@"\\.\pipe\notes.md")]
    [InlineData("Q\0:\\x.md")]
    public void OnlyAFullyQualifiedLocalDrivePathIsLocalStorage(string path)
    {
        if (path is "relative.md" or "C:relative.md")
        {
            // Path.GetFullPath anchors these to a local working directory and drive, which is local.
            Assert.True(NetworkLinkPolicy.IsOnLocalStorage(path));
            return;
        }

        Assert.False(NetworkLinkPolicy.IsOnLocalStorage(path));
    }

    [Fact]
    public void ADriveLetterThatIsNotMappedToLocalStorageIsNotLocal()
    {
        var unused = Enumerable.Range('D', 'Z' - 'D' + 1).Select(letter => (char)letter)
            .FirstOrDefault(letter => !Directory.Exists($@"{letter}:\"));
        if (unused == default)
        {
            return;
        }

        Assert.False(NetworkLinkPolicy.IsOnLocalStorage($@"{unused}:\notes.md"));
        Assert.True(NetworkLinkPolicy.Refuses($@"{unused}:\notes.md", documentOnScreen: true));
    }

    [Fact]
    public void AnExistingLocalFileIsLocalStorage()
    {
        var path = Path.Combine(Path.GetTempPath(), $"tmv-{Guid.NewGuid():N}.md");
        File.WriteAllText(path, "# local");
        try
        {
            Assert.True(NetworkLinkPolicy.IsOnLocalStorage(path));
            Assert.False(NetworkLinkPolicy.Refuses(path, documentOnScreen: true));
        }
        finally
        {
            File.Delete(path);
        }
    }
}
