using System;
using System.IO;
using System.Net.Http;
using System.Reflection;
using System.Text.Json;
using System.Threading.Tasks;

namespace PontenWPF
{
    public class UpdateCheckResult
    {
        public bool IsNewerAvailable { get; set; }
        public string? LatestVersion { get; set; }
        public string? DownloadUrl { get; set; }
        public string? ErrorMessage { get; set; }
    }

    public class Updater
    {
        private const string LatestReleaseUrl = "https://api.github.com/repos/mustafabercerita/ponten/releases/latest";

        public async Task<UpdateCheckResult> CheckForUpdateAsync()
        {
            var result = new UpdateCheckResult();

            try
            {
                using var client = new HttpClient();
                client.DefaultRequestHeaders.UserAgent.ParseAdd("Ponten-WindowsApp");

                using var response = await client.GetAsync(LatestReleaseUrl);
                if (!response.IsSuccessStatusCode)
                {
                    result.ErrorMessage = DescribeHttpError(response.StatusCode);
                    return result;
                }

                await using var stream = await response.Content.ReadAsStreamAsync();
                using var document = await JsonDocument.ParseAsync(stream);
                var root = document.RootElement;

                if (!root.TryGetProperty("tag_name", out var tagElement))
                {
                    result.ErrorMessage = "Update check failed. Invalid release metadata.";
                    return result;
                }

                string tagName = tagElement.GetString() ?? "";
                string latestVersion = tagName.TrimStart('v', 'V');
                var currentVersion = Assembly.GetExecutingAssembly().GetName().Version ?? new Version(0, 0, 0, 0);

                result.LatestVersion = latestVersion;
                result.IsNewerAvailable = IsRemoteVersionNewer(latestVersion, currentVersion);

                if (result.IsNewerAvailable && root.TryGetProperty("assets", out var assetsElement))
                {
                    foreach (var asset in assetsElement.EnumerateArray())
                    {
                        if (!asset.TryGetProperty("name", out var nameElement) ||
                            !asset.TryGetProperty("browser_download_url", out var urlElement))
                        {
                            continue;
                        }

                        string assetName = nameElement.GetString() ?? "";
                        if (assetName.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
                        {
                            result.DownloadUrl = urlElement.GetString();
                            break;
                        }
                    }

                    if (string.IsNullOrEmpty(result.DownloadUrl))
                    {
                        result.ErrorMessage = "Update found, but no Windows installer is available.";
                    }
                }
            }
            catch (Exception ex)
            {
                App.LogException("Update check failed", ex);
                result.ErrorMessage = "Update check failed. Check your network connection.";
            }

            return result;
        }

        public async Task DownloadUpdateAndExecute(string url)
        {
            string secureTempDir = Path.Combine(Path.GetTempPath(), Path.GetRandomFileName());
            Directory.CreateDirectory(secureTempDir);

            string installerPath = Path.Combine(secureTempDir, "Ponten-Update.exe");

            using (HttpClient client = new HttpClient())
            {
                client.DefaultRequestHeaders.UserAgent.ParseAdd("Ponten-WindowsApp");
                using (var stream = await client.GetStreamAsync(url))
                {
                    using (var fileStream = new FileStream(installerPath, FileMode.Create, FileAccess.Write, FileShare.None))
                    {
                        await stream.CopyToAsync(fileStream);
                    }
                }
            }

            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = installerPath,
                UseShellExecute = true
            });
        }

        public static string DescribeHttpError(System.Net.HttpStatusCode statusCode)
        {
            return (int)statusCode switch
            {
                403 => "Update check blocked (rate limit). Try again later.",
                429 => "Too many update checks. Try again later.",
                _ => $"Update check failed (HTTP {(int)statusCode})."
            };
        }

        private static bool IsRemoteVersionNewer(string remoteVersion, Version currentVersion)
        {
            if (Version.TryParse(remoteVersion, out var parsedRemote))
            {
                return parsedRemote > currentVersion;
            }

            string current = currentVersion.ToString(3);
            return string.Compare(remoteVersion, current, StringComparison.OrdinalIgnoreCase) > 0;
        }
    }
}