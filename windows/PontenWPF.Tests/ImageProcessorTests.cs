using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using PontenWPF;

namespace PontenWPF.Tests;

public class ImageProcessorTests
{
    private readonly ImageProcessor _processor = new();

    [Fact]
    public void ValidateWhiteBackground_PassesForWhiteBorderedImage()
    {
        using var bitmap = CreateWhiteBorderedImage(100, 100);
        Assert.True(_processor.ValidateWhiteBackground(bitmap));
    }

    [Fact]
    public void ValidateWhiteBackground_FailsForDarkEdges()
    {
        using var bitmap = new Bitmap(100, 100, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(bitmap))
        {
            g.Clear(Color.Black);
        }

        Assert.False(_processor.ValidateWhiteBackground(bitmap));
    }

    [Fact]
    public void ValidateWhiteBackground_SmallImagePasses()
    {
        using var bitmap = new Bitmap(8, 8, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(bitmap))
        {
            g.Clear(Color.Black);
        }

        Assert.True(_processor.ValidateWhiteBackground(bitmap));
    }

    [Fact]
    public void AdjustColor_ReturnsBitmapOfSameSize()
    {
        using var bitmap = CreateWhiteBorderedImage(50, 50);
        using var result = _processor.AdjustColor(bitmap, 1.5, 0.1);

        Assert.Equal(50, result.Width);
        Assert.Equal(50, result.Height);
    }

    [Fact]
    public void AdjustColor_DesaturatesColoredPixels()
    {
        using var bitmap = new Bitmap(3, 3, PixelFormat.Format32bppArgb);
        bitmap.SetPixel(1, 1, Color.FromArgb(255, 200, 40, 40));

        using var result = _processor.AdjustColor(bitmap, 1.0, 0.0);
        Color center = result.GetPixel(1, 1);

        Assert.InRange(center.R, center.G - 2, center.G + 2);
        Assert.InRange(center.R, center.B - 2, center.B + 2);
    }

    [Fact]
    public void AutoTrimWhitespace_TrimsToContent()
    {
        using var bitmap = CreateWhiteWithBlackSquare(100, 100, 40, 40, 20, 20);
        using var result = _processor.AutoTrimWhitespace(bitmap, 0);

        Assert.True(result.Width <= 21);
        Assert.True(result.Height <= 21);
    }

    [Fact]
    public void WritePngAtomic_WritesFileSuccessfully()
    {
        string directory = Path.Combine(Path.GetTempPath(), "ponten-test-" + Guid.NewGuid());
        string path = Path.Combine(directory, "signature.png");
        byte[] pngBytes = CreateMinimalPngBytes();

        try
        {
            ImageProcessor.WritePngAtomic(path, pngBytes);

            Assert.True(File.Exists(path));
            Assert.Equal(pngBytes.Length, new FileInfo(path).Length);
        }
        finally
        {
            if (Directory.Exists(directory))
            {
                Directory.Delete(directory, recursive: true);
            }
        }
    }

    [Fact]
    public void WritePngAtomic_ThrowsUserFacingMessageOnReadOnlyFile()
    {
        string directory = Path.Combine(Path.GetTempPath(), "ponten-test-" + Guid.NewGuid());
        string path = Path.Combine(directory, "signature.png");
        byte[] pngBytes = CreateMinimalPngBytes();

        try
        {
            ImageProcessor.WritePngAtomic(path, pngBytes);
            File.SetAttributes(path, FileAttributes.ReadOnly);

            var ex = Assert.Throws<IOException>(() => ImageProcessor.WritePngAtomic(path, pngBytes));

            Assert.Contains("Failed to save signature", ex.Message, StringComparison.Ordinal);
        }
        finally
        {
            if (File.Exists(path))
            {
                File.SetAttributes(path, FileAttributes.Normal);
            }

            if (Directory.Exists(directory))
            {
                Directory.Delete(directory, recursive: true);
            }
        }
    }

    private static byte[] CreateMinimalPngBytes()
    {
        using var bitmap = new Bitmap(4, 4, PixelFormat.Format32bppArgb);
        using var stream = new MemoryStream();
        bitmap.Save(stream, ImageFormat.Png);
        return stream.ToArray();
    }

    private static Bitmap CreateWhiteBorderedImage(int width, int height)
    {
        var bitmap = new Bitmap(width, height, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(bitmap))
        {
            g.Clear(Color.White);
            g.FillRectangle(Brushes.Black, width / 2 - 10, height / 2 - 10, 20, 20);
        }
        return bitmap;
    }

    private static Bitmap CreateWhiteWithBlackSquare(int width, int height, int x, int y, int squareWidth, int squareHeight)
    {
        var bitmap = new Bitmap(width, height, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(bitmap))
        {
            g.Clear(Color.White);
            g.FillRectangle(Brushes.Black, x, y, squareWidth, squareHeight);
        }
        return bitmap;
    }
}