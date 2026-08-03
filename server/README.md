# Prism helper

**Optional.** Prism plays almost everything on-device by talking to InnerTube
directly. This exists for the small set it can't reach:

- **"Made for kids" videos.** Every client that hands out plain stream URLs
  refuses them outright — verified across VISIONOS, ANDROID_VR, TVHTML5 and WEB,
  including with a freshly minted PO token. It isn't an authentication problem.
- **SABR-only content.** Google is moving delivery to a protobuf streaming
  protocol where formats carry no URL at all.

yt-dlp handles both. This wraps it in the smallest HTTP surface that works.

## Running it

Needs Node 18+ and yt-dlp on `PATH`.

```bash
curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux \
  -o /usr/local/bin/yt-dlp && chmod +x /usr/local/bin/yt-dlp

node server.js            # listens on 8787
PORT=9000 node server.js  # or pick a port
```

Then put `http://<that machine's IP>:8787` into Prism → Settings → Helper server
and press **Test connection**.

## Why Node has to be there

yt-dlp is invoked with `--js-runtimes node`. The clients that can reach
made-for-kids content require YouTube's player JavaScript to be evaluated;
without a runtime yt-dlp silently skips them and reports the video as simply
unavailable. This was the difference between failing and returning a full 1080p
ladder in testing.

## Endpoints

```
GET /health           → {"ok":true,"service":"prism-helper"}
GET /resolve?v=<id>   → {title, duration, videoUrl, audioUrl, height, vcodec, acodec}
```

`/resolve` prefers H.264 + AAC in MP4, capped at 1080p — the pair every iPhone
decodes in hardware. Resolved URLs are cached for 90 minutes, comfortably inside
their expiry; a cache hit returns in about 10ms against roughly 10 seconds for a
cold extraction.

## Security

There is no authentication, and the video IDs it accepts are matched against a
fixed alphabet before they ever reach a shell. It is still a personal tool —
**don't expose it to the internet.** Run it on your LAN, or reach it over
Tailscale or a VPN.
