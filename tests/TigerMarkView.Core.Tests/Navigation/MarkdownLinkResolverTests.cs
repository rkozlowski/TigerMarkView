using TigerMarkView.Core.Navigation;

namespace TigerMarkView.Core.Tests.Navigation;

/// <summary>
/// The rule that decides whether a clicked link is "another local Markdown document TigerMarkView
/// should render" or something the viewer must keep its hands off. Both bugs this covers were real:
/// a relative <c>.md</c> link showed raw source, and the fix must not turn the viewer into a browser.
/// </summary>
public class MarkdownLinkResolverTests
{
    private const string CurrentDocument = @"C:\docs\guide\index.md";

    [Theory]
    [InlineData("foo.md", @"C:\docs\guide\foo.md")]
    [InlineData("nested/foo.md", @"C:\docs\guide\nested\foo.md")]
    [InlineData("docs/deep/foo.md", @"C:\docs\guide\docs\deep\foo.md")]
    [InlineData("../foo.md", @"C:\docs\foo.md")]
    [InlineData("../../foo.md", @"C:\foo.md")]
    [InlineData("../sibling/foo.md", @"C:\docs\sibling\foo.md")]
    [InlineData("./foo.md", @"C:\docs\guide\foo.md")]
    [InlineData("foo.markdown", @"C:\docs\guide\foo.markdown")]
    [InlineData("FOO.MD", @"C:\docs\guide\FOO.MD")]
    public void RelativeMarkdownLinksResolveAgainstTheCurrentDocumentsFolder(string href, string expected)
    {
        Assert.True(MarkdownLinkResolver.TryResolveLocalMarkdown(CurrentDocument, href, out var resolved));
        Assert.Equal(expected, resolved);
    }

    [Fact]
    public void PercentEncodedSpacesResolveToARealPath()
    {
        Assert.True(MarkdownLinkResolver.TryResolveLocalMarkdown(
            CurrentDocument, "my%20notes.md", out var resolved));

        Assert.Equal(@"C:\docs\guide\my notes.md", resolved);
    }

    [Theory]
    [InlineData(@"C:\other\thing.md")]
    [InlineData(@"C:\other\thing.markdown")]
    public void AbsoluteLocalMarkdownPathsAreAccepted(string href)
    {
        Assert.True(MarkdownLinkResolver.TryResolveLocalMarkdown(CurrentDocument, href, out var resolved));
        Assert.Equal(href, resolved);
    }

    [Fact]
    public void AbsoluteFileUrisAreAccepted()
    {
        Assert.True(MarkdownLinkResolver.TryResolveLocalMarkdown(
            CurrentDocument, "file:///C:/other/thing.md", out var resolved));

        Assert.Equal(@"C:\other\thing.md", resolved);
    }

    /// <summary>
    /// An in-document link must stay in the document. It never reaches the resolver as a navigation in
    /// the running viewer either (the shell's anchor script handles it), but the rule is stated here
    /// so it cannot regress into being treated as a document to open.
    /// </summary>
    [Theory]
    [InlineData("#tables")]
    [InlineData("#a-heading-with-dashes")]
    [InlineData("#")]
    public void FragmentOnlyLinksAreNotDocumentNavigation(string href)
    {
        Assert.False(MarkdownLinkResolver.TryResolveLocalMarkdown(CurrentDocument, href, out _));
    }

    [Theory]
    [InlineData("https://example.com/readme.md")]
    [InlineData("http://example.com/docs/guide.md")]
    [InlineData("https://example.com")]
    [InlineData("mailto:someone@example.com")]
    [InlineData("ftp://example.com/readme.md")]
    public void RemoteLinksAreNeverLocalMarkdownHoweverTheyEnd(string href)
    {
        Assert.False(MarkdownLinkResolver.TryResolveLocalMarkdown(CurrentDocument, href, out _));
    }

    /// <summary>
    /// Images and other resources share the relative-path shape with Markdown links; only the
    /// extension separates them, so nothing else may be mistaken for a document to render.
    /// </summary>
    [Theory]
    [InlineData("images/diagram.png")]
    [InlineData("notes.txt")]
    [InlineData("archive.md.zip")]
    [InlineData("report.pdf")]
    [InlineData("script.mdx")]
    [InlineData("folder/")]
    public void NonMarkdownTargetsAreLeftAlone(string href)
    {
        Assert.False(MarkdownLinkResolver.TryResolveLocalMarkdown(CurrentDocument, href, out _));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void AnAbsentHrefIsNotNavigation(string? href)
    {
        Assert.False(MarkdownLinkResolver.TryResolveLocalMarkdown(CurrentDocument, href, out _));
    }

    [Theory]
    [InlineData(@"C:\docs\a.md", true)]
    [InlineData(@"C:\docs\a.markdown", true)]
    [InlineData(@"C:\docs\A.MD", true)]
    [InlineData("relative.md", true)]
    [InlineData(@"C:\docs\a.png", false)]
    [InlineData(@"C:\docs\a", false)]
    [InlineData("", false)]
    [InlineData(null, false)]
    public void IsMarkdownPathMatchesTheExtensionsEveryEntryPointUses(string? path, bool expected)
    {
        Assert.Equal(expected, MarkdownLinkResolver.IsMarkdownPath(path));
    }

    [Fact]
    public void TheAbsoluteUriOverloadAgreesWithTheHrefOverload()
    {
        Assert.True(MarkdownLinkResolver.TryResolveLocalMarkdown(
            new Uri("file:///C:/docs/guide/foo.md"), out var resolved));
        Assert.Equal(@"C:\docs\guide\foo.md", resolved);

        Assert.False(MarkdownLinkResolver.TryResolveLocalMarkdown(new Uri("https://example.com/x.md"), out _));
        Assert.False(MarkdownLinkResolver.TryResolveLocalMarkdown(new Uri("about:blank"), out _));
        Assert.False(MarkdownLinkResolver.TryResolveLocalMarkdown(null, out _));
    }

    /// <summary>
    /// The generated preview carries a per-navigation <c>?t=</c> cache-buster and may carry a
    /// fragment; neither may confuse the extension check for a real document link.
    /// </summary>
    [Fact]
    public void AQueryStringAndFragmentDoNotHideTheRealExtension()
    {
        Assert.True(MarkdownLinkResolver.TryResolveLocalMarkdown(
            new Uri("file:///C:/docs/foo.md?t=12345#section"), out var resolved));

        Assert.Equal(@"C:\docs\foo.md", resolved);
    }
}
