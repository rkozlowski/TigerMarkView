using System;
using System.IO;

namespace TigerMarkView.Documentation;

/// <summary>
/// One of the documents that ships with the application, as the Help window needs it: where it is and
/// what to call the window showing it.
/// </summary>
/// <remarks>
/// A bundled document is not a <see cref="Core.Rendering.RenderedDocument"/> and deliberately does not
/// become one. It has no watcher, no timestamps, no place in Open Recent or the navigation trail, and
/// nothing about it is exportable — it is application documentation the reader is looking at, not the
/// document they are reviewing.
/// </remarks>
public sealed record BundledDocument(string Path, string Title);

/// <summary>
/// Where the documentation that ships with TigerMarkView lives once it is installed.
/// </summary>
/// <remarks>
/// The same split as <see cref="Settings.SettingsStore"/>, one level down: Core knows how to render a
/// Markdown document, this knows where these particular three files sit on disk. They are copied next
/// to the executable by the project file (see the Docs item group in <c>TigerMarkView.csproj</c>), so
/// Help works from a build output and from an installed copy, needs no repository checkout, and needs
/// no network. The sources live in the repository's <c>docs/</c> folder and <em>LICENSE</em> at its
/// root — never read from there at run time.
/// </remarks>
internal static class BundledDocuments
{
    /// <summary>Output folder the project file copies the documentation into, next to the executable.</summary>
    public const string DirectoryName = "Docs";

    public static string RootPath => Path.Combine(AppContext.BaseDirectory, DirectoryName);

    public static BundledDocument Help => new(PathTo("HELP.md"), "Help");

    /// <summary>
    /// The repository's own LICENSE, copied verbatim and given a <c>.txt</c> extension in the output so
    /// the Help viewer has something it can open. Not Markdown, and rendered as the plain text it is.
    /// </summary>
    public static BundledDocument License => new(PathTo("LICENSE.txt"), "License");

    public static BundledDocument ThirdPartyNotices =>
        new(PathTo("THIRD-PARTY-NOTICES.md"), "Third-party notices");

    /// <summary>
    /// Whether <paramref name="path"/> is one of the bundled documents — the test the Help window
    /// applies to a link before following it, so help can link within itself without ever becoming a
    /// way to browse the filesystem.
    /// </summary>
    public static bool Contains(string path)
    {
        try
        {
            var folder = Path.GetDirectoryName(Path.GetFullPath(path));

            return folder is not null &&
                   string.Equals(
                       folder.TrimEnd(Path.DirectorySeparatorChar),
                       RootPath.TrimEnd(Path.DirectorySeparatorChar),
                       StringComparison.OrdinalIgnoreCase);
        }
        catch (Exception ex) when (ex is ArgumentException or NotSupportedException or PathTooLongException)
        {
            return false;
        }
    }

    private static string PathTo(string fileName) => Path.Combine(RootPath, fileName);
}
