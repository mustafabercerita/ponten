import SwiftUI
import AppKit

enum PenStyle: String, CaseIterable, Identifiable {
    case normal = "Normal"
    case calligraphy = "Calligraphy"
    var id: String { rawValue }
}

struct DrawingLine: Identifiable {
    let id = UUID()
    var points: [CGPoint] = []
    var thickness: CGFloat = 3.0
    var style: PenStyle = .normal
}

struct DrawingView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject private var manager: SignatureManager
    
    @State private var lines: [DrawingLine] = []
    @State private var currentLine = DrawingLine()
    
    @State private var penThickness: CGFloat = 3.0
    @State private var penStyle: PenStyle = .normal
    
    let canvasSize = CGSize(width: 400, height: 200)
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Draw Signature")
                    .font(.headline)
                Spacer()
                Button(action: {
                    lines.removeAll()
                    currentLine = DrawingLine(thickness: penThickness, style: penStyle)
                }) {
                    Text("Clear")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
            }
            .padding()
            
            // Controls
            HStack {
                Text("Thickness:")
                    .font(.subheadline)
                Slider(value: $penThickness, in: 1...10, step: 0.5)
                    .frame(width: 100)
                
                Spacer()
                
                Picker("Style", selection: $penStyle) {
                    Text("Normal").tag(PenStyle.normal)
                    Text("Calligraphy").tag(PenStyle.calligraphy)
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 150)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            
            Divider()
            
            // Canvas
            ZStack {
                Color.white // Ensure white background for contrast while drawing, we'll strip it later.
                
                Canvas { context, size in
                    let allLines = lines + [currentLine]
                    for line in allLines {
                        guard !line.points.isEmpty else { continue }
                        var path = Path()
                        path.addLines(line.points)
                        
                        if line.style == .normal {
                            context.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: line.thickness, lineCap: .round, lineJoin: .round))
                        } else {
                            // Calligraphy simulation
                            let style = StrokeStyle(lineWidth: max(1, line.thickness * 0.5), lineCap: .square, lineJoin: .miter)
                            let transform = CGAffineTransform(translationX: line.thickness * 0.3, y: -line.thickness * 0.3)
                            let path2 = path.applying(transform)
                            context.stroke(path, with: .color(.black), style: style)
                            context.stroke(path2, with: .color(.black), style: style)
                        }
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            if currentLine.points.isEmpty {
                                currentLine.thickness = penThickness
                                currentLine.style = penStyle
                            }
                            let newPoint = value.location
                            currentLine.points.append(newPoint)
                        }
                        .onEnded { value in
                            lines.append(currentLine)
                            currentLine = DrawingLine(thickness: penThickness, style: penStyle)
                        }
                )
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
            .border(Color.gray.opacity(0.2), width: 1)
            
            Divider()
            
            // Footer
            HStack {
                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(SecondaryButtonStyle())
                
                Spacer()
                
                Button("Save Signature") {
                    saveSignature()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(lines.isEmpty && currentLine.points.isEmpty)
            }
            .padding()
        }
        .frame(width: canvasSize.width)
    }
    
    @MainActor
    private func saveSignature() {
        let exportView = ZStack {
            Color.clear // Transparent background
            Canvas { context, size in
                for line in lines {
                    guard !line.points.isEmpty else { continue }
                    var path = Path()
                    path.addLines(line.points)
                    if line.style == .normal {
                        context.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: line.thickness, lineCap: .round, lineJoin: .round))
                    } else {
                        let style = StrokeStyle(lineWidth: max(1, line.thickness * 0.5), lineCap: .square, lineJoin: .miter)
                        let transform = CGAffineTransform(translationX: line.thickness * 0.3, y: -line.thickness * 0.3)
                        let path2 = path.applying(transform)
                        context.stroke(path, with: .color(.black), style: style)
                        context.stroke(path2, with: .color(.black), style: style)
                    }
                }
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        
        let renderer = ImageRenderer(content: exportView)
        renderer.scale = 2.0 // Retina quality
        
        if let nsImage = renderer.nsImage {
            do {
                try manager.saveSignature(image: nsImage, removeBackground: false) // Background is already clear!
                presentationMode.wrappedValue.dismiss()
            } catch {
                manager.showToast("Failed to save drawing: \(error.localizedDescription)")
            }
        }
    }
}
