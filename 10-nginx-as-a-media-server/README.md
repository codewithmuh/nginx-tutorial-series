# 10 — Nginx as a Media Server

Nginx is very good at pushing large files: it hands them from disk to socket
inside the kernel, supports byte ranges so players can seek, and can throttle
per connection so one downloader doesn't eat your bandwidth.

What it does **not** do is transcode. Encoding is ffmpeg's job; Nginx serves
what ffmpeg produced.

---

## Table of Contents

1. [Byte ranges — why seeking works](#1-byte-ranges--why-seeking-works)
2. [Progressive MP4 with the mp4 module](#2-progressive-mp4-with-the-mp4-module)
3. [HLS streaming](#3-hls-streaming)
4. [MIME types](#4-mime-types)
5. [CORS for browser players](#5-cors-for-browser-players)
6. [Bandwidth throttling](#6-bandwidth-throttling)
7. [Protecting paid content](#7-protecting-paid-content)
8. [Images](#8-images)
9. [Live streaming with RTMP](#9-live-streaming-with-rtmp)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. Byte ranges — why seeking works

When you drag a video's scrub bar, the player asks for a slice of the file:

```
Range: bytes=5242880-10485759
```

Nginx answers `206 Partial Content` for static files out of the box. Confirm:

```bash
curl -sI https://media.example.com/videos/demo.mp4 | grep -i accept-ranges
# Accept-Ranges: bytes

curl -sI -H 'Range: bytes=0-1023' https://media.example.com/videos/demo.mp4 | head -1
# HTTP/1.1 206 Partial Content
```

If you get `200` instead of `206`, something upstream stripped the range —
usually `gzip` on media, or a proxy layer. **Never gzip video.**

## 2. Progressive MP4 with the mp4 module

```nginx
location /videos/ {
    mp4;
    mp4_buffer_size     1m;
    mp4_max_buffer_size 10m;
}
```

This adds pseudo-streaming: `/videos/demo.mp4?start=120` begins the response at
the 120-second mark. Check the module is compiled in:

```bash
nginx -V 2>&1 | tr ' ' '\n' | grep mp4
# --with-http_mp4_module
```

The file also needs its `moov` atom at the front, or playback won't start until
the whole file downloads:

```bash
ffmpeg -i in.mp4 -c copy -movflags +faststart out.mp4
```

That one flag fixes most "video takes forever to start" complaints.

## 3. HLS streaming

HLS chops the video into small segments plus a playlist, letting the player
switch quality as bandwidth changes. Generate it once with ffmpeg:

```bash
ffmpeg -i source.mp4 \
  -c:v h264 -c:a aac \
  -hls_time 6 -hls_playlist_type vod \
  -hls_segment_filename '/var/www/media/hls/seg_%03d.ts' \
  /var/www/media/hls/index.m3u8
```

Then serve the directory as static files — with opposite caching rules for the
two file types:

```nginx
location /hls/ {
    location ~ \.m3u8$ {                       # playlist: changes, never cache
        add_header Cache-Control "no-cache, no-store";
        add_header Access-Control-Allow-Origin "*";
    }
    location ~ \.ts$ {                         # segments: immutable, cache hard
        expires 1y;
        add_header Cache-Control "public, immutable";
        add_header Access-Control-Allow-Origin "*";
    }
}
```

Caching the playlist is the classic HLS bug: viewers get stuck on an old segment
list and the stream stalls.

Safari plays HLS natively; everywhere else use [hls.js](https://github.com/video-dev/hls.js).

## 4. MIME types

Serve the wrong `Content-Type` and players simply refuse the file. Older
distributions ship a `mime.types` without the streaming formats:

```nginx
types {
    application/vnd.apple.mpegurl  m3u8;
    video/mp2t                     ts;
    application/dash+xml           mpd;
    image/avif                     avif;
}
```

Verify what you're actually sending:

```bash
curl -sI https://media.example.com/hls/index.m3u8 | grep -i content-type
```

## 5. CORS for browser players

hls.js and dash.js fetch segments with `fetch()`/XHR, so a media host on a
different domain needs CORS — including the `Range` header:

```nginx
add_header Access-Control-Allow-Origin   "https://example.com" always;
add_header Access-Control-Allow-Methods  "GET, HEAD, OPTIONS" always;
add_header Access-Control-Allow-Headers  "Range" always;
add_header Access-Control-Expose-Headers "Content-Length, Content-Range" always;
```

Prefer naming your origin over `*`. Use `*` only for genuinely public assets —
with `*` any site on the internet can embed your media and spend your bandwidth.

## 6. Bandwidth throttling

```nginx
limit_rate_after 5m;      # first 5MB at full speed → instant playback start
limit_rate       1m;      # then ~8 Mbps, roughly the stream's bitrate
```

The player buffers the opening seconds immediately, then downloads at about the
speed it consumes. Serving 4K at 20 Mbps to someone who watches 30 seconds and
leaves is pure waste.

`limit_rate` is **per connection**. Pair it with `limit_conn` (chapter 08) or one
client can open ten connections and multiply their share.

## 7. Protecting paid content

### Signed URLs (`secure_link`)

```nginx
location /secure/ {
    secure_link     $arg_md5,$arg_expires;
    secure_link_md5 "$secure_link_expires$uri YOUR_SECRET";

    if ($secure_link = "")  { return 403; }   # bad hash
    if ($secure_link = "0") { return 410; }   # expired
}
```

Your app generates `?md5=...&expires=...`; the link dies on schedule, so it
can't be posted somewhere and reused forever.

### `X-Accel-Redirect` (usually better)

Let your app decide who's allowed, and let Nginx do the sending:

```nginx
location /protected-files/ {
    internal;                        # not reachable from outside
    alias /var/www/private/;
}
```

Your app checks the session, then returns an empty response with:

```
X-Accel-Redirect: /protected-files/movie.mp4
```

Nginx serves the file at full speed while your app worker is freed instantly.
This is how you gate large downloads without pinning a Python/Node process for
the length of the transfer.

## 8. Images

```nginx
location /images/ {
    expires 30d;
    add_header Cache-Control "public";
    access_log off;

    location ~* ^/images/(.+)\.(jpe?g|png)$ {
        try_files /images/$1.webp /images/$1.$2 =404;    # WebP when available
    }
}
```

Pre-generate the WebP/AVIF versions in your build. Nginx's `image_filter` module
can resize on the fly, but it does it per request — fine for thumbnails, not a
substitute for an image pipeline or a CDN.

## 9. Live streaming with RTMP

Live ingest needs the third-party
[nginx-rtmp-module](https://github.com/arut/nginx-rtmp-module), which is not
part of core Nginx and must be compiled in:

```nginx
rtmp {
    server {
        listen 1935;
        application live {
            live on;
            hls on;
            hls_path /var/www/media/hls;
            hls_fragment 3s;
        }
    }
}
```

OBS pushes to `rtmp://your-server/live/streamkey`, the module writes HLS
segments, and the `location /hls/` block above serves them. Note the module is
lightly maintained — for anything critical, consider a purpose-built stack.

## 10. Troubleshooting

| Symptom | Cause |
|---|---|
| Can't seek; scrub bar dead | `206` not returned — gzip enabled on media, or a proxy stripping ranges |
| Video starts only after full download | `moov` atom at the end — re-mux with `-movflags +faststart` |
| HLS stalls after a few segments | Playlist got cached — `no-cache` on `.m3u8` |
| Player shows a CORS error | Missing `Access-Control-Allow-Origin`, or `Range` not in allowed headers |
| `.m3u8` downloads instead of playing | Wrong MIME type |
| High CPU serving video | `sendfile off`, or gzip running on media files |
| `unknown directive "mp4"` | Nginx built without `--with-http_mp4_module` |

---

## Files

- [`example.conf`](./example.conf) — range requests, HLS, CORS, signed URLs and throttling

## Next

[11 — Debugging and Monitoring](../11-debuging-and-monitoring/)
