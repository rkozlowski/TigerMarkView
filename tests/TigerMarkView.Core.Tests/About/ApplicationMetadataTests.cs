using TigerMarkView.Core.About;

namespace TigerMarkView.Core.Tests.About;

public class ApplicationMetadataTests
{
    [Fact]
    public void ShippedCoreAssemblyCarriesCanonicalProductMetadata()
    {
        var metadata = ApplicationMetadata.FromAssembly(typeof(ApplicationMetadata).Assembly);

        Assert.False(string.IsNullOrWhiteSpace(metadata.ProductName));
        Assert.False(string.IsNullOrWhiteSpace(metadata.Company));
        Assert.False(string.IsNullOrWhiteSpace(metadata.Copyright));
        Assert.Equal("MIT", metadata.LicenseIdentity);
        Assert.NotNull(metadata.Repository);
        Assert.NotNull(metadata.Documentation);
        Assert.NotNull(metadata.IssueTracker);
        Assert.NotNull(metadata.Website);
        Assert.Equal(metadata.Repository!.Host, metadata.IssueTracker!.Host);
        Assert.EndsWith("/issues", metadata.IssueTracker.AbsolutePath, StringComparison.Ordinal);
    }

    [Fact]
    public void ReadingMetadataRequiresAnAssembly()
    {
        Assert.Throws<ArgumentNullException>(() => ApplicationMetadata.FromAssembly(null!));
    }
}
