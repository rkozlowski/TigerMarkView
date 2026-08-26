using System;
using System.Threading.Tasks;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Platform.Storage;
using TigerMarkView.Core.Editing;
using TigerMarkView.Windowing;

namespace TigerMarkView;

/// <summary>
/// Focused configuration surface for a Custom editor (executable + arguments template).
/// Deliberately not a general application-settings window.
/// </summary>
public partial class CustomEditorDialog : Window
{
    public CustomEditorDialog()
    {
        InitializeComponent();
        ArgumentsTemplateBox.Text = EditorConfiguration.DefaultArgumentsTemplate;
    }

    public static Task<EditorConfiguration?> ShowAsync(Window owner, EditorConfiguration current)
    {
        var dialog = new CustomEditorDialog();
        if (current.Type == EditorType.Custom)
        {
            dialog.ExecutablePathBox.Text = current.ExecutablePath;
            dialog.ArgumentsTemplateBox.Text = current.ArgumentsTemplate ?? EditorConfiguration.DefaultArgumentsTemplate;
        }

        return dialog.ShowDialog<EditorConfiguration?>(owner);
    }

    /// <inheritdoc cref="MessageDialog.OnOpened"/>
    protected override void OnOpened(EventArgs e)
    {
        base.OnOpened(e);
        NativeTitleBar.ApplyCurrentTheme(this);
    }

    private async void OnBrowseClick(object? sender, RoutedEventArgs e)
    {
        var files = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title = "Select Editor Executable",
            AllowMultiple = false,
            FileTypeFilter = new[]
            {
                new FilePickerFileType("Executable") { Patterns = new[] { "*.exe" } },
            },
        });

        var path = files.Count > 0 ? files[0].TryGetLocalPath() : null;
        if (path is not null)
        {
            ExecutablePathBox.Text = path;
        }
    }

    private void OnCancelClick(object? sender, RoutedEventArgs e) => Close(null);

    private void OnOkClick(object? sender, RoutedEventArgs e)
    {
        var configuration = EditorConfiguration.Custom(ExecutablePathBox.Text?.Trim() ?? "", ArgumentsTemplateBox.Text);
        var error = EditorConfigurationValidator.Validate(configuration);
        if (error is not null)
        {
            ErrorText.Text = error;
            ErrorText.IsVisible = true;
            return;
        }

        Close(configuration);
    }
}
