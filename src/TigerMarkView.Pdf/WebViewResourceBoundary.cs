using Microsoft.Web.WebView2.Core;
using TigerMarkView.Core.Rendering;

namespace TigerMarkView.Pdf;

/// <summary>
/// Enforces <see cref="WebResourcePolicy"/> on a WebView2 that shows rendered documents: each resource
/// request callback is checked, and a refused request is answered with <c>403</c>.
/// </summary>
/// <remarks>
/// <para>
/// This is the host-side layer under the sanitized HTML and the page's Content Security Policy, and
/// it refuses non-image loads even if either earlier layer fails. It runs when the engine asks for a
/// resource; the sanitizer drops absolute network-backed drive URLs earlier still, so their protection
/// never rests on this callback alone. It lives here because this is the Windows/WebView2 assembly both the PDF
/// exporter and the application already reference, so the viewer, Help, and export apply the very same
/// code rather than three copies of it.
/// </para>
/// <para>
/// The filter covers every resource context and every request source — the document, its frames, and
/// any worker — which is why it uses the three-argument overload; the two-argument one misses frames.
/// </para>
/// </remarks>
public static class WebViewResourceBoundary
{
    // WebView2 negotiates NTLM with an intranet image host before BasicAuthenticationRequested is
    // raised, so permitted web images are fetched here without ambient credentials or cookies and
    // their bytes supplied to the engine. The system proxy is still used, but never signed in to:
    // DefaultProxyCredentials stays null, so a proxy that demands Windows authentication answers 407
    // and the image does not load, rather than the reader's credentials being offered on behalf of a
    // URL a document chose. Nothing here prompts for or stores a credential.
    private static readonly HttpClientHandler ImageHandler = new()
    {
        UseCookies = false,
        UseDefaultCredentials = false,
        Credentials = null,
        DefaultProxyCredentials = null,
        PreAuthenticate = false,
        AutomaticDecompression = System.Net.DecompressionMethods.All,
    };

    private static readonly HttpClient ImageClient = new(ImageHandler);

    /// <summary>
    /// The handler settings that decide which credentials an image request can carry, for the tests
    /// that pin them: none for the destination and none for the proxy.
    /// </summary>
    internal static (bool UseDefaultCredentials, bool DestinationCredentials, bool ProxyCredentials) CredentialUse
    {
        get
        {
            var handler = ImageHandler;
            return (handler.UseDefaultCredentials, handler.Credentials is not null, handler.DefaultProxyCredentials is not null);
        }
    }

    /// <summary>
    /// Installs the request filter on <paramref name="core"/>. Call it before the first navigation, and
    /// once per <see cref="CoreWebView2"/>.
    /// </summary>
    /// <param name="core">The engine to protect.</param>
    /// <param name="remoteImages">
    /// Asked on every request: whether <c>http</c>/<c>https</c> images may load now. Omitted, they may —
    /// the default of the reader's Load Remote Images setting, and what <c>tiger-mark</c> uses.
    /// </param>
    public static void Apply(CoreWebView2 core, Func<bool>? remoteImages = null)
    {
        ArgumentNullException.ThrowIfNull(core);

        core.AddWebResourceRequestedFilter(
            "*",
            CoreWebView2WebResourceContext.All,
            CoreWebView2WebResourceRequestSourceKinds.All);

        core.FrameNavigationStarting += (_, e) => e.Cancel = true;
        core.BasicAuthenticationRequested += (_, e) => e.Cancel = true;

        core.WebResourceRequested += async (_, e) =>
        {
            if (!IsAllowed(e.Request.Uri, e.ResourceContext, remoteImages?.Invoke() ?? true))
            {
                e.Response = core.Environment.CreateWebResourceResponse(null, 403, "Forbidden", string.Empty);
                return;
            }

            var target = new Uri(e.Request.Uri);
            if (target.Scheme is not ("http" or "https")) { return; }

            using var deferral = e.GetDeferral();
            try
            {
                // HttpClient only follows HTTP(S) redirects, and a 401/407 is a failure, not a
                // request to authenticate the reader. Preserve image negotiation, but never forward
                // cookies, Authorization, or Referer from the browser profile.
                using var request = new HttpRequestMessage(HttpMethod.Get, target);
                foreach (var header in new[] { "Accept", "User-Agent" })
                {
                    if (e.Request.Headers.Contains(header))
                    {
                        request.Headers.TryAddWithoutValidation(header, e.Request.Headers.GetHeader(header));
                    }
                }
                using var response = await ImageClient.SendAsync(request);
                response.EnsureSuccessStatusCode();
                var bytes = await response.Content.ReadAsByteArrayAsync();
                var type = response.Content.Headers.ContentType?.ToString() ?? "application/octet-stream";
                // WebView2 reads this managed buffer after the callback returns. Its COM stream
                // wrapper retains it; it owns no file/socket handle needing separate disposal.
                // no-store: a page re-rendered after Load Remote Images is turned off must ask again,
                // and be refused, rather than reuse an image the engine kept from before.
                e.Response = core.Environment.CreateWebResourceResponse(
                    new MemoryStream(bytes, writable: false), 200, "OK", "Content-Type: " + type + "\r\nCache-Control: no-store");
            }
            catch (Exception exception) when (exception is HttpRequestException or OperationCanceledException
                or IOException or System.Runtime.InteropServices.COMException or InvalidOperationException)
            {
                try { e.Response = core.Environment.CreateWebResourceResponse(null, 403, "Forbidden", string.Empty); }
                catch (Exception closed) when (closed is System.Runtime.InteropServices.COMException or InvalidOperationException)
                {
                    // The control may have closed while its image was being downloaded.
                }
            }
        };
    }

    /// <summary>
    /// The policy decision for one request, with WebView2's resource context mapped onto the kinds the
    /// platform-neutral policy knows.
    /// </summary>
    public static bool IsAllowed(string uri, CoreWebView2WebResourceContext context, bool remoteImages = true)
    {
        if (!Uri.TryCreate(uri, UriKind.Absolute, out var target)
            || !WebResourcePolicy.Allows(target, KindOf(context), remoteImages))
        {
            return false;
        }

        if (!target.IsFile)
        {
            return true;
        }

        return LocalImageStorage.IsLocal(target);
    }

    private static WebResourceKind KindOf(CoreWebView2WebResourceContext context) => context switch
    {
        CoreWebView2WebResourceContext.Document => WebResourceKind.Document,
        CoreWebView2WebResourceContext.Image => WebResourceKind.Image,
        _ => WebResourceKind.Other,
    };
}
