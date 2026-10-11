# Apple toolchain and native validation

Verified 2026-10-11. The managed development workspace is Linux; it cannot run Xcode. Native build and launch checks run on GitHub's Apple silicon `xcode-27` image.

## Resolved blocker

The previous `macos-latest` runner supplied Xcode 26.6. The workflow checked only its installed apps and stopped. That was an incomplete investigation, not proof that SDK 27 was unavailable.

Apple documents Xcode 27 / Swift 6.4 / iOS and macOS 27 SDKs as compatible with macOS 26.6 and later. GitHub provides the `xcode-27` runner label; its current image runs macOS 27.0.1 and includes stable Xcode 27 as well as newer prereleases. The native workflow now selects that image and still verifies the actual compiler and SDK versions.

[First complete iOS and Mac build](https://github.com/kmshdev/foundation-models-utilities/actions/runs/38155972610): Xcode 27.0, Apple Swift 6.4; both production targets, the real FoundationPlanner, and both local Swift packages built successfully. This is stronger evidence than SDK 26 view typechecking with a planner stub. Builds were unsigned; they are not TestFlight or notarized distribution artifacts.

## Installation fallback

If this runner image is unavailable, use an Apple silicon Mac running macOS 26.6 or later with a supported Xcode 27 download. `xcodes install 27.0` or `xcodes install --latest-prerelease` can install an additional Xcode. Xcodes is a third-party Swift CLI, not an Apple CLI, and its downloads normally require Apple account authentication. Do not invent or print Apple credentials. An already downloaded, verified XIP can be supplied with `--path`.

Apple's `xcode-select -s /Applications/Xcode.app` selects an installed bundle; it does not download a new Xcode. `xcodebuild -runFirstLaunch` initializes its components. `xcodebuild -downloadPlatform iOS -buildVersion 27.0` obtains a supported simulator runtime; adding a runtime to Xcode 26 does not replace its compiler and SDK with Xcode 27. Choose the correct Xcode bundle first.

The repository workflow uses the supported hosted image rather than requiring an account-authenticated download on every build. It launches the actual built Mac app and an iOS 27 simulator app and collects screenshots when builds succeed. These are startup smoke checks, not full UI interaction, VoiceOver, live model or integration tests.

## Sources

- [Apple SDKs and system requirements](https://developer.apple.com/xcode/system-requirements/)
- [Apple command-line component installation](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components)
- [GitHub Xcode 27 runner announcement](https://github.com/actions/runner-images/issues/14404)
- [Runner software inventory](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)
- [Xcodes installation instructions](https://github.com/XcodesOrg/xcodes)
