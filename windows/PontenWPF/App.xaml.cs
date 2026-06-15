using System.Configuration;
using System.Data;
using System.Windows;
using System.Threading;
using System.IO;
using System;
using H.NotifyIcon;

namespace PontenWPF;

public partial class App : Application
{
    private TaskbarIcon? notifyIcon;
    private static Mutex? _mutex;
    private const string MutexName = "PontenWPF.SingleInstance";

    protected override void OnStartup(StartupEventArgs e)
    {
        Log("App startup initiated");
        Log($"Version: {System.Reflection.Assembly.GetExecutingAssembly().GetName().Version}");
        
        bool createdNew;
        _mutex = new Mutex(true, MutexName, out createdNew);

        if (!createdNew)
        {
            Log("Another instance is already running. Exiting.");
            Application.Current.Shutdown();
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
            notifyIcon = (TaskbarIcon)FindResource("NotifyIcon");
            Log("Tray icon initialized successfully");
        }
        catch (Exception ex)
        {
            Log($"Failed to initialize Tray Icon: {ex}");
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
        Log($"App shutting down with exit code: {e.ApplicationExitCode}");
        notifyIcon?.Dispose();
        _mutex?.ReleaseMutex();
        _mutex?.Dispose();
        base.OnExit(e);
    }
}
