using System;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Microsoft.Win32;

namespace PontenWPF
{
    public class SignatureDisplayItem : INotifyPropertyChanged
    {
        public SignatureItem Item { get; set; } = new();
        public BitmapImage? ImageSource { get; set; }

        public string DisplayName
        {
            get => string.IsNullOrWhiteSpace(Item.Name) ? "" : Item.Name;
            set
            {
                Item.Name = value;
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(DisplayName)));
            }
        }

        public event PropertyChangedEventHandler? PropertyChanged;
    }

    public partial class MenuBarView : Window
    {
        private SignatureStorage _storage = new SignatureStorage(E2EMode.DataDirectory);
        private ImageProcessor _manager = new ImageProcessor();
        private GlobalShortcutManager? _shortcutManager;
        private bool _suppressSelectionCopy;
        private DispatcherTimer? _statusTimer;

        public ObservableCollection<SignatureDisplayItem> DisplayItems { get; set; } = new();

        public MenuBarView()
        {
            InitializeComponent();
            this.Deactivated += MenuBarView_Deactivated;
            this.Loaded += MenuBarView_Loaded;
            this.SourceInitialized += MenuBarView_SourceInitialized;
            this.Closed += MenuBarView_Closed;

            SignaturesListBox.ItemsSource = DisplayItems;

            if (E2EMode.IsEnabled)
            {
                ShowInTaskbar = true;
            }
        }

        private void MenuBarView_SourceInitialized(object? sender, EventArgs e)
        {
            var helper = new System.Windows.Interop.WindowInteropHelper(this);
            _shortcutManager = new GlobalShortcutManager(helper.Handle);

            uint MOD_ALT = 0x0001;
            uint MOD_CONTROL = 0x0002;
            uint VK_S = 0x53;
            _shortcutManager.RegisterShortcut(9000, MOD_CONTROL | MOD_ALT, VK_S);
            if (!_shortcutManager.Success)
            {
                App.Log("Failed to register global hotkey Ctrl+Alt+S");
            }

            _shortcutManager.HotKeyPressed += () =>
            {
                Dispatcher.InvokeAsync(async () => await HandleHotKeyAsync());
            };
        }

        private async Task HandleHotKeyAsync()
        {
            if (DisplayItems.Count == 0 || !_storage.ActiveSignatureID.HasValue)
            {
                ShowAtBottomRight();
                return;
            }

            var active = DisplayItems.FirstOrDefault(d => d.Item.Id == _storage.ActiveSignatureID.Value);
            if (active?.ImageSource == null)
            {
                ShowAtBottomRight();
                return;
            }

            await CopyActiveSignatureToClipboard(_storage.Settings.AutoPaste, hideWindow: false);
        }

        private void MenuBarView_Closed(object? sender, EventArgs e)
        {
            _statusTimer?.Stop();
            _shortcutManager?.Dispose();
        }

        private void MenuBarView_Loaded(object sender, RoutedEventArgs e)
        {
            var version = System.Reflection.Assembly.GetExecutingAssembly().GetName().Version;
            VersionLabel.Text = $"v{version?.Major}.{version?.Minor}.{version?.Build}";
            LoadSignatures();
            LaunchAtLoginCheck.IsChecked = _storage.Settings.LaunchAtLogin;
            AutoPasteCheck.IsChecked = _storage.Settings.AutoPaste;
            RemoveBgToggle.IsChecked = _storage.Settings.RemoveBackground;

            if (E2EMode.IsEnabled)
            {
                ShowAtBottomRight();
            }
        }

        private void LoadSignatures()
        {
            DisplayItems.Clear();
            _storage.Load();

            foreach (var item in _storage.Signatures)
            {
                string path = _storage.GetSignatureFilePath(item.Filename);
                if (File.Exists(path))
                {
                    try
                    {
                        var bitmap = new BitmapImage();
                        bitmap.BeginInit();
                        bitmap.CacheOption = BitmapCacheOption.OnLoad;
                        bitmap.UriSource = new Uri(path);
                        bitmap.EndInit();

                        DisplayItems.Add(new SignatureDisplayItem { Item = item, ImageSource = bitmap });
                    }
                    catch (Exception ex)
                    {
                        App.Log($"Failed to load image for item {item.Filename}: {ex.Message}");
                    }
                }
            }

            EmptyStateText.Visibility = DisplayItems.Count == 0 ? Visibility.Visible : Visibility.Collapsed;

            if (_storage.ActiveSignatureID.HasValue)
            {
                var active = DisplayItems.FirstOrDefault(d => d.Item.Id == _storage.ActiveSignatureID.Value);
                if (active != null)
                {
                    _suppressSelectionCopy = true;
                    SignaturesListBox.SelectedItem = active;
                }
            }
        }

        private void MenuBarView_Deactivated(object? sender, EventArgs e)
        {
            if (E2EMode.IsEnabled)
            {
                return;
            }

            this.Hide();
        }

        public void ShowAtBottomRight()
        {
            this.UpdateLayout();

            var workArea = SystemParameters.WorkArea;
            double margin = 12;
            this.Left = workArea.Right - this.Width - margin;
            this.Top = workArea.Bottom - this.Height - margin;

            this.Show();
            this.Activate();
        }

        private void ShowStatus(string message)
        {
            StatusText.Text = message;
            StatusText.Visibility = Visibility.Visible;

            _statusTimer?.Stop();
            _statusTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2.5) };
            _statusTimer.Tick += (_, _) =>
            {
                StatusText.Text = "";
                StatusText.Visibility = Visibility.Collapsed;
                _statusTimer?.Stop();
            };
            _statusTimer.Start();
        }

        private SignatureDisplayItem? GetActiveDisplayItem()
        {
            if (SignaturesListBox.SelectedItem is SignatureDisplayItem selected)
            {
                return selected;
            }

            if (_storage.ActiveSignatureID.HasValue)
            {
                return DisplayItems.FirstOrDefault(d => d.Item.Id == _storage.ActiveSignatureID.Value);
            }

            return null;
        }

        private async Task CopyActiveSignatureToClipboard(bool autoPaste, bool hideWindow = true)
        {
            var active = GetActiveDisplayItem();
            if (active?.ImageSource == null)
            {
                return;
            }

            try
            {
                Clipboard.SetImage(active.ImageSource);
                ShowStatus("Signature copied ✓");

                if (hideWindow)
                {
                    Hide();
                }

                if (autoPaste)
                {
                    await Task.Delay(150);
                    await Dispatcher.InvokeAsync(() => _manager.AutoPaste());
                }
            }
            catch (Exception ex)
            {
                App.Log($"Clipboard error: {ex.Message}");
            }
        }

        private void SignaturesListBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (SignaturesListBox.SelectedItem is not SignatureDisplayItem selected)
            {
                return;
            }

            _storage.SetActiveSignature(selected.Item.Id);

            if (_suppressSelectionCopy)
            {
                _suppressSelectionCopy = false;
                return;
            }

            if (selected.ImageSource != null)
            {
                _ = CopyActiveSignatureToClipboard(_storage.Settings.AutoPaste);
            }
        }

        private async void SignButton_Click(object sender, RoutedEventArgs e)
        {
            if (DisplayItems.Count == 0)
            {
                MessageBox.Show("Add a signature first", "Ponten", MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }

            if (SignaturesListBox.SelectedItem is SignatureDisplayItem selected && selected.ImageSource != null)
            {
                await CopyActiveSignatureToClipboard(_storage.Settings.AutoPaste);
                return;
            }

            if (_storage.ActiveSignatureID.HasValue)
            {
                var active = DisplayItems.FirstOrDefault(d => d.Item.Id == _storage.ActiveSignatureID.Value);
                if (active != null)
                {
                    _suppressSelectionCopy = true;
                    SignaturesListBox.SelectedItem = active;
                    await CopyActiveSignatureToClipboard(_storage.Settings.AutoPaste);
                }
            }
        }

        private void DrawSignature_Click(object sender, RoutedEventArgs e)
        {
            TriggerDrawSignature();
        }

        private void RemoveSignature_Click(object sender, RoutedEventArgs e)
        {
            if (SignaturesListBox.SelectedItem is not SignatureDisplayItem selected)
            {
                return;
            }

            var result = MessageBox.Show(
                "Are you sure you want to remove this signature?",
                "Remove Signature",
                MessageBoxButton.YesNo,
                MessageBoxImage.Question);

            if (result != MessageBoxResult.Yes)
            {
                return;
            }

            _storage.RemoveSignature(selected.Item.Id);
            LoadSignatures();
        }

        private static SignatureDisplayItem? GetSignatureDisplayItemFromMenuItem(MenuItem menuItem)
        {
            if (menuItem.DataContext is SignatureDisplayItem displayItem)
            {
                return displayItem;
            }

            if (menuItem.Parent is ContextMenu { PlacementTarget: ListBoxItem listBoxItem })
            {
                return listBoxItem.DataContext as SignatureDisplayItem;
            }

            return null;
        }

        private void EditSignature_Click(object sender, RoutedEventArgs e)
        {
            if (sender is not MenuItem menuItem)
            {
                return;
            }

            var displayItem = GetSignatureDisplayItemFromMenuItem(menuItem);
            if (displayItem == null)
            {
                return;
            }

            string path = _storage.GetSignatureFilePath(displayItem.Item.Filename);
            if (!File.Exists(path))
            {
                MessageBox.Show("Signature file not found.", "Edit Signature", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }

            try
            {
                using var loaded = new Bitmap(path);
                using var normalized = _manager.Ensure32bpp(loaded);
                bool removeBg = RemoveBgToggle.IsChecked ?? true;
                OpenImageEditor(normalized, removeBg, processedBmp =>
                {
                    string savePath = _storage.GetSignatureFilePath(displayItem.Item.Filename);
                    using (var ms = new MemoryStream())
                    {
                        processedBmp.Save(ms, System.Drawing.Imaging.ImageFormat.Png);
                        ImageProcessor.WritePngAtomic(savePath, ms.ToArray());
                    }
                    processedBmp.Dispose();
                    LoadSignatures();
                });
            }
            catch (Exception ex)
            {
                MessageBox.Show($"Failed to load signature: {ex.Message}", "Edit Signature", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        private void RenameSignature_Click(object sender, RoutedEventArgs e)
        {
            if (sender is not MenuItem menuItem)
            {
                return;
            }

            var displayItem = GetSignatureDisplayItemFromMenuItem(menuItem);
            if (displayItem == null)
            {
                return;
            }

            string? newName = InputDialog.Show(this, "Rename Signature", "Name:", displayItem.Item.Name ?? "");
            if (newName == null)
            {
                return;
            }

            displayItem.DisplayName = newName.Trim();
            _storage.SaveIndex();
        }

        private void Grid_DragOver(object sender, DragEventArgs e)
        {
            if (e.Data.GetDataPresent(DataFormats.FileDrop))
            {
                var files = (string[]?)e.Data.GetData(DataFormats.FileDrop);
                if (files != null && files.Any(IsSupportedImageFile))
                {
                    e.Effects = DragDropEffects.Copy;
                    e.Handled = true;
                    return;
                }
            }

            e.Effects = DragDropEffects.None;
            e.Handled = true;
        }

        private void Grid_Drop(object sender, DragEventArgs e)
        {
            if (!e.Data.GetDataPresent(DataFormats.FileDrop))
            {
                return;
            }

            var files = (string[]?)e.Data.GetData(DataFormats.FileDrop);
            var file = files?.FirstOrDefault(IsSupportedImageFile);
            if (file == null)
            {
                return;
            }

            ImportImageFromPath(file);
        }

        private static bool IsSupportedImageFile(string path)
        {
            string ext = Path.GetExtension(path).ToLowerInvariant();
            return ext is ".png" or ".jpg" or ".jpeg" or ".bmp" or ".tiff";
        }

        private void ImportImageFromPath(string filePath)
        {
            try
            {
                using var loaded = new Bitmap(filePath);
                using var normalized = _manager.Ensure32bpp(loaded);
                if (!_manager.ValidateWhiteBackground(normalized))
                {
                    MessageBox.Show("Image edges must be predominantly white or transparent.", "Invalid Image", MessageBoxButton.OK, MessageBoxImage.Warning);
                    ShowAtBottomRight();
                    return;
                }

                bool removeBg = RemoveBgToggle.IsChecked ?? true;
                OpenImageEditor(normalized, removeBg, processedBmp =>
                {
                    var id = Guid.NewGuid();
                    string filename = $"{id}.png";
                    string path = _storage.GetSignatureFilePath(filename);

                    using (var ms = new MemoryStream())
                    {
                        processedBmp.Save(ms, System.Drawing.Imaging.ImageFormat.Png);
                        ImageProcessor.WritePngAtomic(path, ms.ToArray());
                    }
                    processedBmp.Dispose();

                    _storage.AddSignature(new SignatureItem { Id = id, Filename = filename });
                    LoadSignatures();
                });
            }
            catch (Exception ex)
            {
                MessageBox.Show($"Failed to load image: {ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
                ShowAtBottomRight();
            }
        }

        private void OpenImageEditor(Bitmap normalized, bool removeBg, Action<Bitmap> onSave)
        {
            this.Hide();
            bool saved = false;
            var editor = new ImageEditorWindow(normalized);
            editor.RemoveBgCheckBox.IsChecked = removeBg;
            editor.OnSave += processedBmp =>
            {
                saved = true;
                onSave(processedBmp);
            };
            editor.Closed += (_, _) =>
            {
                if (!saved)
                {
                    Dispatcher.InvokeAsync(ShowAtBottomRight);
                }
            };
            editor.Show();
        }

        private void LaunchAtLoginCheck_Click(object sender, RoutedEventArgs e)
        {
            _storage.ApplyLaunchAtLogin(LaunchAtLoginCheck.IsChecked ?? false);
        }

        private void AutoPasteCheck_Click(object sender, RoutedEventArgs e)
        {
            _storage.Settings.AutoPaste = AutoPasteCheck.IsChecked ?? false;
            _storage.SaveIndex();
        }

        private void RemoveBgToggle_Changed(object sender, RoutedEventArgs e)
        {
            if (!IsLoaded)
            {
                return;
            }

            _storage.Settings.RemoveBackground = RemoveBgToggle.IsChecked ?? true;
            _storage.SaveIndex();
        }

        private async void CheckUpdates_Click(object sender, RoutedEventArgs e)
        {
            var version = System.Reflection.Assembly.GetExecutingAssembly().GetName().Version;
            var currentVersionText = $"v{version?.Major}.{version?.Minor}.{version?.Build}";

            try
            {
                var updater = new Updater();
                var result = await updater.CheckForUpdateAsync();

                if (!string.IsNullOrEmpty(result.ErrorMessage))
                {
                    MessageBox.Show(result.ErrorMessage, "Update", MessageBoxButton.OK, MessageBoxImage.Warning);
                    return;
                }

                if (result.IsNewerAvailable && !string.IsNullOrEmpty(result.DownloadUrl))
                {
                    var response = MessageBox.Show(
                        $"A new version (v{result.LatestVersion}) is available. You are on {currentVersionText}. Download and install now?",
                        "Update Available",
                        MessageBoxButton.YesNo,
                        MessageBoxImage.Information);

                    if (response == MessageBoxResult.Yes)
                    {
                        await updater.DownloadUpdateAndExecute(result.DownloadUrl);
                        Application.Current.Shutdown();
                    }

                    return;
                }

                MessageBox.Show(
                    $"Ponten is up to date ({currentVersionText}).",
                    "Update",
                    MessageBoxButton.OK,
                    MessageBoxImage.Information);
            }
            catch (Exception ex)
            {
                App.LogException("Update check failed", ex);
                MessageBox.Show("Update check failed. Check your network connection.", "Update", MessageBoxButton.OK, MessageBoxImage.Warning);
            }
        }

        private void Quit_Click(object sender, RoutedEventArgs e)
        {
            Application.Current.Shutdown();
        }

        public void TriggerAddSignature()
        {
            AddSignature_Click(this, new RoutedEventArgs());
        }

        public void TriggerDrawSignature()
        {
            this.Hide();
            bool saved = false;
            var drawWin = new DrawSignatureWindow();
            drawWin.OnSave += (bitmap) =>
            {
                saved = true;
                SaveSignatureBitmap(bitmap);
            };
            drawWin.Closed += (_, _) =>
            {
                if (!saved)
                {
                    Dispatcher.InvokeAsync(ShowAtBottomRight);
                }
            };
            drawWin.Show();
        }

        private void SaveSignatureBitmap(Bitmap bitmap)
        {
            var id = Guid.NewGuid();
            string filename = $"{id}.png";
            string path = _storage.GetSignatureFilePath(filename);

            using (var ms = new MemoryStream())
            {
                bitmap.Save(ms, System.Drawing.Imaging.ImageFormat.Png);
                ImageProcessor.WritePngAtomic(path, ms.ToArray());
            }
            bitmap.Dispose();

            _storage.AddSignature(new SignatureItem { Id = id, Filename = filename });
            LoadSignatures();
        }

        private void AddSignature_Click(object sender, RoutedEventArgs e)
        {
            this.Hide();

            var openFileDialog = new OpenFileDialog
            {
                Filter = "Image Files (*.png;*.jpeg;*.jpg;*.bmp;*.tiff)|*.png;*.jpeg;*.jpg;*.bmp;*.tiff|All files (*.*)|*.*",
                Title = "Select a Signature Image"
            };

            if (openFileDialog.ShowDialog() != true)
            {
                ShowAtBottomRight();
                return;
            }

            ImportImageFromPath(openFileDialog.FileName);
        }
    }
}