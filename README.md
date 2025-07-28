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
