using System.Reflection;
using TigerMarkView.Core.About;

namespace TigerMarkView.Core.Tests.About;

/// <summary>
/// The About line's formatting rule. The version <em>value</em> is not tested here and should not be —
/// it lives in Version.props, and a test asserting it would be a second place to update on
/// every release, which is exactly what having one canonical definition is meant to avoid.
/// </summary>
public class ApplicationVersionTests
{
    [Theory]
    [InlineData("0.8.0", "0.8.0")]
    [InlineData("1.0", "1.0")]
    [InlineData("  0.8.0  ", "0.8.0")]
    public void APlainVersionIsShownAsWritten(string informational, string expected)
    {
        Assert.Equal(expected, ApplicationVersion.Format(informational));
    }

    /// <summary>
    /// SemVer build metadata is provenance, not version: a build that stamps the commit hash into the
    /// informational version must not turn the About line into "0.8.0+3a91c7f".
    /// </summary>
    [Theory]
    [InlineData("0.8.0+3a91c7f", "0.8.0")]
    [InlineData("0.8.0-beta.2+3a91c7f", "0.8.0-beta.2")]
    public void BuildMetadataIsDropped(string informational, string expected)
    {
        Assert.Equal(expected, ApplicationVersion.Format(informational));
    }

    /// <summary>
    /// The four-part shape comes from the CLR's assembly version, used as a fallback. Its trailing zero
    /// is an artefact of that format rather than anything the project wrote.
    /// </summary>
    [Fact]
    public void AnAssemblyVersionsRedundantRevisionIsDropped()
    {
        Assert.Equal("0.8.0", ApplicationVersion.Format("0.8.0.0"));
    }

    [Theory]
    [InlineData("0.8.0.4")]      // a real fourth component says something; keep it
    [InlineData("0.8.0.x")]      // not the four-part numeric shape at all
    [InlineData("2026.1.0-rc1")] // prerelease, three parts
    public void AnythingThatIsNotThatShapeIsLeftAlone(string informational)
    {
        Assert.Equal(informational, ApplicationVersion.Format(informational));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("+3a91c7f")]
    public void AMissingVersionReadsAsUnknownRatherThanBlank(string? informational)
    {
        Assert.Equal(ApplicationVersion.Unknown, ApplicationVersion.Format(informational));
    }

    /// <summary>
    /// <see cref="ApplicationVersion.Of"/> is the one reader of assembly version metadata, shared by
    /// the GUI's About dialog and the CLI's <c>--version</c> so the two cannot disagree. As above, the
    /// value is not asserted — only that the build really stamped one and that it was formatted.
    /// </summary>
    [Fact]
    public void ReadingAnAssemblyReportsItsFormattedVersion()
    {
        var version = ApplicationVersion.Of(Assembly.GetExecutingAssembly());

        Assert.NotEqual(ApplicationVersion.Unknown, version);
        Assert.DoesNotContain('+', version);
    }

    [Fact]
    public void ReadingAnAssemblyRequiresOne()
    {
        Assert.Throws<ArgumentNullException>(() => ApplicationVersion.Of(null!));
    }
}
