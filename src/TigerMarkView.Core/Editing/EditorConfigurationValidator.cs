namespace TigerMarkView.Core.Editing;

/// <summary>
/// Catches the obvious Custom-editor misconfigurations before a launch is attempted. Presets
/// (System Default / VS Code / Notepad3) aren't validated here — their "not found" case is handled
/// by <see cref="EditorDiscovery"/> instead, since it's a discovery failure, not a config error.
/// </summary>
public static class EditorConfigurationValidator
{
    public static string? Validate(EditorConfiguration configuration)
    {
        if (configuration.Type != EditorType.Custom)
        {
            return null;
        }

        if (string.IsNullOrWhiteSpace(configuration.ExecutablePath))
        {
            return "No executable is configured for the custom editor.";
        }

        if (!File.Exists(configuration.ExecutablePath))
        {
            return $"Custom editor executable not found: {configuration.ExecutablePath}";
        }

        return null;
    }
}
