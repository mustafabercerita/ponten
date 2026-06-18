using System;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading.Tasks;

namespace PontenWPF
{
    public class ImageProcessor
    {
        public Bitmap Ensure32bpp(Bitmap source)
        {
            var normalized = Ensure32bppArgb(source);
            if (ReferenceEquals(normalized, source))
                return new Bitmap(source);
            return normalized;
        }

        public static void WritePngAtomic(string path, byte[] pngBytes)
        {
            try
            {
                string directory = Path.GetDirectoryName(path) ?? ".";
                Directory.CreateDirectory(directory);

                string tempPath = path + ".tmp";
                File.WriteAllBytes(tempPath, pngBytes);

                if (File.Exists(path))
                    File.Replace(tempPath, path, null);
                else
                    File.Move(tempPath, path);
            }
            catch (Exception ex)
            {
                throw new IOException(StorageError.UserFacingMessage(ex, "Failed to save signature"), ex);
            }
        }

        private static Bitmap Ensure32bppArgb(Bitmap source)
        {
            if (source.PixelFormat == System.Drawing.Imaging.PixelFormat.Format32bppArgb)
                return source;

            var normalized = new Bitmap(source.Width, source.Height, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(normalized))
            {
                g.DrawImage(source, 0, 0, source.Width, source.Height);
            }
            return normalized;
        }

        private static void ReleaseNormalized(Bitmap source, Bitmap normalized)
        {
            if (!ReferenceEquals(source, normalized))
                normalized.Dispose();
        }

        public bool ValidateWhiteBackground(Bitmap original)
        {
            var source = Ensure32bppArgb(original);
            try
            {
                int width = source.Width;
                int height = source.Height;

                if (width <= 10 || height <= 10)
                    return true;

                const int margin = 2;
                Rectangle rect = new Rectangle(0, 0, width, height);
                System.Drawing.Imaging.BitmapData bmpData = source.LockBits(
                    rect,
                    System.Drawing.Imaging.ImageLockMode.ReadOnly,
                    System.Drawing.Imaging.PixelFormat.Format32bppArgb);

                try
                {
                    int stride = Math.Abs(bmpData.Stride);
                    int bytes = stride * height;
                    byte[] rgbValues = new byte[bytes];
                    Marshal.Copy(bmpData.Scan0, rgbValues, 0, bytes);

                    int edgePixelCount = 0;
                    int whiteOrTransparentCount = 0;

                    for (int y = 0; y < height; y++)
                    {
                        for (int x = 0; x < width; x++)
                        {
                            if (x < margin || x >= width - margin || y < margin || y >= height - margin)
                            {
                                edgePixelCount++;
                                int index = y * stride + x * 4;
                                byte b = rgbValues[index];
                                byte g = rgbValues[index + 1];
                                byte r = rgbValues[index + 2];
                                byte a = rgbValues[index + 3];

                                if (a < 10 || (r > 240 && g > 240 && b > 240))
                                    whiteOrTransparentCount++;
                            }
                        }
                    }

                    if (edgePixelCount == 0)
                        return true;

                    double ratio = (double)whiteOrTransparentCount / edgePixelCount;
                    return ratio > 0.8;
                }
                finally
                {
                    source.UnlockBits(bmpData);
                }
            }
            finally
            {
                ReleaseNormalized(original, source);
            }
        }

        // 3. Pixel Dilation (Adjustable Thickness)
        public Bitmap Dilation(Bitmap original, int thickness)
        {
            var source = Ensure32bppArgb(original);
            try
            {
                if (thickness <= 0)
                    return new Bitmap(source);

                int width = source.Width;
                int height = source.Height;

                int pad = thickness;
                int newWidth = width + pad * 2;
                int newHeight = height + pad * 2;

                Bitmap result = new Bitmap(newWidth, newHeight, System.Drawing.Imaging.PixelFormat.Format32bppArgb);

                Rectangle origRect = new Rectangle(0, 0, width, height);
                Rectangle resRect = new Rectangle(0, 0, newWidth, newHeight);
                System.Drawing.Imaging.BitmapData origData = source.LockBits(
                    origRect,
                    System.Drawing.Imaging.ImageLockMode.ReadOnly,
                    System.Drawing.Imaging.PixelFormat.Format32bppArgb);
                System.Drawing.Imaging.BitmapData resData = result.LockBits(
                    resRect,
                    System.Drawing.Imaging.ImageLockMode.WriteOnly,
                    System.Drawing.Imaging.PixelFormat.Format32bppArgb);

                try
                {
                    int origStride = Math.Abs(origData.Stride);
                    int origBytes = origStride * height;
                    byte[] origValues = new byte[origBytes];

                    int resStride = Math.Abs(resData.Stride);
                    int resBytes = resStride * newHeight;
                    byte[] resValues = new byte[resBytes];

                    Marshal.Copy(origData.Scan0, origValues, 0, origBytes);

                    // First, copy everything into the offset position
                    for (int y = 0; y < height; y++)
                    {
                        for (int x = 0; x < width; x++)
                        {
                            int oIndex = y * origStride + x * 4;
                            int rIndex = (y + pad) * resStride + (x + pad) * 4;
                            resValues[rIndex] = origValues[oIndex];
                            resValues[rIndex + 1] = origValues[oIndex + 1];
                            resValues[rIndex + 2] = origValues[oIndex + 2];
                            resValues[rIndex + 3] = origValues[oIndex + 3];
                        }
                    }

                    for (int y = 0; y < height; y++)
                    {
                        for (int x = 0; x < width; x++)
                        {
                            int index = y * origStride + x * 4;
                            byte b = origValues[index];
                            byte g = origValues[index + 1];
                            byte r = origValues[index + 2];
                            byte a = origValues[index + 3];

                            // Consider it a stroke pixel if it's not white and not transparent
                            if (a > 0 && (r < 200 || g < 200 || b < 200))
                            {
                                // Dilate around this pixel in the new coordinate space
                                for (int dy = -thickness; dy <= thickness; dy++)
                                {
                                    for (int dx = -thickness; dx <= thickness; dx++)
                                    {
                                        if (dx * dx + dy * dy <= thickness * thickness)
                                        {
                                            int nx = x + pad + dx;
                                            int ny = y + pad + dy;

                                            if (nx >= 0 && nx < newWidth && ny >= 0 && ny < newHeight)
                                            {
                                                int nIndex = ny * resStride + nx * 4;
                                                resValues[nIndex] = b;
                                                resValues[nIndex + 1] = g;
                                                resValues[nIndex + 2] = r;
                                                resValues[nIndex + 3] = Math.Max(resValues[nIndex + 3], a);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Marshal.Copy(resValues, 0, resData.Scan0, resBytes);
                }
                finally
                {
                    source.UnlockBits(origData);
                    result.UnlockBits(resData);
                }

                return result;
            }
            finally
            {
                ReleaseNormalized(original, source);
            }
        }

        // 1. Strip White Background
        // Turns white background pixels transparent and returns the modified image
        public Bitmap StripWhiteBackground(Bitmap original)
        {
            var source = Ensure32bppArgb(original);
            try
            {
                Bitmap result = new Bitmap(source.Width, source.Height, System.Drawing.Imaging.PixelFormat.Format32bppArgb);

                Rectangle rect = new Rectangle(0, 0, source.Width, source.Height);
                System.Drawing.Imaging.BitmapData bmpData = result.LockBits(
                    rect,
                    System.Drawing.Imaging.ImageLockMode.WriteOnly,
                    System.Drawing.Imaging.PixelFormat.Format32bppArgb);
                System.Drawing.Imaging.BitmapData origData = source.LockBits(
                    rect,
                    System.Drawing.Imaging.ImageLockMode.ReadOnly,
                    System.Drawing.Imaging.PixelFormat.Format32bppArgb);

                try
                {
                    int bytes = Math.Abs(bmpData.Stride) * source.Height;
                    byte[] rgbValues = new byte[bytes];
                    byte[] origValues = new byte[bytes];

                    Marshal.Copy(origData.Scan0, origValues, 0, bytes);

                    for (int counter = 0; counter < rgbValues.Length; counter += 4)
                    {
                        byte b = origValues[counter];
                        byte g = origValues[counter + 1];
                        byte r = origValues[counter + 2];
                        byte a = origValues[counter + 3];

                        if (r > 240 && g > 240 && b > 240)
                        {
                            rgbValues[counter] = 0;
                            rgbValues[counter + 1] = 0;
                            rgbValues[counter + 2] = 0;
                            rgbValues[counter + 3] = 0;
                        }
                        else
                        {
                            rgbValues[counter] = b;
                            rgbValues[counter + 1] = g;
                            rgbValues[counter + 2] = r;
                            rgbValues[counter + 3] = a;
                        }
                    }

                    Marshal.Copy(rgbValues, 0, bmpData.Scan0, bytes);
                }
                finally
                {
                    source.UnlockBits(origData);
                    result.UnlockBits(bmpData);
                }

                return result;
            }
            finally
            {
                ReleaseNormalized(original, source);
            }
        }

        // 2. Auto-Paste Logic — SendInput for reliable Ctrl+V
        [DllImport("user32.dll", SetLastError = true)]
        private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

        [DllImport("user32.dll")]
        private static extern bool SetForegroundWindow(IntPtr hWnd);

        [StructLayout(LayoutKind.Sequential)]
        private struct INPUT
        {
            public uint type;
            public InputUnion U;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct InputUnion
        {
            public KEYBDINPUT ki;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct KEYBDINPUT
        {
            public ushort wVk;
            public ushort wScan;
            public uint dwFlags;
            public uint time;
            public IntPtr dwExtraInfo;
        }

        private const uint INPUT_KEYBOARD = 1;
        private const ushort VK_CONTROL = 0x11;
        private const ushort VK_V = 0x56;
        private const uint KEYEVENTF_KEYUP = 0x0002;
        private const ushort VK_MENU = 0x12;
        private const ushort VK_SHIFT = 0x10;
        private const ushort VK_LWIN = 0x5B;
        private const ushort VK_RWIN = 0x5C;

        private static void SendKey(ushort vk, bool keyUp)
        {
            var input = new INPUT
            {
                type = INPUT_KEYBOARD,
                U = new InputUnion
                {
                    ki = new KEYBDINPUT
                    {
                        wVk = vk,
                        wScan = 0,
                        dwFlags = keyUp ? KEYEVENTF_KEYUP : 0,
                        time = 0,
                        dwExtraInfo = IntPtr.Zero
                    }
                }
            };
            uint sent = SendInput(1, new[] { input }, Marshal.SizeOf<INPUT>());
            if (sent == 0)
            {
                int error = Marshal.GetLastWin32Error();
                App.Log($"SendInput failed for VK=0x{vk:X} keyUp={keyUp}: Win32 error {error}");
            }
        }

        /// <summary>
        /// Sends Ctrl+V to paste the clipboard contents. When <paramref name="targetWindow"/> is set,
        /// restores focus to that HWND first so paste reaches the app the user was working in
        /// (avoids racing with Hide() on the Ponten menu window).
        /// </summary>
        public async Task AutoPasteAsync(IntPtr? targetWindow = null)
        {
            // First ensure Alt, Shift, and Win keys are released to avoid triggering unintended shortcuts
            SendKey(VK_MENU, true);
            SendKey(VK_SHIFT, true);
            SendKey(VK_LWIN, true);
            SendKey(VK_RWIN, true);

            await Task.Delay(50).ConfigureAwait(false);

            if (targetWindow.HasValue && targetWindow.Value != IntPtr.Zero)
            {
                SetForegroundWindow(targetWindow.Value);
                await Task.Delay(200).ConfigureAwait(false);
            }

            SendKey(VK_CONTROL, false);
            SendKey(VK_V, false);

            await Task.Delay(50).ConfigureAwait(false);

            SendKey(VK_V, true);
            SendKey(VK_CONTROL, true);
        }

        public Bitmap AutoTrimWhitespace(Bitmap original, int padding)
        {
            var source = Ensure32bppArgb(original);
            try
            {
                int width = source.Width;
                int height = source.Height;

                int minX = width, minY = height, maxX = 0, maxY = 0;

                Rectangle rect = new Rectangle(0, 0, width, height);
                System.Drawing.Imaging.BitmapData bmpData = source.LockBits(
                    rect,
                    System.Drawing.Imaging.ImageLockMode.ReadOnly,
                    System.Drawing.Imaging.PixelFormat.Format32bppArgb);
                int stride = Math.Abs(bmpData.Stride);
                int bytes = stride * height;
                byte[] rgbValues = new byte[bytes];
                Marshal.Copy(bmpData.Scan0, rgbValues, 0, bytes);
                source.UnlockBits(bmpData);

                for (int y = 0; y < height; y++)
                {
                    for (int x = 0; x < width; x++)
                    {
                        int index = y * stride + x * 4;
                        byte b = rgbValues[index];
                        byte g = rgbValues[index + 1];
                        byte r = rgbValues[index + 2];
                        byte a = rgbValues[index + 3];

                        if (a > 0 && (r < 240 || g < 240 || b < 240))
                        {
                            if (x < minX) minX = x;
                            if (x > maxX) maxX = x;
                            if (y < minY) minY = y;
                            if (y > maxY) maxY = y;
                        }
                    }
                }

                if (minX > maxX || minY > maxY)
                {
                    return new Bitmap(source);
                }

                minX = Math.Max(0, minX - padding);
                minY = Math.Max(0, minY - padding);
                maxX = Math.Min(width - 1, maxX + padding);
                maxY = Math.Min(height - 1, maxY + padding);

                int newWidth = maxX - minX + 1;
                int newHeight = maxY - minY + 1;

                Bitmap cropped = new Bitmap(newWidth, newHeight, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
                using (Graphics g = Graphics.FromImage(cropped))
                {
                    g.DrawImage(source, new Rectangle(0, 0, newWidth, newHeight), new Rectangle(minX, minY, newWidth, newHeight), GraphicsUnit.Pixel);
                }
                return cropped;
            }
            finally
            {
                ReleaseNormalized(original, source);
            }
        }

        public Bitmap AdjustColor(Bitmap original, double contrast, double brightness)
        {
            var source = Ensure32bppArgb(original);
            try
            {
                Bitmap adjusted = new Bitmap(source.Width, source.Height, System.Drawing.Imaging.PixelFormat.Format32bppArgb);

                float c = (float)contrast;
                float b = (float)brightness;
                float t = b + (1.0f - c) / 2.0f;

                // Desaturate for parity with macOS (saturation = 0) while preserving contrast/brightness.
                const float rw = 0.299f;
                const float gw = 0.587f;
                const float bw = 0.114f;
                float sr = (1.0f - 0.0f) * c * rw + 0.0f;
                float sg = (1.0f - 0.0f) * c * gw + 0.0f;
                float sb = (1.0f - 0.0f) * c * bw + 0.0f;

                System.Drawing.Imaging.ColorMatrix colorMatrix = new System.Drawing.Imaging.ColorMatrix(new float[][]
                {
                    new float[] {sr, sr, sr, 0, 0},
                    new float[] {sg, sg, sg, 0, 0},
                    new float[] {sb, sb, sb, 0, 0},
                    new float[] {0, 0, 0, 1, 0},
                    new float[] {t, t, t, 0, 1}
                });

                using (System.Drawing.Imaging.ImageAttributes attributes = new System.Drawing.Imaging.ImageAttributes())
                {
                    attributes.SetColorMatrix(colorMatrix);
                    using (Graphics g = Graphics.FromImage(adjusted))
                    {
                        g.DrawImage(source, new Rectangle(0, 0, source.Width, source.Height),
                            0, 0, source.Width, source.Height, GraphicsUnit.Pixel, attributes);
                    }
                }

                return adjusted;
            }
            finally
            {
                ReleaseNormalized(original, source);
            }
        }

        public Bitmap Rotate(Bitmap original, float angle)
        {
            var source = Ensure32bppArgb(original);
            try
            {
                double radians = angle * Math.PI / 180.0;
                double cos = Math.Abs(Math.Cos(radians));
                double sin = Math.Abs(Math.Sin(radians));
                int newWidth = (int)(source.Width * cos + source.Height * sin);
                int newHeight = (int)(source.Width * sin + source.Height * cos);

                Bitmap rotated = new Bitmap(newWidth, newHeight, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
                using (Graphics g = Graphics.FromImage(rotated))
                {
                    g.TranslateTransform((float)newWidth / 2, (float)newHeight / 2);
                    g.RotateTransform(angle);
                    g.TranslateTransform(-(float)source.Width / 2, -(float)source.Height / 2);
                    g.DrawImage(source, new Point(0, 0));
                }
                return rotated;
            }
            finally
            {
                ReleaseNormalized(original, source);
            }
        }
    }
}