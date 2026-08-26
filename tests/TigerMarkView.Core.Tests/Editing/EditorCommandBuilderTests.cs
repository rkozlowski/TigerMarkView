using TigerMarkView.Core.Editing;

namespace TigerMarkView.Core.Tests.Editing;

public class EditorCommandBuilderTests
{
    private const string PathWithSpaces = @"C:\My Documents\Test File.md";

    [Fact]
    public void ExpandArguments_QuotedPlaceholderProducesSingleArgumentEvenWithSpaces()
    {
        var result = EditorCommandBuilder.ExpandArguments("\"{file}\"", PathWithSpaces);

        Assert.Equal(new[] { PathWithSpaces }, result);
    }

    [Fact]
    public void ExpandArguments_AdditionalArgumentsExpandAlongsidePlaceholder()
    {
        var result = EditorCommandBuilder.ExpandArguments("--reuse-window \"{file}\"", PathWithSpaces);

        Assert.Equal(new[] { "--reuse-window", PathWithSpaces }, result);
    }

    [Fact]
    public void ExpandArguments_MissingPlaceholderAppendsFilePathAutomatically()
    {
        // Chosen behavior: a template that forgets {file} still opens the right document, rather
        // than silently launching the editor with no file (or rejecting the configuration outright).
        var result = EditorCommandBuilder.ExpandArguments("--reuse-window", PathWithSpaces);

        Assert.Equal(new[] { "--reuse-window", PathWithSpaces }, result);
    }

    [Fact]
    public void ExpandArguments_NullOrEmptyTemplateJustPassesThePath()
    {
        Assert.Equal(new[] { PathWithSpaces }, EditorCommandBuilder.ExpandArguments(null, PathWithSpaces));
        Assert.Equal(new[] { PathWithSpaces }, EditorCommandBuilder.ExpandArguments("", PathWithSpaces));
        Assert.Equal(new[] { PathWithSpaces }, EditorCommandBuilder.ExpandArguments("   ", PathWithSpaces));
    }

    [Fact]
    public void ExpandArguments_UnquotedPlaceholderStillSubstitutes()
    {
        var result = EditorCommandBuilder.ExpandArguments("{file}", PathWithSpaces);

        Assert.Equal(new[] { PathWithSpaces }, result);
    }

    [Fact]
    public void ExpandArguments_PlaceholderCanBeCombinedWithOtherTextInsideAToken()
    {
        // Future-proofing check: a template embedding {file} alongside other text in one quoted
        // token (e.g. a future "{file}:{line}" style) must expand within that single argument.
        var result = EditorCommandBuilder.ExpandArguments("\"--path={file}\"", PathWithSpaces);

        Assert.Equal(new[] { $"--path={PathWithSpaces}" }, result);
    }

    [Fact]
    public void BuildLaunchPlan_SystemDefaultUsesShellExecuteWithTheFilePath()
    {
        var result = EditorCommandBuilder.BuildLaunchPlan(EditorConfiguration.SystemDefault(), PathWithSpaces);

        Assert.True(result.IsSuccess);
        Assert.True(result.Plan!.UseShellExecute);
        Assert.Equal(PathWithSpaces, result.Plan.FileNameOrExecutable);
        Assert.Empty(result.Plan.Arguments);
    }

    [Fact]
    public void BuildLaunchPlan_VisualStudioCodeFailsGracefullyWhenNotFound()
    {
        var discovery = new EditorDiscovery(_ => false);

        var result = EditorCommandBuilder.BuildLaunchPlan(EditorConfiguration.VisualStudioCode(), PathWithSpaces, discovery);

        Assert.False(result.IsSuccess);
        Assert.Null(result.Plan);
        Assert.Contains("Visual Studio Code", result.ErrorMessage);
    }

    [Fact]
    public void BuildLaunchPlan_VisualStudioCodeSucceedsWhenFoundAndDoesNotUseShellExecute()
    {
        // Use a real per-user-install candidate path so a fake "exists" predicate can match it —
        // EditorDiscovery only ever probes its own fixed candidate list, not arbitrary paths.
        var vsCodePath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Programs", "Microsoft VS Code", "Code.exe");
        var discovery = new EditorDiscovery(path => path == vsCodePath);

        var result = EditorCommandBuilder.BuildLaunchPlan(EditorConfiguration.VisualStudioCode(), PathWithSpaces, discovery);

        Assert.True(result.IsSuccess);
        Assert.False(result.Plan!.UseShellExecute);
        Assert.Equal(vsCodePath, result.Plan.FileNameOrExecutable);
        Assert.Equal(new[] { PathWithSpaces }, result.Plan.Arguments);
    }

    [Fact]
    public void BuildLaunchPlan_Notepad3FailsGracefullyWhenNotFound()
    {
        var discovery = new EditorDiscovery(_ => false);

        var result = EditorCommandBuilder.BuildLaunchPlan(EditorConfiguration.Notepad3(), PathWithSpaces, discovery);

        Assert.False(result.IsSuccess);
        Assert.Contains("Notepad3", result.ErrorMessage);
    }

    [Fact]
    public void BuildLaunchPlan_CustomWithEmptyExecutableFails()
    {
        var result = EditorCommandBuilder.BuildLaunchPlan(EditorConfiguration.Custom("", "\"{file}\""), PathWithSpaces);

        Assert.False(result.IsSuccess);
        Assert.NotNull(result.ErrorMessage);
    }

    [Fact]
    public void BuildLaunchPlan_CustomWithNonExistentExecutableFails()
    {
        var missingPath = Path.Combine(Path.GetTempPath(), "TigerMarkViewTests_" + Guid.NewGuid(), "editor.exe");

        var result = EditorCommandBuilder.BuildLaunchPlan(EditorConfiguration.Custom(missingPath, "\"{file}\""), PathWithSpaces);

        Assert.False(result.IsSuccess);
        Assert.Contains(missingPath, result.ErrorMessage);
    }

    [Fact]
    public void BuildLaunchPlan_CustomWithExistingExecutableSucceeds()
    {
        // Use this test assembly's own DLL as a stand-in "existing executable" — only File.Exists matters here.
        var existingPath = typeof(EditorCommandBuilderTests).Assembly.Location;

        var result = EditorCommandBuilder.BuildLaunchPlan(EditorConfiguration.Custom(existingPath, "--reuse-window \"{file}\""), PathWithSpaces);

        Assert.True(result.IsSuccess);
        Assert.False(result.Plan!.UseShellExecute);
        Assert.Equal(existingPath, result.Plan.FileNameOrExecutable);
        Assert.Equal(new[] { "--reuse-window", PathWithSpaces }, result.Plan.Arguments);
    }
}
