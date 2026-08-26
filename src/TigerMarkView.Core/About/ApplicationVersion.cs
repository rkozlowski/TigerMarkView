using System.Reflection;

namespace TigerMarkView.Core.About;

/// <summary>
/// Turns the version string the build stamps into an assembly into the one line About shows.
/// </summary>
/// <remarks>
/// <para>
/// The version itself is not defined here and must never be: it lives in <c>Directory.Build.props</c>
/// and reaches the application as assembly metadata. This is only the formatting rule, which is in
/// Core because it is a pure string transformation worth testing and because <c>tiger-mark
/// --version</c> must match the GUI's About dialog.
/// </para>
/// <para>
/// Two things need trimming. An informational version may carry SemVer build metadata
/// (<c>0.8.0+3a91c7f</c>) once a build stamps the commit into it — real, but not what a reader wants
/// on an About line. And a caller falling back to the assembly version gets the CLR's four-part form
/// (<c>0.8.0.0</c>), whose trailing zero is noise the project never wrote.
/// </para>
/// </remarks>
public static class ApplicationVersion
{
    /// <summary>Shown when an assembly carries no version metadata at all, so About still reads sensibly.</summary>
    public const string Unknown = "unknown";

    /// <summary>
    /// The formatted version of <paramref name="assembly"/> as stamped by the build.
    /// </summary>
    /// <remarks>
    /// The informational version is the authoritative one — it is what <c>&lt;Version&gt;</c> in
    /// Directory.Build.props produces verbatim — but an assembly built without it should still report
    /// something true rather than "unknown", hence the assembly-version fallback. This is the one
    /// reader of that metadata, so the GUI's About dialog and the CLI's <c>--version</c> cannot drift.
    /// </remarks>
    public static string Of(Assembly assembly)
    {
        ArgumentNullException.ThrowIfNull(assembly);

        var informational = assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion;

        return Format(string.IsNullOrWhiteSpace(informational)
            ? assembly.GetName().Version?.ToString()
            : informational);
    }

    public static string Format(string? informationalVersion)
    {
        if (string.IsNullOrWhiteSpace(informationalVersion))
        {
            return Unknown;
        }

        var version = informationalVersion.Trim();

        // SemVer build metadata: everything from the '+' is provenance, not version.
        var metadata = version.IndexOf('+');
        if (metadata >= 0)
        {
            version = version[..metadata].Trim();
        }

        return version.Length == 0 ? Unknown : TrimRedundantRevision(version);
    }

    /// <summary>
    /// Drops the fourth component of a four-part numeric version when it is zero — the shape an
    /// assembly version has, rather than one anybody wrote. A prerelease suffix or a non-numeric part
    /// means this is not that shape, and the string is left exactly as it came.
    /// </summary>
    private static string TrimRedundantRevision(string version)
    {
        var parts = version.Split('.');

        if (parts.Length != 4 || parts[3] != "0" || !parts.All(IsAllDigits))
        {
            return version;
        }

        return string.Join('.', parts[..3]);
    }

    private static bool IsAllDigits(string part) => part.Length > 0 && part.All(char.IsAsciiDigit);
}
