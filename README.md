# 📷 Bambu Cam — Bambu Lab Printer Camera, Streamed via Docker

_Watch your Bambu Lab 3D printer's camera in **LAN mode** from any browser or
VLC — a single, environment-variable-driven Docker container. No Bambu Studio
install needed at runtime._

🏠 Built for people who just want the printer cam on a dashboard, a phone, or
Home Assistant without keeping Bambu Studio open.

![Live stream in a web browser](https://i.imgur.com/hvHuyc6.png)

## ✨ What it does

1. 🔌 Connects to a Bambu Lab printer over the local network (LAN mode) using
   Bambu's prebuilt `libBambuSource.so` (downloaded automatically at image
   build time).
2. 🎥 Pulls the camera frames and re-serves them as a video stream.
3. 🌐 **HTTP mode** — a `multipart/x-mixed-replace` MJPEG stream you can open
   in any browser.
4. 📺 **RTP mode** — an MPEG-2 / RTP (Pro-MPEG FEC) stream you can open in VLC.
5. 🧪 **Fake mode** — a built-in RGB test pattern so you can verify everything
   works with no printer at all.

## 🐳 Quick Start with Docker

The image bundles the camera plugin and both server builds. It's
**`linux/amd64`** (the Bambu plugin is x86-64 only — ARM still works, see
[below](#-running-on-arm)).

### Using the pre-built image from Docker Hub

Fastest way — pull and run:

```bash
docker run -d --name bambucam -p 8080:8080 \
  -e BAMBU_IP=192.168.0.200 \
  -e BAMBU_DEVICE=0123456789ABCDE \
  -e BAMBU_PASSCODE=12345678 \
  daimik/bambucam:latest
```

Or create a **`docker-compose.yml`**:

```yaml
services:
  bambucam:
    image: daimik/bambucam:latest
    platform: linux/amd64
    restart: unless-stopped
    ports:
      - "8080:8080"
    environment:
      BAMBU_IP: "192.168.0.200"
      BAMBU_DEVICE: "0123456789ABCDE"
      BAMBU_PASSCODE: "12345678"
      # SERVER: "HTTP"        # or "RTP"
      # BAMBU_FAKE: "1"       # uncomment for the test pattern, no printer
    healthcheck:
      test: ["CMD", "nc", "-z", "localhost", "8080"]
      interval: 30s
      timeout: 5s
      start_period: 20s
      retries: 3
```

```bash
docker compose up -d
```

Then open **`http://<host>:8080/`** in a browser and you're watching the
printer. 🎉

No printer to hand? Swap the printer vars for `-e BAMBU_FAKE=1` (or uncomment
it in the compose file) to get a 640×480 image cycling red → green → blue.

### Building from source

Clone the repo and let compose build the image from the `Dockerfile`:

```bash
git clone https://github.com/daimik/bambucam.git
cd bambucam
cp .env.example .env       # fill in BAMBU_IP / BAMBU_DEVICE / BAMBU_PASSCODE
docker compose up -d --build       # builds the image, then starts it
```

The bundled `docker-compose.yml` uses `build:` so the proprietary Bambu camera
plugin is fetched and the binaries are compiled during the build.

## 🗂️ Project Structure

```
.
├── Dockerfile              # multi-stage build: fetch plugin, compile, slim runtime
├── docker-compose.yml      # builds & runs the container (env via .env)
├── entrypoint.sh           # maps env vars -> bambucam args, picks the binary
├── .env.example            # copy to .env and fill in your printer details
├── .dockerignore
├── Makefile                # native build (also used inside the Docker build)
├── bambucam.c              # entry point: wires the camera thread + server
├── bambu.c / bambu.h       # real camera via libBambuSource.so
├── bambu_fake.c            # fake RGB test-pattern camera (BAMBU_FAKE=1)
├── bambu_tunnel.h          # Bambu plugin ABI header
├── server.h                # server interface
├── server_microhttpd.c     # HTTP / MJPEG server
├── server_ffmpeg_rtp.c     # RTP (Pro-MPEG FEC) server
└── test/
    └── test_entrypoint.sh  # unit tests for entrypoint.sh
```

## ⚙️ Configuration

Everything is configured through environment variables:

| Variable | Default | Description |
|---|---|---|
| `BAMBU_IP` | _(required)_ | Printer local IP, e.g. `192.168.0.200` |
| `BAMBU_DEVICE` | _(required)_ | Printer serial / device ID |
| `BAMBU_PASSCODE` | _(required)_ | LAN-mode access code from the printer screen |
| `BAMBU_PORT` | `8080` | Port to serve the stream on |
| `SERVER` | `HTTP` | `HTTP` (browser MJPEG) or `RTP` (VLC) |
| `BAMBU_FAKE` | _(unset)_ | Any non-empty value = RGB test pattern, no printer needed |

ℹ️ `BAMBU_FAKE` triggers fake mode for **any** non-empty value (even
`BAMBU_FAKE=0`) — leave it empty/unset for real-printer mode. Find the LAN
access code and device ID on the printer:
[enable LAN mode](https://wiki.bambulab.com/en/knowledge-sharing/enable-lan-mode).

**Build args** (when building the image yourself):

- `BAMBU_STUDIO_VERSION` (default `01.07.07`) — which Bambu plugin version to
  fetch.
- `BAMBU_PLUGIN_URL` — a direct URL to a **Linux** plugin `.zip`, used instead
  of the Bambu API (handy if Bambu changes their CDN).

## 📺 RTP Mode (VLC)

The RTP server pushes UDP straight to the container's loopback, so normal
published ports won't reach it. To use RTP:

1. Set `SERVER=RTP` in `.env` (or the compose `environment:`).
2. In `docker-compose.yml`, comment out the `ports:` and `healthcheck:`
   blocks and uncomment `network_mode: host`.
3. Open it in VLC: `vlc rtp://<host>/<BAMBU_PORT>`

![Live stream in VLC](https://i.imgur.com/lOo64MV.png)

It uses the Pro-MPEG Code of Practice #3 Release 2 FEC protocol (2D
parity-check FEC for MPEG-2 TS over RTP), which VLC speaks directly — so no
SDP/RTSP needs to be served. The healthcheck is HTTP-only; RTP has no
equivalent TCP liveness probe.

## 💪 Running on ARM

The official Bambu plugin is x86-64 only, so the image is `linux/amd64` and
runs on ARM hosts (Apple Silicon, Raspberry Pi, …) via QEMU emulation:

- 🍏 **Docker Desktop (macOS/Windows):** works automatically, nothing to do.
- 🐧 **Linux ARM hosts:** register QEMU binfmt once:
  ```bash
  docker run --privileged --rm tonistiigi/binfmt --install amd64
  ```
  then `docker compose up -d` (or `docker run`) works unchanged.

Emulation adds some CPU overhead, but the camera workload (small JPEG frames
at a low frame rate) shrugs it off.

## 🧠 How It Works

`bambucam` opens a LAN-mode connection through Bambu's prebuilt
`libBambuSource.so`, reads camera frames, and re-serves them. Two server
implementations are compiled into the image; the `SERVER` env var picks which
one runs:

- **HTTP** — `multipart/x-mixed-replace` MJPEG over microhttpd.
- **RTP** — MPEG-2 transport stream over RTP (Pro-MPEG FEC) via FFmpeg.

## 🛠️ Native Build (no Docker)

For hacking on the C source directly. Needs the FFmpeg + libmicrohttpd dev
headers and a Bambu Studio install (run once so the camera plugin lands in
`~/.config/BambuStudio/plugins`):

```bash
sudo apt install libavcodec-dev libavformat-dev libavutil-dev \
                  libjpeg-dev libmicrohttpd-dev
make -j
./bambucam <device-ip> <device-id> <passcode> <port>
```

Handy `make` flags:

| Flag | Effect |
|---|---|
| `SERVER=HTTP` / `SERVER=RTP` | Pick the streaming server (default `HTTP`) |
| `BAMBU_FAKE=1` | Fake camera, no printer/plugin needed |
| `DEBUG=1` | Verbose logging + debug symbols |
| `PLUGIN_PATH=/path` | Override the Bambu plugin directory |

⚠️ The source targets a modern toolchain — **FFmpeg ≥ 5.1** and
**libmicrohttpd ≥ 0.9.74** (e.g. Debian 12 "bookworm"). Older distros will
fail to compile the server files. The Docker image already handles this for
you.

## 🙏 Credits & Inspiration

This project is **based on and inspired by**
[**jtessler/bambucam**](https://github.com/jtessler/bambucam) by
[@jtessler](https://github.com/jtessler) — the original C implementation of
the Bambu LAN-mode camera wrapper. All the core C code comes from there, and
he figured out the genuinely hard parts. This repo just wraps it in a
self-contained Docker image. Massive thanks to him. 🙌
