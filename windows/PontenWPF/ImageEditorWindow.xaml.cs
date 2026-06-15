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
        private SignatureManager _signatureManager = new SignatureManager();
        private CancellationTokenSource? _debounceCts;
        private Bitmap? _originalImage;

        public Action<Bitmap>? OnSave { get; set; }
        private Bitmap? _currentProcessedBitmap;

        public ImageEditorWindow(Bitmap originalImage)
        {
            InitializeComponent();
            _originalImage = new Bitmap(originalImage);
            DebounceUpdate();
        }

        // Keep default constructor for backward compatibility if needed
        public ImageEditorWindow()
        {
            InitializeComponent();
            LoadDummyImage();
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
            if (ImageRotate != null && RotateSlider != null)
            {
                ImageRotate.Angle = RotateSlider.Value;
            }

            int thickness = (int)(ThicknessSlider?.Value ?? 0);
            bool removeBg = RemoveBgCheckBox?.IsChecked ?? false;
            
            Task.Run(async () =>
            {
                try
                {
                    await Task.Delay(100, token);
                    if (token.IsCancellationRequested) return;

                    await ProcessImageAsync(thickness, removeBg, token);
                }
                catch (TaskCanceledException)
                {
                }
            }, token);
        }

        private async Task ProcessImageAsync(int thickness, bool removeBg, CancellationToken token)
        {
            if (_originalImage == null) return;

            Bitmap processingBmp;
            lock (_originalImage)
            {
                processingBmp = new Bitmap(_originalImage);
            }

            try
            {
                var resultBmp = await Task.Run(() =>
                {
                    Bitmap current = processingBmp;

                    if (removeBg)
                    {
                        var stripped = _signatureManager.StripWhiteBackground(current);
                        if (current != processingBmp) current.Dispose();
                        current = stripped;
                    }

                    if (thickness > 0)
                    {
                        var dilated = _signatureManager.Dilation(current, thickness);
                        if (current != processingBmp) current.Dispose();
                        current = dilated;
                    }
                    
                    return current;
                }, token);

                if (token.IsCancellationRequested) return;

                var imageSource = BitmapToImageSource(resultBmp);

                Application.Current.Dispatcher.Invoke(() =>
                {
                    if (_currentProcessedBitmap != null && _currentProcessedBitmap != _originalImage)
                    {
                        _currentProcessedBitmap.Dispose();
                    }
                    _currentProcessedBitmap = new Bitmap(resultBmp);
                    PreviewImage.Source = imageSource;
                });
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

        private void UpdatePreviewAsync()
        {
            DebounceUpdate();
        }

        protected override void OnClosed(EventArgs e)
        {
            _originalImage?.Dispose();
            _currentProcessedBitmap?.Dispose();
            _debounceCts?.Dispose();
            base.OnClosed(e);
        }
    }
}
