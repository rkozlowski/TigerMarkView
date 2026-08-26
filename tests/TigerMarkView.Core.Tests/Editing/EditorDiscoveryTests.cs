using TigerMarkView.Core.Editing;

namespace TigerMarkView.Core.Tests.Editing;

public class EditorDiscoveryTests
{
    [Fact]
    public void FindVisualStudioCode_ReturnsNullWhenNoCandidateExists()
    {
        var discovery = new EditorDiscovery(_ => false);

        Assert.Null(discovery.FindVisualStudioCode());
    }

    [Fact]
    public void FindVisualStudioCode_PrefersThePerUserInstallLocation()
    {
        var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var expected = Path.Combine(localAppData, "Programs", "Microsoft VS Code", "Code.exe");

        // Make every candidate "exist" and confirm the per-user one wins, proving priority order.
        var discovery = new EditorDiscovery(_ => true);

        Assert.Equal(expected, discovery.FindVisualStudioCode());
    }

    [Fact]
    public void FindVisualStudioCode_FallsBackToProgramFilesWhenPerUserInstallIsMissing()
    {
        var programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        var expected = Path.Combine(programFiles, "Microsoft VS Code", "Code.exe");

        var discovery = new EditorDiscovery(path => path == expected);

        Assert.Equal(expected, discovery.FindVisualStudioCode());
    }

    [Fact]
    public void FindNotepad3_ReturnsNullWhenNoCandidateExists()
    {
        var discovery = new EditorDiscovery(_ => false);

        Assert.Null(discovery.FindNotepad3());
    }

    [Fact]
    public void FindNotepad3_PrefersProgramFilesOverProgramFilesX86()
    {
        var programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        var expected = Path.Combine(programFiles, "Notepad3", "Notepad3.exe");

        var discovery = new EditorDiscovery(_ => true);

        Assert.Equal(expected, discovery.FindNotepad3());
    }

    [Fact]
    public void FindNotepad3_FallsBackToProgramFilesX86()
    {
        var programFilesX86 = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86);
        var expected = Path.Combine(programFilesX86, "Notepad3", "Notepad3.exe");

        var discovery = new EditorDiscovery(path => path == expected);

        Assert.Equal(expected, discovery.FindNotepad3());
    }
}
