using Microsoft.Web.WebView2.Core;
using TigerMarkView.Core.Exporting;
using TigerMarkView.Pdf;

namespace TigerMarkView.Cli.Tests;

public class WebViewResourceBoundaryTests
{
    [Fact]
    public void AnExistingLocalImageIsStillAllowedAfterFilesystemChecks()
    {
        var path = Path.GetTempFileName();
        try
        {
            Assert.True(WebViewResourceBoundary.IsAllowed(new Uri(path).AbsoluteUri, CoreWebView2WebResourceContext.Image));
            Assert.True(WebViewResourceBoundary.IsAllowed(new Uri(path).AbsoluteUri, CoreWebView2WebResourceContext.Document));
            Assert.False(WebViewResourceBoundary.IsAllowed(new Uri(path).AbsoluteUri, CoreWebView2WebResourceContext.Script));
        }
        finally { File.Delete(path); }
    }

    [Theory]
    [InlineData("file:///%255c%255cserver%255cshare%255cx.png")]
    [InlineData("file:///%5c%5cserver%5cshare%5cx.png")]
    [InlineData("file://localhost/share/x.png")]
    [InlineData("file://[::1]/share/x.png")]
    [InlineData("file://2130706433/share/x.png")]
    [InlineData("file://0x7f000001/share/x.png")]
    [InlineData("file:////server/share/x.png")]
    [InlineData("file:///%5c%5c?%5cUNC%5cserver%5cshare%5cx.png")]
    [InlineData("\\\\?\\UNC\\server\\share\\x.png")]
    [InlineData("//server/share/x.png")]
    [InlineData("/\\server/share/x.png")]
    [InlineData("relative/image.png")]
    public void UntrustedNetworkAndNonAbsoluteReferencesAreRefused(string uri)
    {
        Assert.False(WebViewResourceBoundary.IsAllowed(uri, CoreWebView2WebResourceContext.Image));
        Assert.False(WebViewResourceBoundary.IsAllowed(uri, CoreWebView2WebResourceContext.Document));
    }

    [Theory]
    [InlineData("http://localhost/a.png")]
    [InlineData("http://127.0.0.1/a.png")]
    [InlineData("http://[::1]/a.png")]
    [InlineData("https://example.com/a.png")]
    [InlineData("data:image/svg+xml,%3Csvg/%3E")]
    public void ImagePermissionDoesNotAuthorizeOtherResourceContexts(string uri)
    {
        foreach (var context in Enum.GetValues<CoreWebView2WebResourceContext>())
        {
            Assert.Equal(context == CoreWebView2WebResourceContext.Image, WebViewResourceBoundary.IsAllowed(uri, context));
        }
    }

    [Theory]
    [InlineData("https://example.com/a.png", false)]
    [InlineData("http://localhost/a.png", false)]
    [InlineData("data:image/svg+xml,%3Csvg/%3E", true)]
    public void TurningRemoteImagesOffRefusesWebImagesOnly(string uri, bool allowed)
    {
        Assert.Equal(allowed, WebViewResourceBoundary.IsAllowed(uri, CoreWebView2WebResourceContext.Image, remoteImages: false));
        Assert.True(WebViewResourceBoundary.IsAllowed(uri, CoreWebView2WebResourceContext.Image, remoteImages: true));
    }

    [Fact]
    public void ALocalImageStillLoadsWithRemoteImagesOff()
    {
        var path = Path.GetTempFileName();
        try
        {
            Assert.True(WebViewResourceBoundary.IsAllowed(new Uri(path).AbsoluteUri, CoreWebView2WebResourceContext.Image, remoteImages: false));
        }
        finally { File.Delete(path); }
    }

    /// <summary>
    /// The boundary asks the live setting at the request, so a window follows a value another window
    /// changed after it started; it asks only where the answer decides something.
    /// </summary>
    [Fact]
    public void TheLiveSettingIsAskedForEachWebImageAndDecidesIt()
    {
        var asked = 0;
        var remoteImages = true;
        bool Current() { asked++; return remoteImages; }

        Assert.True(WebViewResourceBoundary.IsAllowed("https://example.com/a.png", CoreWebView2WebResourceContext.Image, Current));
        remoteImages = false;
        Assert.False(WebViewResourceBoundary.IsAllowed("https://example.com/a.png", CoreWebView2WebResourceContext.Image, Current));
        remoteImages = true;
        Assert.True(WebViewResourceBoundary.IsAllowed("https://example.com/a.png", CoreWebView2WebResourceContext.Image, Current));
        Assert.Equal(3, asked);
    }

    /// <summary>
    /// GUI export carries the question rather than an answer, so a change made in any window while an
    /// export runs governs its next request; <c>tiger-mark</c>'s request carries none and always may.
    /// </summary>
    [Fact]
    public void AnExportRequestFollowsTheSettingWhileItRuns()
    {
        var remoteImages = true;
        var gui = new PdfExportRequest("<html></html>", "out.pdf", RemoteImages: () => remoteImages);
        var cli = new PdfExportRequest("<html></html>", "out.pdf");

        Assert.True(WebViewResourceBoundary.IsAllowed("https://example.com/a.png", CoreWebView2WebResourceContext.Image, gui.RemoteImages));
        remoteImages = false;
        Assert.False(WebViewResourceBoundary.IsAllowed("https://example.com/a.png", CoreWebView2WebResourceContext.Image, gui.RemoteImages));
        Assert.True(WebViewResourceBoundary.IsAllowed("https://example.com/a.png", CoreWebView2WebResourceContext.Image, cli.RemoteImages));
    }

    [Theory]
    [InlineData("file://server/share/x.png")]
    [InlineData("file:///%5c%5cserver%5cshare%5cx.png")]
    [InlineData("//server/share/x.png")]
    public void ANetworkImageStaysRefusedWhateverTheLiveSettingSays(string uri) =>
        Assert.False(WebViewResourceBoundary.IsAllowed(uri, CoreWebView2WebResourceContext.Image, () => true));

    [Fact]
    public void TheLiveSettingIsNotAskedForWhatItCannotChange()
    {
        var path = Path.GetTempFileName();
        try
        {
            bool Refuse() => throw new InvalidOperationException("asked");

            Assert.True(WebViewResourceBoundary.IsAllowed(new Uri(path).AbsoluteUri, CoreWebView2WebResourceContext.Image, Refuse));
            Assert.True(WebViewResourceBoundary.IsAllowed(new Uri(path).AbsoluteUri, CoreWebView2WebResourceContext.Document, Refuse));
            Assert.True(WebViewResourceBoundary.IsAllowed("data:image/svg+xml,%3Csvg/%3E", CoreWebView2WebResourceContext.Image, Refuse));
            Assert.False(WebViewResourceBoundary.IsAllowed("https://example.com/a.js", CoreWebView2WebResourceContext.Script, Refuse));
        }
        finally { File.Delete(path); }
    }

    /// <summary>
    /// The image client offers no credentials to anyone: not the reader's Windows sign-in to the image
    /// host, not explicit credentials, and not the Windows sign-in to an authenticating proxy.
    /// </summary>
    [Fact]
    public void ImageRequestsCarryNoAmbientOrProxyCredentials()
    {
        var use = WebViewResourceBoundary.CredentialUse;

        Assert.False(use.UseDefaultCredentials);
        Assert.False(use.DestinationCredentials);
        Assert.False(use.ProxyCredentials);
    }
}