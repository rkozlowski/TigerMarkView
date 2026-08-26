using System;
using System.Collections;
using System.Collections.Generic;
using Avalonia.Controls;
using Avalonia.Interactivity;

namespace TigerMarkView.Menus;

/// <summary>
/// Shows the menu bar's commands as a flyout, for the toolbar's menu button.
/// </summary>
/// <remarks>
/// <para>
/// <strong>A mirror, not a second menu.</strong> The hamburger has to offer everything the menu bar
/// offers, and a hand-written copy of six menus would be a second command tree to keep in step — the
/// exact failure the toolbar rule ("a toolbar button is never its own implementation") exists to
/// prevent, multiplied by every command in the application. So the flyout is generated from the live
/// <see cref="Menu"/>: same headers, same order, same separators, same enabled state, same check
/// marks, and clicks forwarded to the menu bar's own items so the handler that runs is literally the
/// menu's. Adding a command to the menu bar adds it here, with nothing to remember.
/// </para>
/// <para>
/// <strong>Built at open time</strong>, for the same reason the history surfaces are (see
/// <c>MainWindow.BuildHistoryItems</c>): a flyout populates its presenter once, so anything captured
/// earlier would be shown stale — a Back that is greyed out after the reader has navigated, a theme
/// still ticked as Light. Mirroring immediately before showing means the state cannot be older than
/// the click that asked for it.
/// </para>
/// <para>
/// Forwarding is <see cref="Interactive.RaiseEvent"/> of <see cref="MenuItem.ClickEvent"/> on the
/// source item. On Avalonia 12.1 that runs the item's <c>Click</c> handlers but does
/// <em>not</em> flip <see cref="MenuItem.IsChecked"/> the way a real click on the item does. The
/// checkbox commands are therefore written not to read the sender's toggled state — they derive the
/// new value from the application's own state and write <c>IsChecked</c> back explicitly — which is
/// what makes the two surfaces produce identical results rather than opposite ones.
/// </para>
/// </remarks>
internal static class MenuMirror
{
    /// <summary>
    /// Builds a flyout of <paramref name="menu"/>'s commands as they stand right now. The returned
    /// flyout is single-use: show it, let it close, and build another next time.
    /// </summary>
    /// <remarks>
    /// The placement is stated rather than left to the default. A flyout's default
    /// <see cref="PlacementMode.Bottom"/> centres the popup on its anchor, and a menu wider than the
    /// icon button that opened it then hangs to the left of that button, reading as a panel that
    /// happens to be below rather than a menu opening from the button.
    /// <see cref="PlacementMode.BottomEdgeAlignedLeft"/> lines the flyout's left edge up with the
    /// button's. Submenus are unaffected: they are positioned by the flyout's presenter, not by this.
    /// </remarks>
    public static MenuFlyout Create(Menu menu)
    {
        ArgumentNullException.ThrowIfNull(menu);

        return new MenuFlyout
        {
            ItemsSource = Mirror(menu.Items),
            Placement = PlacementMode.BottomEdgeAlignedLeft,
        };
    }

    private static List<Control> Mirror(IEnumerable sourceItems)
    {
        var items = new List<Control>();

        foreach (var source in sourceItems)
        {
            switch (source)
            {
                case MenuItem item:
                    items.Add(Mirror(item));
                    break;

                case Separator:
                    items.Add(new Separator());
                    break;
            }
        }

        return items;
    }

    /// <summary>
    /// One mirrored command. Everything copied here is presentation or state; the behaviour stays with
    /// the source item, which is what the click is forwarded to.
    /// </summary>
    /// <remarks>
    /// <see cref="MenuItem.GroupName"/> is deliberately <em>not</em> copied. A radio group is about
    /// mutual exclusion within a menu, and the mirror is discarded as soon as it closes; sharing the
    /// menu bar's group names would let a throwaway control uncheck the real one. The check marks are
    /// copied, so the group still reads correctly. <see cref="MenuItem.Icon"/> is not copied either —
    /// it is a control, and a control belongs to one visual tree at a time. Nothing in this menu has
    /// one; anything that grows one needs a factory here rather than a shared instance.
    /// </remarks>
    private static MenuItem Mirror(MenuItem source)
    {
        var mirror = new MenuItem
        {
            Header = source.Header,
            IsEnabled = source.IsEnabled,
            ToggleType = source.ToggleType,
            IsChecked = source.IsChecked,
            InputGesture = source.InputGesture,
        };

        if (ToolTip.GetTip(source) is { } tip)
        {
            ToolTip.SetTip(mirror, tip);
        }

        var children = Mirror(source.Items);
        if (children.Count > 0)
        {
            mirror.ItemsSource = children;
            return mirror;
        }

        mirror.Click += (_, _) => source.RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent));
        return mirror;
    }
}
