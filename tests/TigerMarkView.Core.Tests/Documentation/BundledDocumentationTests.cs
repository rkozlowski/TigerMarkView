using TigerMarkView.Core.Navigation;

namespace TigerMarkView.Core.Tests.Documentation;

/// <summary>
/// Guards the sources of the documentation the application ships with.
/// </summary>
/// <remarks>
/// These check the repository, not a build output: the copy into <c>Docs\</c> next to the executable is
/// declared in <c>TigerMarkView.csproj</c> and belongs to the app project, which this Core test project
/// deliberately does not reference. What is worth catching automatically is the cheap half — a help
/// file renamed, moved, or emptied, which would leave Help showing an error page and nothing failing
/// until someone opened it.
/// </remarks>
public class BundledDocumentationTests
{
    [Theory]
    [InlineData("docs/HELP.md")]
    [InlineData("docs/THIRD-PARTY-NOTICES.md")]
    [InlineData("LICENSE")]
    public void TheDocumentsTheApplicationBundlesArePresentAndNotEmpty(string relativePath)
    {
        if (FindRepositoryRoot() is not { } root)
        {
            // Running from somewhere with no repository above it (a published test bundle, say). The
            // file layout is not this run's to judge.
            return;
        }

        var path = Path.Combine(root, relativePath);

        Assert.True(File.Exists(path), $"{relativePath} is bundled with the application and must exist.");
        Assert.True(File.ReadAllText(path).Trim().Length > 200, $"{relativePath} looks empty or truncated.");
    }

    /// <summary>
    /// HELP.md is rendered by the same pipeline as any other document, so it has to actually be
    /// Markdown by the application's own definition of the word — the one the viewer, the file picker,
    /// and drag/drop all share.
    /// </summary>
    [Fact]
    public void TheHelpDocumentIsMarkdownByTheApplicationsOwnDefinition()
    {
        Assert.True(MarkdownLinkResolver.IsMarkdownPath("docs/HELP.md"));
        Assert.True(MarkdownLinkResolver.IsMarkdownPath("docs/THIRD-PARTY-NOTICES.md"));

        // ...and the licence is not, which is why the Help window renders it as plain text instead.
        Assert.False(MarkdownLinkResolver.IsMarkdownPath("LICENSE.txt"));
    }

    private static string? FindRepositoryRoot()
    {
        for (var directory = new DirectoryInfo(AppContext.BaseDirectory);
             directory is not null;
             directory = directory.Parent)
        {
            if (File.Exists(Path.Combine(directory.FullName, "TigerMarkView.slnx")))
            {
                return directory.FullName;
            }
        }

        return null;
    }
}
