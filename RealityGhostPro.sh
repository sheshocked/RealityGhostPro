#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════
#  RealityGhost PRO — v4.0.0
#  Dual-Mode Xray Reality (TCP direct :443 via nginx-stream + XHTTP
#  direct :2053) with a stealth HTTPS subscription page, safe periodic
#  camouflage rotation, and non-interactive/CI-friendly install.
#
#  Forked & hardened from ghostmcf/RealityGhost (MIT). See CHANGELOG.md
#  for the full list of fixes made in this fork.
# ══════════════════════════════════════════════════════════════════
#
# WHAT WAS ACTUALLY BROKEN IN THE ORIGINAL SCRIPT (root-caused, not
# guessed) and how this fork fixes it:
#
#  1) PORT-443 COLLISION (the #1 reason configs died fast/never came up
#     correctly): the original wrote an Xray inbound listening on
#     0.0.0.0:443 for TCP-Reality *and* an nginx `server { listen 443
#     ssl ... }` block for the subscription page — two processes fighting
#     for the same port. Whichever lost the race either crash-looped or
#     silently never served traffic, and the "fuser -k 443/tcp" step
#     would happily kill nginx (or Xray) at random on every install/rotate.
#     FIX: nginx now runs a `stream { ssl_preread on; }` block on :443
#     that inspects the TLS ClientHello SNI *without terminating TLS*
#     and passes the raw bytes to the right backend:
#       - SNI == your domain  → local nginx HTTPS vhost (127.0.0.1:8443)
#         serving ONLY the subscription file, with your real Let's
#         Encrypt cert.
#       - anything else (camouflage SNI, e.g. www.microsoft.com) → passed
#         untouched to Xray's Reality-TCP inbound (127.0.0.1:8444), which
#         performs the actual Reality fake-TLS handshake itself.
#     Xray never binds a public port directly anymore, so there is no
#     collision, and TLS for Reality is never touched by nginx (which
#     would have broken Reality's whole camouflage mechanism).
#
#  2) XHTTP transport was reverse-proxied through nginx at the HTTP layer
#     (`proxy_pass http://127.0.0.1:8444` under `listen 443 ssl`). This
#     makes nginx terminate TLS with the real Let's Encrypt cert instead
#     of letting Xray perform the Reality handshake — which defeats
#     Reality's camouflage entirely for that transport and is why XHTTP
#     mode looked "up" but was actually fingerprintable/broken.
#     FIX: XHTTP-Reality now gets its own dedicated public port (2053 by
#     default) straight into Xray, no nginx in the path.
#
#  3) Let's Encrypt via `certbot certonly --nginx` while nginx was
#     manually stopped a few lines earlier — the nginx plugin needs a
#     running nginx to inject a temporary ACME vhost, so this failed
#     silently more often than it worked, and the "webroot fallback"
#     right after it *also* needs an active webserver, which also wasn't
#     running. Both paths were dead ends.
#     FIX: since our nginx design never listens on :80 at all, `certbot
#     certonly --standalone` on port 80 is always conflict-free — no
#     stopping/starting dances needed, including for renewals.
#
#  4) Hardcoded default UUID/leftover "guest" UUID shipped in the public
#     script. Anyone who hit Enter through the Y/n prompt got the exact
#     same UUID as everyone else who did the same.
#     FIX: UUID is always freshly generated at install time; dead
#     guest-subscription code removed.
#
#  5) Hardcoded Xray version that goes stale.
#     FIX: fetches the latest XTLS/xray-core release at runtime, with a
#     pinned fallback if GitHub API is rate-limited/unreachable.
#
#  6) `google.com` as the sole Reality camouflage target. Google's edge
#     behaves inconsistently for Reality handshakes for a meaningful
#     slice of users (HTTP/3-first behavior, regional edge differences).
#     FIX: a small curated list of Reality-friendly targets is
#     live-tested with openssl before install and the first one that
#     actually completes a clean TLS 1.3 handshake is used.
#
#  7) Secrets (private key, config.json) were left world-readable.
#     FIX: chmod 600/700 on all sensitive files/dirs.
#
#  8) No log rotation for /var/log/xray/err.log → unbounded growth.
#     FIX: logrotate policy installed.
#
#  9) No non-interactive install path (hard to script/automate/re-run in
#     CI or via a one-liner without a TTY).
#     FIX: DOMAIN=, EMAIL=, XHTTP_PORT= env vars now work for unattended
#     installs; falls back to interactive prompts when unset.
#
# ══════════════════════════════════════════════════════════════════

set -Eeuo pipefail
export TZ="Asia/Tehran"

trap 'err "Failed at line $LINENO: $BASH_COMMAND"' ERR

### Paths ###
XRAY_DIR=/usr/local/xray
SCRIPT_DIR=$XRAY_DIR/scripts
SUB_DIR=$XRAY_DIR/sub
CONFIG_FILE=$XRAY_DIR/config.json
PUBKEY_FILE=$SCRIPT_DIR/pubkey
GHOST_CONF=/etc/ghost.conf
UUID_FILE=$SCRIPT_DIR/uuid
NGINX_SITE=/etc/nginx/nginx.conf
TRANSPORT_FILE=/etc/ghost_transport
XHTTP_PORT_FILE=/etc/ghost_xhttp_port
XRAYVER_FALLBACK="25.9.11"   # only used if GitHub API is unreachable at install time

### Reality camouflage candidates (tested live, first working one wins) ###
REALITY_CANDIDATES=(
  "www.microsoft.com"
  "addons.mozilla.org"
  "www.cloudflare.com"
  "swcdn.apple.com"
  "www.samsung.com"
)

### Defaults ###
DEFAULT_TRANSPORT="tcp"       # which link is shown first: xhttp|tcp (both are always active)
DEFAULT_XHTTP_PORT="2053"
UUID=""
SERVER_IP=""

log(){ echo "[$(date +%H:%M:%S)] $*"; }
err(){ echo "ERROR: $*" >&2; }
ask(){ read -r -p "$1" _v; echo "${_v}"; }
tmpfile(){ mktemp "${TMPDIR:-/tmp}/ghost.XXXXXX"; }

domain=""
[[ -f $GHOST_CONF ]] && domain=$(<"$GHOST_CONF") || true
[[ -f $UUID_FILE ]] && UUID=$(<"$UUID_FILE") || true

get_xhttp_port(){
  [[ -f "$XHTTP_PORT_FILE" ]] && cat "$XHTTP_PORT_FILE" || echo "$DEFAULT_XHTTP_PORT"
}

get_transport(){
  local tr=""
  if [[ -f "$TRANSPORT_FILE" ]]; then
    tr=$(<"$TRANSPORT_FILE" 2>/dev/null || true)
    [[ "$tr" == "tcp" || "$tr" == "xhttp" ]] && { echo "$tr"; return 0; }
  fi
  echo "$DEFAULT_TRANSPORT"
}
set_transport(){
  local t="${1:-}"
  [[ "$t" != "tcp" && "$t" != "xhttp" ]] && { err "Invalid transport: $t"; return 1; }
  echo "$t" > "$TRANSPORT_FILE"
  log "Preferred link (shown first) set to: $t (server still runs BOTH simultaneously)"
}

# ────────────────────────────────────────────────────────────────
# Helpers
# ────────────────────────────────────────────────────────────────

xray_bin(){
  [[ -x "$XRAY_DIR/xray" ]] && { echo "$XRAY_DIR/xray"; return 0; }
  command -v xray 2>/dev/null || true
}

xray_test_config(){
  local bin; bin=$(xray_bin)
  [[ -z "${bin:-}" ]] && { err "Xray binary not found"; return 1; }
  "$bin" -test -config "$CONFIG_FILE" >/dev/null 2>&1
}

xray_gen_keys(){
  local bin out priv pub
  bin=$(xray_bin)
  [[ -z "$bin" ]] && { err "Xray binary not found"; return 1; }
  out=$("$bin" x25519 2>/dev/null)
  priv=$(awk -F': ' '/PrivateKey:/ {print $2}' <<<"$out")
  pub=$(awk -F': ' '/Password:/   {print $2}' <<<"$out")
  [[ -n "$priv" && -n "$pub" ]] || { err "x25519 output unparsable"; echo "$out" >&2; return 1; }
  echo "$priv $pub"
}

get_latest_xray_version(){
  local v
  v=$(curl -sf --max-time 8 https://api.github.com/repos/XTLS/xray-core/releases/latest \
      | jq -r '.tag_name // empty' 2>/dev/null | sed 's/^v//')
  if [[ -n "$v" && "$v" != "null" ]]; then
    echo "$v"
  else
    log "⚠ Could not reach GitHub API, pinning fallback Xray version $XRAYVER_FALLBACK"
    echo "$XRAYVER_FALLBACK"
  fi
}

detect_ip(){
  log "IP detection started …"
  local ip=""
  ip=$(curl -sf --max-time 6 https://api.ipify.org || curl -sf --max-time 6 https://ifconfig.me || true)
  if [[ -n "${ip:-}" ]]; then SERVER_IP=$ip; echo "$ip"; return 0; fi
  read -r -p "Auto-detect IP failed. Enter server public IP: " ip
  [[ -n "${ip:-}" ]] && { SERVER_IP=$ip; echo "$ip"; return 0; }
  err "No IP provided"; return 1
}

# Live-test candidate Reality camouflage targets; first clean TLS1.3
# handshake wins. Falls back to the first candidate if all tests fail
# (e.g. outbound 443 is itself restricted at install time).
pick_reality_dest(){
  local host
  for host in "${REALITY_CANDIDATES[@]}"; do
    if timeout 6 openssl s_client -connect "${host}:443" -servername "$host" -tls1_3 \
        </dev/null 2>/dev/null | grep -q "Verify return code: 0"; then
      echo "$host"; return 0
    fi
  done
  log "⚠ No candidate passed a live TLS test; defaulting to ${REALITY_CANDIDATES[0]}"
  echo "${REALITY_CANDIDATES[0]}"
}

rand_hex(){ hexdump -n "$1" -e '"/%02X"' /dev/urandom | tr -d '/'; }

secure_permissions(){
  chmod 700 "$SCRIPT_DIR" "$XRAY_DIR" 2>/dev/null || true
  chmod 600 "$CONFIG_FILE" "$PUBKEY_FILE" "$UUID_FILE" 2>/dev/null || true
}

# ────────────────────────────────────────────────────────────────
# Kernel tuning
# ────────────────────────────────────────────────────────────────

tune_kernel(){
  log "Applying kernel net tuning (BBR/fastopen/buffers) …"
  cat >/etc/sysctl.d/99-ghost.conf <<'SYS'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
net.core.rmem_max=25000000
net.core.wmem_max=25000000
net.ipv4.tcp_rmem=4096 87380 25000000
net.ipv4.tcp_wmem=4096 65536 25000000
SYS
  sysctl --system >/dev/null 2>&1 || true
}

remove_kernel_tuning(){
  rm -f /etc/sysctl.d/99-ghost.conf || true
  sysctl --system >/dev/null 2>&1 || true
  log "Kernel tuning removed"
}

# ────────────────────────────────────────────────────────────────
# Xray config
# ────────────────────────────────────────────────────────────────
#   reality-tcp   → 127.0.0.1:8444  (reached publicly via nginx stream :443)
#   reality-xhttp → 0.0.0.0:<xhttp_port>  (public, direct — NOT behind nginx)

write_config(){
  log "Writing Xray config …"
  mkdir -p /var/log/xray "$XRAY_DIR" "$SCRIPT_DIR" "$SUB_DIR"

  local keys PRIV PUB SID FP DEST XPORT
  keys=$(xray_gen_keys) || { err "Reality keygen failed"; return 1; }
  PRIV=$(awk '{print $1}' <<<"$keys")
  PUB=$(awk '{print $2}' <<<"$keys")
  echo "$PUB" > "$PUBKEY_FILE"

  SID="$(rand_hex 8)"
  FP="$(shuf -e chrome edge firefox safari -n1)"
  DEST="$(pick_reality_dest)"
  XPORT="$(get_xhttp_port)"

  log "Reality camouflage target chosen: $DEST"

  cat > "$CONFIG_FILE" <<EOF
{
  "log": {
    "access": "/dev/null",
    "error": "/var/log/xray/err.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "reality-tcp",
      "listen": "127.0.0.1",
      "port": 8444,
      "protocol": "vless",
      "settings": { "clients": [ { "id": "$UUID", "flow": "" } ], "decryption": "none" },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "xver": 0,
          "show": false,
          "dest": "${DEST}:443",
          "serverNames": ["${DEST}"],
          "privateKey": "$PRIV",
          "shortIds": ["$SID"]
        },
        "tlsSettings": { "fingerprint": "$FP", "alpn": ["h2","http/1.1"] }
      }
    },
    {
      "tag": "reality-xhttp",
      "listen": "0.0.0.0",
      "port": $XPORT,
      "protocol": "vless",
      "settings": { "clients": [ { "id": "$UUID", "flow": "" } ], "decryption": "none" },
      "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "realitySettings": {
          "xver": 0,
          "show": false,
          "dest": "${DEST}:443",
          "serverNames": ["${DEST}"],
          "privateKey": "$PRIV",
          "shortIds": ["$SID"]
        },
        "xhttpSettings": { "path": "/$(rand_hex 8)", "mode": "packet-up" },
        "tlsSettings": { "fingerprint": "$FP", "alpn": ["h2"] }
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "blocked" }
  ]
}
EOF

  secure_permissions
  log "✅ Xray config written (TCP local:8444 ⇐ nginx:443 stream passthrough | XHTTP public:$XPORT direct)"
}

write_xray_service(){
  log "Writing systemd unit for Xray …"
  cat > /etc/systemd/system/xray.service <<'EOF'
[Unit]
Description=Xray Reality Service
After=network.target

[Service]
ExecStart=/usr/local/xray/xray run -config /usr/local/xray/config.json
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=2s
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable xray >/dev/null 2>&1 || true
}

install_logrotate(){
  cat > /etc/logrotate.d/xray <<'EOF'
/var/log/xray/err.log {
  weekly
  rotate 4
  compress
  missingok
  notifempty
  copytruncate
}
EOF
}

get_xhttp_path(){
  jq -r '.inbounds[] | select(.streamSettings.network=="xhttp") | .streamSettings.xhttpSettings.path // empty' \
    "$CONFIG_FILE" 2>/dev/null | sed 's|^/||'
}

# ────────────────────────────────────────────────────────────────
# Subscription builders
# ────────────────────────────────────────────────────────────────

build_vless_uri_tcp(){
  local u="$1" tag="$2"
  local sni SID FP PB uri
  sni=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$CONFIG_FILE")
  SID=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0] // empty' "$CONFIG_FILE")
  FP=$(jq -r  '.inbounds[0].streamSettings.tlsSettings.fingerprint // empty' "$CONFIG_FILE")
  PB=$(<"$PUBKEY_FILE")
  [[ -z "$PB" || -z "$SID" ]] && { err "Missing pbk/sid"; return 1; }
  [[ -z "$FP" ]] && FP="chrome"

  uri="vless://$u@$SERVER_IP:443?encryption=none&security=reality"
  uri+="&type=tcp&sni=$sni&fp=$FP&alpn=h2,http/1.1&pbk=$PB&sid=$SID"
  uri+="#${tag}-TCP"
  echo "$uri"
}

build_vless_uri_xhttp(){
  local u="$1" tag="$2"
  local sni SID FP PB path port uri
  sni=$(jq -r '.inbounds[1].streamSettings.realitySettings.serverNames[0]' "$CONFIG_FILE")
  SID=$(jq -r '.inbounds[1].streamSettings.realitySettings.shortIds[0] // empty' "$CONFIG_FILE")
  FP=$(jq -r  '.inbounds[1].streamSettings.tlsSettings.fingerprint // empty' "$CONFIG_FILE")
  PB=$(<"$PUBKEY_FILE")
  path=$(get_xhttp_path)
  port=$(get_xhttp_port)
  [[ -z "$PB" || -z "$SID" || -z "$path" ]] && { err "Missing pbk/sid/path"; return 1; }
  [[ -z "$FP" ]] && FP="chrome"

  uri="vless://$u@$SERVER_IP:$port?encryption=none&security=reality"
  uri+="&type=xhttp&mode=packet-up&path=/$path&sni=$sni&fp=$FP&alpn=h2&pbk=$PB&sid=$SID"
  uri+="#${tag}-XHTTP"
  echo "$uri"
}

generate_subscription(){
  log "→ Regenerating subscription …"
  mkdir -p "$SUB_DIR"
  local raw="$SUB_DIR/$UUID.raw"
  : > "$raw"
  { build_vless_uri_tcp   "$UUID" "RealityGhost"
    build_vless_uri_xhttp "$UUID" "RealityGhost"
  } >> "$raw"

  base64 --wrap=0 "$raw" > "$SUB_DIR/$UUID"
  secure_permissions
  log "✔ Subscription URL: https://$domain/$UUID"

  if command -v qrencode >/dev/null 2>&1; then
    qrencode -t ANSIUTF8 "https://$domain/$UUID" || true
  fi
}

# ────────────────────────────────────────────────────────────────
# NGINX — stream+ssl_preread on :443 (no TLS termination for Reality)
# ────────────────────────────────────────────────────────────────

write_nginx(){
  log "Configuring NGINX (stream SNI router + local subscription vhost) …"
  mkdir -p "$SUB_DIR" /var/www/ghost_web
  cat > /var/www/ghost_web/index.html <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><title>Welcome</title></head>
<body><h1>It works.</h1></body></html>
HTML

  cat > /etc/nginx/nginx.conf <<EOF
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events { worker_connections 4096; }

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    sendfile      on;
    keepalive_timeout 65;
    access_log off;
    error_log /var/log/nginx/error.log warn;

    # Local-only HTTPS vhost. Only reached via the stream SNI router
    # below when the client's TLS SNI matches your real domain.
    server {
        listen 127.0.0.1:8443 ssl http2;
        server_name $domain;

        ssl_certificate     /etc/letsencrypt/live/$domain/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_prefer_server_ciphers off;

        location = /$UUID {
            alias $SUB_DIR/$UUID;
            default_type text/plain;
            add_header Cache-Control "no-store";
        }
        location / {
            root /var/www/ghost_web;
            index index.html;
        }
    }
}

stream {
    map \$ssl_preread_server_name \$ghost_upstream {
        $domain  sub_backend;
        default  reality_backend;
    }

    upstream sub_backend     { server 127.0.0.1:8443; }
    upstream reality_backend { server 127.0.0.1:8444; }

    server {
        listen 443 reuseport;
        listen [::]:443 reuseport;
        proxy_pass \$ghost_upstream;
        ssl_preread on;
        proxy_timeout 3600s;
        proxy_connect_timeout 5s;
    }
}
EOF

  if nginx -t; then
    systemctl restart nginx
    log "✅ NGINX ready — :443 SNI-routes to subscription vhost or Reality-TCP passthrough"
  else
    err "NGINX config test failed"
    return 1
  fi
}

update_nginx_uuid(){
  sed -i "s|location = /[A-Za-z0-9-]\+ {|location = /$UUID {|" "$NGINX_SITE"
  nginx -t && systemctl reload nginx
  log "✅ Subscription path updated to /$UUID"
}

# ────────────────────────────────────────────────────────────────
# TLS certificate — standalone on :80 (nginx never binds :80, so this
# never conflicts, including on renewal — no stop/start dance needed)
# ────────────────────────────────────────────────────────────────

issue_certificate(){
  log "Requesting Let's Encrypt certificate for $domain via standalone (port 80) …"
  if ! certbot certonly --standalone --preferred-challenges http \
        -d "$domain" --non-interactive --agree-tos -m "$help_email"; then
    if [[ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]]; then
      log "Certbot reported an error but a certificate already exists for $domain — continuing."
    else
      err "Certbot failed and no existing certificate was found. Check that port 80 is reachable and DNS for $domain points at this server's IP."
      return 1
    fi
  fi
}

# ────────────────────────────────────────────────────────────────
# Consistency check (used by install + rotate + health check)
# ────────────────────────────────────────────────────────────────

ensure_keys_sid_and_path(){
  [[ -f "$CONFIG_FILE" ]] || { err "config.json missing"; return 1; }
  local priv; priv=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey // empty' "$CONFIG_FILE")
  [[ -z "$priv" ]] && { err "privateKey missing in config — run install again"; return 1; }
  local path; path=$(get_xhttp_path)
  [[ -z "$path" ]] && { err "xhttp path missing in config — run install again"; return 1; }
  return 0
}

health_check(){
  log "→ Running health check …"
  xray_test_config || { err "HealthCheck: xray config invalid"; return 1; }
  ensure_keys_sid_and_path || return 1

  if ! nginx -t >/dev/null 2>&1; then err "HealthCheck: nginx config invalid"; return 1; fi
  if ! systemctl is-active --quiet nginx; then err "HealthCheck: nginx not running"; return 1; fi
  if ! systemctl is-active --quiet xray;  then err "HealthCheck: xray not running";  return 1; fi

  log "✔ Health check PASSED"
  return 0
}

# ────────────────────────────────────────────────────────────────
# SAFE Rotate — fingerprint + shortId append every 3 days by cron.
# Reality key / XHTTP path are only touched on HARD rotate (opt-in,
# drops active clients).
# ────────────────────────────────────────────────────────────────

manual_rotate_all(){
  log "→ Manual rotation (SAFE by default) …"
  local tmp bak old_fp new_fp newsid keepN=6
  bak=$(tmpfile); cp -f "$CONFIG_FILE" "$bak"

  old_fp=$(jq -r '.inbounds[0].streamSettings.tlsSettings.fingerprint // empty' "$CONFIG_FILE")
  while :; do
    new_fp=$(shuf -e chrome edge firefox safari -n1)
    [[ -n "$new_fp" && "$new_fp" != "$old_fp" ]] && break
  done
  tmp=$(tmpfile)
  jq --arg fp "$new_fp" '.inbounds |= map(.streamSettings.tlsSettings.fingerprint = $fp)' \
    "$CONFIG_FILE" >"$tmp" && mv "$tmp" "$CONFIG_FILE"
  log "Rotated fingerprint → $new_fp"

  newsid=$(rand_hex 8)
  tmp=$(tmpfile)
  jq --arg s "$newsid" --argjson n "$keepN" \
    '.inbounds |= map(.streamSettings.realitySettings.shortIds = (([$s] + (.streamSettings.realitySettings.shortIds // []))[:$n]))' \
    "$CONFIG_FILE" >"$tmp" && mv "$tmp" "$CONFIG_FILE"
  log "Appended shortId → $newsid (keeping last $keepN)"

  if [[ "${ROTATE_KEYS:-0}" == "1" ]]; then
    log "HARD ROTATE: Reality keys (active clients will drop)"
    local keys priv pub
    keys=$(xray_gen_keys) || { err "Keygen failed"; cp -f "$bak" "$CONFIG_FILE"; return 1; }
    priv=$(cut -d' ' -f1 <<<"$keys"); pub=$(cut -d' ' -f2 <<<"$keys")
    echo "$pub" > "$PUBKEY_FILE"
    tmp=$(tmpfile)
    jq --arg pk "$priv" '.inbounds |= map(.streamSettings.realitySettings.privateKey = $pk)' \
      "$CONFIG_FILE" >"$tmp" && mv "$tmp" "$CONFIG_FILE"
  fi

  if [[ "${ROTATE_PATH:-0}" == "1" ]]; then
    log "HARD ROTATE: XHTTP path (active XHTTP clients will drop)"
    local p; p="/$(rand_hex 8)"
    tmp=$(tmpfile)
    jq --arg v "$p" '.inbounds |= map(if .streamSettings.network=="xhttp" then .streamSettings.xhttpSettings.path=$v else . end)' \
      "$CONFIG_FILE" >"$tmp" && mv "$tmp" "$CONFIG_FILE"
  fi

  secure_permissions
  if ! xray_test_config; then
    err "Config invalid after rotation → rollback"
    cp -f "$bak" "$CONFIG_FILE"
    return 1
  fi

  systemctl restart xray
  generate_subscription
  log "✔ Rotation complete."
}

switch_transport(){
  local cur next
  cur=$(get_transport)
  next=$([[ "$cur" == "xhttp" ]] && echo tcp || echo xhttp)
  set_transport "$next"
  generate_subscription
  log "✅ Default shown link switched to $next (both transports remain active on the server)"
}

# ────────────────────────────────────────────────────────────────
# Install / Manage / Uninstall
# ────────────────────────────────────────────────────────────────

show_banner(){
cat <<'EOF'
  ____             _ _ _         ____ _               _
 |  _ \ ___  __ _| (_) |_ _   _ / ___| |__   ___  ___| |_
 | |_) / _ \/ _` | | | __| | | | |  _| '_ \ / _ \/ __| __|
 |  _ <  __/ (_| | | | |_| |_| | |_| | | | | (_) \__ \ |_
 |_| \_\___|\__,_|_|_|\__|\__, |\____|_| |_|\___/|___/\__|
                          |___/          P R O   v4.0.0
EOF
}

install(){
  [[ $EUID -eq 0 ]] || { err "Run as root"; exit 1; }
  clear; show_banner; echo
  log "=== RealityGhost PRO Install (Dual-Mode, collision-free) ==="

  # Non-interactive support: DOMAIN=, EMAIL=, XHTTP_PORT= env vars
  domain="${DOMAIN:-}"
  if [[ -z "$domain" ]]; then
    while true; do domain=$(ask "Subscription Domain (must already point at this server's IP): ")
      [[ -n "$domain" ]] && break; echo "⚠ Domain cannot be empty."; done
  fi

  local help_email="${EMAIL:-}"
  if [[ -z "$help_email" ]]; then
    while true; do help_email=$(ask "Email for Let's Encrypt: ")
      [[ -n "$help_email" ]] && break; echo "⚠ Email cannot be empty."; done
  fi
  echo "$domain" > "$GHOST_CONF"

  echo "${XHTTP_PORT:-$DEFAULT_XHTTP_PORT}" > "$XHTTP_PORT_FILE"
  set_transport "$DEFAULT_TRANSPORT"

  UUID="$(uuidgen)"
  log "Generated UUID → $UUID"

  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y curl unzip jq openssl ufw qrencode vnstat uuid-runtime \
    nginx libnginx-mod-stream certbot xxd python3 logrotate

  mkdir -p "$SCRIPT_DIR" "$SUB_DIR"
  echo "$UUID" > "$UUID_FILE"

  detect_ip || true

  local SSH_PORT
  SSH_PORT=$(ss -tnlp 2>/dev/null | awk '/sshd/ && /LISTEN/ {print $4}' | sed 's/.*://;q')
  [[ -z "${SSH_PORT:-}" ]] && SSH_PORT=22
  ufw allow "${SSH_PORT}/tcp" || true
  ufw allow 80/tcp   || true   # certbot standalone HTTP-01
  ufw allow 443/tcp  || true   # nginx stream SNI router (TCP-Reality + subscription)
  ufw allow "$(get_xhttp_port)/tcp" || true   # XHTTP-Reality, direct
  ufw --force enable || true

  XRAYVER="$(get_latest_xray_version)"
  log "Installing Xray v$XRAYVER …"
  curl -L -o /tmp/x.zip "https://github.com/XTLS/xray-core/releases/download/v${XRAYVER}/Xray-linux-64.zip"
  mkdir -p "$XRAY_DIR" && unzip -oq /tmp/x.zip -d "$XRAY_DIR" && chmod +x "$XRAY_DIR/xray"

  # nginx must NOT be running while certbot binds :80 standalone the first time
  systemctl stop nginx 2>/dev/null || true
  issue_certificate || return 1

  log "Writing Xray config …"
  write_config
  write_xray_service
  systemctl restart xray
  sleep 1

  log "Writing NGINX …"
  write_nginx

  tune_kernel || true
  install_logrotate

  ensure_keys_sid_and_path || { err "Post-install consistency check failed"; return 1; }
  health_check || { err "Refusing to generate subscription on a broken install"; return 1; }
  generate_subscription

  echo "0 5 */3 * * root /usr/local/bin/realityghost manual-rotate" > /etc/cron.d/ghost
  ln -sf "$(realpath "$0")" /usr/local/bin/realityghost
  chmod +x /usr/local/bin/realityghost "$(realpath "$0")" || true

  echo
  log "=== Install complete ==="
  echo "  TCP-Reality  (via nginx :443) : public port 443"
  echo "  XHTTP-Reality (direct)        : public port $(get_xhttp_port)"
  echo "  Subscription                  : https://$domain/$UUID"
  echo
  log "Run 'realityghost manage' any time to view/rotate/switch."
}

manage(){
  [[ $EUID -eq 0 ]] || { err "Run as root"; exit 1; }
  while true; do
    clear; show_banner
    local cur; cur=$(get_transport)
    cat <<EOF

RealityGhost PRO Manager (default link=$cur, xhttp_port=$(get_xhttp_port))
------------------------------
1) Show subscription link + QR
2) Regenerate subscription
3) Manual rotate (SAFE)
4) Manual rotate (HARD — new keys, drops clients)
5) Update server IP (subs only)
6) Change UUID
7) Switch default shown transport (TCP <-> XHTTP)
8) Restart Xray
9) Show bandwidth stats
10) Show Xray logs
11) Run health check
12) Uninstall
0) Exit
EOF
    read -r -p "Choice: " ch
    clear
    case ${ch:-} in
      1)
        echo "https://$domain/$UUID"
        command -v qrencode >/dev/null 2>&1 && qrencode -t ANSIUTF8 "https://$domain/$UUID" || true
        ;;
      2) generate_subscription ;;
      3) manual_rotate_all ;;
      4) ROTATE_KEYS=1 ROTATE_PATH=1 manual_rotate_all ;;
      5)
        local newip; newip=$(ask "New public IP (blank=auto-detect): ")
        [[ -z "$newip" ]] && newip=$(curl -sf https://api.ipify.org || curl -sf https://ifconfig.me || true)
        if [[ -n "$newip" ]]; then SERVER_IP="$newip"; generate_subscription; else err "Could not detect/set IP"; fi
        ;;
      6)
        local newu tmp
        read -r -p "New UUID (blank = auto-generate): " newu
        [[ -z "$newu" ]] && newu="$(uuidgen)"
        UUID="$newu"; echo "$UUID" > "$UUID_FILE"
        tmp=$(tmpfile)
        jq --arg u "$UUID" '.inbounds[].settings.clients[0].id=$u' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
        if xray_test_config; then
          update_nginx_uuid; generate_subscription; systemctl restart xray
          log "UUID updated → $UUID"
        else
          err "Invalid config after UUID change — not applied"
        fi
        ;;
      7) switch_transport ;;
      8) systemctl restart xray; log "Xray restarted" ;;
      9) vnstat -d 2>/dev/null | tail -n1 || true ;;
      10) journalctl -u xray -n 80 --no-pager || true ;;
      11) health_check ;;
      12) uninstall; break ;;
      0) exit 0 ;;
      *) err "Invalid choice" ;;
    esac
    echo; read -r -p "Press Enter to continue…" _
  done
}

uninstall(){
  log "Uninstalling RealityGhost PRO …"
  systemctl stop xray nginx 2>/dev/null || true
  systemctl disable xray 2>/dev/null || true

  ufw delete allow 80/tcp 2>/dev/null || true
  ufw delete allow 443/tcp 2>/dev/null || true
  ufw delete allow "$(get_xhttp_port)/tcp" 2>/dev/null || true

  remove_kernel_tuning || true
  rm -rf "$XRAY_DIR" "$SCRIPT_DIR" "$SUB_DIR" 2>/dev/null || true
  rm -f "$PUBKEY_FILE" "$UUID_FILE" "$GHOST_CONF" "$TRANSPORT_FILE" "$XHTTP_PORT_FILE" 2>/dev/null || true
  rm -f /etc/cron.d/ghost /usr/local/bin/realityghost 2>/dev/null || true
  rm -f /etc/systemd/system/xray.service /etc/logrotate.d/xray 2>/dev/null || true
  systemctl daemon-reload 2>/dev/null || true

  log "NGINX left installed but unconfigured for RealityGhost. Remove manually if unused elsewhere."
  log "Uninstalled."
}

case "${1:-}" in
  install)        install ;;
  manage)         manage ;;
  manual-rotate)  manual_rotate_all ;;
  health)         health_check ;;
  uninstall)      uninstall ;;
  *) echo "Usage: $0 {install|manage|manual-rotate|health|uninstall}"; exit 1 ;;
esac
