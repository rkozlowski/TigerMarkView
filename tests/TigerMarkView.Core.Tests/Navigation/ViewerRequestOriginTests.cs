using TigerMarkView.Core.Navigation;
using TigerMarkView.Core.Rendering;
using TigerMarkView.Core.Settings;

namespace TigerMarkView.Core.Tests.Navigation;

/// <summary>
/// A file dropped on the document area and a link followed out of the page reach the viewer as the
/// same WebView request. Only the second may stay out of Open Recent, so the page on screen decides:
/// a link can only come from its own <c>href</c>s. The pages here are rendered by the real pipeline,
/// sanitizer and <c>&lt;base href&gt;</c> included.
/// </summary>
public class ViewerRequestOriginTests
{
    private const string Displayed = @"C:\docs\guide\index.md";

    private static string Render(string markdown) =>
        MarkdownDocumentLoader.RenderHtmlDocument(Displayed, markdown, MarkdownTheme.Light);

    [Theory]
    [InlineData("[next](next.md)", @"C:\docs\guide\next.md")]
    [InlineData("[up](../overview.markdown)", @"C:\docs\overview.markdown")]
    [InlineData("[spaced](<my notes.md>)", @"C:\docs\guide\my notes.md")]
    [InlineData("[unicode](<zażółć gęślą.md>)", @"C:\docs\guide\zażółć gęślą.md")]
    [InlineData("<a href=\"deep/raw.md\">raw html</a>", @"C:\docs\guide\deep\raw.md")]
    public void AFileThePageLinksToIsAFollowedLink(string markdown, string requested)
    {
        Assert.Equal(
            DocumentOpenOrigin.Navigation,
            ViewerRequestOrigin.Classify(requested, Displayed, Render(markdown)));
    }

    [Fact]
    public void LinkTargetsCompareWithoutRegardToCase()
    {
        Assert.Equal(
            DocumentOpenOrigin.Navigation,
            ViewerRequestOrigin.Classify(@"c:\DOCS\guide\NEXT.md", Displayed, Render("[next](next.md)")));
    }

    [Theory]
    [InlineData(@"C:\Users\reader\Downloads\dropped.md")]
    [InlineData(@"C:\docs\guide\sibling-not-linked.md")]
    [InlineData(@"D:\Wiki pages\Zażółć gęślą jaźń.markdown")]
    public void AFileThePageDoesNotLinkToWasBroughtByTheReader(string requested)
    {
        var page = Render("# Guide\n\n[next](next.md) and [web](https://example.com/next.md)");

        var origin = ViewerRequestOrigin.Classify(requested, Displayed, page);

        Assert.Equal(DocumentOpenOrigin.ExplicitOpen, origin);
        Assert.True(RecentFilesPolicy.ShouldRemember(origin));
    }

    [Fact]
    public void EveryRequestWhileNoDocumentIsShownIsTheReadersOwn()
    {
        Assert.Equal(
            DocumentOpenOrigin.ExplicitOpen,
            ViewerRequestOrigin.Classify(@"C:\docs\guide\next.md", null, null));
    }

    [Fact]
    public void TheBaseElementIsNotALink()
    {
        var targets = ViewerRequestOrigin.LocalMarkdownLinkTargets(Displayed, Render("No links here."));

        Assert.Empty(targets);
    }

    [Fact]
    public void RemoteAndNonMarkdownLinksAreNotLocalMarkdownTargets()
    {
        var page = Render("[a](https://example.com/a.md) [b](notes.txt) [c](#top) [d](mailto:x@example.com)");

        Assert.Empty(ViewerRequestOrigin.LocalMarkdownLinkTargets(Displayed, page));
    }
}
