using System;
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
            var item = new SignatureItem { Id = Guid.NewGuid(), Filename = "test.png", Name = "Test Sig" };
            
            // Create dummy file so cleanup doesn't remove it
            File.WriteAllText(Path.Combine(_testDirectory, "test.png"), "dummy content");

            storage.AddSignature(item);

            Assert.Single(storage.Signatures);
            Assert.Equal(item.Id, storage.ActiveSignatureID);

            // Verify index.json was created
            Assert.True(File.Exists(_indexPath));
            
            // Reload storage to verify persistence
            var newStorage = new SignatureStorage(_testDirectory);
            Assert.Single(newStorage.Signatures);
            Assert.Equal(item.Id, newStorage.ActiveSignatureID);
            Assert.Equal("test.png", newStorage.Signatures[0].Filename);
        }

        [Fact]
        public void Load_RemovesMissingFiles()
        {
            // Setup an index with a file that doesn't exist
            var storage = new SignatureStorage(_testDirectory);
            var item1 = new SignatureItem { Id = Guid.NewGuid(), Filename = "exists.png", Name = "Exists" };
            var item2 = new SignatureItem { Id = Guid.NewGuid(), Filename = "missing.png", Name = "Missing" };
            
            File.WriteAllText(Path.Combine(_testDirectory, "exists.png"), "dummy content");
            
            storage.AddSignature(item1);
            storage.AddSignature(item2);

            Assert.Equal(2, storage.Signatures.Count);

            // Reload will trigger cleanup of missing.png
            var newStorage = new SignatureStorage(_testDirectory);
            
            Assert.Single(newStorage.Signatures);
            Assert.Equal("exists.png", newStorage.Signatures[0].Filename);
        }

        [Fact]
        public void RemoveSignature_DeletesFileAndUpdatesIndex()
        {
            var storage = new SignatureStorage(_testDirectory);
            var id = Guid.NewGuid();
            var item = new SignatureItem { Id = id, Filename = "delete_me.png", Name = "Delete Me" };
            
            string filePath = Path.Combine(_testDirectory, "delete_me.png");
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
            var item1 = new SignatureItem { Id = Guid.NewGuid(), Filename = "1.png" };
            var item2 = new SignatureItem { Id = Guid.NewGuid(), Filename = "2.png" };
            
            File.WriteAllText(Path.Combine(_testDirectory, "1.png"), "dummy");
            File.WriteAllText(Path.Combine(_testDirectory, "2.png"), "dummy");
            
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
    }
}
