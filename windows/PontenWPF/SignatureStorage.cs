using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;

namespace PontenWPF
{
    public class SignatureItem
    {
        public Guid Id { get; set; }
        public string Filename { get; set; } = "";
        public string? Name { get; set; }
    }

    public class UserSettings
    {
        public bool LaunchAtLogin { get; set; } = false;
        public bool AutoPaste { get; set; } = true;
    }

    public class IndexWrapper
    {
        public List<SignatureItem> Items { get; set; } = new();
        public Guid? ActiveID { get; set; }
        public UserSettings Settings { get; set; } = new();
    }

    public class SignatureStorage
    {
        private readonly string _storageDirectory;
        private readonly string _indexPath;

        public List<SignatureItem> Signatures { get; private set; } = new();
        public Guid? ActiveSignatureID { get; set; }
        public UserSettings Settings { get; set; } = new();

        public SignatureStorage(string? customStorageDirectory = null)
        {
            if (!string.IsNullOrEmpty(customStorageDirectory))
            {
                _storageDirectory = customStorageDirectory;
            }
            else
            {
                _storageDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Ponten");
            }
            _indexPath = Path.Combine(_storageDirectory, "index.json");
            Directory.CreateDirectory(_storageDirectory);
            Load();
        }

        public string GetSignatureFilePath(string filename)
        {
            return Path.Combine(_storageDirectory, filename);
        }

        public void Load()
        {
            if (File.Exists(_indexPath))
            {
                try
                {
                    string json = File.ReadAllText(_indexPath);
                    var wrapper = JsonSerializer.Deserialize<IndexWrapper>(json, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
                    if (wrapper != null)
                    {
                        Signatures = wrapper.Items;
                        ActiveSignatureID = wrapper.ActiveID;
                        if (wrapper.Settings != null) Settings = wrapper.Settings;
                    }
                }
                catch (Exception ex)
                {
                    App.Log($"Failed to load index.json: {ex.Message}");
                }
            }
            
            // Clean up missing files from the index
            bool changed = false;
            for (int i = Signatures.Count - 1; i >= 0; i--)
            {
                if (!File.Exists(GetSignatureFilePath(Signatures[i].Filename)))
                {
                    Signatures.RemoveAt(i);
                    changed = true;
                }
            }

            if (!Signatures.Any(s => s.Id == ActiveSignatureID))
            {
                ActiveSignatureID = Signatures.FirstOrDefault()?.Id;
                changed = true;
            }

            if (changed) SaveIndex();
        }

        public void SaveIndex()
        {
            var wrapper = new IndexWrapper
            {
                Items = Signatures,
                ActiveID = ActiveSignatureID,
                Settings = Settings
            };
            try
            {
                string json = JsonSerializer.Serialize(wrapper, new JsonSerializerOptions { WriteIndented = true });
                File.WriteAllText(_indexPath, json);
            }
            catch (Exception ex)
            {
                App.Log($"Failed to save index.json: {ex.Message}");
            }
        }

        public void AddSignature(SignatureItem item)
        {
            Signatures.Add(item);
            ActiveSignatureID = item.Id;
            SaveIndex();
        }

        public void RemoveSignature(Guid id)
        {
            var item = Signatures.FirstOrDefault(s => s.Id == id);
            if (item != null)
            {
                Signatures.Remove(item);
                string path = GetSignatureFilePath(item.Filename);
                if (File.Exists(path))
                {
                    try { File.Delete(path); }
                    catch (Exception ex) { App.Log($"Failed to delete signature image {path}: {ex.Message}"); }
                }
                
                if (ActiveSignatureID == id)
                {
                    ActiveSignatureID = Signatures.FirstOrDefault()?.Id;
                }
                SaveIndex();
            }
        }
        
        public void SetActiveSignature(Guid id)
        {
            if (Signatures.Any(s => s.Id == id))
            {
                ActiveSignatureID = id;
                SaveIndex();
            }
        }

        public void ApplyLaunchAtLogin(bool launch)
        {
            Settings.LaunchAtLogin = launch;
            SaveIndex();
            try
            {
                using var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", true);
                if (key != null)
                {
                    string appName = "PontenSignatures";
                    if (launch)
                    {
                        string exePath = System.Diagnostics.Process.GetCurrentProcess().MainModule?.FileName ?? "";
                        if (!string.IsNullOrEmpty(exePath))
                        {
                            key.SetValue(appName, $"\"{exePath}\"");
                        }
                    }
                    else
                    {
                        key.DeleteValue(appName, false);
                    }
                }
            }
            catch (Exception ex)
            {
                App.Log($"Failed to set Launch at Login: {ex.Message}");
            }
        }
    }
}
