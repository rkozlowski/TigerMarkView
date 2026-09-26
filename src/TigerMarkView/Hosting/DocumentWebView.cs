using System.Runtime.InteropServices;
using Avalonia.Controls;
using Avalonia.Platform;
using Microsoft.Web.WebView2.Core;
using TigerMarkView.Core.Navigation;
using TigerMarkView.Core.Rendering;
using TigerMarkView.Pdf;

namespace TigerMarkView.Hosting;

/// <summary>
/// Puts <see cref="WebViewResourceBoundary"/> on a window's <see cref="NativeWebView"/> and lets
/// nothing be shown in it without that boundary.
/// </summary>
/// <remarks>
/// <para>
/// Avalonia creates the WebView2 lazily, when the control first joins the visual tree, and raises
/// <see cref="NativeWebView.AdapterCreated"/> only <em>after</em> it has already started navigating to
/// whatever <see cref="NativeWebView.Source"/> was set before that. The viewer sets its first document in
/// its constructor — often a file named on the command line, which is exactly the document least
/// vetted by the reader — so navigation goes through <see cref="Navigate"/>, and
/// <see cref="ViewerNavigationGate"/> holds it until the boundary is in.
/// </para>
/// <para>
/// It fails closed. If the platform handle is not a WebView2, or installing the boundary throws, no
/// document is ever shown in this control: it shows a generated notice naming the reason instead, and
/// <see cref="BoundaryUnavailable"/> tells the window so its status can say the same. On supported
/// Windows the handle is always WebView2, so this is a diagnosable dead end rather than a path anyone
/// is expected to reach.
/// </para>
/// </remarks>
internal sealed class DocumentWebView
{
    private readonly NativeWebView _webView;
    private readonly Func<MarkdownTheme> _theme;
    private readonly ViewerNavigationGate _gate = new();

    /// <summary>
    /// The managed wrapper the boundary's request handler is registered on, kept for the lifetime of
    /// the control so the handler is never orphaned by garbage collection.
    /// </summary>
    private CoreWebView2? _core;

    private DocumentWebView(NativeWebView webView, Func<MarkdownTheme> theme)
    {
        _webView = webView;
        _theme = theme;
        webView.AdapterCreated += OnAdapterCreated;
    }

    /// <summary>Raised once, on the UI thread, when the boundary could not be installed.</summary>
    public event EventHandler<string>? BoundaryUnavailable;

    /// <summary>Why no document can be shown, or <c>null</c> while that is not the case.</summary>
    public string? UnavailableReason => _gate.UnavailableReason;

    /// <summary>
    /// Takes over navigation of <paramref name="webView"/>. Call it before anything navigates the
    /// control, and navigate through the returned object from then on. <paramref name="theme"/> styles
    /// the notice shown if the boundary cannot be installed.
    /// </summary>
    public static DocumentWebView Attach(NativeWebView webView, Func<MarkdownTheme> theme)
    {
        ArgumentNullException.ThrowIfNull(webView);
        ArgumentNullException.ThrowIfNull(theme);
        return new DocumentWebView(webView, theme);
    }

    /// <summary>
    /// Shows <paramref name="source"/> once the boundary is in place — immediately, after that — and
    /// never if it could not be installed.
    /// </summary>
    public void Navigate(Uri source)
    {
        if (_gate.Request(source) is { } target)
        {
            _webView.Source = target;
        }
    }

    private void OnAdapterCreated(object? sender, WebViewAdapterEventArgs e)
    {
        // A recreated adapter (the control re-parented) is a new CoreWebView2 and needs its own filter.
        if (!TryApplyBoundary(e.TryGetPlatformHandle(), out var core, out var failure))
        {
            var alreadyUnavailable = _gate.State == ViewerBoundaryState.Unavailable;
            _gate.BoundaryUnavailable(failure);
            ShowUnavailableNotice(failure);

            if (!alreadyUnavailable)
            {
                BoundaryUnavailable?.Invoke(this, failure);
            }

            return;
        }

        _core = core;

        if (_gate.BoundaryInstalled() is { } held)
        {
            _webView.Source = held;
        }
    }

    /// <summary>
    /// A page of TigerMarkView's own, with nothing from any document in it, so it is safe to show in an
    /// engine without the boundary.
    /// </summary>
    private void ShowUnavailableNotice(string reason)
    {
        var html = MarkdownRenderer.ToErrorDocument(
            "Documents are not shown because TigerMarkView could not install its network protection on the viewer.",
            reason,
            _theme());

        _webView.NavigateToString(html, new Uri("about:blank"));
    }

    private static bool TryApplyBoundary(IPlatformHandle? handle, out CoreWebView2? core, out string failure)
    {
        core = null;

        if (handle is not IWindowsWebView2PlatformHandle webView2)
        {
            failure = $"The viewer engine is not Microsoft Edge WebView2 ({handle?.HandleDescriptor ?? "no platform handle"}).";
            return false;
        }

        // Avalonia hands out an AddRef'd interface pointer; the managed wrapper takes a reference of
        // its own, so this one is released whatever happens.
        var pointer = webView2.CoreWebView2;
        if (pointer == IntPtr.Zero)
        {
            failure = "The WebView2 engine was not available when the viewer was created.";
            return false;
        }

        try
        {
            core = CoreWebView2.CreateFromComICoreWebView2(pointer);
            WebViewResourceBoundary.Apply(core);
            failure = string.Empty;
            return true;
        }
        catch (Exception exception) when (exception is COMException or InvalidComObjectException
                                             or InvalidCastException or ArgumentException)
        {
            core = null;
            failure = $"Installing the request filter failed: {exception.GetType().Name}: {exception.Message}";
            return false;
        }
        finally
        {
            Marshal.Release(pointer);
        }
    }
}
