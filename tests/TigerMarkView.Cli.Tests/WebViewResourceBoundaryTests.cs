using Microsoft.Web.WebView2.Core;
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
}
