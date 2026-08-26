namespace TigerMarkView.Core.Navigation;

/// <summary>
/// Back/Forward history over <em>documents</em>, with the ordinary browser semantics: navigating
/// somewhere new from a position inside the history discards everything that was ahead of it.
/// </summary>
/// <remarks>
/// <para>
/// This models document navigation only. Reloads (manual, Confirm, or watcher-driven), theme changes,
/// PDF export, and Open in Editor all act on the document the reader is already on and deliberately
/// leave the history untouched — which is why this type has no notion of them at all: the viewer
/// simply never calls <see cref="Navigate"/> for them.
/// </para>
/// <para>
/// Pure and platform-free by design (no file I/O, no Avalonia), so the semantics are unit-testable
/// without a window.
/// </para>
/// </remarks>
public sealed class NavigationHistory
{
    /// <summary>
    /// Upper bound on retained entries; the oldest are dropped first. A reading session can wander a
    /// long way, and unbounded growth buys nothing — nobody navigates back a hundred documents.
    /// </summary>
    public const int DefaultCapacity = 50;

    private readonly List<NavigationEntry> _entries = [];
    private readonly int _capacity;
    private int _index = -1;

    public NavigationHistory(int capacity = DefaultCapacity)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(capacity, 1);
        _capacity = capacity;
    }

    /// <summary>The document currently being viewed, or null before anything has been opened.</summary>
    public NavigationEntry? Current => _index >= 0 ? _entries[_index] : null;

    public bool CanGoBack => _index > 0;

    public bool CanGoForward => _index >= 0 && _index < _entries.Count - 1;

    /// <summary>
    /// The entries, oldest first — the trail the history list shows the reader, and what tests and
    /// diagnostics read.
    /// </summary>
    public IReadOnlyList<NavigationEntry> Entries => _entries;

    /// <summary>
    /// Position of <see cref="Current"/> within <see cref="Entries"/>, or -1 before anything has been
    /// opened. This is what a history list marks as "you are here".
    /// </summary>
    public int CurrentIndex => _index;

    /// <summary>
    /// Records a user navigation to <paramref name="filePath"/> and makes it current.
    /// </summary>
    /// <remarks>
    /// Navigating to the document already on screen is a no-op: re-opening the current file (from
    /// Open Recent, say) is a reload in everything but name, and neither adding a duplicate entry nor
    /// silently throwing away the Forward history would match what the reader asked for.
    /// </remarks>
    /// <returns>The entry that is now current.</returns>
    public NavigationEntry Navigate(string filePath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(filePath);

        if (Current is { } current && PathsMatch(current.FilePath, filePath))
        {
            return current;
        }

        // Anything ahead of the current position is a branch the reader has just left behind.
        if (_index < _entries.Count - 1)
        {
            _entries.RemoveRange(_index + 1, _entries.Count - _index - 1);
        }

        _entries.Add(new NavigationEntry(filePath));
        _index = _entries.Count - 1;

        TrimToCapacity();

        return _entries[_index];
    }

    /// <summary>Moves one entry back, or returns null when there is nothing behind the current one.</summary>
    public NavigationEntry? GoBack()
    {
        if (!CanGoBack)
        {
            return null;
        }

        _index--;
        return _entries[_index];
    }

    /// <summary>Moves one entry forward, or returns null when nothing lies ahead.</summary>
    public NavigationEntry? GoForward()
    {
        if (!CanGoForward)
        {
            return null;
        }

        _index++;
        return _entries[_index];
    }

    /// <summary>
    /// Moves the cursor onto an entry that is already in the trail, the way picking an item out of a
    /// browser's history dropdown does.
    /// </summary>
    /// <remarks>
    /// This is a <em>move</em>, never a navigation: with A → B → C → D and D current, jumping to B
    /// leaves the trail as A → [B] → C → D, so C and D remain reachable with Forward. Appending a
    /// second B instead — which is what calling <see cref="Navigate"/> would do — would both duplicate
    /// the entry and discard the Forward branch, and would lose B's remembered reading position by
    /// starting a fresh entry for a document the reader has already been in.
    /// </remarks>
    /// <returns>
    /// The entry now current, or null when <paramref name="index"/> is outside the trail — an
    /// out-of-range pick leaves the cursor exactly where it was rather than throwing, since a history
    /// list can outlive the trail it was built from (capacity trimming, a branch discarded meanwhile).
    /// </returns>
    public NavigationEntry? GoTo(int index)
    {
        if (index < 0 || index >= _entries.Count)
        {
            return null;
        }

        _index = index;
        return _entries[_index];
    }

    /// <summary>
    /// Stores the reader's position in the current document, so returning to it later lands where they
    /// left off. Called just before navigating away; a null offset (the position could not be read)
    /// leaves whatever was already recorded alone rather than forgetting it.
    /// </summary>
    public void RecordScrollPosition(double? scrollY)
    {
        if (scrollY is { } y && Current is { } current)
        {
            current.ScrollY = y;
        }
    }

    private void TrimToCapacity()
    {
        var excess = _entries.Count - _capacity;
        if (excess > 0)
        {
            _entries.RemoveRange(0, excess);
            _index -= excess;
        }
    }

    /// <summary>Windows paths are case-insensitive, so two spellings of one file are one document.</summary>
    private static bool PathsMatch(string left, string right) =>
        string.Equals(left, right, StringComparison.OrdinalIgnoreCase);
}
