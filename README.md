# Prism

A native iOS YouTube client. No ads, SponsorBlock built into the scrubber, no downloads.

Built with SwiftUI and AVFoundation. Personal use.

---

## What it is

Prism plays YouTube without the advertising layer, and shows you the shape of a
video before you commit to it. Its one distinctive idea is the **spectrum
scrubber**: every sponsor, intro and self-promotion in the video is drawn in
place as a band of colour, so you can see what's ahead instead of discovering it
by walking into it.

<p align="center">
  <img src="docs/shots/01-home.png" width="270" alt="Home feed">
  <img src="docs/shots/03-scrubber.png" width="270" alt="Watch screen showing the spectrum scrubber">
  <img src="docs/shots/06-settings.png" width="270" alt="Settings">
</p>

On the scrubber above: the played portion runs violet to cyan, then rose marks a
sponsor, a violet tick a subscribe reminder, amber a self-promotion, and cyan the
outro. The same colours label the segment list below the video, so the setting
and its effect are visibly the same object.

These are real captures from an iOS Simulator running the app in CI, not mockups.

There are deliberately **no downloads**. Streaming is transient; a download is a
copy, and that's the line this project doesn't cross.

## How playback works

The interesting engineering is in getting a playable stream without a server.

YouTube's internal API (`youtubei/v1`) gates most clients behind a **PO Token** —
a proof-of-origin blob produced by an obfuscated JavaScript VM that a native app
can't realistically generate. The well-known "use the iOS client" trick is dead:
tested across a range of videos, it returns `playabilityStatus: OK` with zero
usable format URLs.

Two things make a serverless native client work in 2026:

1. **The visionOS client** still returns a real `hlsManifestUrl` with no PO
   Token, no API key, and no JavaScript signature solving. That manifest carries
   a full H.264 ladder from 144p to 1080p alongside VP9 variants — AVPlayer
   ignores the codecs it can't decode and adapts across the rest by itself. One
   URL buys adaptive bitrate, subtitles, AirPlay and Picture in Picture.

2. **`visitorData` is mandatory.** Without it the API answers `LOGIN_REQUIRED`
   for essentially every video, which looks exactly like an IP ban and is
   usually misdiagnosed as one. Prism mints one token, caches it, and sends it in
   both the request context and the `X-Goog-Visitor-Id` header.

The Android VR client is kept as a fallback and is the only route above 1080p —
it returns adaptive formats including 2160p AV1, at the cost of compositing
separate audio and video tracks. AV1 is only selected on hardware that decodes it
(`VTIsHardwareDecodeSupported`), because a software-decoded 4K stream is a worse
experience than a hardware 1080p one.

```
VISIONOS  → hlsManifestUrl → AVPlayer          ← preferred
ANDROID_VR → adaptive formats → AVMutableComposition  ← fallback, >1080p
```

This is inherently fragile. It depends on clients Google has not yet gated, and
it will break. When it does, the fix is usually a client version bump in
`InnerTubeClientProfile`, not a rewrite.

## SponsorBlock

Segment data comes from [SponsorBlock](https://sponsor.ajay.app). Prism uses the
privacy-preserving endpoint: rather than asking "what's in video X", it sends
only the first four hex characters of `sha256(videoID)` and receives every video
in that bucket, then filters locally. The server never learns what you're
watching.

Sponsors, self-promotion and subscribe reminders skip by default. Intros and
outros are drawn but not skipped — on plenty of channels the intro is the thing
people came for. Every skip is announced with an undo.

## Building

The project is authored on Linux, where Xcode can't run, so **CI is the
compiler**. There is no `.xcodeproj` in the repo — it's generated from
`project.yml` by XcodeGen on the runner.

- **`.github/workflows/build.yml`** produces an unsigned `.ipa` artifact.
- **`.github/workflows/screenshots.yml`** boots an iOS Simulator, runs the app
  against bundled fixture data, and captures real PNGs.

```bash
gh run download --name Prism-unsigned-ipa   # the app
gh run download --name screenshots          # what it looks like
```

To install, sign the `.ipa` with your own Apple ID via
[Sideloadly](https://sideloadly.io) or [AltStore](https://altstore.io). A free
account expires after 7 days; a paid one lasts a year.

## Layout

```
Sources/Prism/
  DesignSystem/   palette, type, spacing, motion, ambient glow
  Networking/
    InnerTube/    client, stream selection, feed parsing, visitor session
    SponsorBlock/ segment fetch, overlap resolution
  Player/         engine, spectrum scrubber, controls, video surface
  Features/       home, watch, shorts, search, subscriptions, settings
```

## Status

Working: home feed, search, watch with HLS playback, SponsorBlock skipping,
Shorts, quality selection, background audio, settings.

Not built yet: Google sign-in (subscriptions and likes need OAuth), chapters,
comments, playlists.

Age-restricted and "made for kids" videos don't play — both require account
cookies that no PO-token-free client provides.

## Licence and intent

This is a personal project for personal use. It isn't affiliated with YouTube or
Google, it can't go on the App Store, and using it is against YouTube's Terms of
Service. Build it for yourself; don't distribute builds.
