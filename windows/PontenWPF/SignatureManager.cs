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
            
            Bitmap result = new Bitmap(width, height);
            
            Rectangle rect = new Rectangle(0, 0, width, height);
            System.Drawing.Imaging.BitmapData origData = original.LockBits(rect, System.Drawing.Imaging.ImageLockMode.ReadOnly, System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
            System.Drawing.Imaging.BitmapData resData = result.LockBits(rect, System.Drawing.Imaging.ImageLockMode.WriteOnly, System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
            
            int stride = Math.Abs(origData.Stride);
            int bytes = stride * height;
            byte[] origValues = new byte[bytes];
            byte[] resValues = new byte[bytes];
            
            Marshal.Copy(origData.Scan0, origValues, 0, bytes);
            
            // First, copy everything
            Array.Copy(origValues, resValues, bytes);
            
            for (int y = 0; y < height; y++)
            {
                for (int x = 0; x < width; x++)
                {
                    int index = y * stride + x * 4;
                    byte b = origValues[index];
                    byte g = origValues[index + 1];
                    byte r = origValues[index + 2];
                    byte a = origValues[index + 3];
                    
                    // Consider it a stroke pixel if it's not white and not transparent
                    if (a > 0 && (r < 200 || g < 200 || b < 200))
                    {
                        // Dilate around this pixel
                        for (int dy = -thickness; dy <= thickness; dy++)
                        {
                            for (int dx = -thickness; dx <= thickness; dx++)
                            {
                                if (dx * dx + dy * dy <= thickness * thickness)
                                {
                                    int nx = x + dx;
                                    int ny = y + dy;
                                    
                                    if (nx >= 0 && nx < width && ny >= 0 && ny < height)
                                    {
                                        int nIndex = ny * stride + nx * 4;
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
            
            Marshal.Copy(resValues, 0, resData.Scan0, bytes);
            
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

        public void AutoPaste()
        {
            // Press Ctrl
            keybd_event(VK_CONTROL, 0, 0, UIntPtr.Zero);
            // Press V
            keybd_event(VK_V, 0, 0, UIntPtr.Zero);
            // Release V
            keybd_event(VK_V, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
            // Release Ctrl
            keybd_event(VK_CONTROL, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
        }
    }
}
