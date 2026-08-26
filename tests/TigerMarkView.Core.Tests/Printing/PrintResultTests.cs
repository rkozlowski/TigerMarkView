using TigerMarkView.Core.Printing;

namespace TigerMarkView.Core.Tests.Printing;

/// <summary>
/// What the reader is told when a print does not work, and the one distinction that governs whether
/// they are told anything at all: a cancellation is a decision, not a failure.
/// </summary>
public class PrintResultTests
{
    [Fact]
    public void ASucceededDeviceStatusIsASuccess()
    {
        var result = PrintResult.For(PrintDeviceStatus.Succeeded, "Office Laser");

        Assert.True(result.Success);
        Assert.False(result.WasCancelled);
        Assert.Null(result.ErrorMessage);
    }

    /// <summary>
    /// "Not available" is only actionable if the reader knows which of their printers it is about.
    /// </summary>
    [Fact]
    public void AnUnavailablePrinterIsNamedAndSaysWhatToCheck()
    {
        var result = PrintResult.For(PrintDeviceStatus.PrinterUnavailable, "Office Laser");

        Assert.False(result.Success);
        Assert.False(result.WasCancelled);
        Assert.Contains("Office Laser", result.ErrorMessage);
        Assert.Contains("switched on", result.ErrorMessage);
    }

    [Fact]
    public void AnUnknownFailureStillNamesThePrinter()
    {
        var result = PrintResult.For(PrintDeviceStatus.OtherError, "Office Laser");

        Assert.False(result.Success);
        Assert.Contains("Office Laser", result.ErrorMessage);
    }

    /// <summary>
    /// A message that reads "  is not available" would be worse than useless, so an unnamed printer
    /// falls back to a phrase that still makes a sentence.
    /// </summary>
    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public void AnUnnamedPrinterStillProducesAReadableMessage(string printerName)
    {
        var result = PrintResult.For(PrintDeviceStatus.PrinterUnavailable, printerName);

        Assert.StartsWith("the printer", result.ErrorMessage);
    }

    /// <summary>
    /// Cancellation is not failure: nothing carries a message, because nothing is shown for it beyond a
    /// line in the status bar.
    /// </summary>
    [Fact]
    public void CancellationIsNeitherSuccessNorFailure()
    {
        var result = PrintResult.Cancelled();

        Assert.False(result.Success);
        Assert.True(result.WasCancelled);
        Assert.Null(result.ErrorMessage);
    }

    [Fact]
    public void AFailureIsNotACancellation()
    {
        var result = PrintResult.Failed("boom");

        Assert.False(result.Success);
        Assert.False(result.WasCancelled);
        Assert.Equal("boom", result.ErrorMessage);
    }

    /// <summary>Errors reach the reader as prose, never as a stack trace or an enum name.</summary>
    [Theory]
    [InlineData(PrintDeviceStatus.PrinterUnavailable)]
    [InlineData(PrintDeviceStatus.OtherError)]
    public void NoFailureMessageLeaksTheStatusName(PrintDeviceStatus status)
    {
        var message = PrintResult.For(status, "Office Laser").ErrorMessage!;

        Assert.DoesNotContain(status.ToString(), message, StringComparison.Ordinal);
        Assert.EndsWith(".", message, StringComparison.Ordinal);
    }
}
