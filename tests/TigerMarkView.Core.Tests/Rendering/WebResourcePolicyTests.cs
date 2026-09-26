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

    [Fact]
    public void ARelativeAddressIsRefusedBecauseTheEngineOnlyEverAsksAboutResolvedOnes()
    {
        Assert.False(WebResourcePolicy.Allows(new Uri("images/diagram.png", UriKind.Relative), WebResourceKind.Image));
    }
}
