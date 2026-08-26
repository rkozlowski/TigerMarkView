namespace TigerMarkView.Core.Editing;

/// <summary>
/// In-memory editor choice, kept free of UI, storage, and process-launching concerns.
/// </summary>
public sealed record EditorConfiguration(EditorType Type, string? ExecutablePath = null, string? ArgumentsTemplate = null)
{
    /// <summary>Default arguments template used by the built-in presets: quote the path so spaces survive tokenization.</summary>
    public const string DefaultArgumentsTemplate = "\"{file}\"";

    public static EditorConfiguration SystemDefault() => new(EditorType.SystemDefault);

    public static EditorConfiguration VisualStudioCode() => new(EditorType.VisualStudioCode, ArgumentsTemplate: DefaultArgumentsTemplate);

    public static EditorConfiguration Notepad3() => new(EditorType.Notepad3, ArgumentsTemplate: DefaultArgumentsTemplate);

    public static EditorConfiguration Custom(string executablePath, string? argumentsTemplate) =>
        new(EditorType.Custom, executablePath, argumentsTemplate);
}
