using System;
using System.Reflection;
using System.Threading.Tasks;
using Avalonia.Controls;
using Avalonia.Interactivity;
using TigerMarkView.Core.About;
using TigerMarkView.Documentation;
using TigerMarkView.Windowing;

namespace TigerMarkView;

/// <summary>
/// Help &gt; About TigerMarkView: what this application is, which version of it is running, and where
/// to read the documentation and the licences.
/// </summary>
/// <remarks>
/// <para>
/// <strong>Every line of it comes from assembly metadata</strong> — product name, version, description,
/// and copyright are read off the running assembly, which the SDK stamped from
/// <c>Directory.Build.props</c>. Nothing is written into the XAML or into this file, because a version
/// spelled out in a dialog is a version that will eventually disagree with the one that shipped.
/// </para>
/// <para>
/// The three links are bundled documents, so they remain available offline. They open in the Help
/// window. The dialog closes as it hands one over, so a modal dialog and a modeless Help window are
/// never on screen fighting over the same owner.
/// </para>
/// </remarks>
public partial class AboutDialog : Window
{
    private BundledDocument? _requested;

    public AboutDialog()
    {
        InitializeComponent();

        var assembly = typeof(AboutDialog).Assembly;

        ProductNameText.Text = Read<AssemblyProductAttribute>(assembly, attribute => attribute.Product) ?? "TigerMarkView";
        VersionText.Text = $"Version {ApplicationVersion.Of(assembly)}";
        DescriptionText.Text = Read<AssemblyDescriptionAttribute>(assembly, attribute => attribute.Description) ?? "";
        CopyrightText.Text = Read<AssemblyCopyrightAttribute>(assembly, attribute => attribute.Copyright) ?? "";

        // Stated, not inferred: the repository ships an MIT LICENSE, and the link below opens that
        // exact file rather than a description of it.
        LicenseText.Text = "MIT License";
    }

    /// <summary>
    /// Shows the dialog and reports which bundled document, if any, the reader asked to read. The
    /// caller opens it — window ownership is the main window's business, not a dialog's.
    /// </summary>
    public static async Task<BundledDocument?> ShowAsync(Window owner)
    {
        ArgumentNullException.ThrowIfNull(owner);

        var dialog = new AboutDialog();
        await dialog.ShowDialog(owner);

        return dialog._requested;
    }

    /// <summary>
    /// A dialog inherits the application's theme variant for everything Avalonia draws, but its native
    /// caption needs the same DWM nudge every other window gets.
    /// </summary>
    protected override void OnOpened(EventArgs e)
    {
        base.OnOpened(e);
        NativeTitleBar.ApplyCurrentTheme(this);
    }

    private static string? Read<TAttribute>(Assembly assembly, Func<TAttribute, string?> select)
        where TAttribute : Attribute
    {
        var value = assembly.GetCustomAttribute<TAttribute>() is { } attribute ? select(attribute) : null;

        return string.IsNullOrWhiteSpace(value) ? null : value;
    }

    private void OnHelpClick(object? sender, RoutedEventArgs e) => Request(BundledDocuments.Help);

    private void OnLicenseClick(object? sender, RoutedEventArgs e) => Request(BundledDocuments.License);

    private void OnThirdPartyNoticesClick(object? sender, RoutedEventArgs e) =>
        Request(BundledDocuments.ThirdPartyNotices);

    private void Request(BundledDocument document)
    {
        _requested = document;
        Close();
    }

    private void OnCloseClick(object? sender, RoutedEventArgs e) => Close();
}
