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
the web images a document refers to, for a document you open from another computer, and, in the
installer, to obtain a missing Microsoft runtime; each is described below. The Microsoft components it
runs on have their own diagnostics, also described below.

## What TigerMarkView stores on your computer

Everything below is stored under your own Windows user profile.

**Settings** — `%LocalAppData%\TigerMarkView\settings.json`:

- the theme, the reload mode, and the rendering options (emoji shortcodes and syntax highlighting);
- the editor you chose, and a custom editor's path and arguments once you have entered them;
- the **Open Recent** list (see below);
- the PDF export page setup;
- the window's size and position and whether it was maximized, and which bars and optional toolbar
  buttons are showing.

If the settings file is damaged and cannot be understood, TigerMarkView starts with default settings
and keeps the damaged file beside the new one as `settings.json.invalid`, replacing any earlier one. If
the file cannot be read at all, the defaults are used and replace it when TigerMarkView closes.

**Browser engine data** — `%LocalAppData%\TigerMarkView\WebView2\`. TigerMarkView displays documents
and exports PDFs with the Microsoft Edge WebView2 Runtime, which keeps its working data there: the
`Viewer` folder for the viewer and Help, and the `Export` folder for PDF export and `tiger-mark`. Like a
web browser profile, this data includes caches and a **browsing history of the pages the engine has
shown**: for every document you view or export, its file name (the page title) and the time. This
history is not shown anywhere in TigerMarkView, is not sent anywhere, and is kept until you delete the
folder or uninstall TigerMarkView. Clearing the Open Recent list does not clear it.

**Generated pages** — `%TEMP%\TigerMarkView\`. The rendered page of the document you are viewing is
written to `preview.html` there: a copy of the document's text as shown, which also names the folder
the document is in. It stays after you close the application, until it is replaced by the next document
or page, removed by Windows' temporary-file cleanup, or removed by uninstalling. Help uses `help.html`
the same way. PDF export prints from a temporary page under `%TEMP%\TigerMarkView\pdf\`, which is
deleted when the export ends; if the export is interrupted, the page can remain there until cleanup or
uninstalling.

**Not stored:** TigerMarkView's own navigation history (**Navigate > History**, Back and Forward)
exists only while the application is running and is forgotten when you close it, apart from the
browser engine's history described above. Which PDF you last exported from a document is also
remembered for the current session only.

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

Each open TigerMarkView window keeps its own copy of the list and saves all of its settings, that list
included, when you open a document, when you change a setting, and when it closes. Clear the list when
no other TigerMarkView window is open; otherwise another window can save its older list again.

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
  data with its history; and
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
your Open Recent list, and the browser engine data.

TigerMarkView 0.10.0 and earlier did not remove this data when uninstalled. If you uninstalled one of
those versions, you can delete `%LocalAppData%\TigerMarkView` and `%TEMP%\TigerMarkView` yourself.

To reset TigerMarkView to its defaults without uninstalling it, close it and delete
`%LocalAppData%\TigerMarkView`.

## Network requests

**Web images in documents.** A Markdown document can refer to an image by an `http://` or `https://`
address, as many README files do for badges and screenshots. When TigerMarkView renders such a
document — in the viewer, when exporting a PDF, and with `tiger-mark` — it requests each of those
images from the address written in the document, and requests it again whenever it renders the document
again. This happens whenever a document contains such an address; there is no setting that turns it
off, and a document without one causes no such request.

Each request goes to the web server the document names, and to any web server that server redirects it
to. The request carries the `Accept-Encoding` header and, as the browser engine supplies them, the
`Accept` and `User-Agent` headers, which identify the browser engine and the Windows version. It never
carries cookies or the name or location of the document, and the web server is never sent your Windows
sign-in: an image that requires signing in does not load.

**Proxy servers.** If Windows or your environment configures a proxy server — the proxy settings of your
Windows account, including an automatic configuration script or automatic proxy detection, or the
`HTTP_PROXY`, `HTTPS_PROXY`, or `ALL_PROXY` environment variables — image requests go through that
proxy, which sees the address of each image. If that proxy requires Windows authentication (Negotiate,
Kerberos, or NTLM), TigerMarkView signs in to the proxy with your Windows account, as other Windows
applications do. Only the proxy receives that sign-in; it is never passed to the image's web server.
With automatic proxy detection, the proxy is whichever server your network announces.

As with any web request, the server that receives one can see your IP address and when the request was
made, and because the author of the document chose the address, a web image can tell its author or the
server's operator that the document was opened. These requests go to IT Tiger only if a document you
open itself refers to an image on an IT Tiger server.

Nothing else in a document is fetched automatically: scripts, frames, forms, stylesheets, fonts, and
media from a document are removed or blocked. Images on network shares are never requested, not even
when the document itself is on a share. Images stored on your computer are read from disk; if a file
is kept online only by a sync service such as OneDrive, that service downloads it when it is read, as
it does for any application.

**Documents on other computers.** Opening a document from a network share — with **File > Open**, from
Explorer, from Open Recent, or by following a link in a document to a Markdown file on a share — reads
it from that computer, and watches it there for changes, as Windows reads any network file: Windows
connects to that computer and signs in to it with your Windows account. A link in a document can name
such a file, so check where a link leads before following it.

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
