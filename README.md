# Gaming Community in a Box

> **⚠️ Work in Progress.** This project is under active development and not yet production-ready. Use at your own risk. EVLBOX provides no warranty, support, or liability for damages arising from use of this software. See [LICENSE](LICENSE).

Everything a gaming community needs — chat, voice, forums, image sharing — without Discord's ToS, data collection, or platform risk.

Part of [EVLBOX Stacks](https://evlbox.com) — pre-configured, self-hosted server bundles.

## What's Included

**Core (always installed):**

| Service | Purpose | URL |
|---|---|---|
| [Stoat](https://github.com/stoatchat/self-hosted) | Discord-like chat | `chat.yourdomain.com` |
| Stoat API | Chat backend (required by Stoat) | `api.yourdomain.com` (always reserved) |
| [Caddy](https://caddyserver.com/) | Reverse proxy + auto HTTPS | — |

**Optional (choose during setup):**

| Service | Purpose | URL | Profile |
|---|---|---|---|
| [Flarum](https://flarum.org/) | Community forum | `forum.yourdomain.com` | `forum` |
| [Mumble](https://www.mumble.info/) | Low-latency voice chat | `yourdomain.com:64738` | `voice` |
| [Zipline](https://github.com/diced/zipline) | Screenshot & image hosting | `screenshots.yourdomain.com` | `screenshots` |
| [PrivateBin](https://privatebin.info/) | Encrypted paste service | `paste.yourdomain.com` | `paste` |
| [Ghost](https://ghost.org/) | Blog / community news | `blog.yourdomain.com` | `blog` |

## Requirements

- **OS:** Debian 13 (Trixie)
- **RAM:** 4 GB minimum (8 GB recommended)
- **Disk:** 40 GB+ SSD
- **Ports:** 80, 443, 64738 (Mumble, if enabled)

## Quick Start

If deployed via EVLBOX VirtFusion, provisioning is automatic. Just SSH in and run:

```bash
evlbox setup
```

The setup wizard walks you through domain config, service selection, and passwords.

## Manual Install

```bash
# 1. Install evlbox-core
curl -fsSL https://raw.githubusercontent.com/EVLBOX/evlbox-core/main/install.sh | bash

# 2. Clone this stack + Stoat
git clone https://github.com/EVLBOX/evlbox-gaming-community.git /opt/evlbox/stack
git clone https://github.com/stoatchat/self-hosted.git /opt/evlbox/stoat

# 3. Run setup
evlbox setup
```

## Managing Services

```bash
evlbox status              # Check service health
evlbox enable forum        # Enable a service
evlbox disable blog        # Disable a service
evlbox backup              # Create a backup
evlbox update              # Pull updates (auto-backs up first)
evlbox secure-ssh          # Disable password auth after adding SSH key
evlbox help                # All available commands
```

## Backups

Local backups run daily via cron (3 daily + 1 weekly retention). Only enabled services are backed up.

```bash
evlbox backup              # Manual backup
evlbox backup list         # List available snapshots
```

Backups protect against app-level mistakes. They do **not** protect against disk failure. [Export backups off-server](https://evlbox.com/docs) for full protection.

## Routing Modes

The setup wizard offers three domain configurations:

- **Express** (recommended) — enter your domain, subdomains are auto-assigned (`chat.`, `forum.`, `img.`, `paste.`, `api.`)
- **Custom** — pick your own URLs per service (some apps require subdomains, some support subpaths)
- **IP-only** — no domain needed, only Stoat runs with self-signed TLS. Add a domain later with `evlbox setup`

> **Note:** `api.yourdomain.com` is always reserved by Stoat's backend and cannot be reassigned to another service.

## Architecture

Stoat runs as its own Docker Compose project (`/opt/evlbox/stoat`) with MongoDB, KeyDB, RabbitMQ, and MinIO. Optional services run in a second Compose project (`/opt/evlbox/stack`) using [Docker Compose profiles](https://docs.docker.com/compose/profiles/). Caddy sits in the stack project and routes to both. The `.compose-projects` file tells the `evlbox` CLI about Stoat so `evlbox status/update/restart` manages both projects.

## License

GPL-3.0 — see [LICENSE](LICENSE)
