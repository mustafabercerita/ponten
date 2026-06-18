using System;
using System.IO;
using System.Runtime.InteropServices;

namespace PontenWPF
{
    internal static class StorageError
    {
        private const int ERROR_DISK_FULL = 0x70;

        public static bool IsDiskFull(Exception ex)
        {
            if (ex is IOException ioEx)
            {
                if (ioEx.HResult == unchecked((int)0x80070070))
                {
                    return true;
                }

                if (ioEx.HResult == unchecked((int)0x80070027))
                {
                    return true;
                }
            }

            if (ex is UnauthorizedAccessException)
            {
                return false;
            }

            if (ex.InnerException != null)
            {
                return IsDiskFull(ex.InnerException);
            }

            return Marshal.GetLastWin32Error() == ERROR_DISK_FULL;
        }

        public static string UserFacingMessage(Exception ex, string fallbackPrefix)
        {
            if (IsDiskFull(ex))
            {
                return "Not enough disk space to save signatures.";
            }

            return $"{fallbackPrefix}: {ex.Message}";
        }
    }
}