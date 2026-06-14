using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Navigation;
using System.Windows.Shapes;
using System.Windows.Ink;

namespace PontenWPF;

public partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        
        // Hide window initially so it acts as a tray popup
        Hide();
        UpdatePen();
    }

    private void ThicknessSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        UpdatePen();
    }

    private void StyleComboBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        UpdatePen();
    }

    private void UpdatePen()
    {
        if (SignatureCanvas == null || ThicknessSlider == null || StyleComboBox == null) return;
        
        double thickness = ThicknessSlider.Value;
        bool isCalligraphy = StyleComboBox.SelectedIndex == 1;

        DrawingAttributes attributes = new DrawingAttributes();
        attributes.Color = Colors.Black;
        
        if (isCalligraphy)
        {
            attributes.StylusTip = StylusTip.Rectangle;
            attributes.Width = thickness * 2;
            attributes.Height = thickness;
            attributes.StylusTipTransform = new Matrix(1, 1, -1, 1, 0, 0); // Rotate 45 degrees
        }
        else
        {
            attributes.StylusTip = StylusTip.Ellipse;
            attributes.Width = thickness;
            attributes.Height = thickness;
        }

        SignatureCanvas.DefaultDrawingAttributes = attributes;
    }
}
