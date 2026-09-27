using System.Runtime.InteropServices;
using Avalonia.Controls;
using Avalonia.Platform;
using Avalonia.Threading;
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
    private IntPtr _coreIdentity;
    private Uri? _source;
    private string? _unavailableHtml;

    private DocumentWebView(NativeWebView webView, Func<MarkdownTheme> theme)
    {
        _webView = webView;
        _theme = theme;
        webView.AdapterCreated += OnAdapterCreated;
        webView.AdapterDestroyed += (_, _) =>
        {
            _core = null;
            _coreIdentity = IntPtr.Zero;
            HoldNavigation();
        };
        // Some Avalonia native hosts detach without raising AdapterDestroyed. Do not leave the
        // gate open while a replacement adapter can be created, regardless of that notification.
        webView.DetachedFromVisualTree += (_, _) => HoldNavigation();
        webView.AttachedToVisualTree += (_, _) => Dispatcher.UIThread.Post(() =>
        {
            // After child controls have attached: a retained adapter needs no new Created event;
            // an asynchronously created one is still absent and will raise Created when ready.
            if (_gate.State == ViewerBoundaryState.Pending && webView.TryGetPlatformHandle() is { } handle)
            {
                OnAdapterReady(handle);
            }
        });
        webView.NavigationStarted += (_, e) =>
        {
            if (_gate.State != ViewerBoundaryState.Protected && e.Request?.AbsoluteUri != "about:blank"
                && !IsUnavailableNoticeNavigation(e.Request))
            {
                e.Cancel = true;
            }
        };
    }

    private void HoldNavigation()
    {
        _gate.BoundaryDestroyed();
        var blank = new Uri("about:blank");
        _webView.Source = blank;
        // Navigate also clears a queued URL if Source was already blank.
        _webView.Navigate(blank);
    }

    /// <summary>Raised once, on the UI thread, when the boundary could not be installed.</summary>
    public event EventHandler<string>? BoundaryUnavailable;

    /// <summary>Messages from the protected, current top-level preview only.</summary>
    public event EventHandler<string>? WebMessageReceived;

    /// <summary>Why no document can be shown, or <c>null</c> while that is not the case.</summary>
    public string? UnavailableReason => _gate.UnavailableReason;

    /// <summary>Only the host-generated failure page may navigate after protection failed.</summary>
    public bool IsUnavailableNoticeNavigation(Uri? request)
    {
        if (_gate.State != ViewerBoundaryState.Unavailable || request is null) { return false; }
        if (request.AbsoluteUri == "about:blank") { return true; }
        // NavigateToString can report its input as a base64 data URI at NavigationStarting even
        // though its committed origin is about:blank. Do not grant arbitrary data-page navigation.
        var text = request.AbsoluteUri;
        var comma = text.IndexOf(',');
        if (comma < 0 || _unavailableHtml is null) { return false; }
        var type = text[..comma];
        if (!type.Equals("data:text/html;base64", StringComparison.OrdinalIgnoreCase)
            && !type.Equals("data:text/html;charset=utf-8;base64", StringComparison.OrdinalIgnoreCase)) { return false; }
        try
        {
            return Convert.FromBase64String(Uri.UnescapeDataString(text[(comma + 1)..])).AsSpan()
                .SequenceEqual(System.Text.Encoding.UTF8.GetBytes(_unavailableHtml));
        }
        catch (FormatException) { return false; }
    }

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
        _source = source;
        if (_gate.Request(source) is { } target)
        {
            _webView.Navigate(target);
        }
    }

    private void OnAdapterCreated(object? sender, WebViewAdapterEventArgs e) => OnAdapterReady(e.TryGetPlatformHandle());

    private void OnAdapterReady(IPlatformHandle? handle)
    {
        // A recreated adapter (the control re-parented) is a new CoreWebView2 and needs its own filter.
        if (!TryApplyBoundary(handle, out var core, out var failure))
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

        // Replay the last page only when this engine has not shown it yet: a new engine, or one whose
        // gate closed while it was detached. A repeated Created notification for the same protected
        // engine must not reload the document.
        var replay = _gate.State == ViewerBoundaryState.Pending || !ReferenceEquals(_core, core);

        if (!ReferenceEquals(_core, core))
        {
            _core = core;
            core!.WebMessageReceived += (_, message) =>
            {
                if (ReferenceEquals(_core, core) && _gate.State == ViewerBoundaryState.Protected
                    && Uri.TryCreate(message.Source, UriKind.Absolute, out var source)
                    && source == _source)
                {
                    try
                    {
                        WebMessageReceived?.Invoke(this, message.TryGetWebMessageAsString());
                    }
                    catch (ArgumentException)
                    {
                        // Only the shell's string commands are part of the bridge contract.
                    }
                }
            };
        }

        if (_gate.BoundaryInstalled() is { } held && replay)
        {
            _webView.Navigate(held);
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

        _unavailableHtml = html;
        _webView.NavigateToString(html, new Uri("about:blank"));
    }

    private bool TryApplyBoundary(IPlatformHandle? handle, out CoreWebView2? core, out string failure)
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
            // The engine already protected: _core keeps a COM reference to it, so no other object can
            // occupy that address while it is retained.
            if (_core is not null && pointer == _coreIdentity)
            {
                core = _core;
                failure = string.Empty;
                return true;
            }

            core = CoreWebView2.CreateFromComICoreWebView2(pointer);
            core.Settings.AreHostObjectsAllowed = false;
            WebViewResourceBoundary.Apply(core);
            _coreIdentity = pointer;
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
