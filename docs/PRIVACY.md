# TigerMarkView privacy statement

This statement covers the TigerMarkView desktop application, the `tiger-mark` command, and the
TigerMarkView installer, as released in one version. It describes what they store on your computer,
how to remove it, and the network requests they make.

TigerMarkView is published by IT Tiger (<https://www.ittiger.net/>).

Each release publishes the statement for that version as the `PRIVACY.md` file of its GitHub Release,
<https://github.com/rkozlowski/TigerMarkView/releases>, and never changes it afterwards. The installed
application carries the identical file in its `Docs` folder. A later version may change this statement;
its own release then carries the new one.

TigerMarkView is a viewer for Markdown files on your computer. It has no accounts, telemetry,
analytics, advertising, crash reporting of its own, or update checks, and it asks for and stores no
passwords, keys, or other credentials. TigerMarkView does not send your settings, your recent-file
history, or the documents you open to IT Tiger or to anyone else. It makes network requests only for
the web images a document refers to (on by default; you can turn them off), for a document you open
from another computer, and, in the installer, to obtain a missing Microsoft runtime; each is described
below. The Microsoft components it runs on have their own diagnostics, also described below.

## What TigerMarkView stores on your computer

Everything below is stored under your own Windows user profile.

**Settings** — `%LocalAppData%\TigerMarkView\settings.json`:

- the theme, the reload mode, and the rendering options (emoji shortcodes, syntax highlighting, and
  whether remote images load);
- the editor you chose, and a custom editor's path and arguments once you have entered them;
- the **Open Recent** list (see below);
- the PDF export page setup;
- the window's size and position and whether it was maximized, and which bars and optional toolbar
  buttons are showing.

If the settings file is damaged and cannot be understood, TigerMarkView starts with default settings
and keeps the damaged file beside the new one as `settings.json.invalid`, replacing any earlier one. If
the file exists but cannot be read at that moment, that window uses the defaults and leaves the file as
it is.

Every open TigerMarkView window uses this one settings file. A window saves only the setting you change
in it, on top of whatever the other windows have saved, and saves its own size and position when it
closes.

**Browser engine data** — `%LocalAppData%\TigerMarkView\WebView2\`. TigerMarkView displays documents
and exports PDFs with the Microsoft Edge WebView2 Runtime, which keeps its own working files there: the
`Viewer` folder for the viewer and Help, and the `Export` folder for PDF export and `tiger-mark`. The
browser engine runs in **InPrivate** mode, so it keeps no browsing history, cache, or other record of the
pages it shows on disk; what it holds while TigerMarkView runs is discarded when the last window closes.
What remains in these folders is the engine's own runtime data, such as components it downloaded and
graphics caches, which names no document — except that if the engine itself crashes, it can keep a
crash report there, which can include part of the page it was showing (see **The WebView2 Runtime and
Windows** below).

Earlier versions of TigerMarkView ran the browser engine with an ordinary profile, which kept a browsing
history of the pages it had shown — for every document viewed or exported, its file name (the page title)
and the time — together with a cache. This version deletes that profile the first time it starts, and
the `Export` one the first time it exports a PDF. If an older TigerMarkView window is still open then,
the deletion is tried again the next time.

**Generated pages** — `%TEMP%\TigerMarkView\`. Each window writes the rendered page of the document it is
showing to `preview-<number>.html` there, where the number identifies the window's process: a copy of the
document's text as shown, which also names the folder the document is in. The window deletes it when it
closes. Help uses `help-<number>.html` the same way and deletes it when Help closes. If a window ends
without closing normally, its page stays until TigerMarkView next starts and deletes it, Windows'
temporary-file cleanup removes it, or you uninstall. PDF export prints from a temporary page under
`%TEMP%\TigerMarkView\pdf\`, which is deleted when the export ends; if the export is interrupted, the page
can remain there until cleanup or uninstalling.

**Not stored:** TigerMarkView's own navigation history (**Navigate > History**, Back and Forward)
exists only while the window is open and is forgotten when you close it. Which PDF you last exported
from a document is also remembered for the current session only.

The `tiger-mark` command stores no settings and no recent files. It uses the browser engine's `Export`
folder and a temporary page under `%TEMP%\TigerMarkView\pdf\` that is deleted when the export ends.

**PDFs** are written only where you save them. `tiger-mark` writes beside the Markdown file unless you
name another output with `-o`; with `--timestamped-fallback` it can leave a PDF with a timestamp in its
name beside the target.

TigerMarkView itself keeps nothing in the registry. The installer's registrations are described under
**Uninstalling and upgrading**.

## Recent-file history

**File > Open Recent** lists up to 10 documents you opened explicitly — with **File > Open**, by
dragging a file onto the window, through **Open with** in Explorer, by naming a file on the command
line, or by choosing an entry from the list again. Each entry is the document's full path, including
the computer and share name for a document on a network share. Documents you reach only by following
a link are not added. The list is saved in the settings file so that it is available the next time you
start TigerMarkView.

An entry is kept until 10 newer documents push it out of the list, or until you clear the list.

To clear it, choose **File > Open Recent > Clear Recent Files**. The list is emptied at once and the
empty list is saved. Your documents themselves are not changed, moved, or deleted, and your other
settings are kept. The same command is at the end of the toolbar's Open Recent list when that button
is shown.

All open TigerMarkView windows share one list. A document opened in any window is added to it, and
clearing it in one window clears it for all of them: another window shows the current list when you
switch to it or open its menu, and saving its own settings never brings cleared entries back.

Windows itself keeps its own records of files and folders used with its standard Open dialog and in
**Recent** items in Explorer, as it does for every application. Those records belong to Windows;
clearing the Open Recent list or uninstalling TigerMarkView does not remove them.

## Uninstalling and upgrading

**Uninstalling** TigerMarkView — from **Settings > Apps**, with the uninstaller, or with
`winget uninstall` — removes the installed program files, its Start menu and desktop shortcuts, its
`PATH` entry, its registration as an app for Markdown files, and its Add/Remove Programs entry and
installation records. It then removes TigerMarkView's data for the Windows account that runs the
uninstall:

- `%LocalAppData%\TigerMarkView`, which holds the settings, the Open Recent list, and the browser engine
  data, including any history an earlier version's browser engine kept; and
- `%TEMP%\TigerMarkView`, which holds the generated pages.

An all-users installation is removed with administrator rights, and the data removed is that of the
account the uninstall runs as. Other people who used TigerMarkView on the same computer keep their own
`%LocalAppData%\TigerMarkView` folders; each of them can delete theirs.

If another program is still using a file in one of these folders, everything else is removed and that
file, with the folders that contain it, is left; the uninstall still completes and does not list what
remains. You can delete it yourself afterwards.

The uninstaller writes a log of its own steps, which names the installation's folders but none of your
documents, to `%TEMP%\TigerSetup\` and leaves it there for Windows' temporary-file cleanup; you can
also delete it yourself.

Uninstalling does not touch your Markdown documents, the PDFs you exported, a default app you chose for
Markdown files, or the .NET Desktop Runtime and WebView2 Runtime, which other applications may use.

**Upgrading** — installing a newer version over an installed one, including with `winget upgrade`,
and the first install of a newer version over TigerMarkView 0.9.0 or earlier — keeps your settings,
your Open Recent list, and the browser engine data; the browsing history an earlier version kept is
then deleted as described under **Browser engine data**.

TigerMarkView 0.10.0 and earlier did not remove this data when uninstalled. If you uninstalled one of
those versions, you can delete `%LocalAppData%\TigerMarkView` and `%TEMP%\TigerMarkView` yourself.

To reset TigerMarkView to its defaults without uninstalling it, close it and delete
`%LocalAppData%\TigerMarkView`.

## Network requests

**Web images in documents.** A Markdown document can refer to an image by an `http://` or `https://`
address, as many README files do for badges and screenshots. Loading these **remote images is on by
default**. While it is on, when TigerMarkView renders such a document — in the viewer and when exporting
a PDF — it requests each of those images from the address written in the document, and requests it
again whenever it renders the document again. A document without such an address causes no such
request.

To turn remote images off, clear **View > Rendering > Load Remote Images**. The choice is saved with
your settings and applies to every TigerMarkView window. While it is off, the viewer and PDF export
send no request for any `http://` or `https://` image — each is refused before anything leaves your
computer, and shown as a missing image — while images stored on your computer and images embedded in
the document itself still show. Turning it back on shows the remote images again. Help never requests
web images. The `tiger-mark` command has no settings: it always requests the web images of the document
it converts.

Each request goes to the web server the document names, and to any web server that server redirects it
to. The request carries the `Accept-Encoding` header and, as the browser engine supplies them, the
`Accept` and `User-Agent` headers, which identify the browser engine and the Windows version. It never
carries cookies or the name or location of the document, and it never carries a sign-in: your Windows
account is not offered to the web server, and an image that requires signing in does not load.

**Proxy servers.** If Windows or your environment configures a proxy server — the proxy settings of your
Windows account, including an automatic configuration script or automatic proxy detection, or the
`HTTP_PROXY`, `HTTPS_PROXY`, or `ALL_PROXY` environment variables — image requests go through that
proxy, which sees the address of each image. With automatic proxy detection, the proxy is whichever
server your network announces. TigerMarkView never offers a proxy your Windows account, and it never
asks for or stores a credential. If your proxy requires signing in, remote images do not load;
everything else in TigerMarkView works as usual. The one exception is a user name and password you have
written into one of those environment variables yourself (`http://name:password@proxy:port`): like other
programs that read them, TigerMarkView then sends them to that proxy.

As with any web request, the server that receives one can see your IP address and when the request was
made, and because the author of the document chose the address, a web image can tell its author or the
server's operator that the document was opened. These requests go to IT Tiger only if a document you
open itself refers to an image on an IT Tiger server.

Nothing else in a document is fetched automatically: scripts, frames, forms, stylesheets, fonts, and
media from a document are removed or blocked. Images on network shares are never requested, not even
when the document itself is on a share. Images stored on your computer are read from disk; if a file
is kept online only by a sync service such as OneDrive, that service downloads it when it is read, as
it does for any application.

**Documents on other computers.** Opening a document from a network share yourself — with
**File > Open**, by dragging it onto the window (outside a shown document), from Explorer, from Open
Recent, or by naming it on the command line — reads it from that computer, and watches it there for changes, as Windows reads any
network file: Windows connects to that computer and signs in to it with your Windows account.

A document never does this. While a document is shown, nothing in it can open a Markdown file on a
network share — including one on a mapped network drive, and one a relative link reaches inside a
document that is itself on a share: TigerMarkView says in the status bar that the link leads to a
network location and makes no connection. Dropping such a file onto the document area is refused the
same way, because it cannot be told apart from following a link; drop it on the window's menu bar,
toolbar or status bar, or use **File > Open**, to read it.

**Links.** A web or mail link you click in a document or in Help is opened by your default browser or
mail application; TigerMarkView does not load the linked page itself. Other kinds of links are refused.

**Help** is bundled with the application and works without a network connection.

**The installer** makes network requests only if the .NET Desktop Runtime 10 or the Microsoft Edge
WebView2 Runtime is missing, and only to obtain and install it. It downloads the runtime from the
download address that the Windows Package Manager (WinGet) community catalog lists for it, and installs
it only if the download matches the SHA-256 hash the catalog records. The installer carries that
address from the time it was built; when that is more than 14 days old, or the download fails, it first
reads the current catalog from Microsoft's WinGet server, `cdn.winget.microsoft.com`. The .NET runtime
is looked for in `%ProgramFiles%\dotnet`; a copy installed elsewhere is not found, and the runtime is
then obtained as if it were missing. Uninstalling and repairing make no network requests.

**The WebView2 Runtime and Windows.** The WebView2 Runtime is a Windows component that Microsoft
installs and keeps up to date. Running in TigerMarkView's browser engine folder, it can exchange data
with Microsoft on its own — for example to update its components, for security features, and, as your
Windows diagnostic data settings allow, to report its own crashes, which can include part of the page
that was shown. Windows can likewise report an application crash. TigerMarkView does not add to or
configure these exchanges; Microsoft's privacy statement describes them.

## Questions

Report questions or concerns about this statement at
<https://github.com/rkozlowski/TigerMarkView/issues>.
