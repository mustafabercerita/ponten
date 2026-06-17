namespace PontenWPF;

internal static class E2EMode
{
    public static bool IsEnabled { get; private set; }
    public static string? DataDirectory { get; private set; }

    public static void Initialize(string[]? args)
    {
        args ??= Array.Empty<string>();

        IsEnabled = args.Contains("--e2e")
            || string.Equals(Environment.GetEnvironmentVariable("PONTEN_E2E"), "1", StringComparison.Ordinal);

        DataDirectory = Environment.GetEnvironmentVariable("PONTEN_DATA_DIR");

        foreach (var arg in args)
        {
            if (arg.StartsWith("--data-dir=", StringComparison.Ordinal))
            {
                DataDirectory = arg["--data-dir=".Length..];
            }
        }
    }
}