using System.Text;

namespace TigerMarkView.Core.Editing;

/// <summary>
/// Turns an <see cref="EditorConfiguration"/> plus a target file path into a ready-to-launch
/// <see cref="EditorLaunchPlan"/>. Contains no process-launching or Avalonia-specific code, so it's
/// independently testable — the actual <c>Process.Start</c> call lives in the app project.
/// </summary>
public static class EditorCommandBuilder
{
    private const string FilePlaceholder = "{file}";

    public static EditorLaunchResult BuildLaunchPlan(EditorConfiguration configuration, string filePath, EditorDiscovery? discovery = null)
    {
        discovery ??= EditorDiscovery.Default;

        return configuration.Type switch
        {
            EditorType.SystemDefault => EditorLaunchResult.Success(EditorLaunchPlan.ShellExecute(filePath)),
            EditorType.VisualStudioCode => ResolvePreset(discovery.FindVisualStudioCode(), "Visual Studio Code", configuration, filePath),
            EditorType.Notepad3 => ResolvePreset(discovery.FindNotepad3(), "Notepad3", configuration, filePath),
            EditorType.Custom => ResolveCustom(configuration, filePath),
            _ => EditorLaunchResult.Failure("Unknown editor configuration."),
        };
    }

    private static EditorLaunchResult ResolvePreset(string? executablePath, string editorName, EditorConfiguration configuration, string filePath)
    {
        if (executablePath is null)
        {
            return EditorLaunchResult.Failure(
                $"{editorName} was not found in the usual install locations. Configure a custom editor instead.");
        }

        return EditorLaunchResult.Success(
            EditorLaunchPlan.DirectProcess(executablePath, ExpandArguments(configuration.ArgumentsTemplate, filePath)));
    }

    private static EditorLaunchResult ResolveCustom(EditorConfiguration configuration, string filePath)
    {
        var error = EditorConfigurationValidator.Validate(configuration);
        if (error is not null)
        {
            return EditorLaunchResult.Failure(error);
        }

        return EditorLaunchResult.Success(
            EditorLaunchPlan.DirectProcess(configuration.ExecutablePath!, ExpandArguments(configuration.ArgumentsTemplate, filePath)));
    }

    /// <summary>
    /// Expands an arguments template into a list of arguments suitable for
    /// <see cref="System.Diagnostics.ProcessStartInfo.ArgumentList"/> (each entry is a raw argument
    /// value — the .NET process-launch machinery handles OS-level quoting, so callers never need to
    /// escape spaces themselves). The template is tokenized in a small, deliberately non-general way:
    /// split on whitespace, except inside double-quoted segments (so <c>"{file}"</c> stays one token
    /// even when the expanded path contains spaces). <c>{file}</c> is replaced with
    /// <paramref name="filePath"/> wherever it appears in a token. If no token contains the
    /// placeholder, <paramref name="filePath"/> is appended as a final argument — a template that
    /// forgets <c>{file}</c> still opens the right document rather than silently doing nothing.
    /// </summary>
    public static IReadOnlyList<string> ExpandArguments(string? argumentsTemplate, string filePath)
    {
        var tokens = Tokenize(argumentsTemplate ?? string.Empty);
        var expanded = new List<string>(tokens.Count + 1);
        var sawPlaceholder = false;

        foreach (var token in tokens)
        {
            if (token.Contains(FilePlaceholder, StringComparison.Ordinal))
            {
                sawPlaceholder = true;
                expanded.Add(token.Replace(FilePlaceholder, filePath, StringComparison.Ordinal));
            }
            else
            {
                expanded.Add(token);
            }
        }

        if (!sawPlaceholder)
        {
            expanded.Add(filePath);
        }

        return expanded;
    }

    private static List<string> Tokenize(string template)
    {
        var tokens = new List<string>();
        var current = new StringBuilder();
        var inQuotes = false;
        var hasContent = false;

        foreach (var c in template)
        {
            if (c == '"')
            {
                inQuotes = !inQuotes;
                hasContent = true; // an empty "" segment still counts as a (possibly empty) token
                continue;
            }

            if (char.IsWhiteSpace(c) && !inQuotes)
            {
                if (hasContent)
                {
                    tokens.Add(current.ToString());
                    current.Clear();
                    hasContent = false;
                }
                continue;
            }

            current.Append(c);
            hasContent = true;
        }

        if (hasContent)
        {
            tokens.Add(current.ToString());
        }

        return tokens;
    }
}
