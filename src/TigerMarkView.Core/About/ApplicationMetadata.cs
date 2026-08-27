using System.Reflection;

namespace TigerMarkView.Core.About;

/// <summary>
/// The small runtime view of product metadata authored by the build and consumed by application UI.
/// </summary>
public sealed record ApplicationMetadata(
    string ProductName,
    string Version,
    string Description,
    string Company,
    string Copyright,
    string LicenseIdentity,
    Uri? Website,
    Uri? Documentation,
    Uri? Repository,
    Uri? IssueTracker)
{
    /// <summary>Reads the SDK assembly attributes and canonical link metadata from one assembly.</summary>
    public static ApplicationMetadata FromAssembly(Assembly assembly)
    {
        ArgumentNullException.ThrowIfNull(assembly);

        var links = assembly.GetCustomAttributes<AssemblyMetadataAttribute>()
            .Where(attribute => !string.IsNullOrWhiteSpace(attribute.Key))
            .GroupBy(attribute => attribute.Key, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(
                group => group.Key,
                group => group.Select(attribute => attribute.Value)
                    .FirstOrDefault(value => !string.IsNullOrWhiteSpace(value)),
                StringComparer.OrdinalIgnoreCase);

        return new ApplicationMetadata(
            Read<AssemblyProductAttribute>(assembly, attribute => attribute.Product)
                ?? assembly.GetName().Name
                ?? "Application",
            ApplicationVersion.Of(assembly),
            Read<AssemblyDescriptionAttribute>(assembly, attribute => attribute.Description) ?? string.Empty,
            Read<AssemblyCompanyAttribute>(assembly, attribute => attribute.Company) ?? string.Empty,
            Read<AssemblyCopyrightAttribute>(assembly, attribute => attribute.Copyright) ?? string.Empty,
            ReadLink(links, "License") ?? string.Empty,
            ReadUri(links, "Website"),
            ReadUri(links, "Documentation", "ProjectUrl", "PackageProjectUrl"),
            ReadUri(links, "RepositoryUrl", "Repository", "SourceCodeUrl", "SourceCode"),
            ReadUri(links, "IssueTrackerUrl"));
    }

    private static string? Read<TAttribute>(Assembly assembly, Func<TAttribute, string?> select)
        where TAttribute : Attribute
    {
        var value = assembly.GetCustomAttribute<TAttribute>() is { } attribute ? select(attribute) : null;
        return string.IsNullOrWhiteSpace(value) ? null : value.Trim();
    }

    private static Uri? ReadUri(IReadOnlyDictionary<string, string?> metadata, params string[] keys)
    {
        var value = ReadLink(metadata, keys);
        return Uri.TryCreate(value, UriKind.Absolute, out var uri) &&
               (uri.Scheme == Uri.UriSchemeHttps || uri.Scheme == Uri.UriSchemeHttp)
            ? uri
            : null;
    }

    private static string? ReadLink(IReadOnlyDictionary<string, string?> metadata, params string[] keys)
    {
        foreach (var key in keys)
        {
            if (metadata.TryGetValue(key, out var value) && !string.IsNullOrWhiteSpace(value))
            {
                return value.Trim();
            }
        }

        return null;
    }
}
