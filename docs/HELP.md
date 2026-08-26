# TigerMarkView Help

TigerMarkView is a Markdown **viewer and reviewer** for Windows. It shows `.md` and `.markdown` files
the way they are meant to be read, keeps you aware when a file changes on disk, and exports a clean
PDF.

It is deliberately **not** a Markdown editor. Editing stays in the editor you already use — see
[External editor](#external-editor).

This help is part of the application and works offline. Press **F1** at any time to bring it back, or
use **Help > Help**. Reading it does not disturb the document you have open.

## Contents

- [Overview](#overview)
- [Opening documents](#opening-documents)
- [Navigation](#navigation)
- [Reload modes](#reload-modes)
- [External editor](#external-editor)
- [PDF export](#pdf-export)
- [Themes and window layout](#themes-and-window-layout)
- [Rendering options](#rendering-options)
- [What TigerMarkView remembers](#what-tigermarkview-remembers)
- [Troubleshooting](#troubleshooting)

## Overview

TigerMarkView does four things:

- renders local Markdown files (`.md`, `.markdown`) as a formatted document;
- tells you clearly when the file on disk is newer than what you are looking at, and reloads it the
  way you asked it to;
- hands the file to your editor when you want to change it;
- exports what you are reading to a PDF.

Documents are rendered on your own machine and are not uploaded anywhere. Viewing local documents,
using Help, and exporting PDFs work without an internet connection; opening a web link naturally uses
your default browser and network connection.

Markdown is rendered as GitHub-Flavored Markdown, so headings, lists, tables, task lists, fenced code
blocks, block quotes, and links all work as they do on GitHub. The full syntax is described in the
[GFM specification](https://github.github.com/gfm/).

## Opening documents

There are four ways to open a document:

- **File > Open...** — pick a file. The toolbar's folder button does the same thing.
- **Drag and drop** — drag a `.md` file from Explorer onto the TigerMarkView window.
- **File > Open Recent** — the last 10 documents you opened explicitly, newest first. The toolbar can
  show the same list too; see [Toolbar buttons](#toolbar-buttons).
- **From the command line** — `TigerMarkView.exe C:\notes\README.md` opens that file at startup.

### Open Recent is not the same as history

These two lists answer different questions, and they are kept apart on purpose:

| | What it holds |
|---|---|
| **File > Open Recent** | Documents you *chose* — File > Open, a drag and drop, a command-line file, or an Open Recent entry picked again. Remembered between sessions. |
| **Navigate > History** | Every document you visited in this session, including ones you only reached by clicking a link. Forgotten when you close the application. |

So following a link from one document to another puts the second document in your browsing history,
but it does not clutter Open Recent with files you never asked for.

## Navigation

Clicking a link to another local Markdown file opens it in TigerMarkView, and you can move through the
documents you have visited like pages in a browser:

| Action | Where |
|---|---|
| **Back** | `Navigate > Back`, the toolbar's left arrow, or **Alt+Left** |
| **Forward** | `Navigate > Forward`, the toolbar's right arrow, or **Alt+Right** |
| **Jump to any visited document** | `Navigate > History`, or the chevron at the right of the toolbar's arrows |

Back and Forward remember where you had scrolled to, so returning to a long document puts you back
where you were reading. Picking a document from the history list moves you to it without throwing away
the documents ahead of it — Forward still works afterwards.

Other kinds of link behave like this:

- **Anchor links** (`[Reload modes](#reload-modes)`) scroll to that heading in the current document.
- **Web links** (`http`, `https`) and **mail links** (`mailto:`) open in your default browser or mail
  client. TigerMarkView does not display web pages itself.
- **Links to other kinds of local file** are not opened. A note appears in the status bar instead.
  This is deliberate: a Markdown document you were sent should not be able to launch programs.

## Reload modes

TigerMarkView always watches the file you have open. What it does when the file changes is up to you —
choose from the **Reload Mode** menu, or the mode button on the right of the toolbar.

| Mode | What happens when the file changes on disk |
|---|---|
| **Manual** | Nothing is reloaded. The status bar turns orange to say a newer version exists; you reload when you want to. |
| **Confirm** | A strip appears at the top of the window reading *File modified externally* with a reload button. Nothing changes on screen until you press it. This is the default. |
| **Automatic** | The document reloads by itself, keeping your place in it. |

You can reload at any time in any mode: **File > Reload Now**, the toolbar's reload button, or the
reload button at the right of the status bar. They are all the same command.

### Reading the status bar

The status bar answers two questions: is what you are reading still current, and when did it last
load? The coloured dot at the left summarises it:

| Dot | Meaning |
|---|---|
| **Grey** | What you are reading matches the file on disk. |
| **Green** | The document reloaded successfully a few minutes ago. |
| **Orange** | The file on disk is newer than what is on screen. Reload to catch up. |
| **Red** | Something went wrong — usually the file has been deleted, moved, or cannot be read. |

A document does not go red merely for being open a long time. If it still matches the file on disk, it
stays grey.

Three different times are shown, and they mean different things:

- **Viewed** — when the version *you are looking at* was last written.
- **File** — when the file *on disk* was last written.
- **Reloaded** — when TigerMarkView last loaded the document successfully.

Times from today are shown as `10:23:07`; older ones include the date, as `6 Aug 2026 22:41:08`.

## External editor

TigerMarkView does not edit documents. **Tools > Open in Editor** (or the toolbar's edit button)
hands the current file to an editor of your choice; when you save there, TigerMarkView notices, and
your reload mode decides what happens next.

Choose the editor under **Tools > Editor**:

- **System Default** — whatever Windows opens `.md` files with.
- **Visual Studio Code** — found automatically if it is installed in the usual place.
- **Notepad3** — likewise.
- **Custom...** — any program you like. Give the path to its executable and an arguments template,
  where `{file}` stands for the document, for example `"{file}"`. If the template has no `{file}`, the
  path is added at the end.

If a preset editor is not installed, TigerMarkView says so when you try to use it and suggests
configuring a custom editor instead.

## PDF export

**File > Export to PDF...** turns the document into a PDF. You choose where to save it.

Two things are worth knowing:

- **It exports what you are looking at.** If the file changed on disk and you have not reloaded, the
  PDF contains the version you have read and reviewed, not the unseen newer one. Reload first if the
  newer version is what you want.
- **PDFs are always light.** Exporting while the dark theme is on still produces a black-on-white
  document, because that is what prints and shares sensibly.

No browser headers, footers, or page URLs are added. Tables, code blocks, and images are fitted to the
page.

### Page setup

**Tools > PDF Export Settings** holds four settings that apply to every export. They are remembered
between sessions, so exporting itself stays a single step: pick a file name and you are done.

| Setting | Choices | Default |
|---|---|---|
| Paper Size | A3, A4, A5, Letter, Legal | A4 |
| Orientation | Portrait, Landscape | Portrait |
| Margins | Narrow, Normal, Wide | Normal |
| Page Numbers | on or off | off |

**Margins** are three fixed choices rather than four boxes to fill in:

| Preset | Top and bottom | Left and right |
|---|---|---|
| Narrow | 12 mm | 10 mm |
| Normal | 18 mm | 16 mm |
| Wide | 25 mm | 25 mm |

**Page Numbers** puts a small number at the bottom centre of every page, starting at 1. It is printed
in the bottom margin, so it never overlaps your text; with Narrow margins the bottom margin grows
slightly (to 14 mm) to make room for it.

Changing any of these does not disturb what you are reading — the document is not reloaded, your place
is kept, and the file is not re-read from disk. Only the next PDF you export changes.

After a successful export the status bar shows where the file went, with two buttons beside it:

- **Open exported PDF** — opens it in your PDF reader.
- **Open containing folder** — shows it in Explorer. This one stays available afterwards, so you can
  get back to the last PDF you exported from the current document at any time in the session.

## Themes and window layout

- **View > Theme > Light / Dark** switches the whole application, document included. Your place in the
  document is kept, and the document is not re-read from disk.
- **View > Menu Bar**, **View > Toolbar**, and **View > Status Bar** hide or show those strips if you
  want a plainer window.

With the menu bar hidden, every menu is still one click away: the **☰** button at the left of the
toolbar opens the same File, Navigate, View, Reload Mode, Tools, and Help menus. Keyboard shortcuts —
`F1`, `Alt+Left`, `Alt+Right` — work either way.

The menu bar and the toolbar cannot both be hidden, so you are never left without a way to reach a
command. Whichever of the two is the last one showing stays ticked in the View menu and cannot be
switched off; show the other one first if you want to swap them. The **☰** button follows the same
rule — see *Toolbar buttons* below.

### Toolbar buttons

**View > Toolbar Buttons** decides which buttons the toolbar carries. Everything on that list is on
the menus whether or not you add it, so turning one on saves a click and never unlocks anything.

| Item | What appears |
|---|---|
| **Menu** | The **☰** button at the far left. On to begin with; see below for when it cannot be turned off. |
| **Open Recent** | A small chevron immediately right of the **Open** button. Clicking it drops down the same list as `File > Open Recent`, in the same order; the Open button itself still opens the file picker. |
| **Export to PDF** | A PDF button, doing exactly what `File > Export to PDF...` does. It wears the same icon as the status bar's *Open exported PDF* action, because they are about the same thing. |

The last two start off, so the toolbar you get is the compact one. Export to PDF is greyed out until a
document is open — the same moment its menu entry becomes available. Your choices are remembered
between sessions. The submenu is greyed out while the toolbar itself is hidden, since there is then no
toolbar to put a button on.

**Menu** is the one entry with a rule attached. With the menu bar hidden it is your only way to reach
the full command tree, so it stays ticked and greyed out until you bring the menu bar back — and, for
the same reason, **View > Menu Bar** is greyed out while the **☰** button is off. Turn the one you
want to keep back on first, and the other becomes available again.

This is the whole of toolbar customisation: a short list of named buttons. There is no reordering and
nothing else to configure.

The *File modified externally* strip is not on that list on purpose: it is the whole of what Confirm
mode does, and hiding it would leave a mode that quietly behaved like Manual. Use Manual mode if you
would rather not be prompted.

## Rendering options

**View > Rendering** holds two optional ways of rendering a document. Both are **off by default**, and
each can be turned on independently.

| Option | What it does |
|---|---|
| **Emoji Shortcodes** | Expands common `:name:` forms — `:rocket:`, `:warning:` — into the matching emoji. |
| **Syntax Highlighting** | Colours fenced code blocks whose language TigerMarkView recognises. |

**Emoji Shortcodes** only affects text you wrote as a shortcode. Emoji typed directly into the document
always appear whether the option is on or not, a shortcode nobody recognises is left exactly as
written, and shortcodes inside inline code or a code block are never touched.

**Syntax Highlighting** uses the language named on the fence, so ```` ```csharp ```` or ```` ```sql ````
is coloured and a fence with no language is not. Common short forms work — `cs` for C#, `js`, `ts`,
`py`. A language TigerMarkView does not know is left as an ordinary code block rather than guessed at,
so turning the option on can only ever add colour, never change how a listing reads. Colours follow the
light or dark theme on screen; a PDF always uses a palette designed for paper, whichever theme you are
reading in.

Changing either option re-renders what you are already looking at. Your place in the document is kept,
the file is not re-read from disk, and the times in the status bar do not change — so a document you
have reviewed stays the version you reviewed, and that is still the version a PDF will contain.

This help is not affected by either option: it is part of the application and always looks the same.

## What TigerMarkView remembers

Between sessions, TigerMarkView remembers:

- the theme (light or dark);
- the reload mode;
- the editor you chose, including a custom editor's path and arguments;
- your recent files;
- the page setup used by PDF export — paper size, orientation, margins, and page numbers;
- the rendering options — emoji shortcodes and syntax highlighting;
- the window's size, position, and whether it was maximized;
- whether the menu bar, toolbar, and status bar were showing;
- which optional toolbar buttons you added.

These are kept in a small settings file in your own user profile, under
`%LocalAppData%\TigerMarkView`. Deleting it resets TigerMarkView to its defaults; nothing else is
affected.

## Troubleshooting

**The file changed but the view did not.**
Check the reload mode. In Manual mode nothing reloads by itself, and in Confirm mode nothing reloads
until you press the reload button on the strip. Reload at any time with **File > Reload Now**.

**"Not found" when opening the editor.**
The preset editors are only found where their installers normally put them. If yours is somewhere
else — or is a different program entirely — set it up under **Tools > Editor > Custom...** with the
full path to its executable.

**The exported PDF is not where I left it.**
Use **Open containing folder** in the status bar to go straight to the last PDF exported from this
document. If it has been moved or deleted, export it again.

**An image in the document does not appear.**
Images are resolved relative to the Markdown file itself, exactly as they are on GitHub. Check that
the path in the document matches where the image really sits next to the file, and that the file name's
capitalisation and extension match.

**A link does nothing.**
Links to local files that are not Markdown are refused on purpose, with a note in the status bar. Web
links open in your default browser — if nothing happens, Windows may have no browser associated.

**The window came back in an odd place.**
TigerMarkView keeps a restored window inside a connected monitor's working area, so a window saved on
a screen you no longer have comes back centred instead of off the edge.
