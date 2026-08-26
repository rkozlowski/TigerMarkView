using System.ComponentModel;

namespace TigerMarkView.Cli;

/// <summary>
/// What <c>tiger-mark</c> reports to the shell. Four values, deliberately: a script needs to know
/// whether the PDF was written, and it is worth separating "you typed the command wrong" from "the
/// command was fine but the conversion failed", because only the first is worth re-reading the usage
/// text over.
/// </summary>
/// <remarks>
/// The numeric values are the process exit codes and are the CLI's published contract — they are the
/// ones <c>tiger-mark</c> has always returned. TigerCli resolves them through the policy
/// <see cref="TigerMarkApp"/> configures and documents this enum under <c>--help-errors</c>, reading
/// the <see cref="DescriptionAttribute"/> text below. That is why there is no hand-written exit-code
/// section anywhere: one declaration, documented where the reader asks for it.
/// </remarks>
internal enum TigerMarkExitCode
{
    /// <summary>The PDF was written.</summary>
    [Description("The PDF was written.")]
    Success = 0,

    /// <summary>The command was understood but could not be carried out.</summary>
    [Description("The command was understood but the PDF could not be created.")]
    ConversionFailed = 1,

    /// <summary>The command line itself was wrong: unknown option, no input file, two inputs.</summary>
    [Description("The command line was wrong: an unknown option, a bad value, or no input file.")]
    UsageError = 2,

    /// <summary>Ctrl+C. Distinct from <see cref="ConversionFailed"/> because nothing went wrong.</summary>
    [Description("Interrupted before the PDF was written.")]
    Cancelled = 3,
}
