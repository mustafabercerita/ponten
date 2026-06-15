import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

class ImageProcessor {
    
    /// Shared CIContext to prevent expensive reallocations and Metal shader recompilations on every filter call
    private static let sharedCIContext = CIContext(options: nil)
    
    /// Thickens dark lines by rendering over a white background and applying morphological minimum
    static func thickenLines(image: NSImage, radius: Double) -> NSImage? {
        guard radius > 0 else { return image }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        
        // Add padding to prevent the thickened lines from being clipped
        let padding = Int(ceil(radius)) + 10
        
        // 1. Draw over white background with padding
        let width = cgImage.width + (padding * 2)
        let height = cgImage.height + (padding * 2)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        
        // Draw the original image centered
        context.draw(cgImage, in: CGRect(x: padding, y: padding, width: cgImage.width, height: cgImage.height))
        
        guard let whiteBgCGImage = context.makeImage() else { return nil }
        let ciImage = CIImage(cgImage: whiteBgCGImage)
        
        // 2. Morphology Minimum
        let filter = CIFilter.morphologyMinimum()
        filter.inputImage = ciImage
        filter.radius = Float(radius)
        
        guard let outputImage = filter.outputImage else { return nil }
        guard let finalCGImage = sharedCIContext.createCGImage(outputImage, from: ciImage.extent) else { return nil }
        
        return NSImage(cgImage: finalCGImage, size: NSSize(width: width, height: height))
    }
    
    /// Adjusts contrast and brightness of an NSImage
    static func adjustColor(image: NSImage, contrast: Double, brightness: Double) -> NSImage? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let ciImage = CIImage(bitmapImageRep: bitmap) else {
            return nil
        }
        
        let filter = CIFilter.colorControls()
        filter.inputImage = ciImage
        filter.contrast = Float(contrast)
        filter.brightness = Float(brightness)
        // Saturation 0 to make the ink purely black/white without color tint
        filter.saturation = 0.0
        
        guard let outputImage = filter.outputImage else { return nil }
        guard let finalCGImage = sharedCIContext.createCGImage(outputImage, from: ciImage.extent) else { return nil }
        
        return NSImage(cgImage: finalCGImage, size: image.size)
    }
    
    /// Rotates the image by a given degree (usually 90, 180, 270, -90)
    static func rotate(image: NSImage, degrees: CGFloat) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        
        let radians = degrees * .pi / 180.0
        var rect = CGRect(origin: .zero, size: CGSize(width: cgImage.width, height: cgImage.height))
        rect = rect.applying(CGAffineTransform(rotationAngle: radians))
        
        let newWidth = Int(rect.width)
        let newHeight = Int(rect.height)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        
        guard let ctx = context else { return nil }
        ctx.translateBy(x: CGFloat(newWidth) / 2, y: CGFloat(newHeight) / 2)
        ctx.rotate(by: radians)
        ctx.translateBy(x: -CGFloat(cgImage.width) / 2, y: -CGFloat(cgImage.height) / 2)
        
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        
        guard let newCGImage = ctx.makeImage() else { return nil }
        return NSImage(cgImage: newCGImage, size: NSSize(width: newWidth, height: newHeight))
    }
    
    /// Automatically crops out purely white or transparent borders around the ink
    static func autoTrimWhitespace(image: NSImage) -> NSImage? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return image }
        
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        
        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        var hasInk = false
        
        for y in 0..<height {
            for x in 0..<width {
                guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                
                // If it's transparent, skip
                if color.alphaComponent < 0.05 { continue }
                // If it's very white, skip
                if color.redComponent > 0.94 && color.greenComponent > 0.94 && color.blueComponent > 0.94 { continue }
                
                // It's ink!
                hasInk = true
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        
        if !hasInk { return image }
        
        // Add a small padding
        let padding = 10
        minX = max(0, minX - padding)
        minY = max(0, minY - padding)
        maxX = min(width - 1, maxX + padding)
        maxY = min(height - 1, maxY + padding)
        
        let cropRect = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let croppedCGImage = cgImage.cropping(to: cropRect) else { return nil }
        
        return NSImage(cgImage: croppedCGImage, size: NSSize(width: croppedCGImage.width, height: croppedCGImage.height))
    }
}
