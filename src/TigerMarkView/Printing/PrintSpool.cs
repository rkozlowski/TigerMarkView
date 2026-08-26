using System;
using System.IO;
using TigerMarkView.Core.Printing;

namespace TigerMarkView.Printing;

/// <summary>
/// The folder the temporary print PDFs live in, and the filesystem half of their lifecycle.
/// </summary>
/// <remarks>
/// <para>
/// The same split as <see cref="Settings.SettingsStore"/>: <see cref="PrintJobFiles"/> in Core knows
/// the naming and staleness <em>rules</em>, this knows they live under
/// <c>%TEMP%\TigerMarkView\Print</c> and how to create and delete them. Nothing here is ever written
/// beside the reader's Markdown, into the application directory, or over a file TigerMarkView did not
/// create — every name carries a GUID, so two prints in one session, or in two running copies of the
/// application, cannot collide.
/// </para>
/// <para>
/// <strong>Lifecycle.</strong> A print PDF is deleted as soon as the operation it belongs to ends —
/// printed, failed, or cancelled at the printer dialog — because the print is finished when
/// <c>PdfPrinter.PrintAsync</c> returns and nothing else holds the file. <see cref="SweepStale"/> is
/// only for what a crash leaves behind, and every operation here is best-effort: a temp file that
/// cannot be deleted is not a reason to fail a print, still less to take the application down.
/// </para>
/// </remarks>
internal sealed class PrintSpool
{
    private readonly string _tempRoot;
    private readonly string _directory;

    public PrintSpool() : this(Path.GetTempPath())
    {
    }

    public PrintSpool(string tempRoot)
    {
        _tempRoot = tempRoot;
        _directory = PrintJobFiles.DirectoryIn(tempRoot);
    }

    /// <summary>
    /// Creates the folder if needed and returns a fresh, unused path to print
    /// <paramref name="markdownPath"/> to. Throws only if the folder itself cannot be made — which is a
    /// real failure the reader has to be told about, since there is then nowhere to print from.
    /// </summary>
    public string CreateJobPath(string? markdownPath)
    {
        Directory.CreateDirectory(_directory);

        return PrintJobFiles.PathIn(_tempRoot, markdownPath, Guid.NewGuid());
    }

    /// <summary>Deletes a finished print job's PDF. Best-effort by design — see the type remarks.</summary>
    public void Discard(string? path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return;
        }

        try
        {
            File.Delete(path);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException
                                       or NotSupportedException or System.Security.SecurityException)
        {
            // Left for SweepStale to collect on a later run.
        }
    }

    /// <summary>
    /// Deletes print PDFs old enough to be crash residue. Called once at startup, off the UI thread,
    /// and swallows everything: an unreadable temp folder must never stop the application starting.
    /// </summary>
    public void SweepStale(DateTime nowUtc)
    {
        try
        {
            if (!Directory.Exists(_directory))
            {
                return;
            }

            foreach (var path in Directory.EnumerateFiles(_directory))
            {
                if (PrintJobFiles.IsStale(path, File.GetLastWriteTimeUtc(path), nowUtc))
                {
                    Discard(path);
                }
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException
                                       or NotSupportedException or System.Security.SecurityException)
        {
            // Nothing to do and nothing worth telling the reader: the files are temporary either way.
        }
    }
}
