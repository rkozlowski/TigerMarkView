namespace TigerMarkView.Cli;

/// <summary>
/// The process entry point. TigerCli takes it from here — see <see cref="TigerMarkApp"/>.
/// </summary>
internal static class Program
{
    private static Task<int> Main(string[] args) => TigerMarkApp.Create().RunAsync(args);
}
