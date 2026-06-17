using System.Collections;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Text;
using System.Text.Json;
using FlaUI.Core;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Conditions;
using FlaUI.UIA3;
using PontenWPF;

namespace PontenWPF.E2E.Tests;

public sealed class E2ETestFixture : IDisposable
{
    public string DataDirectory { get; }
    public UIA3Automation Automation { get; }
    public Application Application { get; }

    public E2ETestFixture(string? dataDirectory = null)
    {
        DataDirectory = dataDirectory ?? Path.Combine(Path.GetTempPath(), "PontenE2E_" + Guid.NewGuid().ToString());
        Directory.CreateDirectory(DataDirectory);

        KillStalePontenProcesses();
        Automation = new UIA3Automation();
        Application = LaunchApp(DataDirectory);
    }

    private static void KillStalePontenProcesses()
    {
        foreach (var process in Process.GetProcessesByName("PontenWPF"))
        {
            try
            {
                if (!process.HasExited)
                {
                    process.Kill(entireProcessTree: true);
                    process.WaitForExit(3000);
                }
            }
            catch
            {
                // Best-effort cleanup between E2E runs.
            }
        }
    }

    public static string ResolveAppExecutable()
    {
        var configuration = Environment.GetEnvironmentVariable("CONFIGURATION") ?? "Release";
        var candidates = new[]
        {
            Path.Combine(AppContext.BaseDirectory, "PontenWPF.exe"),
            Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "PontenWPF", "bin", configuration, "net8.0-windows", "PontenWPF.exe")),
            Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "PontenWPF", "bin", "Debug", "net8.0-windows", "PontenWPF.exe")),
            Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "PontenWPF", "bin", "Release", "net8.0-windows", "PontenWPF.exe")),
        };

        foreach (var candidate in candidates)
        {
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }

        throw new FileNotFoundException("PontenWPF.exe not found. Build the solution before running E2E tests.");
    }

    private static Application LaunchApp(string dataDirectory)
    {
        var exePath = ResolveAppExecutable();
        var startInfo = new ProcessStartInfo
        {
            FileName = exePath,
            Arguments = $"--e2e --data-dir=\"{dataDirectory}\"",
            WorkingDirectory = Path.GetDirectoryName(exePath) ?? AppContext.BaseDirectory,
            UseShellExecute = false
        };

        // UseShellExecute=false does not inherit the parent environment.
        foreach (DictionaryEntry entry in Environment.GetEnvironmentVariables())
        {
            if (entry.Key is string key && entry.Value is string value)
            {
                startInfo.Environment[key] = value;
            }
        }

        startInfo.Environment["PONTEN_E2E"] = "1";
        startInfo.Environment["PONTEN_DATA_DIR"] = dataDirectory;

        var process = Process.Start(startInfo)
            ?? throw new InvalidOperationException($"Failed to start Ponten at {exePath}");

        if (!process.WaitForInputIdle(15_000))
        {
            throw new TimeoutException($"Ponten process {process.Id} did not become idle.");
        }

        if (process.HasExited)
        {
            throw new InvalidOperationException(
                $"Ponten exited immediately with code {process.ExitCode}. Another instance may be holding the mutex.");
        }

        return Application.Attach(process);
    }

    public Window WaitForMainWindow(TimeSpan? timeout = null)
    {
        timeout ??= TimeSpan.FromSeconds(20);
        var deadline = DateTime.UtcNow.Add(timeout.Value);

        while (DateTime.UtcNow < deadline)
        {
            if (Application.HasExited)
            {
                throw new InvalidOperationException(
                    $"Ponten exited before showing the main window (exit code {Application.ExitCode}). {ReadLaunchDiagnostics()}");
            }

            var window = FindPontenWindow(Application.GetAllTopLevelWindows(Automation))
                ?? FindPontenWindow(Automation.GetDesktop().FindAllChildren(cf => cf.ByControlType(FlaUI.Core.Definitions.ControlType.Window)));
            if (window != null)
            {
                return window.AsWindow();
            }

            Thread.Sleep(200);
        }

        throw new TimeoutException($"Ponten main window was not found. {ReadLaunchDiagnostics()}");
    }

    private string ReadLaunchDiagnostics()
    {
        var builder = new StringBuilder();
        builder.Append($"ProcessId={Application.ProcessId}; ");

        var logPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Ponten", "logs", "app.log");
        if (File.Exists(logPath))
        {
            var lines = File.ReadAllLines(logPath);
            var tail = lines.TakeLast(5);
            builder.Append("LogTail=");
            builder.Append(string.Join(" | ", tail));
        }

        return builder.ToString();
    }

    private static AutomationElement? FindPontenWindow(IEnumerable<AutomationElement> windows)
    {
        foreach (var window in windows)
        {
            if (window.Name == "Ponten Menu"
                || window.Properties.AutomationId.ValueOrDefault == "PontenMenu")
            {
                return window;
            }
        }

        return null;
    }

    public AutomationElement RequireElement(
        Window window,
        Func<ConditionFactory, ConditionBase> condition,
        TimeSpan? timeout = null)
    {
        timeout ??= TimeSpan.FromSeconds(10);
        var deadline = DateTime.UtcNow.Add(timeout.Value);

        while (DateTime.UtcNow < deadline)
        {
            var element = window.FindFirstDescendant(condition);
            if (element != null)
            {
                return element;
            }

            Thread.Sleep(200);
        }

        throw new TimeoutException("Required UI element was not found.");
    }

    public AutomationElement RequireTextContaining(
        Window window,
        string substring,
        TimeSpan? timeout = null)
    {
        timeout ??= TimeSpan.FromSeconds(10);
        var deadline = DateTime.UtcNow.Add(timeout.Value);

        while (DateTime.UtcNow < deadline)
        {
            foreach (var text in window.FindAllDescendants(cf => cf.ByControlType(FlaUI.Core.Definitions.ControlType.Text)))
            {
                if (text.Name?.Contains(substring, StringComparison.OrdinalIgnoreCase) == true)
                {
                    return text;
                }
            }

            Thread.Sleep(200);
        }

        throw new TimeoutException($"Text containing '{substring}' was not found.");
    }

    public FlaUI.Core.AutomationElements.CheckBox WaitForCheckBoxChecked(
        Window window,
        string label,
        TimeSpan? timeout = null)
    {
        timeout ??= TimeSpan.FromSeconds(10);
        var deadline = DateTime.UtcNow.Add(timeout.Value);

        while (DateTime.UtcNow < deadline)
        {
            var checkBox = window.FindFirstDescendant(
                cf => cf.ByControlType(FlaUI.Core.Definitions.ControlType.CheckBox).And(cf.ByName(label)))?.AsCheckBox();

            if (checkBox?.IsChecked == true)
            {
                return checkBox;
            }

            Thread.Sleep(200);
        }

        throw new TimeoutException($"Checkbox '{label}' was not checked.");
    }

    public static void AssertAutoPastePersisted(string dataDirectory)
    {
        var indexPath = Path.Combine(dataDirectory, "index.json");
        Assert.True(File.Exists(indexPath), "index.json was not created.");

        var json = File.ReadAllText(indexPath);
        Assert.Contains("\"AutoPaste\": true", json, StringComparison.Ordinal);
    }

    public void WaitForAutoPasteEnabled(string dataDirectory, TimeSpan? timeout = null)
    {
        timeout ??= TimeSpan.FromSeconds(5);
        var deadline = DateTime.UtcNow.Add(timeout.Value);
        var indexPath = Path.Combine(dataDirectory, "index.json");

        while (DateTime.UtcNow < deadline)
        {
            if (File.Exists(indexPath))
            {
                var json = File.ReadAllText(indexPath);
                if (json.Contains("\"AutoPaste\": true", StringComparison.Ordinal))
                {
                    return;
                }
            }

            Thread.Sleep(100);
        }

        throw new TimeoutException("AutoPaste setting was not persisted to index.json.");
    }

    public static void SeedSignature(string dataDirectory, string name = "Test Signature")
    {
        Directory.CreateDirectory(dataDirectory);

        var signatureId = Guid.NewGuid();
        var filename = $"{signatureId}.png";
        var imagePath = Path.Combine(dataDirectory, filename);

        using (var bitmap = new Bitmap(160, 80))
        using (var graphics = Graphics.FromImage(bitmap))
        {
            graphics.Clear(Color.White);
            using var pen = new Pen(Color.Black, 3);
            graphics.DrawLine(pen, 20, 50, 140, 30);
            bitmap.Save(imagePath, ImageFormat.Png);
        }

        var wrapper = new IndexWrapper
        {
            Items =
            [
                new SignatureItem
                {
                    Id = signatureId,
                    Filename = filename,
                    Name = name
                }
            ],
            ActiveID = signatureId,
            Settings = new UserSettings()
        };

        var indexPath = Path.Combine(dataDirectory, "index.json");
        File.WriteAllText(indexPath, JsonSerializer.Serialize(wrapper, new JsonSerializerOptions { WriteIndented = true }));
    }

    public void Dispose()
    {
        try
        {
            if (!Application.HasExited)
            {
                try
                {
                    Application.Close();
                    Application.WaitWhileBusy(TimeSpan.FromSeconds(5));
                }
                catch
                {
                    Application.Kill();
                }
            }

            if (!Application.HasExited)
            {
                Application.Kill();
                Application.WaitWhileBusy(TimeSpan.FromSeconds(5));
            }
        }
        catch
        {
            // Best-effort cleanup for flaky UI automation shutdown.
        }

        Application.Dispose();
        Automation.Dispose();

        if (Directory.Exists(DataDirectory))
        {
            try
            {
                Directory.Delete(DataDirectory, true);
            }
            catch
            {
                // Temp cleanup can fail if the app is still releasing file handles.
            }
        }
    }
}