using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using Xunit;
using PontenWPF;

namespace PontenWPF.Tests
{
    public class SignatureStorageTests : IDisposable
    {
        private readonly string _testDirectory;
        private readonly string _indexPath;

        public SignatureStorageTests()
        {
            _testDirectory = Path.Combine(Path.GetTempPath(), "PontenTest_" + Guid.NewGuid().ToString());
            _indexPath = Path.Combine(_testDirectory, "index.json");
            Directory.CreateDirectory(_testDirectory);
        }

        public void Dispose()
        {
            if (Directory.Exists(_testDirectory))
            {
                Directory.Delete(_testDirectory, true);
            }
        }

        [Fact]
        public void SignatureStorage_InitializesEmpty()
        {
            var storage = new SignatureStorage(_testDirectory);
            Assert.Empty(storage.Signatures);
            Assert.Null(storage.ActiveSignatureID);
            Assert.NotNull(storage.Settings);
        }

        [Fact]
        public void AddSignature_SavesToIndex()
        {
            var storage = new SignatureStorage(_testDirectory);
            var id = Guid.NewGuid();
            string filename = $"{id}.png";
            var item = new SignatureItem { Id = id, Filename = filename, Name = "Test Sig" };
            
            // Create dummy file so cleanup doesn't remove it
            File.WriteAllText(Path.Combine(_testDirectory, filename), "dummy content");

            storage.AddSignature(item);

            Assert.Single(storage.Signatures);
            Assert.Equal(item.Id, storage.ActiveSignatureID);

            // Verify index.json was created
            Assert.True(File.Exists(_indexPath));
            
            // Reload storage to verify persistence
            var newStorage = new SignatureStorage(_testDirectory);
            Assert.Single(newStorage.Signatures);
            Assert.Equal(item.Id, newStorage.ActiveSignatureID);
            Assert.Equal(filename, newStorage.Signatures[0].Filename);
        }

        [Fact]
        public void Load_RemovesMissingFiles()
        {
            // Setup an index with a file that doesn't exist
            var storage = new SignatureStorage(_testDirectory);
            var id1 = Guid.NewGuid();
            var id2 = Guid.NewGuid();
            string existsFilename = $"{id1}.png";
            string missingFilename = $"{id2}.png";
            var item1 = new SignatureItem { Id = id1, Filename = existsFilename, Name = "Exists" };
            var item2 = new SignatureItem { Id = id2, Filename = missingFilename, Name = "Missing" };
            
            File.WriteAllText(Path.Combine(_testDirectory, existsFilename), "dummy content");
            
            storage.AddSignature(item1);
            storage.AddSignature(item2);

            Assert.Equal(2, storage.Signatures.Count);

            // Reload will trigger cleanup of missing.png
            var newStorage = new SignatureStorage(_testDirectory);
            
            Assert.Single(newStorage.Signatures);
            Assert.Equal(existsFilename, newStorage.Signatures[0].Filename);
        }

        [Fact]
        public void RemoveSignature_DeletesFileAndUpdatesIndex()
        {
            var storage = new SignatureStorage(_testDirectory);
            var id = Guid.NewGuid();
            string filename = $"{id}.png";
            var item = new SignatureItem { Id = id, Filename = filename, Name = "Delete Me" };
            
            string filePath = Path.Combine(_testDirectory, filename);
            File.WriteAllText(filePath, "dummy content");
            
            storage.AddSignature(item);
            Assert.True(File.Exists(filePath));
            
            storage.RemoveSignature(id);
            
            Assert.Empty(storage.Signatures);
            Assert.False(File.Exists(filePath));
        }

        [Fact]
        public void SetActiveSignature_UpdatesActiveId()
        {
            var storage = new SignatureStorage(_testDirectory);
            var id1 = Guid.NewGuid();
            var id2 = Guid.NewGuid();
            string filename1 = $"{id1}.png";
            string filename2 = $"{id2}.png";
            var item1 = new SignatureItem { Id = id1, Filename = filename1 };
            var item2 = new SignatureItem { Id = id2, Filename = filename2 };
            
            File.WriteAllText(Path.Combine(_testDirectory, filename1), "dummy");
            File.WriteAllText(Path.Combine(_testDirectory, filename2), "dummy");
            
            storage.AddSignature(item1);
            storage.AddSignature(item2);
            
            storage.SetActiveSignature(item1.Id);
            Assert.Equal(item1.Id, storage.ActiveSignatureID);
            
            var newStorage = new SignatureStorage(_testDirectory);
            Assert.Equal(item1.Id, newStorage.ActiveSignatureID);
        }

        [Fact]
        public void Load_CorruptedIndexCleanup()
        {
            // Create a corrupted index.json
            File.WriteAllText(_indexPath, "{ invalid json }");
            
            // Should not throw, should initialize empty
            var storage = new SignatureStorage(_testDirectory);
            Assert.Empty(storage.Signatures);
        }

        [Fact]
        public void Load_CorruptedIndexRebuildsFromPNGFiles()
        {
            var id = Guid.NewGuid();
            string filename = $"{id}.png";
            File.WriteAllText(_indexPath, "{ invalid json }");
            File.WriteAllText(Path.Combine(_testDirectory, filename), "dummy content");

            var storage = new SignatureStorage(_testDirectory);

            Assert.Single(storage.Signatures);
            Assert.Equal(id, storage.ActiveSignatureID);
            Assert.Equal(filename, storage.Signatures[0].Filename);
        }

        [Fact]
        public void Load_CorruptedIndexPreservesSettings()
        {
            var id = Guid.NewGuid();
            string filename = $"{id}.png";
            var corruptJson = """
            {
              "items": "not-an-array",
              "settings": {
                "launchAtLogin": true,
                "autoPaste": false,
                "removeBackground": false
              }
            }
            """;
            File.WriteAllText(_indexPath, corruptJson);
            File.WriteAllText(Path.Combine(_testDirectory, filename), "dummy content");

            var storage = new SignatureStorage(_testDirectory);

            Assert.Single(storage.Signatures);
            Assert.True(storage.Settings.LaunchAtLogin);
            Assert.False(storage.Settings.AutoPaste);
            Assert.False(storage.Settings.RemoveBackground);
        }

        [Fact]
        public void SaveIndex_WritesCamelCaseJson()
        {
            var storage = new SignatureStorage(_testDirectory);
            var item = new SignatureItem { Id = Guid.NewGuid(), Filename = "camel.png", Name = "Camel" };
            File.WriteAllText(Path.Combine(_testDirectory, "camel.png"), "dummy content");

            storage.AddSignature(item);
            storage.Settings.AutoPaste = true;
            storage.Settings.RemoveBackground = false;
            storage.SaveIndex();

            var json = File.ReadAllText(_indexPath);
            Assert.Contains("\"items\"", json, StringComparison.Ordinal);
            Assert.Contains("\"activeID\"", json, StringComparison.Ordinal);
            Assert.Contains("\"settings\"", json, StringComparison.Ordinal);
            Assert.Contains("\"autoPaste\"", json, StringComparison.Ordinal);
            Assert.Contains("\"removeBackground\"", json, StringComparison.Ordinal);
            Assert.DoesNotContain("\"Items\"", json, StringComparison.Ordinal);
            Assert.DoesNotContain("\"ActiveID\"", json, StringComparison.Ordinal);
        }

        [Fact]
        public void Load_ReadsLegacyPascalCaseJson()
        {
            var id = Guid.NewGuid();
            string filename = $"{id}.png";
            var legacyJson = $$"""
            {
              "Items": [
                { "Id": "{{id}}", "Filename": "{{filename}}", "Name": "Legacy" }
              ],
              "ActiveID": "{{id}}",
              "Settings": {
                "LaunchAtLogin": false,
                "AutoPaste": true,
                "RemoveBackground": true
              }
            }
            """;
            File.WriteAllText(_indexPath, legacyJson);
            File.WriteAllText(Path.Combine(_testDirectory, filename), "dummy content");

            var storage = new SignatureStorage(_testDirectory);

            Assert.Single(storage.Signatures);
            Assert.Equal(id, storage.ActiveSignatureID);
            Assert.True(storage.Settings.AutoPaste);
            Assert.True(storage.Settings.RemoveBackground);
        }

        [Fact]
        public void Settings_RoundTripInIndexJson()
        {
            var storage = new SignatureStorage(_testDirectory);
            storage.Settings.AutoPaste = false;
            storage.Settings.LaunchAtLogin = true;
            storage.Settings.RemoveBackground = false;
            storage.SaveIndex();

            var reloaded = new SignatureStorage(_testDirectory);
            Assert.False(reloaded.Settings.AutoPaste);
            Assert.True(reloaded.Settings.LaunchAtLogin);
            Assert.False(reloaded.Settings.RemoveBackground);
        }

        [Fact]
        public void UserSettings_Toggles()
        {
            var storage = new SignatureStorage(_testDirectory);
            
            storage.Settings.AutoPaste = false;
            storage.SaveIndex();
            
            var newStorage = new SignatureStorage(_testDirectory);
            Assert.False(newStorage.Settings.AutoPaste);
            
            // We can't fully test ApplyLaunchAtLogin on non-Windows easily without mocking Registry,
            // but we can ensure it sets the LaunchAtLogin boolean property.
            // On Mac this throws or catches exception and logs it.
            storage.ApplyLaunchAtLogin(true);
            Assert.True(storage.Settings.LaunchAtLogin);
            
            var storage3 = new SignatureStorage(_testDirectory);
            Assert.True(storage3.Settings.LaunchAtLogin);
        }

        [Fact]
        public void Load_NullItems_DoesNotCrash()
        {
            var wrapper = new IndexWrapper
            {
                Items = null!,
                ActiveID = null,
                Settings = new UserSettings()
            };
            string json = JsonSerializer.Serialize(wrapper);
            File.WriteAllText(_indexPath, json);

            var storage = new SignatureStorage(_testDirectory);

            Assert.NotNull(storage.Signatures);
            Assert.Empty(storage.Signatures);
        }

        [Theory]
        [InlineData("valid-guid.png", false)]
        [InlineData("550e8400-e29b-41d4-a716-446655440000.png", true)]
        [InlineData("../escape.png", false)]
        [InlineData("subdir/file.png", false)]
        [InlineData("test.png", false)]
        public void IsValidSignatureFilename_RejectsUnsafeNames(string filename, bool expectedValid)
        {
            Assert.Equal(expectedValid, SignatureStorage.IsValidSignatureFilename(filename));
        }

        [Fact]
        public void GetSignatureFilePath_RejectsPathTraversal()
        {
            var storage = new SignatureStorage(_testDirectory);

            Assert.Throws<ArgumentException>(() => storage.GetSignatureFilePath("../secret.png"));
        }

        [Fact]
        public void Load_RemovesInvalidFilenames()
        {
            var id = Guid.NewGuid();
            string validFilename = $"{id}.png";
            var wrapper = new IndexWrapper
            {
                Items = new List<SignatureItem>
                {
                    new SignatureItem { Id = id, Filename = validFilename },
                    new SignatureItem { Id = Guid.NewGuid(), Filename = "../bad.png" },
                    new SignatureItem { Id = Guid.NewGuid(), Filename = "test.png" }
                },
                ActiveID = id
            };
            File.WriteAllText(_indexPath, JsonSerializer.Serialize(wrapper));
            File.WriteAllText(Path.Combine(_testDirectory, validFilename), "dummy");

            var storage = new SignatureStorage(_testDirectory);

            Assert.Single(storage.Signatures);
            Assert.Equal(validFilename, storage.Signatures[0].Filename);
        }

        [Fact]
        public void Constructor_CleansTempFiles()
        {
            File.WriteAllText(Path.Combine(_testDirectory, "index.json.tmp"), "stale");
            File.WriteAllText(Path.Combine(_testDirectory, "orphan.tmp"), "stale");

            _ = new SignatureStorage(_testDirectory);

            Assert.False(File.Exists(Path.Combine(_testDirectory, "index.json.tmp")));
            Assert.False(File.Exists(Path.Combine(_testDirectory, "orphan.tmp")));
        }
    }
}
