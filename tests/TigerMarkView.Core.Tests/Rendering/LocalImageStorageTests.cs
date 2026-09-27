using TigerMarkView.Core.Rendering;

namespace TigerMarkView.Core.Tests.Rendering;

/// <summary>
/// The Windows storage check behind the image policy: a drive letter is local only when its device is
/// local storage and no path component is a link to network storage. Windows-only behaviour is
/// exercised on Windows; elsewhere the check defers to the path's shape.
/// </summary>
public class LocalImageStorageTests
{
    [Fact]
    public void AFileOnALocalVolumeIsLocalWhetherOrNotItExists()
    {
        var path = Path.GetTempFileName();
        try
        {
            Assert.True(LocalImageStorage.IsLocal(new Uri(path)));
            Assert.True(LocalImageStorage.IsLocal(new Uri(Path.Combine(Path.GetDirectoryName(path)!, "missing", "image.png"))));
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void ADriveLetterWithNoDeviceBehindItIsNotLocal()
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        var used = Environment.GetLogicalDrives().Select(drive => char.ToUpperInvariant(drive[0])).ToHashSet();
        var unused = "ZYXWVUTSRQPONMLKJIHGFED".FirstOrDefault(letter => !used.Contains(letter));
        if (unused == default)
        {
            return; // every letter is in use on this machine, so there is no absent drive to name
        }

        Assert.False(LocalImageStorage.IsLocal(new Uri($"file:///{unused}:/image.png")));
    }

    [Theory]
    [InlineData("file://server/share/image.png")]
    [InlineData("file:///%5C%5Cserver%5Cshare%5Cimage.png")]
    [InlineData("file://localhost/C:/image.png")]
    [InlineData("https://example.com/image.png")]
    public void OnlyADriveLetterPathCanBeLocalStorage(string uri)
    {
        Assert.False(LocalImageStorage.IsLocal(new Uri(uri)));
    }
}
