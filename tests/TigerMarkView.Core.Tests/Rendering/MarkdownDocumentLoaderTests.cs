using TigerMarkView.Core.Rendering;

namespace TigerMarkView.Core.Tests.Rendering;

public class MarkdownDocumentLoaderTests : IDisposable
{
    private readonly string _dir;

    public MarkdownDocumentLoaderTests()
    {
        _dir = Path.Combine(Path.GetTempPath(), "TigerMarkViewTests_" + Guid.NewGuid());
        Directory.CreateDirectory(_dir);
    }

    public void Dispose() => Directory.Delete(_dir, recursive: true);

    [Fact]
    public void EmitsBaseHrefPointingAtTheMarkdownFilesDirectory()
    {
        var mdPath = Path.Combine(_dir, "doc.md");
        File.WriteAllText(mdPath, "![alt](diagram.png)");

        var html = MarkdownDocumentLoader.LoadHtmlDocument(mdPath);

        var expectedBase = new Uri(_dir + Path.DirectorySeparatorChar).AbsoluteUri;
        Assert.Contains($"""<base href="{expectedBase}" />""", html);
        Assert.Contains("<img src=\"diagram.png\"", html);
    }

    [Fact]
    public void UsesFileNameAsTitle()
    {
        var mdPath = Path.Combine(_dir, "notes.md");
        File.WriteAllText(mdPath, "# Hello");

        var html = MarkdownDocumentLoader.LoadHtmlDocument(mdPath);

        Assert.Contains("<title>notes.md</title>", html);
    }

    [Fact]
    public void ThrowsOnMissingFile()
    {
        var missingPath = Path.Combine(_dir, "does-not-exist.md");

        Assert.Throws<FileNotFoundException>(() => MarkdownDocumentLoader.LoadHtmlDocument(missingPath));
    }
}
