using Microsoft.Web.WebView2.Core;
using TigerMarkView.Core.Rendering;

namespace TigerMarkView.Pdf;

/// <summary>
/// Enforces <see cref="WebResourcePolicy"/> on a WebView2 that shows rendered documents: every request
/// the page makes is checked, and a refused one is answered with <c>403</c> before it leaves the engine.
/// </summary>
/// <remarks>
/// <para>
/// This is the host-side layer under the sanitized HTML and the page's Content Security Policy, and
/// it does not depend on either: whatever a page manages to run or embed, it cannot fetch anything but
/// a picture from the network. It lives here because this is the Windows/WebView2 assembly both the PDF
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
    /// <summary>
    /// Installs the request filter on <paramref name="core"/>. Call it before the first navigation, and
    /// once per <see cref="CoreWebView2"/>.
    /// </summary>
    public static void Apply(CoreWebView2 core)
    {
        ArgumentNullException.ThrowIfNull(core);

        core.AddWebResourceRequestedFilter(
            "*",
            CoreWebView2WebResourceContext.All,
            CoreWebView2WebResourceRequestSourceKinds.All);

        core.WebResourceRequested += (_, e) =>
        {
            if (!IsAllowed(e.Request.Uri, e.ResourceContext))
            {
                e.Response = core.Environment.CreateWebResourceResponse(null, 403, "Forbidden", string.Empty);
            }
        };
    }

    /// <summary>
    /// The policy decision for one request, with WebView2's resource context mapped onto the kinds the
    /// platform-neutral policy knows.
    /// </summary>
    public static bool IsAllowed(string uri, CoreWebView2WebResourceContext context) =>
        Uri.TryCreate(uri, UriKind.Absolute, out var target) && WebResourcePolicy.Allows(target, KindOf(context));

    private static WebResourceKind KindOf(CoreWebView2WebResourceContext context) => context switch
    {
        CoreWebView2WebResourceContext.Document => WebResourceKind.Document,
        CoreWebView2WebResourceContext.Image => WebResourceKind.Image,
        _ => WebResourceKind.Other,
    };
}
