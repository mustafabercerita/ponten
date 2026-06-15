using System;
using System.Drawing;
using System.Runtime.InteropServices;

namespace PontenWPF
{
    public class SignatureManager
    {
        public bool ValidateWhiteBackground(Bitmap original)
        {
            // Check the 4 edges. If any pixel is not white (or near white), reject.
            int width = original.Width;
            int height = original.Height;
            
            Rectangle rect = new Rectangle(0, 0, width, height);
            System.Drawing.Imaging.BitmapData bmpData = original.LockBits(rect, System.Drawing.Imaging.ImageLockMode.ReadOnly, System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
            
            int stride = Math.Abs(bmpData.Stride);
            int bytes = stride * height;
            byte[] rgbValues = new byte[bytes];
            Marshal.Copy(bmpData.Scan0, rgbValues, 0, bytes);
            original.UnlockBits(bmpData);

            bool CheckPixel(int x, int y)
            {
                int index = y * stride + x * 4;
                byte b = rgbValues[index];
                byte g = rgbValues[index + 1];
                byte r = rgbValues[index + 2];
                // checking if it's near white
                return (r > 240 && g > 240 && b > 240);
            }

            // Check top and bottom edges
            for (int x = 0; x < width; x++)
            {
                if (!CheckPixel(x, 0)) return false;
                if (!CheckPixel(x, height - 1)) return false;
            }

            // Check left and right edges
            for (int y = 0; y < height; y++)
            {
                if (!CheckPixel(0, y)) return false;
                if (!CheckPixel(width - 1, y)) return false;
            }

            return true;
        }

        // 3. Pixel Dilation (Adjustable Thickness)
        public Bitmap Dilation(Bitmap original, int thickness)
        {
            if (thickness <= 0) return new Bitmap(original);
            
            int width = original.Width;
            int height = original.Height;
            
            int pad = thickness;
            int newWidth = width + pad * 2;
            int newHeight = height + pad * 2;
            
            Bitmap result = new Bitmap(newWidth, newHeight);
            
            Rectangle origRect = new Rectangle(0, 0, width, height);
            Rectangle resRect = new Rectangle(0, 0, newWidth, newHeight);
            System.Drawing.Imaging.BitmapData origData = original.LockBits(origRect, System.Drawing.Imaging.ImageLockMode.ReadOnly, System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
            System.Drawing.Imaging.BitmapData resData = result.LockBits(resRect, System.Drawing.Imaging.ImageLockMode.WriteOnly, System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
            
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
            
            original.UnlockBits(origData);
            result.UnlockBits(resData);
            
            return result;
        }

        // 1. Strip White Background
        // Turns white background pixels transparent and returns the modified image
        public Bitmap StripWhiteBackground(Bitmap original)
        {
            Bitmap result = new Bitmap(original.Width, original.Height);
            
            Rectangle rect = new Rectangle(0, 0, original.Width, original.Height);
            System.Drawing.Imaging.BitmapData bmpData = result.LockBits(rect, System.Drawing.Imaging.ImageLockMode.WriteOnly, System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
            System.Drawing.Imaging.BitmapData origData = original.LockBits(rect, System.Drawing.Imaging.ImageLockMode.ReadOnly, System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
            
            int bytes = Math.Abs(bmpData.Stride) * original.Height;
            byte[] rgbValues = new byte[bytes];
            byte[] origValues = new byte[bytes];
            
            Marshal.Copy(origData.Scan0, origValues, 0, bytes);
            
            for (int counter = 0; counter < rgbValues.Length; counter += 4)
            {
                byte b = origValues[counter];
                byte g = origValues[counter + 1];
                byte r = origValues[counter + 2];
                byte a = origValues[counter + 3];
                
                if (r > 200 && g > 200 && b > 200)
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
            
            original.UnlockBits(origData);
            result.UnlockBits(bmpData);
            
            return result;
        }

        // 2. Auto-Paste Logic
        // Simulate Ctrl+V using keybd_event
        [DllImport("user32.dll")]
        private static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

        private const int VK_CONTROL = 0x11;
        private const int VK_V = 0x56;
        private const uint KEYEVENTF_KEYUP = 0x0002;

        private const int VK_MENU = 0x12; // Alt key
        private const int VK_SHIFT = 0x10;
        private const int VK_LWIN = 0x5B;
        private const int VK_RWIN = 0x5C;

        public void AutoPaste()
        {
            // First ensure Alt, Shift, and Win keys are released to avoid triggering unintended shortcuts
            keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
            keybd_event(VK_SHIFT, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
            keybd_event(VK_LWIN, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
            keybd_event(VK_RWIN, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
            
            // Add a tiny delay
            System.Threading.Thread.Sleep(50);
            
            // Press Ctrl
            keybd_event(VK_CONTROL, 0, 0, UIntPtr.Zero);
            // Press V
            keybd_event(VK_V, 0, 0, UIntPtr.Zero);
            
            System.Threading.Thread.Sleep(50);
            
            // Release V
            keybd_event(VK_V, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
            // Release Ctrl
            keybd_event(VK_CONTROL, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
        }

        public Bitmap AutoTrimWhitespace(Bitmap original, int padding)
        {
            int width = original.Width;
            int height = original.Height;

            int minX = width, minY = height, maxX = 0, maxY = 0;

            Rectangle rect = new Rectangle(0, 0, width, height);
            System.Drawing.Imaging.BitmapData bmpData = original.LockBits(rect, System.Drawing.Imaging.ImageLockMode.ReadOnly, System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
            int stride = Math.Abs(bmpData.Stride);
            int bytes = stride * height;
            byte[] rgbValues = new byte[bytes];
            Marshal.Copy(bmpData.Scan0, rgbValues, 0, bytes);
            original.UnlockBits(bmpData);

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
                return new Bitmap(original);
            }

            minX = Math.Max(0, minX - padding);
            minY = Math.Max(0, minY - padding);
            maxX = Math.Min(width - 1, maxX + padding);
            maxY = Math.Min(height - 1, maxY + padding);

            int newWidth = maxX - minX + 1;
            int newHeight = maxY - minY + 1;

            Bitmap cropped = new Bitmap(newWidth, newHeight);
            using (Graphics g = Graphics.FromImage(cropped))
            {
                g.DrawImage(original, new Rectangle(0, 0, newWidth, newHeight), new Rectangle(minX, minY, newWidth, newHeight), GraphicsUnit.Pixel);
            }
            return cropped;
        }

        public Bitmap AdjustColor(Bitmap original, double contrast, double brightness)
        {
            Bitmap adjusted = new Bitmap(original.Width, original.Height);
            
            float c = (float)contrast;
            float b = (float)brightness;
            float t = b + (1.0f - c) / 2.0f;

            System.Drawing.Imaging.ColorMatrix colorMatrix = new System.Drawing.Imaging.ColorMatrix(new float[][]
            {
                new float[] {c, 0, 0, 0, 0},
                new float[] {0, c, 0, 0, 0},
                new float[] {0, 0, c, 0, 0},
                new float[] {0, 0, 0, 1, 0},
                new float[] {t, t, t, 0, 1}
            });

            using (System.Drawing.Imaging.ImageAttributes attributes = new System.Drawing.Imaging.ImageAttributes())
            {
                attributes.SetColorMatrix(colorMatrix);
                using (Graphics g = Graphics.FromImage(adjusted))
                {
                    g.DrawImage(original, new Rectangle(0, 0, original.Width, original.Height),
                        0, 0, original.Width, original.Height, GraphicsUnit.Pixel, attributes);
                }
            }

            return adjusted;
        }

        public Bitmap Rotate(Bitmap original, float angle)
        {
            double radians = angle * Math.PI / 180.0;
            double cos = Math.Abs(Math.Cos(radians));
            double sin = Math.Abs(Math.Sin(radians));
            int newWidth = (int)(original.Width * cos + original.Height * sin);
            int newHeight = (int)(original.Width * sin + original.Height * cos);

            Bitmap rotated = new Bitmap(newWidth, newHeight);
            using (Graphics g = Graphics.FromImage(rotated))
            {
                g.TranslateTransform((float)newWidth / 2, (float)newHeight / 2);
                g.RotateTransform(angle);
                g.TranslateTransform(-(float)original.Width / 2, -(float)original.Height / 2);
                g.DrawImage(original, new Point(0, 0));
            }
            return rotated;
        }
    }
}
