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
        lib = try? device.makeDefaultLibrary(bundle: Bundle.module)
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
/// Usage:
/// ```
/// let inputTrack: AudioTrack = ...
/// let outputTrack: AudioTrack = ...
/// let agentState: AgentState = ...
/// OrbVisualizer(inputTrack: inputTrack, outputTrack: outputTrack, agentState: agentState)
/// ```
///
/// - Parameters:
///   - inputTrack: The input `AudioTrack` providing audio data to be visualized.
///   - outputTrack: The output `AudioTrack` providing audio data to be visualized.
///   - agentState: Triggers transitions between visualizer animation states.
///   - colors: The 2 colors to be used to render the Orb
///
/// Example:
/// ```
/// OrbVisualizer(inputTrack: inputTrack, outputTrack: outputTrack, colors: (.blue, .cyan))
/// ```
public struct OrbVisualizer: View {
    public let colors: (Color, Color)

    private let agentState: AgentState

    @StateObject private var inputProcessor: AudioProcessor
    @StateObject private var outputProcessor: AudioProcessor

    public init(inputTrack: AudioTrack?, outputTrack: AudioTrack?,
                agentState: AgentState = .unknown,
                colors: (Color, Color) = (Color(red: 0.793, green: 0.863, blue: 0.988),
                                          Color(red: 0.627, green: 0.725, blue: 0.820)))
    {
        self.agentState = agentState
        self.colors = colors

        _inputProcessor = StateObject(wrappedValue: AudioProcessor(track: inputTrack, bandCount: 7))
        _outputProcessor = StateObject(wrappedValue: AudioProcessor(track: outputTrack, bandCount: 7))
    }

    public var body: some View {
        GeometryReader { geometry in
            let inputVolume = aggregateVolume(from: inputProcessor.bands)
            let outputVolume = aggregateVolume(from: outputProcessor.bands)

            let effectiveInputVolume = agentState == .thinking ? 1.0 : Float(inputVolume)

            Orb(color1: colors.0,
                color2: colors.1,
                inputVolume: Float(inputVolume),
                outputVolume: Float(outputVolume),
                agentState: agentState)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// Aggregates multiple frequency bands into a single volume value with intelligent weighting.
    /// Emphasizes mid-range frequencies where most speech and music energy is located.
    private func aggregateVolume(from bands: [Float]) -> Float {
        guard !bands.isEmpty else { return 0.0 }

        // Frequency weights: emphasize mid-range (indices 2-4) for speech/music
        // Lower weights for bass (0-1) and treble (5-6) frequencies
        let weights: [Float] = [1, 1, 1, 1, 1, 1.0, 1.0]

        var weightedSum: Float = 0.0
        var totalWeight: Float = 0.0

        for (index, band) in bands.enumerated() {
            let weight = index < weights.count ? weights[index] : 1.0
            weightedSum += band * weight
            totalWeight += weight
        }

        // Calculate weighted average and apply slight amplification for better responsiveness
        let weightedAverage = totalWeight > 0 ? weightedSum / totalWeight : 0.0

        // Apply a more aggressive power curve and amplification for better responsiveness
        // Use a lower power (0.6) to make quiet sounds more visible, and higher amplification (1.8)
        let enhanced = pow(weightedAverage, 0.6) * 1.8

        // Add a small baseline to ensure some movement even with quiet audio
        let withBaseline = enhanced + 0.05

        // Clamp to valid range
        return min(max(withBaseline, 0.0), 1.0)
    }
}

#if DEBUG
struct OrbVisualizer_Previews: PreviewProvider {
    struct AnimatedOrbPreview: View {
        let isInput: Bool
        let agentState: AgentState
        let colors: (Color, Color)

        @State private var volume: Float = 0.0
        @State private var timer: Timer?
        @State private var speechPhase: Float = 0.0
        @State private var isSpeaking: Bool = false
        @State private var pauseCounter: Int = 0

        var body: some View {
            VStack {
                Orb(
                    color1: colors.0,
                    color2: colors.1,
                    inputVolume: isInput ? volume : 0.0,
                    outputVolume: isInput ? 0.0 : volume,
                    agentState: agentState
                )
                .frame(width: 200, height: 200)

                Text(isInput ? "User Speaking" : "Agent \(stateLabel)")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
                isSpeaking = false
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
            switch agentState {
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

    static var previews: some View {
        Group {
            AnimatedOrbPreview(
                isInput: true,
                agentState: .listening,
                colors: (Color(red: 0.793, green: 0.863, blue: 0.988),
                         Color(red: 0.627, green: 0.725, blue: 0.820))
            )
            .padding()
            .previewDisplayName("User Speaking (Input)")

            AnimatedOrbPreview(
                isInput: false,
                agentState: .speaking,
                colors: (Color(red: 0.793, green: 0.863, blue: 0.988),
                         Color(red: 0.627, green: 0.725, blue: 0.820))
            )
            .padding()
            .previewDisplayName("Agent Speaking (Output)")

            AnimatedOrbPreview(
                isInput: false,
                agentState: .thinking,
                colors: (Color(red: 0.793, green: 0.863, blue: 0.988),
                         Color(red: 0.627, green: 0.725, blue: 0.820))
            )
            .padding()
            .previewDisplayName("Agent Thinking")
        }
    }
}
#endif
