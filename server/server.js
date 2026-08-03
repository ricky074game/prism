#!/usr/bin/env node
/**
 * Prism helper — optional.
 *
 * Prism plays almost everything on-device by talking to InnerTube directly. A
 * small amount of content can't be reached that way:
 *
 *   - "Made for kids" videos, which the clients that hand out plain stream URLs
 *     refuse outright.
 *   - Anything Google moves to SABR-only delivery, where formats no longer carry
 *     a URL at all and must be fetched over a protobuf streaming protocol.
 *
 * yt-dlp already handles both. This wraps it in the smallest possible HTTP
 * surface so the app can fall back to it when — and only when — direct
 * extraction fails.
 *
 * Run:  node server.js            (listens on 8787)
 *       PORT=9000 node server.js
 *
 * It shells out to yt-dlp, so yt-dlp must be on PATH:
 *   curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux -o /usr/local/bin/yt-dlp
 *   chmod +x /usr/local/bin/yt-dlp
 *
 * This is a personal tool. It has no authentication, so do not expose it to the
 * internet — run it on your LAN or behind Tailscale.
 */

import { createServer } from 'node:http';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const run = promisify(execFile);
const PORT = Number(process.env.PORT ?? 8787);
const YTDLP = process.env.YTDLP ?? 'yt-dlp';

/** Video ids are a fixed alphabet; anything else never reaches the shell. */
const VIDEO_ID = /^[A-Za-z0-9_-]{11}$/;

/** Resolved URLs expire, so results are cached for well under their lifetime. */
const cache = new Map();
const TTL_MS = 90 * 60 * 1000;

function cached(id) {
  const hit = cache.get(id);
  if (!hit) return null;
  if (Date.now() - hit.at > TTL_MS) {
    cache.delete(id);
    return null;
  }
  return hit.value;
}

async function resolve(id) {
  const hit = cached(id);
  if (hit) return { ...hit, cached: true };

  // Prefer H.264 + AAC in MP4: hardware-decoded on every iPhone. Falls back to
  // whatever single file exists if no adaptive pair is available.
  const format = [
    'bestvideo[vcodec^=avc1][ext=mp4][height<=1080]+bestaudio[acodec^=mp4a][ext=m4a]',
    'best[ext=mp4]',
    'best',
  ].join('/');

  const { stdout } = await run(
    YTDLP,
    [
      '-J', '--no-warnings', '--no-playlist',
      // Required. The clients that can reach "made for kids" content need
      // YouTube's player JS evaluated; without a runtime yt-dlp skips them and
      // reports the video as simply unavailable.
      '--js-runtimes', 'node',
      '-f', format,
      `https://www.youtube.com/watch?v=${id}`,
    ],
    { maxBuffer: 64 * 1024 * 1024, timeout: 120_000 }
  );

  const info = JSON.parse(stdout);
  const chosen = info.requested_formats ?? (info.url ? [info] : []);

  const video = chosen.find((f) => f.vcodec && f.vcodec !== 'none');
  const audio = chosen.find((f) => f.acodec && f.acodec !== 'none' && f.vcodec === 'none');
  const progressive = chosen.find((f) => f.vcodec !== 'none' && f.acodec !== 'none');

  const value = {
    id,
    title: info.title ?? '',
    author: info.uploader ?? '',
    duration: info.duration ?? 0,
    // When one file carries both tracks the app can skip compositing entirely.
    progressiveUrl: progressive?.url ?? null,
    videoUrl: progressive ? null : video?.url ?? null,
    audioUrl: progressive ? null : audio?.url ?? null,
    height: (progressive ?? video)?.height ?? 0,
    vcodec: (progressive ?? video)?.vcodec ?? '',
    acodec: (progressive ?? audio)?.acodec ?? '',
  };

  if (!value.progressiveUrl && !value.videoUrl) {
    throw new Error('no playable format');
  }

  cache.set(id, { at: Date.now(), value });
  return value;
}

const server = createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const send = (code, body) => {
    res.writeHead(code, {
      'Content-Type': 'application/json',
      'Cache-Control': 'no-store',
    });
    res.end(JSON.stringify(body));
  };

  if (url.pathname === '/health') {
    return send(200, { ok: true, service: 'prism-helper' });
  }

  if (url.pathname === '/resolve') {
    const id = url.searchParams.get('v') ?? '';
    if (!VIDEO_ID.test(id)) {
      return send(400, { error: 'bad video id' });
    }
    try {
      const value = await resolve(id);
      return send(200, value);
    } catch (error) {
      // yt-dlp's own message is more accurate about *why* than anything this
      // wrapper could invent.
      const detail = String(error.stderr ?? error.message ?? error).split('\n').filter(Boolean).pop();
      return send(502, { error: detail || 'extraction failed' });
    }
  }

  send(404, { error: 'not found' });
});

server.listen(PORT, () => {
  console.log(`prism-helper listening on :${PORT}`);
  console.log(`  health   http://localhost:${PORT}/health`);
  console.log(`  resolve  http://localhost:${PORT}/resolve?v=VIDEOID`);
});
