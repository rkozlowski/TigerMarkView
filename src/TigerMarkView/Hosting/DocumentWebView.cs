using System.Runtime.InteropServices;
using Avalonia.Controls;
using Avalonia.Platform;
using Microsoft.Web.WebView2.Core;
using TigerMarkView.Pdf;

namespace TigerMarkView.Hosting;

/// <summary>
/// Puts <see cref="WebViewResourceBoundary"/> on a window's <see cref="NativeWebView"/> and holds back
/// navigation until it is in place.
/// </summary>
/// <remarks>
/// <para>
/// Avalonia creates the WebView2 lazily, when the control first joins the visual tree, and raises
/// <see cref="NativeWebView.AdapterCreated"/> only <em>after</em> it has already started navigating to
/// whatever <see cref="NativeWebView.Source"/> was set before that. The viewer sets its first document in
/// its constructor — often a file named on the command line, which is exactly the document least
/// vetted by the reader — so installing the boundary from that event alone would leave the first
/// document's requests unchecked. Navigation therefore goes through <see cref="Navigate"/>, which keeps
/// the latest target until the boundary has been applied and only then hands it to the control.
/// </para>
/// <para>
/// If the platform handle is not a WebView2 or the boundary cannot be installed, the document is still
/// shown: it has already been sanitized and carries its own Content Security Policy, and refusing to
/// display anything would make the reader unusable over the loss of one of three layers. On Windows
/// the handle is always WebView2.
/// </para>
/// </remarks>
internal sealed class DocumentWebView
{
    private readonly NativeWebView _webView;
    private Uri? _pendingSource;
    private bool _adapterReady;

    /// <summary>
    /// The managed wrapper the boundary's request handler is registered on, kept for the lifetime of
    /// the control so the handler is never orphaned by garbage collection.
    /// </summary>
    private CoreWebView2? _core;

    private DocumentWebView(NativeWebView webView)
    {
        _webView = webView;
        webView.AdapterCreated += OnAdapterCreated;
    }

    /// <summary>
    /// Takes over navigation of <paramref name="webView"/>. Call it before anything navigates the
    /// control, and navigate through the returned object from then on.
    /// </summary>
    public static DocumentWebView Attach(NativeWebView webView)
    {
        ArgumentNullException.ThrowIfNull(webView);
        return new DocumentWebView(webView);
    }

    /// <summary>Shows <paramref name="source"/> once the boundary is in place — immediately, after that.</summary>
    public void Navigate(Uri source)
    {
        ArgumentNullException.ThrowIfNull(source);

        if (_adapterReady)
        {
            _webView.Source = source;
        }
        else
        {
            _pendingSource = source;
        }
    }

    private void OnAdapterCreated(object? sender, WebViewAdapterEventArgs e)
    {
        // A recreated adapter (the control re-parented) is a new CoreWebView2 and needs its own filter.
        _core = TryApplyBoundary(e.TryGetPlatformHandle());
        _adapterReady = true;

        if (_pendingSource is { } source)
        {
            _pendingSource = null;
            _webView.Source = source;
        }
    }

    private static CoreWebView2? TryApplyBoundary(IPlatformHandle? handle)
    {
        if (handle is not IWindowsWebView2PlatformHandle webView2)
        {
            return null;
        }

        // Avalonia hands out an AddRef'd interface pointer; the managed wrapper takes a reference of
        // its own, so this one is released whatever happens.
        var pointer = webView2.CoreWebView2;
        if (pointer == IntPtr.Zero)
        {
            return null;
        }

        try
        {
            var core = CoreWebView2.CreateFromComICoreWebView2(pointer);
            WebViewResourceBoundary.Apply(core);
            return core;
        }
        catch (Exception exception) when (exception is COMException or InvalidComObjectException
                                             or InvalidCastException or ArgumentException)
        {
            return null;
        }
        finally
        {
            Marshal.Release(pointer);
        }
    }
}
