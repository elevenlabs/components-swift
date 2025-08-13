<!--BEGIN_BANNER_IMAGE-->

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="/.github/banner_dark.png">
  <source media="(prefers-color-scheme: light)" srcset="/.github/banner_light.png">
  <img style="width:100%;" alt="The ElevenLabs logo and an Orb." src="https://raw.githubusercontent.com/elevenlabs/components-swift/main/.github/banner_light.png">
</picture>

<!--END_BANNER_IMAGE-->

# Swift Components

<!--BEGIN_DESCRIPTION-->

A collection of Swift voice components.

<!--END_DESCRIPTION-->
## Orb Visualizer

<p align="center">
  <table>
    <tr>
      <td valign="middle">
        <img width="200" height="200" alt="Orb Visualizer" src="https://github.com/user-attachments/assets/35a4c016-f06a-4e69-b8d1-5c9c8ad256d2" />
      </td>
      <td valign="middle">
        <pre><code class="language-swift">OrbVisualizer(
  inputTrack: nil,
  outputTrack: nil,
  agentState: .listening,
  colors: (Color(hex: "CADCFC"), Color(hex: "A0B9D1"))
)</code></pre>
      </td>
    </tr>
  </table>
  <sub>Orb visualizer with Swift usage example.</sub>
</p>

A SwiftUI view that visualizes audio levels and agent state as an animated Orb. Pass `AudioTrack` instances for real-time visualization, optional `agentState` to reflect status, and two `Color` values to customize the Orb.

### Parameters

- inputTrack: Optional `AudioTrack` used to visualize microphone/input levels.
- outputTrack: Optional `AudioTrack` used to visualize agent/output levels.
- agentState: `AgentState` controlling visual states (e.g., `.listening`, `.thinking`, `.speaking`).
- colors: Tuple of two `Color` values to customize the orb gradient.

## Docs

Conversational AI docs and guides: [https://elevenlabs.io/docs/conversational-ai/overview](https://elevenlabs.io/docs/conversational-ai/overview)

## Example App

See our [example app](https://github.com/elevenlabs/swift-starter-kit), to see how you can build cross-platform Apple voice experiences.

---

## Installation

You can add ElevenLabsComponents to your project using [Swift Package Manager](https://swift.org/package-manager/).

**In Xcode:**

1. Go to **File > Add Packages...**
2. Enter the repository URL:
   ```
   https://github.com/elevenlabs/components-swift
   ```
3. Select the `main` branch or a version, and add the `ElevenLabsComponents` library to your target.

**Or add to your `Package.swift`:**

```swift
dependencies: [
    .package(url: "https://github.com/elevenlabs/components-swift.git", from: "0.1.3")
]
```

---

## What’s Included

This package provides a set of SwiftUI components for building real-time voice experiences with ElevenLabs Conversational AI, including an `OrbVisualizer`.

## Acknowledgements

This project extends the [LiveKit components-swift](https://github.com/livekit/components-swift) codebase under the same permissive license, with modifications tailored for ElevenLabs voice experiences. We are grateful for their foundational work, which has enabled further innovation in this space.
