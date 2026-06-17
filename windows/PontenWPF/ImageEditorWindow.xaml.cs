using System;
using System.Drawing;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media.Imaging;

namespace PontenWPF
{
    public partial class ImageEditorWindow : Window
    {
        private ImageProcessor _imageProcessor = new ImageProcessor();
        private CancellationTokenSource? _debounceCts;
        private Bitmap? _originalImage;

        public Action<Bitmap>? OnSave { get; set; }
        private Bitmap? _currentProcessedBitmap;

        public ImageEditorWindow(Bitmap originalImage)
        {
            InitializeComponent();
            _originalImage = new Bitmap(originalImage);
            Loaded += OnWindowLoaded;
        }

        // Keep default constructor for backward compatibility if needed
        public ImageEditorWindow()
        {
            InitializeComponent();
            LoadDummyImage();
            Loaded += OnWindowLoaded;
        }

        private void OnWindowLoaded(object sender, RoutedEventArgs e)
        {
            DebounceUpdate();
        }

        private void LoadDummyImage()
        {
            _originalImage = new Bitmap(400, 300);
            using (Graphics g = Graphics.FromImage(_originalImage))
            {
                g.Clear(System.Drawing.Color.White);
                g.DrawString("Sample Signature", new System.Drawing.Font("Arial", 24), System.Drawing.Brushes.Black, new PointF(50, 100));
            }
        }

        private void SaveButton_Click(object sender, RoutedEventArgs e)
        {
            if (_currentProcessedBitmap != null)
            {
                OnSave?.Invoke(new Bitmap(_currentProcessedBitmap));
            }
            this.Close();
        }

        private void CancelButton_Click(object sender, RoutedEventArgs e)
        {
            this.Close();
        }

        private void OnSliderValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
        {
            DebounceUpdate();
        }

        private void OnCheckBoxChanged(object sender, RoutedEventArgs e)
        {
            DebounceUpdate();
        }

        private void DebounceUpdate()
        {
            if (!IsLoaded) return;

            _debounceCts?.Cancel();
            _debounceCts = new CancellationTokenSource();
            var token = _debounceCts.Token;

            if (ImageScale != null && ZoomSlider != null)
            {
                ImageScale.ScaleX = ZoomSlider.Value;
                ImageScale.ScaleY = ZoomSlider.Value;
            }

            int thickness = (int)(ThicknessSlider?.Value ?? 0);
            bool removeBg = RemoveBgCheckBox?.IsChecked ?? false;
            bool autoTrim = AutoTrimCheckBox?.IsChecked ?? false;
            double contrast = ContrastSlider?.Value ?? 1.0;
            double brightness = BrightnessSlider?.Value ?? 0.0;
            float angle = (float)(RotateSlider?.Value ?? 0);
            int padding = Math.Max(10, thickness + 12);

            Task.Run(async () =>
            {
                try
                {
                    await Task.Delay(100, token);
                    if (token.IsCancellationRequested) return;

                    await ProcessImageAsync(thickness, removeBg, autoTrim, contrast, brightness, angle, padding, token);
                }
                catch (OperationCanceledException)
                {
                }
                catch (Exception ex)
                {
                    App.Log($"Image processing error: {ex.Message}");
                }
            }, token);
        }

        private async Task ProcessImageAsync(
            int thickness,
            bool removeBg,
            bool autoTrim,
            double contrast,
            double brightness,
            float angle,
            int padding,
            CancellationToken token)
        {
            Bitmap processingBmp;
            lock (this)
            {
                if (_originalImage == null) return;
                processingBmp = new Bitmap(_originalImage);
            }

            try
            {
                var resultBmp = await Task.Run(() =>
                {
                    Bitmap current = processingBmp;
                    try
                    {
                        if (thickness > 0)
                        {
                            var dilated = _imageProcessor.Dilation(current, thickness);
                            if (current != processingBmp) current.Dispose();
                            current = dilated;
                        }

                        if (contrast != 1.0 || brightness != 0.0)
                        {
                            var adjusted = _imageProcessor.AdjustColor(current, contrast, brightness);
                            if (current != processingBmp) current.Dispose();
                            current = adjusted;
                        }

                        if (angle != 0)
                        {
                            var rotated = _imageProcessor.Rotate(current, angle);
                            if (current != processingBmp) current.Dispose();
                            current = rotated;
                        }

                        if (removeBg)
                        {
                            var stripped = _imageProcessor.StripWhiteBackground(current);
                            if (current != processingBmp) current.Dispose();
                            current = stripped;
                        }

                        if (autoTrim)
                        {
                            var trimmed = _imageProcessor.AutoTrimWhitespace(current, padding);
                            if (current != processingBmp) current.Dispose();
                            current = trimmed;
                        }

                        if (current == processingBmp)
                        {
                            current = new Bitmap(processingBmp);
                        }
                        return current;
                    }
                    catch
                    {
                        if (current != processingBmp) current?.Dispose();
                        throw;
                    }
                }, token);

                if (token.IsCancellationRequested)
                {
                    resultBmp?.Dispose();
                    return;
                }

                var imageSource = BitmapToImageSource(resultBmp);

                Application.Current.Dispatcher.Invoke(() =>
                {
                    if (_currentProcessedBitmap != null && _currentProcessedBitmap != _originalImage)
                    {
                        _currentProcessedBitmap.Dispose();
                    }
                    _currentProcessedBitmap = resultBmp;
                    PreviewImage.Source = imageSource;
                });
            }
            catch (Exception ex)
            {
                App.Log($"Image processing error: {ex.Message}");
            }
            finally
            {
                if (processingBmp != null)
                {
                    processingBmp.Dispose();
                }
            }
        }

        private BitmapImage BitmapToImageSource(Bitmap bitmap)
        {
            using (MemoryStream memory = new MemoryStream())
            {
                bitmap.Save(memory, System.Drawing.Imaging.ImageFormat.Png);
                memory.Position = 0;
                BitmapImage bitmapImage = new BitmapImage();
                bitmapImage.BeginInit();
                bitmapImage.StreamSource = memory;
                bitmapImage.CacheOption = BitmapCacheOption.OnLoad;
                bitmapImage.EndInit();
                bitmapImage.Freeze();
                return bitmapImage;
            }
        }

        protected override void OnClosed(EventArgs e)
        {
            _debounceCts?.Cancel();
            _debounceCts?.Dispose();
            lock (this)
            {
                _originalImage?.Dispose();
                _originalImage = null;
            }
            _currentProcessedBitmap?.Dispose();
            base.OnClosed(e);
        }
    }
}