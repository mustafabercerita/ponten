using System;
using System.Drawing;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace PontenWPF
{
    public partial class DrawSignatureWindow : Window
    {
        public Action<Bitmap>? OnSave { get; set; }

        public DrawSignatureWindow()
        {
            InitializeComponent();
            
            // Set default drawing attributes
            var defaultAttributes = new System.Windows.Ink.DrawingAttributes
            {
                Color = Colors.Black,
                Width = 3,
                Height = 3,
                FitToCurve = true
            };
            SignatureCanvas.DefaultDrawingAttributes = defaultAttributes;
        }

        private void Clear_Click(object sender, RoutedEventArgs e)
        {
            SignatureCanvas.Strokes.Clear();
        }

        private void Cancel_Click(object sender, RoutedEventArgs e)
        {
            this.Close();
        }

        private void Save_Click(object sender, RoutedEventArgs e)
        {
            if (SignatureCanvas.Strokes.Count == 0)
            {
                MessageBox.Show("Please draw a signature first.", "Empty Signature", MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }

            try
            {
                var bounds = SignatureCanvas.Strokes.GetBounds();
                if (bounds.IsEmpty) return;
                
                // Add padding
                int pad = 20;
                bounds.Inflate(pad, pad);
                
                var presentationSource = PresentationSource.FromVisual(this);
                double dpiX = 96.0;
                double dpiY = 96.0;
                if (presentationSource != null)
                {
                    dpiX = 96.0 * presentationSource.CompositionTarget.TransformToDevice.M11;
                    dpiY = 96.0 * presentationSource.CompositionTarget.TransformToDevice.M22;
                }

                int pixelWidth = Math.Max(1, (int)Math.Ceiling(bounds.Width * dpiX / 96.0));
                int pixelHeight = Math.Max(1, (int)Math.Ceiling(bounds.Height * dpiY / 96.0));
                
                var rtb = new RenderTargetBitmap(pixelWidth, pixelHeight, dpiX, dpiY, PixelFormats.Pbgra32);
                
                var drawingVisual = new DrawingVisual();
                using (var context = drawingVisual.RenderOpen())
                {
                    // Draw transparent background explicitly (not strictly required, but ensures explicit clearing)
                    context.DrawRectangle(System.Windows.Media.Brushes.Transparent, null, new Rect(0, 0, bounds.Width, bounds.Height));
                    
                    // Push offset so the top-left of the bounding box aligns with the top-left of the image
                    context.PushTransform(new TranslateTransform(-bounds.X, -bounds.Y));
                    SignatureCanvas.Strokes.Draw(context);
                    context.Pop();
                }
                
                rtb.Render(drawingVisual);
                
                using (var ms = new MemoryStream())
                {
                    var encoder = new PngBitmapEncoder();
                    encoder.Frames.Add(BitmapFrame.Create(rtb));
                    encoder.Save(ms);
                    
                    ms.Position = 0;
                    using (var tempBitmap = new Bitmap(ms))
                    {
                        var bitmap = new Bitmap(tempBitmap);
                        OnSave?.Invoke(bitmap);
                    }
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show($"Failed to save signature: {ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
            }
            finally
            {
                this.Close();
            }
        }
    }
}
