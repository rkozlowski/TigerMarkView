using System;
using System.Threading.Tasks;
using Avalonia.Controls;
using Avalonia.Interactivity;
using TigerMarkView.Windowing;

namespace TigerMarkView;

/// <summary>
/// Minimal reusable error/info dialog. Avalonia has no built-in MessageBox; a small owned Window is
/// enough here rather than pulling in a UI library for one OK button.
/// </summary>
public partial class MessageDialog : Window
{
    public MessageDialog()
    {
        InitializeComponent();
    }

    public static Task ShowAsync(Window owner, string title, string message)
    {
        var dialog = new MessageDialog { Title = title };
        dialog.MessageText.Text = message;
        return dialog.ShowDialog(owner);
    }

    /// <summary>
    /// A dialog inherits the application's theme variant for everything Avalonia draws, but its native
    /// caption needs the same DWM nudge the main window gets — otherwise a Dark-mode error dialog
    /// arrives wearing a white title bar.
    /// </summary>
    protected override void OnOpened(EventArgs e)
    {
        base.OnOpened(e);
        NativeTitleBar.ApplyCurrentTheme(this);
    }

    private void OnOkClick(object? sender, RoutedEventArgs e) => Close();
}
