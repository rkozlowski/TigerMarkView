using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using TigerMarkView.Core.Editing;

namespace TigerMarkView.Editing;

/// <summary>
/// The only place in the app that actually calls <see cref="Process.Start(ProcessStartInfo)"/> for
/// external editors. Everything about *what* to launch (<see cref="EditorLaunchPlan"/>) comes from
/// the Avalonia-independent, unit-tested <see cref="EditorCommandBuilder"/> in Core; this class only
/// owns the OS-specific side effect and turns launch failures into a friendly outcome instead of an
/// unhandled exception.
/// </summary>
public sealed class ExternalEditorLauncher
{
    public LaunchOutcome Launch(EditorConfiguration configuration, string filePath)
    {
        var result = EditorCommandBuilder.BuildLaunchPlan(configuration, filePath);
        if (!result.IsSuccess)
        {
            return LaunchOutcome.Failed(result.ErrorMessage ?? "Could not determine how to launch the editor.");
        }

        var plan = result.Plan!;
        var startInfo = new ProcessStartInfo
        {
            FileName = plan.FileNameOrExecutable,
            UseShellExecute = plan.UseShellExecute,
        };

        if (!plan.UseShellExecute)
        {
            // Explicit argument list, never a shell/cmd.exe command line — the file path is passed
            // as data, not concatenated into anything that could be reinterpreted.
            foreach (var argument in plan.Arguments)
            {
                startInfo.ArgumentList.Add(argument);
            }
        }

        try
        {
            Process.Start(startInfo);
            return LaunchOutcome.Ok();
        }
        catch (Win32Exception ex)
        {
            // Covers both "no shell association for .md" (SystemDefault) and "executable failed to start".
            return LaunchOutcome.Failed($"Could not launch the editor: {ex.Message}");
        }
        catch (Exception ex) when (ex is IOException or InvalidOperationException or ObjectDisposedException)
        {
            return LaunchOutcome.Failed($"Could not launch the editor: {ex.Message}");
        }
    }
}
