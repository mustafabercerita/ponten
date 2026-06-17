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
    private bool _shownDispatcherError;
    private const string MutexName = "PontenWPF.SingleInstance";

    protected override void OnStartup(StartupEventArgs e)
    {
        E2EMode.Initialize(e.Args);
        Current.ShutdownMode = ShutdownMode.OnExplicitShutdown;
        
        Log("App startup initiated");
        if (E2EMode.IsEnabled)
        {
            Log($"E2E mode enabled. DataDirectory={(E2EMode.DataDirectory ?? "(default)")}");
        }
        string? exePath = Environment.ProcessPath ?? System.Diagnostics.Process.GetCurrentProcess().MainModule?.FileName;
        Log($"Version: {System.Reflection.Assembly.GetExecutingAssembly().GetName().Version}");
        
        string mutexName = E2EMode.IsEnabled && !string.IsNullOrEmpty(E2EMode.DataDirectory)
            ? $"PontenWPF.E2E.{E2EMode.DataDirectory.GetHashCode(StringComparison.OrdinalIgnoreCase):X8}"
            : MutexName;

        _mutex = new Mutex(true, mutexName, out _hasMutex);

        if (!_hasMutex)
        {
            Log("Another instance is already running. Exiting.");
            if (!E2EMode.IsEnabled)
            {
                MessageBox.Show(
                    "Ponten is already running in the system tray",
                    "Ponten",
                    MessageBoxButton.OK,
                    MessageBoxImage.Information);
            }
            Environment.Exit(0);
            return;
        }

        AppDomain.CurrentDomain.UnhandledException += (s, args) =>
        {
            if (args.ExceptionObject is Exception ex)
            {
                LogException("Unhandled Exception", ex);
            }
            else
            {
                Log("Unhandled Exception occurred");
            }
        };
        DispatcherUnhandledException += (s, args) =>
        {
            LogException("Dispatcher Unhandled Exception", args.Exception);

            if (IsNonFatalException(args.Exception))
            {
                args.Handled = true;
                return;
            }

            if (!_shownDispatcherError)
            {
                _shownDispatcherError = true;
                MessageBox.Show(
                    $"An unexpected error occurred: {args.Exception.Message}",
                    "Ponten",
                    MessageBoxButton.OK,
                    MessageBoxImage.Error);
            }

            args.Handled = false;
        };

        base.OnStartup(e);

        if (E2EMode.IsEnabled)
        {
            MainWindow = new MenuBarView();
            Log("Main Window created (E2E mode)");
            MainWindow.Show();
            MainWindow.Activate();
            return;
        }

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

            // Setup Context Menu
            var contextMenu = new System.Windows.Controls.ContextMenu();
            
            var openItem = new System.Windows.Controls.MenuItem { Header = "Open Ponten" };
            openItem.Click += (s, ev) => ShowMainWindow();
            contextMenu.Items.Add(openItem);
            
            var addSignItem = new System.Windows.Controls.MenuItem { Header = "Add Signature..." };
            addSignItem.Click += (s, ev) => 
            {
                (MainWindow as MenuBarView)?.TriggerAddSignature();
            };
            contextMenu.Items.Add(addSignItem);
            
            var drawSignItem = new System.Windows.Controls.MenuItem { Header = "Draw Signature..." };
            drawSignItem.Click += (s, ev) => 
            {
                (MainWindow as MenuBarView)?.TriggerDrawSignature();
            };
            contextMenu.Items.Add(drawSignItem);
            
            contextMenu.Items.Add(new System.Windows.Controls.Separator());
            
            var quitItem = new System.Windows.Controls.MenuItem { Header = "Quit Ponten" };
            quitItem.Click += (s, ev) => Current.Shutdown();
            contextMenu.Items.Add(quitItem);

            notifyIcon.ContextMenu = contextMenu;

            notifyIcon.TrayLeftMouseUp += NotifyIcon_TrayLeftMouseUp;
            
            Log("Calling ForceCreate(false)...");
            notifyIcon.ForceCreate(false);
            
            Log($"Tray icon instantiated. IsCreated: {notifyIcon.IsCreated}");
        }
        catch (Exception ex)
        {
            LogException("Failed to instantiate Tray Icon", ex);
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
                ShowMainWindow();
            }
        }
    }

    private void ShowMainWindow()
    {
        if (MainWindow is MenuBarView menuBarView)
        {
            menuBarView.ShowAtBottomRight();
        }
        else
        {
            MainWindow?.Show();
            MainWindow?.Activate();
        }
    }
    
    private static readonly object _logLock = new object();

    public static void Log(string message)
    {
        try
        {
            lock (_logLock)
            {
                string logDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Ponten", "logs");
                Directory.CreateDirectory(logDir);
                string logFile = Path.Combine(logDir, "app.log");
                string formattedMessage = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {SanitizeForLog(message)}{Environment.NewLine}";
                File.AppendAllText(logFile, formattedMessage);
            }
        }
        catch { /* Ignore logging failures */ }
    }

        public static void LogException(string context, Exception ex)
        {
            var inner = ex.InnerException != null ? $" Inner={ex.InnerException.GetType().Name}: {ex.InnerException.Message}" : "";
            Log($"{context}: {ex.GetType().Name} - {ex.Message}{inner}");
        }

    private static bool IsNonFatalException(Exception ex)
    {
        return ex is OperationCanceledException or System.IO.IOException;
    }

    private static string SanitizeForLog(string message)
    {
#if DEBUG
        return message;
#else
        if (string.IsNullOrEmpty(message))
        {
            return message;
        }

        string sanitized = message.Split(new[] { Environment.NewLine, "\n" }, StringSplitOptions.None)[0];
        sanitized = System.Text.RegularExpressions.Regex.Replace(
            sanitized,
            @"[A-Za-z]:\\[^\s]+|/[\w./-]+",
            "[path]");
        return sanitized;
#endif
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
