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

import LiveKit
import SwiftUI

public struct LocalCameraVideoView: View {
    @EnvironmentObject private var _room: Room
    @Environment(\.elevenUIOptions) private var _ui: UIOptions

    public init() {}

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                _ui.videoDisabledView(geometry: geometry)

                if let track = _room.localParticipant.firstCameraVideoTrack {
                    SwiftUIVideoView(track)
                }
            }
        }
    }
}
