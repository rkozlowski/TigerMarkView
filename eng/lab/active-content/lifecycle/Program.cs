using System.Reflection;
using System.Text.Json;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Platform;
using TigerMarkView.Core.Rendering;
using TigerMarkView.Hosting;

internal static class Program
{
    internal static string Root = "";
    internal static int ExitCode = 1;

    [STAThread]
    private static int Main(string[] args)
    {
        Root = args[0];
        AppBuilder.Configure<ProbeApplication>().UsePlatformDetect().StartWithClassicDesktopLifetime(args);
        return ExitCode;
    }
}

internal sealed class ProbeApplication : Application
{
    public override void Initialize() => Styles.Add(new Avalonia.Themes.Fluent.FluentTheme());

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            var browser = new NativeWebView();
            browser.EnvironmentRequested += (_, e) =>
            {
                if (e is WindowsWebView2EnvironmentRequestedEventArgs windows)
                {
                    windows.UserDataFolder = Path.Combine(Program.Root, "lifecycle-profile");
                }
            };
            var host = DocumentWebView.Attach(browser, () => MarkdownTheme.Light);
            var window = new Window { Width = 800, Height = 600, Content = browser, Title = "Security lifecycle probe" };
            desktop.MainWindow = window;
            var checks = new List<object>();
            var created = 0;
            var destroyed = 0;
            var messages = 0;
            var navigations = new List<string>();
            browser.NavigationStarted += (_, e) => navigations.Add($"{e.Request?.AbsoluteUri[..Math.Min(100, e.Request.AbsoluteUri.Length)]}: cancelled={e.Cancel}");
            WebViewAdapterEventArgs? lastAdapter = null;
            browser.AdapterCreated += (_, e) => { created++; lastAdapter = e; };
            browser.AdapterDestroyed += (_, _) => destroyed++;
            host.WebMessageReceived += (_, _) => messages++;
            var path = Path.Combine(Program.Root, "lifecycle-page.html");
            File.WriteAllText(path, "<!doctype html><body><h1>Protected</h1><img src='file://127.0.0.1/tmvprobe/lifecycle.png'>");
            host.Navigate(new Uri(path));
            window.Opened += async (_, _) =>
            {
                void Check(string code, bool passed, string message)
                {
                    checks.Add(new { name = code, code, status = passed ? "PASS" : "FAIL", message });
                    if (!passed) { throw new InvalidOperationException(code + ": " + message); }
                }

                async Task WaitPageAsync()
                {
                    for (var attempt = 0; attempt < 150; attempt++)
                    {
                        try
                        {
                            if (await browser.InvokeScript("document.querySelector('h1')?.textContent === 'Protected' && document.images[0].complete") == "true") { return; }
                        }
                        catch (InvalidOperationException) { }
                        await Task.Delay(200);
                    }
                    throw new TimeoutException("Protected page did not appear.");
                }

                try
                {
                    await WaitPageAsync();
                    Check("lifecycle.first", created == 1 && await browser.InvokeScript("document.images[0].naturalWidth") == "0", "First document is displayed with the UNC image blocked.");
                    await browser.InvokeScript("window.chrome.webview.postMessage('trusted')");
                    await Task.Delay(200);
                    Check("lifecycle.bridge-current", messages == 1, "The current preview can send a shell message.");

                    window.Content = new TextBlock { Text = "Detached" };
                    window.UpdateLayout();
                    await Task.Delay(300);
                    Check("lifecycle.detached", browser.Source.AbsoluteUri == "about:blank" && TopLevel.GetTopLevel(browser) is null,
                        $"Destroyed events: {destroyed}; source: {browser.Source}; detached: {TopLevel.GetTopLevel(browser) is null}.");
                    host.Navigate(new UriBuilder(new Uri(path)) { Query = "second" }.Uri);
                    Check("lifecycle.held", browser.Source.AbsoluteUri == "about:blank", "Navigation while detached is held.");
                    window.Content = browser;
                    await WaitPageAsync();
                    Check("lifecycle.recreated", created == 2 && await browser.InvokeScript("document.images[0].naturalWidth") == "0", "Replacement adapter installs its own boundary before showing the held page.");

                    var foreign = Path.Combine(Program.Root, "lifecycle-foreign.html");
                    File.WriteAllText(foreign, "<!doctype html><body>Foreign<script>window.chrome.webview.postMessage('foreign')</script>");
                    browser.Source = new Uri(foreign);
                    await Task.Delay(800);
                    Check("lifecycle.bridge-source", messages == 1, "An alternate top-level page cannot send messages through the preview bridge.");

                    // Fault injection at the platform seam: an adapter without a Windows handle.
                    // The production class is linked into this test assembly unchanged; no shipped
                    // switch or alternate implementation of boundary installation is involved.
                    var constructor = typeof(WebViewAdapterEventArgs).GetConstructors(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic).Single();
                    var adapterType = constructor.GetParameters().Single().ParameterType;
                    var fake = DispatchProxy.Create(adapterType, typeof(NullAdapter));
                    var badArgs = constructor.Invoke([fake]);
                    var callback = typeof(DocumentWebView).GetMethod("OnAdapterCreated", BindingFlags.Instance | BindingFlags.NonPublic)!;
                    callback.Invoke(host, [browser, badArgs]);
                    host.Navigate(new Uri(path));
                    await Task.Delay(800);
                    var noticeBody = await browser.InvokeScript("document.body.innerText");
                    Check("lifecycle.fail-closed", host.UnavailableReason is not null
                        && await browser.InvokeScript("document.body.innerText.includes('could not install its network protection')") == "true",
                        $"Failure: {host.UnavailableReason}; source: {browser.Source}; body: {noticeBody}; navigations: {string.Join(" | ", navigations)}.");
                    Check("lifecycle.notice-exact", !host.IsUnavailableNoticeNavigation(new Uri(
                        "data:text/html;base64," + Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes("<script>window.chrome.webview.postMessage('forged')</script>")))),
                        "The generated-notice exception cannot authorize document-supplied data HTML.");
                    callback.Invoke(host, [browser, lastAdapter]);
                    host.Navigate(new Uri(path));
                    await Task.Delay(300);
                    Check("lifecycle.retry-closed", host.UnavailableReason is not null
                        && await browser.InvokeScript("document.body.innerText.includes('could not install its network protection')") == "true", "A later successful installation cannot reopen the failed gate.");
                    Program.ExitCode = 0;
                }
                catch (Exception exception)
                {
                    checks.Add(new { name = "Lifecycle probe", code = "lifecycle.error", status = "FAIL", message = exception.ToString() });
                }
                finally
                {
                    File.WriteAllText(Path.Combine(Program.Root, "lifecycle-result.json"), JsonSerializer.Serialize(checks));
                    desktop.Shutdown();
                }
            };
        }
        base.OnFrameworkInitializationCompleted();
    }
}

public class NullAdapter : DispatchProxy
{
    protected override object? Invoke(MethodInfo? targetMethod, object?[]? args) => null;
}
