using Avalonia;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Markup.Xaml;
using TigerMarkView.Core.Rendering;
using TigerMarkView.Settings;

namespace TigerMarkView;

public partial class App : Application
{
    public override void Initialize()
    {
        AvaloniaXamlLoader.Load(this);
    }

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            // Settings are loaded before the window exists so the saved theme is already in force when
            // it first paints — restoring a theme after the fact would show a flash of the wrong one.
            var settingsStore = new SettingsStore();
            var settings = settingsStore.Load();
            ApplyThemeVariant(settings.Theme);

            var initialFilePath = desktop.Args is { Length: > 0 } args ? args[0] : null;
            desktop.MainWindow = new MainWindow(initialFilePath, settings, settingsStore);
        }

        base.OnFrameworkInitializationCompleted();
    }

    /// <summary>
    /// Switches the Avalonia chrome (menus, status bar, dialogs) to match the viewer theme. Applied at
    /// the <see cref="Application"/> level so dialogs opened later inherit it without extra wiring.
    /// </summary>
    public static void ApplyThemeVariant(MarkdownTheme theme)
    {
        if (Current is { } application)
        {
            application.RequestedThemeVariant = theme == MarkdownTheme.Dark
                ? Avalonia.Styling.ThemeVariant.Dark
                : Avalonia.Styling.ThemeVariant.Light;
        }
    }
}
