import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

class ImageProcessor {
    
    /// Thickens dark lines by rendering over a white background and applying morphological minimum
    static func thickenLines(image: NSImage, radius: Double) -> NSImage? {
        guard radius > 0 else { return image }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        
        // 1. Draw over white background
        let width = cgImage.width
        let height = cgImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let whiteBgCGImage = context.makeImage() else { return nil }
        let ciImage = CIImage(cgImage: whiteBgCGImage)
        
        // 2. Morphology Minimum
        let filter = CIFilter.morphologyMinimum()
        filter.inputImage = ciImage
        filter.radius = Float(radius)
        
        guard let outputImage = filter.outputImage else { return nil }
        let ciContext = CIContext(options: nil)
        guard let finalCGImage = ciContext.createCGImage(outputImage, from: ciImage.extent) else { return nil }
        
        return NSImage(cgImage: finalCGImage, size: image.size)
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
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else { return nil }
        
        return NSImage(cgImage: cgImage, size: image.size)
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
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var pixelData = [UInt8](repeating: 0, count: height * bytesPerRow)
        
        let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        
        guard let ctx = context else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        
        var hasInk = false
        
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * bytesPerRow) + (x * bytesPerPixel)
                let r = pixelData[offset]
                let g = pixelData[offset + 1]
                let b = pixelData[offset + 2]
                let a = pixelData[offset + 3]
                
                // If it's transparent, skip
                if a < 10 { continue }
                // If it's very white, skip
                if r > 240 && g > 240 && b > 240 { continue }
                
                // It's ink!
                hasInk = true
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        
        if !hasInk { return image } // Blank image, return as is
        
        // Add a small padding
        let padding = 10
        minX = max(0, minX - padding)
        minY = max(0, minY - padding)
        maxX = min(width - 1, maxX + padding)
        maxY = min(height - 1, maxY + padding)
        
        let cropRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else { return nil }
        
        return NSImage(cgImage: croppedCGImage, size: NSSize(width: croppedCGImage.width, height: croppedCGImage.height))
    }
}
