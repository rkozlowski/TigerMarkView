using TigerMarkView.Core.Editing;

namespace TigerMarkView.Core.Tests.Editing;

public class EditorConfigurationValidatorTests
{
    [Fact]
    public void NonCustomConfigurationsAreAlwaysValid()
    {
        Assert.Null(EditorConfigurationValidator.Validate(EditorConfiguration.SystemDefault()));
        Assert.Null(EditorConfigurationValidator.Validate(EditorConfiguration.VisualStudioCode()));
        Assert.Null(EditorConfigurationValidator.Validate(EditorConfiguration.Notepad3()));
    }

    [Fact]
    public void CustomWithEmptyExecutablePathIsInvalid()
    {
        var error = EditorConfigurationValidator.Validate(EditorConfiguration.Custom("", "\"{file}\""));

        Assert.NotNull(error);
    }

    [Fact]
    public void CustomWithWhitespaceOnlyExecutablePathIsInvalid()
    {
        var error = EditorConfigurationValidator.Validate(EditorConfiguration.Custom("   ", "\"{file}\""));

        Assert.NotNull(error);
    }

    [Fact]
    public void CustomWithNonExistentExecutableIsInvalid()
    {
        var missingPath = Path.Combine(Path.GetTempPath(), "TigerMarkViewTests_" + Guid.NewGuid(), "editor.exe");

        var error = EditorConfigurationValidator.Validate(EditorConfiguration.Custom(missingPath, "\"{file}\""));

        Assert.Contains(missingPath, error);
    }

    [Fact]
    public void CustomWithExistingExecutableIsValid()
    {
        var existingPath = typeof(EditorConfigurationValidatorTests).Assembly.Location;

        var error = EditorConfigurationValidator.Validate(EditorConfiguration.Custom(existingPath, "\"{file}\""));

        Assert.Null(error);
    }
}
