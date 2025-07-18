/*
 * Original work Copyright 2024 LiveKit, Inc.
 * Modifications Copyright 2025 Eleven Labs Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import Foundation
import LiveKit
import MetalKit
import simd
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Color Hex Extension

extension Color {
    /// Initialize a Color from a hex string.
    /// - Parameter hex: Hex string (e.g., "CADCFC" or "#CADCFC")
    public init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

/// CPU-side uniforms must match `OrbUniforms` in `OrbShader.metal` byte‑for‑byte.
/// Stride = 96 bytes.
struct OrbUniforms {
    var time: Float = 0
    var animation: Float = 0
    var inverted: Float = 0
    var _pad0: Float = 0 // 16‑byte align
    var offsets: simd_float8 = .zero // only first 7 used
    var color1: simd_float4 = .zero
    var color2: simd_float4 = .zero
    var inputVolume: Float = 0
    var outputVolume: Float = 0
    var _pad1: SIMD2<Float> = .zero // to 96 bytes

    init() {}
}

/// Convert SwiftUI `Color` -> linear‑space simd_float4.
@inline(__always)
private func colorToSIMD4(_ color: Color) -> simd_float4 {
    #if os(macOS)
    let ns = NSColor(color)
    let rgb = ns.usingColorSpace(.deviceRGB) ?? ns
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
    rgb.getRed(&r, green: &g, blue: &b, alpha: &a)
    #else
    let ui = UIColor(color)
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
    ui.getRed(&r, green: &g, blue: &b, alpha: &a)
    #endif
    func sRGBToLinear(_ v: CGFloat) -> Float {
        if v <= 0.04045 { return Float(v / 12.92) }
        return Float(pow((v + 0.055) / 1.055, 2.4))
    }
    return .init(sRGBToLinear(r), sRGBToLinear(g), sRGBToLinear(b), Float(a))
}

/// Shared Metal renderer backing the SwiftUI representables.
class MetalOrbRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipeline: MTLRenderPipelineState!
    private var vertexBuffer: MTLBuffer!

    private var startTime: CFTimeInterval = CACurrentMediaTime()
    private var animationTime: Float = 0

    private var uniforms = OrbUniforms()
    private var randomOffsets: [Float] = []
    private var currentAgentState: AgentState = .unknown

    // MARK: - Init

    override init() {
        guard let d = MTLCreateSystemDefaultDevice(), let q = d.makeCommandQueue() else {
            fatalError("Metal not available")
        }
        device = d
        commandQueue = q
        super.init()
        generateRandomOffsets()
        buildBuffers()
        buildPipeline()
    }

    // MARK: - Public updaters

    func updateColors(color1: Color, color2: Color) {
        uniforms.color1 = colorToSIMD4(color1)
        uniforms.color2 = colorToSIMD4(color2)
    }

    func updateVolumes(input: Float, output: Float) {
        uniforms.inputVolume = max(0, min(1, input))
        uniforms.outputVolume = max(0, min(1, output))
    }

    func updateAgentState(_ state: AgentState) {
        // No longer inverting colors for thinking state
        uniforms.inverted = 0
        currentAgentState = state
    }

    // MARK: - MTKViewDelegate

    func mtkView(_: MTKView, drawableSizeWillChange _: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let cmd = commandQueue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }

        let fps = max(view.preferredFramesPerSecond, 1)
        // Slow down animation when thinking (0.02x speed instead of 0.1x)
        let animationSpeed: Float = currentAgentState == .thinking ? 0.02 : 0.1
        animationTime += (1.0 / Float(fps)) * animationSpeed
        uniforms.time = Float(CACurrentMediaTime() - startTime)
        uniforms.animation = animationTime
        uniforms.offsets = simd_float8(randomOffsets + [0])

        enc.setRenderPipelineState(pipeline)
        enc.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        var u = uniforms
        enc.setFragmentBytes(&u, length: MemoryLayout<OrbUniforms>.stride, index: 0)

        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }

    // MARK: - Private

    private func generateRandomOffsets() {
        randomOffsets = (0 ..< 7).map { _ in Float.random(in: 0 ... (Float.pi * 2)) }
    }

    private func buildBuffers() {
        // full‑screen quad
        let verts: [Float] = [
            -1, 1,
            -1, -1,
            1, 1,
            1, -1,
        ]
        vertexBuffer = device.makeBuffer(bytes: verts, length: verts.count * MemoryLayout<Float>.size, options: [])
    }

    private func buildPipeline() {
        // Try to load the Metal library from various sources
        var lib: MTLLibrary?

        // First try the module bundle (for SwiftPM)
        #if SWIFT_PACKAGE
        if let bundle = Bundle.allBundles.first(where: { $0.bundleIdentifier?.contains("ElevenLabsComponents") == true }) {
            lib = try? device.makeDefaultLibrary(bundle: bundle)
        }
        #endif

        // If not found, try the main bundle
        if lib == nil {
            lib = try? device.makeDefaultLibrary(bundle: .main)
        }

        // If still not found, try to create default library
        if lib == nil {
            lib = device.makeDefaultLibrary()
        }

        guard let library = lib else {
            fatalError("Unable to load Metal library – ensure OrbShader.metal is included in the target")
        }

        guard let vfn = library.makeFunction(name: "orbVertexShader"),
              let ffn = library.makeFunction(name: "orbFragmentShader")
        else {
            fatalError("Unable to find shader functions in Metal library")
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            pipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            fatalError("Orb pipeline creation failed: \(error)")
        }
    }
}

#if os(macOS)
struct _OrbPlatformView: NSViewRepresentable {
    var color1: Color
    var color2: Color
    var inputVolume: Float
    var outputVolume: Float
    var agentState: AgentState

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.delegate = context.coordinator
        configure(view: view)
        context.coordinator.updateAll(color1: color1, color2: color2, input: inputVolume, output: outputVolume, state: agentState)
        return view
    }

    func updateNSView(_: MTKView, context: Context) {
        context.coordinator.updateAll(color1: color1, color2: color2, input: inputVolume, output: outputVolume, state: agentState)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func configure(view: MTKView) {
        view.framebufferOnly = false
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 60
        view.clearColor = .init(red: 0, green: 0, blue: 0, alpha: 0)
        view.colorPixelFormat = .bgra8Unorm
        view.autoResizeDrawable = true
    }

    final class Coordinator: MetalOrbRenderer {
        func updateAll(color1: Color, color2: Color, input: Float, output: Float, state: AgentState) {
            updateColors(color1: color1, color2: color2)
            updateVolumes(input: input, output: output)
            updateAgentState(state)
        }
    }
}
#else
struct _OrbPlatformView: UIViewRepresentable {
    var color1: Color
    var color2: Color
    var inputVolume: Float
    var outputVolume: Float
    var agentState: AgentState

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.delegate = context.coordinator
        configure(view: view)
        context.coordinator.updateAll(color1: color1, color2: color2, input: inputVolume, output: outputVolume, state: agentState)
        return view
    }

    func updateUIView(_: MTKView, context: Context) {
        context.coordinator.updateAll(color1: color1, color2: color2, input: inputVolume, output: outputVolume, state: agentState)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func configure(view: MTKView) {
        view.framebufferOnly = false
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 60
        view.clearColor = .init(red: 0, green: 0, blue: 0, alpha: 0)
        view.colorPixelFormat = .bgra8Unorm
        view.autoResizeDrawable = true
    }

    final class Coordinator: MetalOrbRenderer {
        func updateAll(color1: Color, color2: Color, input: Float, output: Float, state: AgentState) {
            updateColors(color1: color1, color2: color2)
            updateVolumes(input: input, output: output)
            updateAgentState(state)
        }
    }
}
#endif

public struct Orb: View {
    public var color1: Color
    public var color2: Color
    public var inputVolume: Float
    public var outputVolume: Float
    public var agentState: AgentState

    public init(color1: Color, color2: Color, inputVolume: Float, outputVolume: Float, agentState: AgentState = .unknown) {
        self.color1 = color1
        self.color2 = color2
        self.inputVolume = inputVolume
        self.outputVolume = outputVolume
        self.agentState = agentState
    }

    public var body: some View {
        GeometryReader { geo in
            let side = max(1, min(geo.size.width, geo.size.height))

            // Override input volume to 1.0 when thinking
            let effectiveInputVolume = agentState == .thinking ? 1.0 : inputVolume

            _OrbPlatformView(
                color1: color1,
                color2: color2,
                inputVolume: effectiveInputVolume,
                outputVolume: outputVolume,
                agentState: agentState
            )
            .frame(width: side, height: side)
            .clipShape(Circle())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(Text("Orb visualizer"))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// A SwiftUI view that visualizes audio levels and agent states as an animated Orb.
/// This visualizer is specifically designed to provide visual feedback for different agent states
/// (connecting, initializing, listening, thinking, speaking) while also responding to real-time
/// audio data when available.
///
/// `OrbVisualizer` is a metal shader whose Orb animates dynamically
/// to reflect the magnitude of audio frequencies in real time, creating an
/// interactive, visual representation of the audio track's spectrum. This
/// visualizer can be customized.
///
/// ## Usage Examples
///
/// ### Basic usage with default colors:
/// ```swift
/// OrbVisualizer()
/// ```
///
/// ### With audio tracks and agent state:
/// ```swift
/// OrbVisualizer(
///     inputTrack: inputTrack,
///     outputTrack: outputTrack,
///     agentState: .speaking
/// )
/// ```
///
/// ### With custom colors:
/// ```swift
/// OrbVisualizer(
///     inputTrack: inputTrack,
///     outputTrack: outputTrack,
///     agentState: .thinking,
///     colors: (.blue, .green)
/// )
/// ```
///
/// ### With hex colors:
/// ```swift
/// OrbVisualizer(
///     inputTrack: inputTrack,
///     outputTrack: outputTrack,
///     agentState: .listening,
///     color1Hex: "CADCFC",
///     color2Hex: "A0B9D1"
/// )
/// ```
///
/// ### Standalone orb without audio tracks:
/// ```swift
/// OrbVisualizer(
///     agentState: .thinking,
///     colors: (.purple, .pink)
/// )
/// ```
public struct OrbVisualizer: View {
    public let colors: (Color, Color)
    private let agentState: AgentState
    private let inputTrack: AudioTrack?
    private let outputTrack: AudioTrack?

    @StateObject private var inputProcessor: AudioProcessor
    @StateObject private var outputProcessor: AudioProcessor

    // MARK: - Initializers

    /// Initialize an OrbVisualizer with default settings.
    /// This creates a standalone orb that responds to agent state changes only.
    public init() {
        self.init(inputTrack: nil, outputTrack: nil, agentState: .unknown)
    }

    /// Initialize an OrbVisualizer with agent state only.
    /// - Parameter agentState: The current agent state to visualize
    public init(agentState: AgentState) {
        self.init(inputTrack: nil, outputTrack: nil, agentState: agentState)
    }

    /// Initialize an OrbVisualizer with custom colors and agent state.
    /// - Parameters:
    ///   - agentState: The current agent state to visualize
    ///   - colors: Tuple of two colors for the orb gradient
    public init(agentState: AgentState, colors: (Color, Color)) {
        self.init(inputTrack: nil, outputTrack: nil, agentState: agentState, colors: colors)
    }

    /// Initialize an OrbVisualizer with hex colors and agent state.
    /// - Parameters:
    ///   - agentState: The current agent state to visualize
    ///   - color1Hex: First color as hex string (e.g., "CADCFC" or "#CADCFC")
    ///   - color2Hex: Second color as hex string (e.g., "A0B9D1" or "#A0B9D1")
    public init(agentState: AgentState, color1Hex: String, color2Hex: String) {
        self.init(inputTrack: nil, outputTrack: nil, agentState: agentState, color1Hex: color1Hex, color2Hex: color2Hex)
    }

    /// Initialize an OrbVisualizer with audio tracks and optional parameters.
    /// - Parameters:
    ///   - inputTrack: The input `AudioTrack` providing audio data to be visualized (optional)
    ///   - outputTrack: The output `AudioTrack` providing audio data to be visualized (optional)
    ///   - agentState: Triggers transitions between visualizer animation states
    ///   - colors: The 2 colors to be used to render the Orb
    public init(inputTrack: AudioTrack? = nil,
                outputTrack: AudioTrack? = nil,
                agentState: AgentState = .unknown,
                colors: (Color, Color) = (Color(red: 0.793, green: 0.863, blue: 0.988),
                                          Color(red: 0.627, green: 0.725, blue: 0.820)))
    {
        self.inputTrack = inputTrack
        self.outputTrack = outputTrack
        self.agentState = agentState
        self.colors = colors

        _inputProcessor = StateObject(wrappedValue: AudioProcessor(track: inputTrack, bandCount: 1))
        _outputProcessor = StateObject(wrappedValue: AudioProcessor(track: outputTrack, bandCount: 1))
    }
    
    /// Initialize an OrbVisualizer with audio tracks and hex colors.
    /// - Parameters:
    ///   - inputTrack: The input `AudioTrack` providing audio data to be visualized (optional)
    ///   - outputTrack: The output `AudioTrack` providing audio data to be visualized (optional)
    ///   - agentState: Triggers transitions between visualizer animation states
    ///   - color1Hex: First color as hex string (e.g., "CADCFC" or "#CADCFC")
    ///   - color2Hex: Second color as hex string (e.g., "A0B9D1" or "#A0B9D1")
    public init(inputTrack: AudioTrack? = nil,
                outputTrack: AudioTrack? = nil,
                agentState: AgentState = .unknown,
                color1Hex: String, color2Hex: String) {
        self.inputTrack = inputTrack
        self.outputTrack = outputTrack
        self.agentState = agentState
        self.colors = (Color(hex: color1Hex), Color(hex: color2Hex))
        
        _inputProcessor = StateObject(wrappedValue: AudioProcessor(track: inputTrack, bandCount: 1))
        _outputProcessor = StateObject(wrappedValue: AudioProcessor(track: outputTrack, bandCount: 1))
    }

    public var body: some View {
        GeometryReader { geometry in
            let inputVolume = inputProcessor.bands.first ?? 0
            let outputVolume = outputProcessor.bands.first ?? 0

            // Override input volume to 1.0 when thinking
            let effectiveInputVolume = agentState == .thinking ? 1.0 : Float(inputVolume)

            Orb(color1: colors.0,
                color2: colors.1,
                inputVolume: effectiveInputVolume,
                outputVolume: Float(outputVolume),
                agentState: agentState)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Previews

#if DEBUG
struct OrbVisualizer_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Basic standalone orb
            VStack {
                Text("Standalone Orb")
                    .font(.headline)
                OrbVisualizer(agentState: .thinking)
                    .frame(width: 200, height: 200)
            }
            .padding()
            .previewDisplayName("Standalone Orb")

            // Agent states showcase
            VStack(spacing: 20) {
                Text("Agent States")
                    .font(.headline)
                
                HStack(spacing: 20) {
                    VStack {
                        OrbVisualizer(agentState: .listening)
                            .frame(width: 100, height: 100)
                        Text("Listening")
                            .font(.caption)
                    }
                    
                    VStack {
                        OrbVisualizer(agentState: .thinking)
                            .frame(width: 100, height: 100)
                        Text("Thinking")
                            .font(.caption)
                    }
                    
                    VStack {
                        OrbVisualizer(agentState: .speaking)
                            .frame(width: 100, height: 100)
                        Text("Speaking")
                            .font(.caption)
                    }
                }
            }
            .padding()
            .previewDisplayName("Agent States")

            // Color variations
            VStack(spacing: 20) {
                Text("Color Variations")
                    .font(.headline)
                
                HStack(spacing: 20) {
                    VStack {
                        OrbVisualizer(agentState: .speaking, colors: (.blue, .green))
                            .frame(width: 100, height: 100)
                        Text("Blue/Green")
                            .font(.caption)
                    }
                    
                    VStack {
                        OrbVisualizer(agentState: .speaking, colors: (.purple, .pink))
                            .frame(width: 100, height: 100)
                        Text("Purple/Pink")
                            .font(.caption)
                    }
                    
                    VStack {
                        OrbVisualizer(agentState: .speaking, color1Hex: "FF6B6B", color2Hex: "4ECDC4")
                            .frame(width: 100, height: 100)
                        Text("Hex Colors")
                            .font(.caption)
                    }
                }
            }
            .padding()
            .previewDisplayName("Color Variations")

            // Animated preview
            AnimatedOrbPreview()
                .padding()
                .previewDisplayName("Animated Preview")
        }
    }
}

struct AnimatedOrbPreview: View {
    @State private var currentState: AgentState = .listening
    @State private var volume: Float = 0.0
    @State private var timer: Timer?
    @State private var speechPhase: Float = 0.0
    @State private var pauseCounter: Int = 0

    var body: some View {
        VStack(spacing: 20) {
            Text("Animated Preview")
                .font(.headline)
            
            OrbVisualizer(agentState: currentState, colors: (.blue, .green))
                .frame(width: 200, height: 200)
            
            Text("Current State: \(stateLabel)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 20) {
                Button("Listening") { currentState = .listening }
                Button("Thinking") { currentState = .thinking }
                Button("Speaking") { currentState = .speaking }
            }
        }
        .onAppear {
            // Simulate audio volume changes
            timer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { _ in
                DispatchQueue.main.async {
                    updateVolume()
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    private func updateVolume() {
        speechPhase += 0.1

        if pauseCounter > 0 {
            pauseCounter -= 1
            withAnimation(.easeOut(duration: 0.1)) {
                volume = volume * 0.85 + 0.05 * 0.15
            }
            return
        }

        // Random chance to pause (breathing, thinking)
        if Int.random(in: 0 ..< 100) < 3 {
            pauseCounter = Int.random(in: 10 ... 30) // 0.3 to 0.9 seconds
            return
        }

        // Natural speech envelope
        let basePattern = sin(speechPhase * 2.5) * 0.3 + 0.5
        let microVariation = sin(speechPhase * 15) * 0.1
        let emphasis = sin(speechPhase * 0.8) * 0.2

        // Combine patterns for natural speech
        var targetVolume = basePattern + microVariation + emphasis

        // Add occasional emphasis/loudness
        if Int.random(in: 0 ..< 100) < 5 {
            targetVolume += Float.random(in: 0.1 ... 0.3)
        }

        // Clamp and add noise
        targetVolume = min(max(targetVolume, 0.1), 0.95)
        targetVolume += Float.random(in: -0.05 ... 0.05)

        // Smooth transition
        withAnimation(.linear(duration: 0.03)) {
            volume = volume * 0.7 + targetVolume * 0.3
        }
    }

    private var stateLabel: String {
        switch currentState {
        case .listening:
            "Listening"
        case .thinking:
            "Thinking"
        case .speaking:
            "Speaking"
        default:
            "Unknown"
        }
    }
}
#endif
