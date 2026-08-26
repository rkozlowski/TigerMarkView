using System.Threading;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace TigerMarkView.Pdf;

/// <summary>
/// The invisible WebView2 window one PDF operation runs in — the part that is the same whether the
/// document is being written to a PDF file or sent to a printer.
/// </summary>
/// <remarks>
/// <para>
/// A truly hidden window (<c>SW_HIDE</c> via <c>SetVisibleCore</c>) stops WebView2 producing frames,
/// so this window is <em>shown</em> but positioned outside the virtual
/// desktop, kept out of the taskbar and alt-tab (<c>WS_EX_TOOLWINDOW</c>), and refused activation
/// (<c>WS_EX_NOACTIVATE</c>) so neither exporting nor printing ever steals focus from the main window.
/// </para>
/// <para>
/// Extracted rather than copied: export and print are two things done to the same rendered document by
/// the same engine, and a second copy of the window flags, the navigation wait, or the profile-folder
/// rule is exactly how the two would drift apart.
/// </para>
/// </remarks>
internal abstract class OffScreenWebViewHost : Form
{
    private const int WsExToolWindow = 0x00000080;
    private const int WsExNoActivate = 0x08000000;

    private static readonly TimeSpan NavigationTimeout = TimeSpan.FromSeconds(30);

    protected OffScreenWebViewHost()
    {
        ShowInTaskbar = false;
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        Size = new Size(1000, 1400);

        // Park it clear of every monitor rather than at a fixed negative coordinate, which could land
        // on a display arranged to the left of the primary one.
        Location = new Point(SystemInformation.VirtualScreen.Left - Width - 200, 0);

        Controls.Add(WebView);
    }

    protected WebView2 WebView { get; } = new() { Dock = DockStyle.Fill };

    /// <summary>
    /// Name of this host's WebView2 profile folder, a sibling of every other host's under
    /// <c>%LocalAppData%\TigerMarkView\WebView2</c>.
    /// </summary>
    protected abstract string ProfileName { get; }

    protected override bool ShowWithoutActivation => true;

    protected override CreateParams CreateParams
    {
        get
        {
            var createParams = base.CreateParams;
            createParams.ExStyle |= WsExToolWindow | WsExNoActivate;
            return createParams;
        }
    }

    /// <summary>Creates the WebView2 in this host's own profile folder and returns its core.</summary>
    protected async Task<CoreWebView2> CreateCoreAsync()
    {
        var environment = await CoreWebView2Environment.CreateAsync(userDataFolder: UserDataFolder());
        await WebView.EnsureCoreWebView2Async(environment);

        return WebView.CoreWebView2;
    }

    /// <summary>
    /// Navigates and waits, returning <c>null</c> on success or a reader-facing message describing the
    /// failure. <paramref name="purpose"/> completes the sentence — "for export", "for printing".
    /// </summary>
    protected static async Task<string?> NavigateAsync(
        CoreWebView2 core,
        string uri,
        string purpose,
        CancellationToken cancellationToken)
    {
        var completed = new TaskCompletionSource<CoreWebView2WebErrorStatus?>(TaskCreationOptions.RunContinuationsAsynchronously);
        void OnNavigationCompleted(object? sender, CoreWebView2NavigationCompletedEventArgs e) =>
            completed.TrySetResult(e.IsSuccess ? null : e.WebErrorStatus);

        core.NavigationCompleted += OnNavigationCompleted;
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);

        try
        {
            core.Navigate(uri);

            var finished = await Task.WhenAny(completed.Task, Task.Delay(NavigationTimeout, timeout.Token));
            if (finished != completed.Task)
            {
                cancellationToken.ThrowIfCancellationRequested();
                return $"Timed out while loading the document {purpose}.";
            }

            var errorStatus = await completed.Task;
            return errorStatus is null ? null : $"Could not load the document {purpose} ({errorStatus}).";
        }
        finally
        {
            timeout.Cancel();
            core.NavigationCompleted -= OnNavigationCompleted;
        }
    }

    /// <summary>
    /// Kept out of the application directory (which is read-only for an all-users install) and shared
    /// across operations of the same kind, so repeated exports or prints reuse one browser profile
    /// instead of accumulating folders.
    /// </summary>
    /// <remarks>
    /// A sibling of the viewer's profile under the same <c>WebView2</c> parent, never the same folder:
    /// two WebView2 environments in one process may share a user data folder only when their creation
    /// options match, and the viewer's are Avalonia's to choose. Each host here gets its own sibling
    /// for the same reason — <see cref="ProfileName"/> is what keeps them apart.
    /// </remarks>
    private string UserDataFolder()
    {
        var path = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "TigerMarkView",
            "WebView2",
            ProfileName);

        Directory.CreateDirectory(path);
        return path;
    }

    protected static void TryDelete(string? path)
    {
        if (path is null)
        {
            return;
        }

        try
        {
            File.Delete(path);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // A leftover temp file is not worth failing an otherwise successful operation over.
        }
    }
}
