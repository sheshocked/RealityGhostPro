# Changelog

## v4.0.0 (this fork, "RealityGhost PRO")

Root-caused and fixed against the upstream `ghostmcf/RealityGhost` v3.6.1/3.7.0 source:

- **fix:** eliminated the port-443 collision between Xray's TCP-Reality inbound and nginx's HTTPS vhost by moving to an nginx `stream` + `ssl_preread` SNI router. Xray no longer binds any public port directly for TCP-Reality; it listens on `127.0.0.1:8444` and receives passthrough traffic from nginx.
- **fix:** XHTTP-Reality no longer terminates TLS at nginx (which was defeating Reality's camouflage). It now listens directly and publicly on its own port (`2053` by default, configurable via `XHTTP_PORT`).
- **fix:** certificate issuance switched from `certbot certonly --nginx` (called while nginx was stopped — a guaranteed failure) and a webroot fallback (also called against a stopped webserver) to `certbot certonly --standalone`. Because nginx never binds port 80 in this design, standalone issuance and renewal never conflict.
- **fix:** removed the hardcoded shared default UUID and dead "guest" UUID code path; every install now generates a fresh UUID with `uuidgen`.
- **fix:** `fuser -k 443/tcp` "whatever's on the port dies" step removed — no longer needed since there's no collision to resolve.
- **improvement:** Xray version is now resolved at install time from the GitHub Releases API instead of a hardcoded, aging version string, with an explicit pinned fallback if the API is unreachable.
- **improvement:** Reality camouflage target (`dest`/`serverNames`) is chosen from a small curated list of high-traffic domains, live-tested with `openssl s_client -tls1_3` before install so a known-broken candidate is never selected silently.
- **security:** `chmod 600/700` applied to `config.json`, the public key file, the UUID file, and their containing directories.
- **improvement:** added `logrotate` policy for `/var/log/xray/err.log`.
- **improvement:** non-interactive install support via `DOMAIN=`, `EMAIL=`, `XHTTP_PORT=` environment variables, for scripted/CI use.
- **improvement:** added `realityghost health` subcommand and an in-menu health-check item that verifies Xray config validity, nginx config validity, and that both services are actually running — not just that files exist.
- **improvement:** `set -Eeuo pipefail` + `trap ... ERR` for clearer failure messages during install.
- **cleanup:** removed unused/dead code paths (commented-out guest subscription generation, stray debug comments).

## Upstream (ghostmcf/RealityGhost v3.6.1 / "Just a Simple Private Script")

Base implementation: dual TCP/XHTTP Reality inbounds, safe fingerprint/shortId rotation via cron, base64 subscription file served through nginx. See project history at https://github.com/ghostmcf/RealityGhost for original commits. Upstream README notes the project had not yet reached what its author considered a production-ready state.
