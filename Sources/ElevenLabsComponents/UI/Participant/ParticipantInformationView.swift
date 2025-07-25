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

public struct ParticipantInformationView: View {
    @EnvironmentObject private var _participant: Participant
    @Environment(\.elevenUIOptions) private var _ui: UIOptions

    public var body: some View {
        HStack(spacing: _ui.paddingSmall) {
            if let identity = _participant.identity {
                Text(String(describing: identity))
                    .fontWeight(.bold)
            }

            if let audio = _participant.firstAudioPublication {
                if audio.isSubscribed, !audio.isMuted {
                    _ui.micEnabledView()
                } else {
                    _ui.micDisabledView()
                }
            } else {
                _ui.micDisabledView()
            }

            ConnectionQualityIndicatorView()
        }
    }
}
