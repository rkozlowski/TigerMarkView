using TigerMarkView.Core.Rendering;

namespace TigerMarkView.Core.Tests.Rendering;

/// <summary>
/// The host-side layer's decision table: pictures may come from anywhere, the page itself only from a
/// local file, and nothing else a page can request may reach the network.
/// </summary>
public class WebResourcePolicyTests
{
    public static TheoryData<string, WebResourceKind> AllowedRequests => new()
    {
        { "https://img.shields.io/badge/build-passing-green.svg", WebResourceKind.Image },
        { "http://example.com/photo.png?size=large", WebResourceKind.Image },
        { "file:///C:/Docs/images/diagram.png", WebResourceKind.Image },
        { "data:image/png;base64,iVBORw0KGgo=", WebResourceKind.Image },
        { "file:///C:/Users/Reader/AppData/Local/Temp/TigerMarkView/preview.html?t=1", WebResourceKind.Document },
    };

    [Theory]
    [MemberData(nameof(AllowedRequests))]
    public void PassiveResourcesAreAllowed(string uri, WebResourceKind kind)
    {
        Assert.True(WebResourcePolicy.Allows(new Uri(uri), kind));
    }

    public static TheoryData<string, WebResourceKind> RefusedRequests => new()
    {
        // The channels content could use to send out what it read.
        { "https://attacker.example/collect?d=secret", WebResourceKind.Other },
        { "http://127.0.0.1:47631/exfil/fetch", WebResourceKind.Other },
        { "wss://attacker.example/socket", WebResourceKind.Other },

        // A remote page, whether top-level or framed.
        { "https://attacker.example/frame.html", WebResourceKind.Document },
        { "http://127.0.0.1:47631/exfil/iframe", WebResourceKind.Document },

        // Local files as anything but the page or a picture.
        { "file:///C:/Users/Reader/Documents/secret.txt", WebResourceKind.Other },

        // Schemes that are not a source of pictures.
        { "ftp://attacker.example/a.png", WebResourceKind.Image },
        { "javascript:alert(1)", WebResourceKind.Image },
    };

    [Theory]
    [MemberData(nameof(RefusedRequests))]
    public void EverythingElseIsRefused(string uri, WebResourceKind kind)
    {
        Assert.False(WebResourcePolicy.Allows(new Uri(uri), kind));
    }

    /// <summary>
    /// Every spelling of a file on another host — which Windows would fetch over SMB with the reader's
    /// credentials — is refused, even as an image and even where System.Uri itself does not call it UNC.
    /// </summary>
    [Theory]
    [InlineData("file://server/share/image.png")]
    [InlineData("file:////server/share/image.png")]
    [InlineData("file://///server/share/image.png")]
    [InlineData("file:///server/share/image.png")]
    [InlineData("file:///%5C%5Cserver%5Cshare%5Cimage.png")]
    [InlineData("file:///%5C%5C%3F%5CUNC%5Cserver%5Cshare%5Cimage.png")]
    [InlineData("file:///%5C%5C%3F%5CC:%5Cimage.png")]
    [InlineData("file://127.0.0.1/c$/image.png")]
    [InlineData("file://[::1]/c$/image.png")]
    [InlineData("file://localhost/C:/Docs/image.png")]
    [InlineData("file://server.example.com/share/image.png")]
    public void ANetworkFileIsRefusedAsAnImageAndAsAPage(string uri)
    {
        var target = new Uri(uri);

        Assert.False(WebResourcePolicy.IsLocalFile(target));
        Assert.False(WebResourcePolicy.Allows(target, WebResourceKind.Image));
        Assert.False(WebResourcePolicy.Allows(target, WebResourceKind.Document));
    }

    [Theory]
    [InlineData("file:///C:/Docs/images/diagram.png")]
    [InlineData("file:///c:/Docs/diagram.png")]
    [InlineData("file:///D:/Shared%20Drive/diagram.png")]
    [InlineData("file:///C|/Docs/diagram.png")]
    [InlineData("file:///C:/Docs/../Other/diagram.png")]
    public void ALocalDriveFileIsAllowedAsAnImage(string uri)
    {
        var target = new Uri(uri);

        Assert.True(WebResourcePolicy.IsLocalFile(target));
        Assert.True(WebResourcePolicy.Allows(target, WebResourceKind.Image));
    }

    [Fact]
    public void ARelativeAddressIsRefusedBecauseTheEngineOnlyEverAsksAboutResolvedOnes()
    {
        Assert.False(WebResourcePolicy.Allows(new Uri("images/diagram.png", UriKind.Relative), WebResourceKind.Image));
    }

    /// <summary>
    /// Load Remote Images off refuses web images and nothing else changes: local and data images still
    /// load, and every other rule stays exactly as strict.
    /// </summary>
    [Theory]
    [InlineData("https://img.shields.io/badge/build-passing-green.svg", false)]
    [InlineData("http://example.com/photo.png?size=large", false)]
    [InlineData("HTTPS://EXAMPLE.COM/PHOTO.PNG", false)]
    [InlineData("http://127.0.0.1:8080/local-service.png", false)]
    [InlineData("file:///C:/Docs/images/diagram.png", true)]
    [InlineData("data:image/png;base64,iVBORw0KGgo=", true)]
    public void WithRemoteImagesOffOnlyWebImagesAreRefused(string uri, bool allowed)
    {
        Assert.Equal(allowed, WebResourcePolicy.Allows(new Uri(uri), WebResourceKind.Image, remoteImages: false));
        Assert.True(WebResourcePolicy.Allows(new Uri(uri), WebResourceKind.Image, remoteImages: true));
    }

    [Theory]
    [InlineData("file:///C:/Users/Reader/AppData/Local/Temp/TigerMarkView/preview-1.html?t=1", WebResourceKind.Document, true)]
    [InlineData("https://attacker.example/frame.html", WebResourceKind.Document, false)]
    [InlineData("https://attacker.example/collect", WebResourceKind.Other, false)]
    public void TheRemoteImageSettingChangesNothingButImages(string uri, WebResourceKind kind, bool allowed)
    {
        Assert.Equal(allowed, WebResourcePolicy.Allows(new Uri(uri), kind, remoteImages: false));
        Assert.Equal(allowed, WebResourcePolicy.Allows(new Uri(uri), kind, remoteImages: true));
    }

    [Fact]
    public void RemoteImagesAreAllowedUnlessTurnedOff()
    {
        Assert.True(WebResourcePolicy.Allows(new Uri("https://example.com/a.png"), WebResourceKind.Image));
    }
}