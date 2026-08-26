using TigerMarkView.Core.Rendering;

namespace TigerMarkView.Core.Tests.Rendering;

public class RenderedDocumentTests : IDisposable
{
    private readonly string _directory =
        Directory.CreateDirectory(Path.Combine(Path.GetTempPath(), $"tmv-rendered-{Guid.NewGuid():N}")).FullName;

    [Fact]
    public void LoadCapturesHtmlPathAndSourceTimestamp()
    {
        var path = WriteMarkdown("first.md", "# First\n\nBody text.");
        var expectedTimestamp = File.GetLastWriteTimeUtc(path);

        var document = RenderedDocument.Load(path);

        Assert.Equal(Path.GetFullPath(path), document.FilePath);
        Assert.Contains(">First</h1>", document.Html);
        Assert.Equal(expectedTimestamp, document.SourceTimestampUtc);
    }

    /// <summary>
    /// The behaviour PDF export depends on: a retained <see cref="RenderedDocument"/> keeps reproducing
    /// the version it was rendered from, even once a newer version exists on disk. Exporting from it can
    /// therefore never publish content the reader has not seen.
    /// </summary>
    [Fact]
    public void ARetainedDocumentDoesNotFollowLaterChangesOnDisk()
    {
        var path = WriteMarkdown("evolving.md", "# Version one");
        var viewed = RenderedDocument.Load(path);

        WriteMarkdown("evolving.md", "# Version two");

        Assert.Contains("Version one", viewed.Html);
        Assert.DoesNotContain("Version two", viewed.Html);

        // Re-loading is what "export the latest on disk" would have done — the two genuinely differ.
        Assert.Contains("Version two", RenderedDocument.Load(path).Html);
    }

    [Fact]
    public void LoadEmitsABaseHrefForTheDocumentsOwnFolder()
    {
        var path = WriteMarkdown("with-image.md", "![Diagram](images/diagram.png)");

        var document = RenderedDocument.Load(path);

        Assert.Contains(new Uri(_directory + Path.DirectorySeparatorChar).AbsoluteUri, document.Html);
        Assert.Contains("images/diagram.png", document.Html);
    }

    /// <summary>
    /// A theme switch must restyle the version the reader is looking at, not fetch a newer one — the
    /// same stale-document guarantee PDF export depends on. Re-rendering from the retained Markdown
    /// is what makes that true, so this asserts it against a file that has since changed on disk.
    /// </summary>
    [Fact]
    public void WithThemeRestylesTheViewedVersionWithoutRereadingTheFile()
    {
        var path = WriteMarkdown("themed.md", "# Version one");
        var viewed = RenderedDocument.Load(path, MarkdownTheme.Light);

        WriteMarkdown("themed.md", "# Version two");
        var dark = viewed.WithTheme(MarkdownTheme.Dark);

        Assert.Equal(MarkdownTheme.Dark, dark.Theme);
        Assert.Contains("color-scheme: dark;", dark.Html);
        Assert.Contains("Version one", dark.Html);
        Assert.DoesNotContain("Version two", dark.Html);

        // Everything identifying which version this is stays put.
        Assert.Equal(viewed.FilePath, dark.FilePath);
        Assert.Equal(viewed.Markdown, dark.Markdown);
        Assert.Equal(viewed.SourceTimestampUtc, dark.SourceTimestampUtc);
    }

    [Fact]
    public void WithThemeKeepsTheBaseHrefSoRelativeImagesStillResolve()
    {
        var path = WriteMarkdown("with-image.md", "![Diagram](images/diagram.png)");

        var dark = RenderedDocument.Load(path).WithTheme(MarkdownTheme.Dark);

        Assert.Contains(new Uri(_directory + Path.DirectorySeparatorChar).AbsoluteUri, dark.Html);
        Assert.Contains("images/diagram.png", dark.Html);
    }

    [Fact]
    public void WithTheSameThemeIsANoOp()
    {
        var document = RenderedDocument.Load(WriteMarkdown("same.md", "# Hello"), MarkdownTheme.Dark);

        Assert.Same(document, document.WithTheme(MarkdownTheme.Dark));
    }

    [Fact]
    public void LoadDefaultsToTheLightTheme()
    {
        var document = RenderedDocument.Load(WriteMarkdown("default-theme.md", "# Hello"));

        Assert.Equal(MarkdownTheme.Light, document.Theme);
        Assert.Contains("color-scheme: light;", document.Html);
    }

    [Fact]
    public void LoadDefaultsToBothRenderingOptionsOff()
    {
        var document = RenderedDocument.Load(WriteMarkdown("default-options.md", "# Hi :rocket:"));

        Assert.Equal(MarkdownRenderingOptions.Default, document.RenderingOptions);
        Assert.Contains(":rocket:", document.Html);
    }

    /// <summary>
    /// The same stale-document guarantee <see cref="WithThemeRestylesTheViewedVersionWithoutRereadingTheFile"/>
    /// asserts, for the rendering options: turning a rendering feature on restyles what the reader has
    /// already read, and can never quietly promote the view to a newer version on disk.
    /// </summary>
    [Fact]
    public void WithRenderingOptionsRerendersTheViewedVersionWithoutRereadingTheFile()
    {
        var path = WriteMarkdown("options.md", "# Version one :rocket:");
        var viewed = RenderedDocument.Load(path);

        WriteMarkdown("options.md", "# Version two :rocket:");
        var expanded = viewed.WithRenderingOptions(new MarkdownRenderingOptions(EmojiShortcodes: true));

        Assert.True(expanded.RenderingOptions.EmojiShortcodes);
        Assert.Contains("🚀", expanded.Html);
        Assert.Contains("Version one", expanded.Html);
        Assert.DoesNotContain("Version two", expanded.Html);

        // Everything identifying which version this is stays put, so the status bar's timestamps and
        // PDF export's idea of "what is being viewed" are untouched.
        Assert.Equal(viewed.FilePath, expanded.FilePath);
        Assert.Equal(viewed.Markdown, expanded.Markdown);
        Assert.Equal(viewed.SourceTimestampUtc, expanded.SourceTimestampUtc);
        Assert.Equal(viewed.Theme, expanded.Theme);
        Assert.Equal(viewed.PageSetup, expanded.PageSetup);
    }

    [Fact]
    public void WithTheSameRenderingOptionsIsANoOp()
    {
        var document = RenderedDocument.Load(WriteMarkdown("same-options.md", "# Hello"));

        Assert.Same(document, document.WithRenderingOptions(MarkdownRenderingOptions.Default));
    }

    /// <summary>
    /// The viewer's refresh path changes theme and rendering options together in one pass, so this is
    /// the combination that actually runs when either is toggled.
    /// </summary>
    [Fact]
    public void WithPresentationAppliesThemeAndRenderingOptionsInOneRerender()
    {
        var path = WriteMarkdown("presentation.md", "# Hi :rocket:\n\n```csharp\nvar x = 1;\n```");
        var viewed = RenderedDocument.Load(path);

        var changed = viewed.WithPresentation(
            MarkdownTheme.Dark,
            new MarkdownRenderingOptions(EmojiShortcodes: true, SyntaxHighlighting: true));

        Assert.Equal(MarkdownTheme.Dark, changed.Theme);
        Assert.Contains("color-scheme: dark;", changed.Html);
        Assert.Contains("🚀", changed.Html);
        Assert.Contains("""<span class="syn-keyword">var</span>""", changed.Html);
        Assert.Equal(viewed.SourceTimestampUtc, changed.SourceTimestampUtc);
    }

    /// <summary>
    /// A PDF preference and a rendering option are independent: changing paper must not silently reset
    /// how the document is rendered, and vice versa.
    /// </summary>
    [Fact]
    public void RenderingOptionsSurviveAPageSetupChange()
    {
        var path = WriteMarkdown("paper.md", "# Hi :rocket:");
        var viewed = RenderedDocument
            .Load(path)
            .WithRenderingOptions(new MarkdownRenderingOptions(EmojiShortcodes: true));

        var relaid = viewed.WithPageSetup(TigerMarkView.Core.Exporting.PdfPageSetup.For(
            TigerMarkView.Core.Exporting.PdfPaperSize.A5,
            TigerMarkView.Core.Exporting.PdfOrientation.Landscape,
            TigerMarkView.Core.Exporting.PdfMarginPreset.Wide,
            showPageNumbers: true));

        Assert.Equal(viewed.RenderingOptions, relaid.RenderingOptions);
        Assert.Contains("🚀", relaid.Html);
        Assert.Contains("size: 210mm 148mm;", relaid.Html);
    }

    /// <summary>
    /// With both options off, the retained HTML is exactly what this document produced before either
    /// feature existed — the default path has to be untouched, not merely equivalent.
    /// </summary>
    [Fact]
    public void DefaultOptionsProduceTheSameHtmlAsRenderingWithNoOptionsAtAll()
    {
        var path = WriteMarkdown(
            "unchanged.md",
            "# Title :rocket:\n\nText with `:warning:` and a list.\n\n```csharp\nvar x = 1; // hi\n```\n");

        var document = RenderedDocument.Load(path);
        var direct = MarkdownDocumentLoader.LoadHtmlDocument(path);

        Assert.Equal(direct, document.Html);
        Assert.Contains(":rocket:", document.Html);
        Assert.Contains("""<pre><code class="language-csharp">var x = 1; // hi""", document.Html);

        // The syntax tokens and rules are always in the stylesheet; what must be absent is any span
        // that uses them.
        Assert.DoesNotContain("<span class=\"syn-", document.Html);
    }

    [Fact]
    public void LoadThrowsForAMissingFile()
    {
        var path = Path.Combine(_directory, "does-not-exist.md");

        Assert.Throws<FileNotFoundException>(() => RenderedDocument.Load(path));
    }

    private string WriteMarkdown(string fileName, string markdown)
    {
        var path = Path.Combine(_directory, fileName);
        File.WriteAllText(path, markdown);
        return path;
    }

    public void Dispose()
    {
        try
        {
            Directory.Delete(_directory, recursive: true);
        }
        catch (IOException)
        {
            // Test scratch space; a leftover folder is not a failure.
        }
    }
}
