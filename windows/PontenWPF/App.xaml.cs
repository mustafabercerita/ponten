using System.Configuration;
using System.Data;
using System.Windows;
using H.NotifyIcon;

namespace PontenWPF;

public partial class App : Application
{
    private TaskbarIcon? notifyIcon;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        notifyIcon = (TaskbarIcon)FindResource("NotifyIcon");
        MainWindow = new MainWindow();
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
    
    protected override void OnExit(ExitEventArgs e)
    {
        notifyIcon?.Dispose();
        base.OnExit(e);
    }
}
