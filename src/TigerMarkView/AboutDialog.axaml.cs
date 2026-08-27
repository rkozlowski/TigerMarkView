using System;
using System.Threading.Tasks;
using Avalonia.Controls;
using Avalonia.Interactivity;
using TigerMarkView.Core.About;
using TigerMarkView.Documentation;
using TigerMarkView.Navigation;
using TigerMarkView.Windowing;

namespace TigerMarkView;

/// <summary>
/// Help &gt; About TigerMarkView: what this application is, which version of it is running, and where
/// to read the documentation and the licences.
/// </summary>
/// <remarks>
/// <para>
/// <strong>Every identity value comes from assembly metadata</strong> — product name, version,
/// description, company, copyright, licence, and public links are read off the running assembly,
/// which the SDK stamped from <c>Version.props</c>.
/// </para>
/// <para>
/// The three links are bundled documents, so they remain available offline. They open in the Help
/// window. The dialog closes as it hands one over, so a modal dialog and a modeless Help window are
/// never on screen fighting over the same owner.
/// </para>
/// </remarks>
public partial class AboutDialog : Window
{
    private readonly ApplicationMetadata _metadata;
    private readonly ExternalLinkLauncher _linkLauncher = new();
    private BundledDocument? _requested;

    public AboutDialog()
    {
        InitializeComponent();

        _metadata = ApplicationMetadata.FromAssembly(typeof(AboutDialog).Assembly);

        ProductNameText.Text = _metadata.ProductName;
        VersionText.Text = $"Version {_metadata.Version}";
        DescriptionText.Text = _metadata.Description;
        CompanyText.Text = _metadata.Company;
        CopyrightText.Text = _metadata.Copyright;
        LicenseText.Text = string.IsNullOrWhiteSpace(_metadata.LicenseIdentity)
            ? string.Empty
            : $"{_metadata.LicenseIdentity} License";
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

    private void OnHelpClick(object? sender, RoutedEventArgs e) => Request(BundledDocuments.Help);

    private void OnLicenseClick(object? sender, RoutedEventArgs e) => Request(BundledDocuments.License);

    private void OnThirdPartyNoticesClick(object? sender, RoutedEventArgs e) =>
        Request(BundledDocuments.ThirdPartyNotices);

    private async void OnRepositoryClick(object? sender, RoutedEventArgs e) =>
        await OpenExternalAsync(_metadata.Repository);

    private async void OnIssueTrackerClick(object? sender, RoutedEventArgs e) =>
        await OpenExternalAsync(_metadata.IssueTracker);

    private async Task OpenExternalAsync(Uri? target)
    {
        var outcome = target is null
            ? Editing.LaunchOutcome.Failed("That link is not available in this build.")
            : _linkLauncher.Open(target);

        if (!outcome.Success)
        {
            await MessageDialog.ShowAsync(this, "Could not open link", outcome.ErrorMessage!);
        }
    }

    private void Request(BundledDocument document)
    {
        _requested = document;
        Close();
    }

    private void OnCloseClick(object? sender, RoutedEventArgs e) => Close();
}
