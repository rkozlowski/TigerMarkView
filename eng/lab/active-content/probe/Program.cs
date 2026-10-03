using System.Text.Json;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;
using TigerMarkView.Core.Rendering;
using TigerMarkView.Pdf;

// Runs only in TigerWinLab. Raw pages deliberately bypass one or both rendering layers to test
// the remaining layer against Chromium itself. Nothing here is part of the shipped application.
internal static class Program
{
    private const string Origin = "http://127.0.0.1:47631";
    private static readonly List<object> Checks = [];
    private static string _root = "";

    [STAThread]
    private static int Main(string[] args)
    {
        _root = args[0];
        if (args.Length > 1 && args[1] == "--noop") { return 0; }
        if (args.Length > 1 && args[1] == "--storage")
        {
            var allowed = WebViewResourceBoundary.IsAllowed(args[2], CoreWebView2WebResourceContext.Image);
            Console.WriteLine(allowed);
            return allowed == (args[2].Contains("local-link") || args[2].StartsWith("file:///X:")) ? 0 : 1;
        }
        if (args.Length > 3 && args[1] == "--history-control")
        {
            return RunHistoryControl(userDataFolder: args[2], page: args[3]);
        }
        using var form = new Form { Width = 900, Height = 700, ShowInTaskbar = false };
        using var view = new WebView2 { Dock = DockStyle.Fill };
        form.Controls.Add(view);
        var success = false;
        form.Shown += async (_, _) =>
        {
            try
            {
                var environment = await CoreWebView2Environment.CreateAsync(userDataFolder: Path.Combine(_root, "probe-profile"));
                await view.EnsureCoreWebView2Async(environment);
                var core = view.CoreWebView2;
                core.Settings.AreDefaultScriptDialogsEnabled = false;
                if (args.Length > 1 && args[1] is "--request" or "--rendered-request")
                {
                    WebViewResourceBoundary.Apply(core);
                    var markup = "<img src=\"" + args[2] + "\">";
                    var html = "<!doctype html><body>" + markup;
                    if (args[1] == "--rendered-request")
                    {
                        html = MarkdownRenderer.ToHtmlDocument(markup, "Alias", new Uri(_root + "\\").AbsoluteUri);
                        Check("probe.alias-removed", !html.Contains(args[2]), "The network drive alias is removed before Chromium sees it.");
                    }
                    await LoadAsync(core, html);
                    var shouldLoad = args[2].Contains("local-link") || args[2].StartsWith("file:///X:");
                    Check("probe.storage-image", await core.ExecuteScriptAsync("document.images[0]?.naturalWidth > 0") == (shouldLoad ? "true" : "false"), "Only local storage images decode.");
                    success = true;
                    return;
                }
                await TestRendererAsync(core);
                await TestCspAsync(core);
                await TestBoundaryAsync(core);
                success = true;
            }
            catch (Exception exception)
            {
                Checks.Add(new { name = "Probe completed", code = "probe.error", status = "FAIL", message = exception.ToString() });
            }
            finally
            {
                File.WriteAllText(Path.Combine(_root, "probe-result.json"), JsonSerializer.Serialize(Checks));
                form.Close();
            }
        };
        Application.Run(form);
        return success ? 0 : 1;
    }

    /// <summary>
    /// The counterfactual for the browsing-history check: a WebView2 engine with an ordinary persistent
    /// profile, as TigerMarkView ran one before InPrivate, shows <paramref name="page"/> and closes. Its
    /// folder must then hold a record of the visit that the same scan finds.
    /// </summary>
    private static int RunHistoryControl(string userDataFolder, string page)
    {
        using var form = new Form { Width = 900, Height = 700, ShowInTaskbar = false };
        using var view = new WebView2 { Dock = DockStyle.Fill };
        form.Controls.Add(view);
        var loaded = false;
        form.Shown += async (_, _) =>
        {
            try
            {
                var environment = await CoreWebView2Environment.CreateAsync(userDataFolder: userDataFolder);
                await view.EnsureCoreWebView2Async(environment);
                var completed = new TaskCompletionSource<bool>();
                view.CoreWebView2.NavigationCompleted += (_, e) => completed.TrySetResult(e.IsSuccess);
                view.CoreWebView2.Navigate(new Uri(page).AbsoluteUri);
                loaded = await completed.Task;
                // Chromium commits History on a timer of about ten seconds; stay open past one.
                await Task.Delay(15000);
            }
            finally
            {
                form.Close();
            }
        };
        Application.Run(form);
        return loaded ? 0 : 1;
    }

    private static void Check(string code, bool passed, string message)
    {
        Checks.Add(new { name = code, code, status = passed ? "PASS" : "FAIL", message });
        if (!passed) { throw new InvalidOperationException($"{code}: {message}"); }
    }

    private static async Task LoadAsync(CoreWebView2 core, string html)
    {
        var path = Path.Combine(_root, $"probe-{Guid.NewGuid():N}.html");
        File.WriteAllText(path, html);
        var loaded = new TaskCompletionSource<bool>();
        void Completed(object? sender, CoreWebView2NavigationCompletedEventArgs e) => loaded.TrySetResult(e.IsSuccess);
        core.NavigationCompleted += Completed;
        try
        {
            core.Navigate(new Uri(path).AbsoluteUri);
            if (!await loaded.Task.WaitAsync(TimeSpan.FromSeconds(30))) { throw new Exception("Probe page did not load."); }
            await Task.Delay(500);
        }
        finally { core.NavigationCompleted -= Completed; }
    }

    private static async Task TestRendererAsync(CoreWebView2 core)
    {
        string[] malformed = [
            "<svg><style><a id=\"</style><img src=x onerror=window.pwned=1>\">x</a></style></svg>",
            "<math><mtext><table><mglyph><style><!--</style><img title=\"--><img src=x onerror=window.pwned=1>\">",
            "<noscript><p title=\"</noscript><img src=x onerror=window.pwned=1>\"></p></noscript>",
            "<svg><p><style><img src=x onerror=window.pwned=1></style></p></svg>",
            "<table><svg><desc><table><img src=x onerror=window.pwned=1></table></desc></svg></table>",
            "<IMG SRC=x oNeRrOr=window.pwned=1><details open ontoggle=window.pwned=1><summary>test</summary></details>",
            "<a href='java&#9;script:window.pwned=1'>x</a><iframe srcdoc='<script>parent.pwned=1</script>'></iframe>",
            "# Title {onclick=window.pwned=1}\n\n![x](x){onerror=window.pwned=1}\n\n<script>window.pwned=1</script>"
        ];
        foreach (var input in malformed)
        {
            // No CSP and no request boundary: a sanitizer failure cannot hide behind either.
            await LoadAsync(core, "<!doctype html><body>" + MarkdownRenderer.ToHtmlFragment(input));
            var safe = await core.ExecuteScriptAsync("!window.pwned && !document.querySelector('script,iframe,object,embed,style,meta,base,form,[onerror],[ontoggle],[onclick]')");
            Check("probe.chromium-reparse", safe == "true", input);
        }

        var payload = "</span></code></pre><img src=x onerror=window.pwned=1><script>window.pwned=1</script>";
        foreach (var language in new[] { "csharp", "html", "javascript", "xml", "sql", "powershell", "python", "css", "unknown", "csharp\"onmouseover=\"x" })
        {
            await LoadAsync(core, "<!doctype html><body>" + MarkdownRenderer.ToHtmlFragment(
                $"```{language}\n{payload}\n```", new MarkdownRenderingOptions(false, true)));
            var safe = await core.ExecuteScriptAsync($"!window.pwned && document.querySelector('code').textContent === {JsonSerializer.Serialize(payload + "\n")} && !document.querySelector('img,script,[onmouseover]')");
            Check("probe.chromium-code", safe == "true", language);
        }

        var passive = """
            # Heading {#custom .note}

            <details open><summary>More</summary><kbd>Ctrl</kbd><sub>2</sub><sup>3</sup></details>

            | A | B |
            |--:|:--|
            | 1 | 2 |

            - [x] Done

            Note[^1]

            [^1]: Footnote

            > [!NOTE]
            > Alert

            <img src="local.png" width="32" align="right">

            ```csharp
            var x = 1; // note
            ```
            """;
        await LoadAsync(core, MarkdownRenderer.ToHtmlDocument(passive, "passive", new Uri(_root + "\\").AbsoluteUri,
            renderingOptions: new MarkdownRenderingOptions(false, true)));
        Check("probe.compatibility", await core.ExecuteScriptAsync("!!document.querySelector('h1#custom.note') && !!document.querySelector('details[open] summary') && !!document.querySelector('kbd') && !!document.querySelector('sub') && !!document.querySelector('sup') && !!document.querySelector('table td[style]') && !!document.querySelector('input:disabled:checked') && !!document.querySelector('.footnote-ref') && !!document.querySelector('.markdown-alert-title svg path') && !!document.querySelector('.syn-keyword') && document.querySelector('img').naturalWidth === 48") == "true", "Passive HTML, Markdig extensions and local image decode in Chromium.");
    }

    private static async Task TestCspAsync(CoreWebView2 core)
    {
        var html = MarkdownRenderer.ToHtmlDocument("# CSP", "CSP", new Uri(_root + "\\").AbsoluteUri);
        // Deliberately insert unsanitized markup after the policy: test actual enforcement, not its text.
        html = html.Replace("<body>", $$"""
            <body>
            <script>window.pwned=1;new Image().src='{{Origin}}/exfil/probe-csp-script'</script>
            <img src=x onerror="window.pwned=1;fetch('{{Origin}}/exfil/probe-event')">
            <iframe src="{{Origin}}/exfil/probe-frame"></iframe>
            <object data="{{Origin}}/exfil/probe-object"></object>
            <style>@import '{{Origin}}/exfil/probe-import'; base[href^='file:'] { background:url('{{Origin}}/exfil/probe-css'); }</style>
            <a id=bad href="javascript:window.pwned=1">bad</a>
            <svg onload="window.pwned=1"><script>window.pwned=1</script></svg>
            <img src="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg'%3E%3Cscript%3Eparent.pwned=1%3C/script%3E%3C/svg%3E">
            """);
        var requests = new List<string>();
        core.AddWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All, CoreWebView2WebResourceRequestSourceKinds.All);
        void Requested(object? sender, CoreWebView2WebResourceRequestedEventArgs e) => requests.Add(e.Request.Uri);
        core.WebResourceRequested += Requested;
        await LoadAsync(core, html);
        await core.ExecuteScriptAsync("document.getElementById('bad').click()");
        await Task.Delay(500);
        Check("probe.csp-execution", await core.ExecuteScriptAsync("!window.pwned") == "true", "Unsanitized scripts, SVG and event handlers cannot execute.");
        Check("probe.csp-requests", !requests.Any(url => url.Contains("/exfil/")), string.Join(", ", requests));
        core.WebResourceRequested -= Requested;
    }

    private static async Task TestBoundaryAsync(CoreWebView2 core)
    {
        WebViewResourceBoundary.Apply(core);
        var requests = new List<(string Url, int? Status)>();
        void Requested(object? sender, CoreWebView2WebResourceRequestedEventArgs e) => requests.Add((e.Request.Uri, e.Response?.StatusCode));
        core.WebResourceRequested += Requested;
        var html = $$"""
            <!doctype html><body>
            <img src="{{Origin}}/img/probe-boundary.png">
            <img src="{{Origin}}/redirect/web">
            <img src="{{Origin}}/redirect/share">
            <img src="file://127.0.0.1/tmvprobe/boundary.png">
            <img src="file:///Z:/mapped.png">
            <img src="remote-link/boundary.png">
            <img src="local-link/local.png">
            <div style="background:url('{{Origin}}/img/probe-css.png');width:20px;height:20px"></div>
            <link rel=stylesheet href="{{Origin}}/exfil/probe-boundary-css">
            <script src="{{Origin}}/exfil/probe-boundary-script"></script>
            <script>fetch('{{Origin}}/exfil/probe-boundary-fetch').catch(()=>{});</script>
            <iframe src="data:text/html,%3Cscript%3Eparent.pwned=1%3C/script%3E"></iframe>
            <img src="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='48' height='48'%3E%3Cimage href='{{Origin}}/exfil/nested-svg-image'/%3E%3Cscript%3Eparent.pwned=1%3C/script%3E%3C/svg%3E">
            <img src="http://localhost:47631/auth/ntlm">
            """;
        await LoadAsync(core, html);
        Check("probe.boundary-other", requests.Any(r => r.Url.Contains("probe-boundary-fetch") && r.Status == 403)
            && requests.Where(r => r.Url.Contains("/exfil/")).All(r => r.Status == 403), JsonSerializer.Serialize(requests.Select(r => new { r.Url, r.Status })));
        Check("probe.boundary-images", await core.ExecuteScriptAsync("document.images[0].naturalWidth > 0 && document.images[1].naturalWidth > 0 && document.images[2].naturalWidth === 0 && document.images[3].naturalWidth === 0 && document.images[4].naturalWidth === 0") == "true", "Web image and HTTP redirect decode; redirect to share, UNC and mapped-drive images do not.");
        Check("probe.boundary-mapped", !WebViewResourceBoundary.IsAllowed("file:///Z:/mapped.png", CoreWebView2WebResourceContext.Image), "The mapped drive is refused before Windows opens its file.");
        Check("probe.boundary-links", await core.ExecuteScriptAsync("document.images[5].naturalWidth === 0 && document.images[6].naturalWidth === 48") == "true", "Network symlink blocked without opening its target; local symlink still decodes.");
        Check("probe.svg-image-isolation", await core.ExecuteScriptAsync("!window.pwned && document.images[7].naturalWidth === 48") == "true"
            && !requests.Any(r => r.Url.Contains("nested-svg-image")), "A data SVG decodes as an image without executing script or fetching its nested external image.");
        core.WebResourceRequested -= Requested;
    }
}
