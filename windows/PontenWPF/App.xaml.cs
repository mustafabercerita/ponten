using System.Configuration;
using System.Data;
using System.Windows;
using System.Threading;
using System.IO;
using System;
using System.Windows.Media.Imaging;
using H.NotifyIcon;

namespace PontenWPF;

public partial class App : Application
{
    private TaskbarIcon? notifyIcon;
    private static Mutex? _mutex;
    private bool _hasMutex;
    private const string MutexName = "PontenWPF.SingleInstance";

    protected override void OnStartup(StartupEventArgs e)
    {
        Current.ShutdownMode = ShutdownMode.OnExplicitShutdown;
        
        Log("App startup initiated");
        string? exePath = Environment.ProcessPath ?? System.Diagnostics.Process.GetCurrentProcess().MainModule?.FileName;
        Log($"Executable Path: {exePath ?? "null"}");
        Log($"Version: {System.Reflection.Assembly.GetExecutingAssembly().GetName().Version}");
        
        _mutex = new Mutex(true, MutexName, out _hasMutex);

        if (!_hasMutex)
        {
            Log("Another instance is already running. Exiting.");
            Environment.Exit(0);
            return;
        }

        AppDomain.CurrentDomain.UnhandledException += (s, args) =>
        {
            Log($"Unhandled Exception: {args.ExceptionObject}");
        };
        DispatcherUnhandledException += (s, args) =>
        {
            Log($"Dispatcher Unhandled Exception: {args.Exception}");
            args.Handled = true;
        };

        base.OnStartup(e);
        try 
        {
            Log("Extracting Associated Icon...");
            System.Drawing.Icon? sysIcon = null;
            
            if (!string.IsNullOrEmpty(exePath))
            {
                try 
                {
                    sysIcon = System.Drawing.Icon.ExtractAssociatedIcon(exePath);
                }
                catch (Exception iconEx)
                {
                    Log($"Warning: Failed to extract icon from {exePath}. {iconEx.Message}");
                }
            }

            notifyIcon = new TaskbarIcon
            {
                ToolTipText = "Ponten",
                Visibility = Visibility.Visible
            };

            if (sysIcon != null)
            {
                notifyIcon.Icon = sysIcon;
                Log("Using extracted sysIcon.");
            }
            else
            {
                notifyIcon.IconSource = new BitmapImage(new Uri("pack://application:,,,/Assets/Ponten.ico"));
                Log("Fallback to IconSource with BitmapImage.");
            }

            notifyIcon.TrayLeftMouseUp += NotifyIcon_TrayLeftMouseUp;
            
            Log("Calling ForceCreate(false)...");
            notifyIcon.ForceCreate(false);
            
            Log($"Tray icon instantiated. IsCreated: {notifyIcon.IsCreated}");
        }
        catch (Exception ex)
        {
            Log($"Failed to instantiate Tray Icon: {ex}");
            Log($"Stacktrace: {ex.StackTrace}");
        }
        
        MainWindow = new MenuBarView();
        Log("Main Window created");
    }

    private void NotifyIcon_TrayLeftMouseUp(object sender, RoutedEventArgs e)
    {
        if (MainWindow != null)
        {
            if (MainWindow.Visibility == Visibility.Visible)
            {
                MainWindow.Hide();
            }
            else
            {
                MainWindow.Show();
                MainWindow.Activate();
            }
        }
    }
    
    private void Log(string message)
    {
        try
        {
            string logDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Ponten", "logs");
            Directory.CreateDirectory(logDir);
            string logFile = Path.Combine(logDir, "app.log");
            string formattedMessage = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {message}{Environment.NewLine}";
            File.AppendAllText(logFile, formattedMessage);
        }
        catch { /* Ignore logging failures */ }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        if (_hasMutex)
        {
            Log($"App shutting down with exit code: {e.ApplicationExitCode}");
            notifyIcon?.Dispose();
            _mutex?.ReleaseMutex();
        }
        _mutex?.Dispose();
        base.OnExit(e);
    }
}
