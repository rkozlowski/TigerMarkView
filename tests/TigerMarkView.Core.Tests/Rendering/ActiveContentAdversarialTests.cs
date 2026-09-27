using AngleSharp.Dom;
using AngleSharp.Html.Parser;
using TigerMarkView.Core.Rendering;

namespace TigerMarkView.Core.Tests.Rendering;

public class ActiveContentAdversarialTests
{
    [Theory]
    [InlineData("a")]
    [InlineData("area")]
    public void AHyperlinkCannotAuthorizeItsOwnAutomaticNetworkFileRequest(string tag)
    {
        var body = Render($"<{tag} href=\"file://server/share/x.png\" style=\"background-image:url(file://server/share/x.png)\">link</{tag}>");
        var link = body.QuerySelector(tag)!;
        Assert.Equal("file://server/share/x.png", link.GetAttribute("href"));
        Assert.DoesNotContain("server", link.GetAttribute("style") ?? "");
    }

    [Theory]
    [InlineData("url(file://server/share/paint.svg#x)")]
    [InlineData("url(https://example.com/paint.svg#x)")]
    [InlineData(@"u\72l(//server/share/x)")]
    [InlineData("url(data:image/svg+xml,abc)")]
    public void SvgPaintCannotReferenceAnotherResource(string fill)
    {
        var path = Render($"<svg><path fill=\"{fill}\" d=\"M0 0h20v20z\" /></svg>").QuerySelector("path")!;
        Assert.Null(path.GetAttribute("fill"));
        Assert.NotNull(path.GetAttribute("d"));
    }

    [Fact]
    public void DataImagesAreAllowedOnlyInTheSourceAttribute()
    {
        var image = Render("<img src=\"data:image/png;base64,AAAA\" href=\"data:image/png;base64,AAAA\" style=\"background:url(data:image/png;base64,AAAA)\">").QuerySelector("img")!;
        Assert.Equal("data:image/png;base64,AAAA", image.GetAttribute("src"));
        Assert.Null(image.GetAttribute("href"));
        Assert.DoesNotContain("data:", image.GetAttribute("style") ?? "");
    }

    private static IElement Render(string markdown) => new HtmlParser().ParseDocument(
        MarkdownRenderer.ToHtmlDocument(markdown, "Review")).Body!;

    [Theory]
    [InlineData("currentColor")]
    [InlineData("none")]
    [InlineData("#123abc")]
    [InlineData("rgb(1, 2, 3)")]
    public void SvgSolidPaintRemainsAvailable(string fill)
    {
        Assert.Equal(fill, Render($"<svg><path fill=\"{fill}\" d=\"M0 0\" /></svg>").QuerySelector("path")!.GetAttribute("fill"));
    }

    [Theory]
    [InlineData("file://[::1]/share/x.png")]
    [InlineData("file://localhost/share/x.png")]
    [InlineData("file://2130706433/share/x.png")]
    [InlineData("file://0177.0.0.1/share/x.png")]
    [InlineData("file://0x7f000001/share/x.png")]
    [InlineData("f&#9;ile://server/share/x.png")]
    [InlineData("file:&#10;//server/share/x.png")]
    [InlineData("%2f%5cserver/share/x.png")]
    [InlineData("file:///%5c%5c?%5cUNC%5cserver%5cshare%5cx.png")]
    public void AlternateShareReferencesCannotSurviveAsImageSources(string source)
    {
        Assert.Null(Render($"<img src=\"{source}\">").QuerySelector("img")!.GetAttribute("src"));
    }

    [Theory]
    [InlineData("background-image: u\\72l('file://server/share/x.png')")]
    [InlineData("background-image: image-set('file://server/share/x.png' 1x)")]
    [InlineData("background-image: -webkit-image-set(url(file://server/share/x.png) 1x)")]
    [InlineData("background: url(file://server/share/x.png) var(--missing)")]
    [InlineData("width: e/**/xpression(alert(1)); behavior:url(file://server/share/x.htc)")]
    public void CssEscapesAndShorthandsDoNotHideNetworkFileRequests(string style)
    {
        Assert.DoesNotContain("server", Render($"<div style=\"{style}\">x</div>").InnerHtml);
    }
}
