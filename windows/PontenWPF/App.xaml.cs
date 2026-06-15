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
        Log("App startup initiated");
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
            notifyIcon = new TaskbarIcon
            {
                IconSource = new BitmapImage(new Uri("pack://application:,,,/Assets/Ponten.ico")),
                ToolTipText = "Ponten",
                Visibility = Visibility.Visible
            };
            notifyIcon.TrayLeftMouseUp += NotifyIcon_TrayLeftMouseUp;
            Log("Tray icon instantiated and set to visible successfully");
        }
        catch (Exception ex)
        {
            Log($"Failed to instantiate Tray Icon: {ex}");
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
