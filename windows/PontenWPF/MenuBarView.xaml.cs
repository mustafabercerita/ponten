using System;
using System.Collections.ObjectModel;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Media.Imaging;
using Microsoft.Win32;

namespace PontenWPF
{
    public class SignatureDisplayItem
    {
        public SignatureItem Item { get; set; } = new();
        public BitmapImage? ImageSource { get; set; }
    }

    public partial class MenuBarView : Window
    {
        private SignatureStorage _storage = new SignatureStorage();
        private SignatureManager _manager = new SignatureManager();
        private GlobalShortcutManager? _shortcutManager;
        public ObservableCollection<SignatureDisplayItem> DisplayItems { get; set; } = new();

        public MenuBarView()
        {
            InitializeComponent();
            this.Deactivated += MenuBarView_Deactivated;
            this.Loaded += MenuBarView_Loaded;
            this.SourceInitialized += MenuBarView_SourceInitialized;
            this.Closed += MenuBarView_Closed;
            
            SignaturesListBox.ItemsSource = DisplayItems;
        }

        private void MenuBarView_SourceInitialized(object? sender, EventArgs e)
        {
            var helper = new System.Windows.Interop.WindowInteropHelper(this);
            _shortcutManager = new GlobalShortcutManager(helper.Handle);
            
            // Register Ctrl(2) + Alt(1) + S(0x53)
            uint MOD_ALT = 0x0001;
            uint MOD_CONTROL = 0x0002;
            uint VK_S = 0x53;
            _shortcutManager.RegisterShortcut(9000, MOD_CONTROL | MOD_ALT, VK_S);
            
            _shortcutManager.HotKeyPressed += () => 
            {
                // Auto-paste active signature
                if (_storage.ActiveSignatureID.HasValue)
                {
                    var active = DisplayItems.FirstOrDefault(d => d.Item.Id == _storage.ActiveSignatureID.Value);
                    if (active?.ImageSource != null)
                    {
                        try
                        {
                            Clipboard.SetImage(active.ImageSource);
                            _manager.AutoPaste();
                        }
                        catch (Exception) { /* Handle clipboard error gracefully */ }
                    }
                }
            };
        }

        private void MenuBarView_Closed(object? sender, EventArgs e)
        {
            _shortcutManager?.Dispose();
        }

        private void MenuBarView_Loaded(object sender, RoutedEventArgs e)
        {
            LoadSignatures();
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
                    SignaturesListBox.SelectedItem = active;
                }
            }
        }

        private void MenuBarView_Deactivated(object? sender, EventArgs e)
        {
            // Hide the window when user clicks outside
            this.Hide();
        }

        public void ShowAtBottomRight()
        {
            // Ensure layout is updated to get actual width/height
            this.UpdateLayout();

            var workArea = SystemParameters.WorkArea;
            
            // Calculate bottom right corner with a small margin (e.g., 12 pixels)
            double margin = 12;
            this.Left = workArea.Right - this.Width - margin;
            this.Top = workArea.Bottom - this.Height - margin;

            this.Show();
            this.Activate();
        }

        private void SignaturesListBox_SelectionChanged(object sender, System.Windows.Controls.SelectionChangedEventArgs e)
        {
            if (SignaturesListBox.SelectedItem is SignatureDisplayItem selected)
            {
                _storage.SetActiveSignature(selected.Item.Id);
                
                // Copy to clipboard
                if (selected.ImageSource != null)
                {
                    try
                    {
                        Clipboard.SetImage(selected.ImageSource);
                        
                        // Hide to restore focus to previous window, then paste
                        this.Hide();
                        System.Threading.Tasks.Task.Delay(100).ContinueWith(_ => 
                        {
                            _manager.AutoPaste();
                        });
                    }
                    catch (Exception) { /* Handle clipboard error gracefully */ }
                }
            }
        }

        public void TriggerAddSignature()
        {
            AddSignature_Click(this, new RoutedEventArgs());
        }

        public void TriggerDrawSignature()
        {
            this.Hide();
            var drawWin = new DrawSignatureWindow();
            drawWin.OnSave += (bitmap) => 
            {
                var id = Guid.NewGuid();
                string filename = $"{id}.png";
                string path = _storage.GetSignatureFilePath(filename);
                
                bitmap.Save(path, System.Drawing.Imaging.ImageFormat.Png);
                bitmap.Dispose();
                
                _storage.AddSignature(new SignatureItem { Id = id, Filename = filename });
                LoadSignatures();
            };
            drawWin.Show();
        }

        private void AddSignature_Click(object sender, RoutedEventArgs e)
        {
            this.Hide();
            
            var openFileDialog = new OpenFileDialog
            {
                Filter = "Image Files (*.png;*.jpeg;*.jpg;*.bmp;*.tiff)|*.png;*.jpeg;*.jpg;*.bmp;*.tiff|All files (*.*)|*.*",
                Title = "Select a Signature Image"
            };

            if (openFileDialog.ShowDialog() == true)
            {
                try
                {
                    using var original = new Bitmap(openFileDialog.FileName);
                    if (!_manager.ValidateWhiteBackground(original))
                    {
                        MessageBox.Show("Image edges must be predominantly white or transparent.", "Invalid Image", MessageBoxButton.OK, MessageBoxImage.Warning);
                        return;
                    }

                    // Open ImageEditorWindow to fine-tune thickness/remove background
                    var editor = new ImageEditorWindow(original);
                    editor.OnSave += (processedBmp) => 
                    {
                        var id = Guid.NewGuid();
                        string filename = $"{id}.png";
                        string path = _storage.GetSignatureFilePath(filename);
                        
                        processedBmp.Save(path, System.Drawing.Imaging.ImageFormat.Png);
                        processedBmp.Dispose();
                        
                        _storage.AddSignature(new SignatureItem { Id = id, Filename = filename });
                        LoadSignatures();
                    };
                    editor.Show();
                }
                catch (Exception ex)
                {
                    MessageBox.Show($"Failed to load image: {ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
                }
            }
        }
    }
}
