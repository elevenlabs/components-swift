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

import XCTest
import SwiftUI
@testable import ElevenLabsComponents

@MainActor
final class OrbVisualizerTests: XCTestCase {
    
    func testDefaultInitializer() {
        // Test that the default initializer works
        let visualizer = OrbVisualizer()
        XCTAssertNotNil(visualizer)
    }
    
    func testAgentStateInitializer() {
        // Test initializer with just agent state
        let visualizer = OrbVisualizer(agentState: .thinking)
        XCTAssertNotNil(visualizer)
    }
    
    func testAgentStateWithColorsInitializer() {
        // Test initializer with agent state and colors
        let visualizer = OrbVisualizer(
            agentState: .speaking,
            colors: (.blue, .green)
        )
        XCTAssertNotNil(visualizer)
    }
    
    func testAgentStateWithHexColorsInitializer() {
        // Test initializer with agent state and hex colors
        let visualizer = OrbVisualizer(
            agentState: .listening,
            color1Hex: "CADCFC",
            color2Hex: "A0B9D1"
        )
        XCTAssertNotNil(visualizer)
    }
    
    func testFullInitializerWithOptionalTracks() {
        // Test full initializer with optional tracks
        let visualizer = OrbVisualizer(
            inputTrack: nil,
            outputTrack: nil,
            agentState: .thinking,
            colors: (.purple, .pink)
        )
        XCTAssertNotNil(visualizer)
    }
    
    func testFullInitializerWithHexColors() {
        // Test full initializer with hex colors
        let visualizer = OrbVisualizer(
            inputTrack: nil,
            outputTrack: nil,
            agentState: .speaking,
            color1Hex: "FF6B6B",
            color2Hex: "4ECDC4"
        )
        XCTAssertNotNil(visualizer)
    }
    
    func testColorHexExtension() {
        // Test the Color hex extension
        let color1 = Color(hex: "FF0000") // Red
        let color2 = Color(hex: "#00FF00") // Green with hash
        let color3 = Color(hex: "0000FF") // Blue
        
        // These should not crash and should create valid colors
        XCTAssertNotNil(color1)
        XCTAssertNotNil(color2)
        XCTAssertNotNil(color3)
    }
    
    func testAgentStateEnum() {
        // Test that all AgentState cases are available
        let states: [AgentState] = [.unknown, .connecting, .initializing, .listening, .thinking, .speaking, .disconnected]
        
        for state in states {
            let visualizer = OrbVisualizer(agentState: state)
            XCTAssertNotNil(visualizer)
        }
    }
    
    func testOrbComponent() {
        // Test the underlying Orb component
        let orb = Orb(
            color1: .blue,
            color2: .green,
            inputVolume: 0.5,
            outputVolume: 0.3,
            agentState: .speaking
        )
        XCTAssertNotNil(orb)
    }
} 