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

@_exported import LiveKit
@_exported import SwiftUI

public let elevenlabsComponentsVersion = "0.1.1"

public typealias ComponentBuilder<Content: View> = () -> Content
public typealias ParticipantComponentBuilder<Content: View> = (_: Participant) -> Content
public typealias TrackReferenceComponentBuilder<Content: View> = (_: TrackReference) -> Content
public typealias ParticipantLayoutBuilder<Content: View> = (_ participant: Participant,
                                                            _ geometry: GeometryProxy) -> Content
