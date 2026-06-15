import SwiftUI

struct ImageEditorView: View {
    @EnvironmentObject private var manager: SignatureManager
    
    let sourceImage: NSImage
    
    @State private var contrast: Double = 1.0
    @State private var brightness: Double = 0.0
    @State private var thicken: Double = 0.0
    @State private var rotation: Double = 0
    @State private var autoTrim: Bool = true
    @State private var removeBackground: Bool = true
    
    @State private var previewImage: NSImage?
    @State private var isProcessingPreview: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit Signature")
                    .font(.headline)
                Spacer()
                Button(action: {
                    manager.pendingImageToEdit = nil
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            
            Divider()
            
            // Preview Area
            ZStack {
                Color(NSColor.controlBackgroundColor)
                
                if let img = previewImage {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .padding(20)
                }
                
                if isProcessingPreview {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                }
            }
            .frame(height: 200)
            
            Divider()
            
            // Controls
            VStack(spacing: 16) {
                // Rotation
                HStack {
                    Text("Rotate")
                        .frame(width: 80, alignment: .leading)
                    Button(action: { rotation -= 90 }) {
                        Image(systemName: "rotate.left")
                    }
                    Button(action: { rotation += 90 }) {
                        Image(systemName: "rotate.right")
                    }
                    Spacer()
                }
                
                // Contrast Slider
                HStack {
                    Text("Contrast")
                        .frame(width: 80, alignment: .leading)
                    Slider(value: $contrast, in: 0.5...3.0)
                    Text(String(format: "%.1f", contrast))
                        .frame(width: 30, alignment: .trailing)
                }
                
                // Brightness Slider
                HStack {
                    Text("Brightness")
                        .frame(width: 80, alignment: .leading)
                    Slider(value: $brightness, in: -0.5...0.5)
                    Text(String(format: "%.1f", brightness))
                        .frame(width: 30, alignment: .trailing)
                }
                
                // Thicken Slider
                HStack {
                    Text("Thicken")
                        .frame(width: 80, alignment: .leading)
                    Slider(value: $thicken, in: 0.0...30.0)
                    Text(String(format: "%.0f", thicken))
                        .frame(width: 30, alignment: .trailing)
                }
                
                HStack(spacing: 24) {
                    Toggle("Auto-Trim Margins", isOn: $autoTrim)
                    Toggle("Remove Background", isOn: $removeBackground)
                }
                .padding(.top, 4)
            }
            .padding(16)
            
            Divider()
            
            // Actions
            HStack {
                Button("Cancel") {
                    manager.pendingImageToEdit = nil
                    manager.pendingEditSignatureID = nil
                }
                .keyboardShortcut(.escape, modifiers: [])
                
                Spacer()
                
                Button("Save Signature") {
                    saveEditedImage()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(isProcessingPreview || previewImage == nil)
            }
            .padding(16)
        }
        .frame(width: 400)
        .onAppear {
            updatePreview()
        }
        .onChange(of: contrast) { _ in updatePreview() }
        .onChange(of: brightness) { _ in updatePreview() }
        .onChange(of: thicken) { _ in updatePreview() }
        .onChange(of: rotation) { _ in updatePreview() }
        .onChange(of: autoTrim) { _ in updatePreview() }
        .onChange(of: removeBackground) { _ in updatePreview() }
    }
    
    private func updatePreview() {
        isProcessingPreview = true
        
        let currentContrast = contrast
        let currentBrightness = brightness
        let currentThicken = thicken
        let currentRotation = rotation
        let currentAutoTrim = autoTrim
        let currentRemoveBg = removeBackground
        
        DispatchQueue.global(qos: .userInitiated).async {
            var img = sourceImage
            
            // 0. Thicken Lines
            if currentThicken > 0 {
                if let thickened = ImageProcessor.thickenLines(image: img, radius: currentThicken) {
                    img = thickened
                }
            }
            
            // 1. Color Adjustments
            if let colorAdjusted = ImageProcessor.adjustColor(image: img, contrast: currentContrast, brightness: currentBrightness) {
                img = colorAdjusted
            }
            
            // 2. Rotation
            if currentRotation != 0 {
                if let rotated = ImageProcessor.rotate(image: img, degrees: CGFloat(currentRotation)) {
                    img = rotated
                }
            }
            
            // 3. Remove Background & Vectorize preview (Optional)
            // For preview, we only do the removeBackground if requested, vectorize can be heavy so we just do it on final save,
            // or we can do it here. Ponten uses `removingWhiteBackground()`
            if currentRemoveBg {
                if let removed = img.removingWhiteBackground() {
                    img = removed
                }
            }
            
            // 4. Auto-Trim
            if currentAutoTrim {
                if let trimmed = ImageProcessor.autoTrimWhitespace(image: img) {
                    img = trimmed
                }
            }
            
            DispatchQueue.main.async {
                self.previewImage = img
                self.isProcessingPreview = false
            }
        }
    }
    
    private func saveEditedImage() {
        guard let finalImage = previewImage else { return }
        
        let targetID = manager.pendingEditSignatureID
        manager.pendingImageToEdit = nil
        manager.pendingEditSignatureID = nil
        manager.isProcessing = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try manager.saveSignature(image: finalImage, removeBackground: false, vectorize: removeBackground, overwriteID: targetID)
                DispatchQueue.main.async {
                    manager.isProcessing = false
                }
            } catch {
                DispatchQueue.main.async {
                    manager.errorMessage = error.localizedDescription
                    manager.isProcessing = false
                }
            }
        }
    }
}
