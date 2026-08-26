namespace TigerMarkView.Core.Rendering;

/// <summary>
/// Which screen palette the rendered Markdown document uses. Affects the on-screen viewer only —
/// print/PDF output re-declares the light palette inside <c>@media print</c> (see
/// <see cref="DocumentShell.PrintCss"/>), so a reader in Dark mode still gets a normal readable PDF.
/// </summary>
public enum MarkdownTheme
{
    Light = 0,
    Dark = 1,
}
