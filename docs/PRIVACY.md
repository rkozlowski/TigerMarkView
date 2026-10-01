# TigerMarkView privacy statement

This statement covers the TigerMarkView desktop application, the `tiger-mark` command, and the
TigerMarkView installer. It describes what they store on your computer, how to remove it, and the
network requests they make. Each release links the copy of this statement that ships in that
release's source, and the installed application carries the same copy in its `Docs` folder.

TigerMarkView is a local Markdown viewer. It has no accounts, telemetry, analytics, crash reporting,
advertising, or automatic update checks. It does not send your settings, your recent-file history, or
the documents you open to IT Tiger or to anyone else.

## What TigerMarkView stores on your computer

Everything below is stored in your own Windows user profile and stays on your computer.

**Settings** — `%LocalAppData%\TigerMarkView\settings.json`:

- the theme, the reload mode, and the rendering options;
- the editor you chose, including a custom editor's path and arguments;
- the **Open Recent** list (see below);
- the PDF export page setup;
- the window's size and position, and which bars and optional toolbar buttons are showing.

If a settings file ever cannot be read, it is kept beside the new one as `settings.json.invalid` so
that you can inspect it.

**Browser engine data** — `%LocalAppData%\TigerMarkView\WebView2\`. TigerMarkView displays documents
and exports PDFs with the Microsoft Edge WebView2 Runtime, which keeps its working data (such as
caches) in these folders.

**Generated pages** — `%TEMP%\TigerMarkView\`. The rendered page of the document you are viewing is
written to `preview.html` there and stays after you close the application, until it is replaced by
the next document, removed by Windows' temporary-file cleanup, or removed by uninstalling. Help uses
`help.html` the same way. The temporary page PDF export prints from is deleted when the export ends.

**Not stored:** the navigation history (**Navigate > History**, Back and Forward) exists only while
the application is running and is forgotten when you close it. Which PDF you last exported from a
document is also remembered for the current session only.

The `tiger-mark` command stores no settings and no recent files. It uses the same browser engine
folder and a temporary page under `%TEMP%\TigerMarkView` that is deleted when the export ends.

PDFs you export are written only where you choose to save them.

## Recent-file history

**File > Open Recent** lists up to 10 documents you opened explicitly — with **File > Open**, by
dragging a file onto the window, through **Open with** in Explorer, by naming a file on the command
line, or by choosing an entry from the list again. Each entry is the document's full path. Documents
you reach only by following a link are not added. The list is saved in the settings file so that it
is available the next time you start TigerMarkView.

An entry is kept until 10 newer documents push it out of the list, or until you clear the list.

To clear it, choose **File > Open Recent > Clear Recent Files**. The list is emptied at once and the
empty list is saved. Your documents themselves are not changed, moved, or deleted, and your other
settings are kept. The same command is at the end of the toolbar's Open Recent list when that button
is shown.

Windows itself keeps its own records of files and folders used with its standard Open dialog and in
**Recent** items in Explorer, as it does for every application. Those records belong to Windows;
clearing the Open Recent list or uninstalling TigerMarkView does not remove them.

## Uninstalling and upgrading

**Uninstalling** TigerMarkView — from **Settings > Apps**, with the uninstaller, or with
`winget uninstall` — removes the installed program files, its Start menu and desktop shortcuts, its
`PATH` entry, its registration as an app for Markdown files, and the installer's own records. It then
removes TigerMarkView's data for the Windows account that runs the uninstall:

- `%LocalAppData%\TigerMarkView`, which holds the settings, the Open Recent list, and the browser engine
  data; and
- `%TEMP%\TigerMarkView`, which holds the generated pages.

An all-users installation is removed with administrator rights, and the data removed is that of the
account the uninstall runs as. Other people who used TigerMarkView on the same computer keep their own
`%LocalAppData%\TigerMarkView` folders; each of them can delete theirs. If another program is still
using a file in one of these folders, the uninstall completes without removing that folder, and you
can delete it yourself.

Uninstalling does not touch your Markdown documents, the PDFs you exported, or a default app you chose
for Markdown files.

**Upgrading** — installing a newer version over an installed one, including with `winget upgrade`,
and the first install of a newer version over TigerMarkView 0.9.0 or earlier — keeps your settings and
your Open Recent list.

TigerMarkView 0.10.0 and earlier did not remove this data when uninstalled. If you uninstalled one of
those versions, you can delete `%LocalAppData%\TigerMarkView` and `%TEMP%\TigerMarkView` yourself.

To reset TigerMarkView to its defaults without uninstalling it, close it and delete
`%LocalAppData%\TigerMarkView`.

## Network requests

**Web images in documents.** A Markdown document can refer to an image by an `http://` or `https://`
address, as many README files do for badges and screenshots. When TigerMarkView renders such a
document — in the viewer, when exporting a PDF, and with `tiger-mark` — it requests each of those
images from the address written in the document, and may request it again whenever it renders the
document again. The request goes to the server the document names, and to any server that server
redirects it to, through your system proxy if one is configured.

These requests carry the image request headers a browser would send (`Accept` and `User-Agent`, which
identify the browser engine and the Windows version). They never carry cookies, Windows sign-in
credentials, or the name or location of the document. As with any web request, the server that
receives one can see your IP address and when the request was made, and because the author of the
document chose the address, a web image can tell its author or the server's operator that the
document was opened. These requests go to IT Tiger only if a document you open itself refers to an
image on an IT Tiger server.

Nothing else in a document can make a network request: scripts, frames, forms, stylesheets, fonts, and
media from a document are removed or blocked. Images on network shares are never requested. Images
stored on your computer are read from disk.

**Links.** A web or mail link you click in a document or in Help is handed to your default browser or
mail application; TigerMarkView does not contact that address itself.

**Help** is bundled with the application and works without a network connection.

**The installer** downloads the .NET Desktop Runtime or the Microsoft Edge WebView2 Runtime from
Microsoft only if one of them is missing, and only to install it. It makes no other network
requests.

**The WebView2 Runtime** is a Windows component that Microsoft installs and keeps up to date. What
that component itself exchanges with Microsoft is described by Microsoft's privacy statement, not by
this one.

## Questions

Report questions or concerns about this statement at
<https://github.com/rkozlowski/TigerMarkView/issues>.
