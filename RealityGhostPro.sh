#!/bin/bash
# RealityGhost PRO v6.0 — Fully automatic Xray VLESS+Reality installer

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; PURPLE='\033[0;35m'; WHITE='\033[1;37m'
BOLD='\033[1m'; NC='\033[0m'
INFO="${CYAN}[ℹ]${NC}"; OK="${GREEN}[✓]${NC}"; ERR="${RED}[✗]${NC}"; WARN="${YELLOW}[⚠]${NC}"

DOMAIN="${DOMAIN:-}"; EMAIL="${EMAIL:-}"
SUB_PORT="443"; XRAY_TCP_PORT="8443"
INSTALL_DIR="/usr/local/share/xray"
CONFIG_DIR="/usr/local/etc/xray"
NGINX_CONF_DIR="/etc/nginx"
LOG_DIR="/var/log/xray"
STATUS_DIR="/var/www/html/status"
SUB_DIR="/var/www/html/sub"
STATE_DIR="/var/lib/realityghost"
MONITOR_SCRIPT="/usr/local/bin/realityghost_monitor.sh"

SNI_LIST=(
  "www.gstatic.com:Google Static:Google%20Static"
  "ajax.googleapis.com:Google AJAX:Google%20AJAX"
  "storage.googleapis.com:Google Storage:Google%20Storage"
  "fonts.gstatic.com:Google Fonts:Google%20Fonts"
  "fonts.googleapis.com:Google Fonts API:Google%20Fonts%20API"
  "www.google.com:Google:Google"
)

detect_location() {
  local data country ip retries=0
  # Retry up to 3 times with 2s delay to handle slow DNS on first boot
  while [[ $retries -lt 3 ]]; do
    data=$(curl -4 -s --max-time 5 "https://ipapi.co/json/" 2>/dev/null)
    country=$(echo "$data" | jq -r '.country_code // ""' 2>/dev/null)
    ip=$(echo "$data" | jq -r '.ip // ""' 2>/dev/null)
    [[ -n "$country" && "$country" != "null" && ${#country} -le 3 ]] && break
    data=$(curl -4 -s --max-time 5 "http://ip-api.com/json/" 2>/dev/null)
    country=$(echo "$data" | jq -r '.countryCode // ""' 2>/dev/null)
    ip=$(echo "$data" | jq -r '.query // ""' 2>/dev/null)
    [[ -n "$country" && "$country" != "null" ]] && break
    data=$(curl -4 -s --max-time 5 "https://ipinfo.io/json" 2>/dev/null)
    country=$(echo "$data" | jq -r '.country // ""' 2>/dev/null)
    ip=$(echo "$data" | jq -r '.ip // ""' 2>/dev/null)
    [[ -n "$country" && "$country" != "null" ]] && break
    retries=$((retries+1))
    [[ $retries -lt 3 ]] && sleep 2
  done
  [[ -z "$country" || "$country" == "null" ]] && country="XX"
  case "$country" in
    IR) FLAG="%F0%9F%87%AE%F0%9F%87%B7"; FLAG_RAW="🇮🇷"; LOC="Iran" ;;
    DE) FLAG="%F0%9F%87%A9%F0%9F%87%AA"; FLAG_RAW="🇩🇪"; LOC="Germany" ;;
    NL) FLAG="%F0%9F%87%B3%F0%9F%87%B1"; FLAG_RAW="🇳🇱"; LOC="Netherlands" ;;
    FR) FLAG="%F0%9F%87%AB%F0%9F%87%B7"; FLAG_RAW="🇫🇷"; LOC="France" ;;
    GB) FLAG="%F0%9F%87%AC%F0%9F%87%A7"; FLAG_RAW="🇬🇧"; LOC="UK" ;;
    CA) FLAG="%F0%9F%87%A8%F0%9F%87%A6"; FLAG_RAW="🇨🇦"; LOC="Canada" ;;
    SE) FLAG="%F0%9F%87%B8%F0%9F%87%AA"; FLAG_RAW="🇸🇪"; LOC="Sweden" ;;
    NO) FLAG="%F0%9F%87%B3%F0%9F%87%B4"; FLAG_RAW="🇳🇴"; LOC="Norway" ;;
    FI) FLAG="%F0%9F%87%AB%F0%9F%87%AE"; FLAG_RAW="🇫🇮"; LOC="Finland" ;;
    CH) FLAG="%F0%9F%87%A8%F0%9F%87%AD"; FLAG_RAW="🇨🇭"; LOC="Switzerland" ;;
    TR) FLAG="%F0%9F%87%B9%F0%9F%87%B7"; FLAG_RAW="🇹🇷"; LOC="Turkey" ;;
    AE) FLAG="%F0%9F%87%A6%F0%9F%87%AA"; FLAG_RAW="🇦🇪"; LOC="UAE" ;;
    SG) FLAG="%F0%9F%87%B8%F0%9F%87%AC"; FLAG_RAW="🇸🇬"; LOC="Singapore" ;;
    JP) FLAG="%F0%9F%87%AF%F0%9F%87%B5"; FLAG_RAW="🇯🇵"; LOC="Japan" ;;
    US) FLAG="%F0%9F%87%BA%F0%9F%87%B8"; FLAG_RAW="🇺🇸"; LOC="USA" ;;
    LV) FLAG="%F0%9F%87%B1%F0%9F%87%BB"; FLAG_RAW="🇱🇻"; LOC="Latvia" ;;
    XX) FLAG=""; FLAG_RAW="🌍"; LOC="Unknown" ;;
    *)  FLAG=""; FLAG_RAW="🌍"; LOC="Unknown" ;;
  esac
}

check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo -e "${ERR}This script must be run as root${NC}"
    exit 1
  fi
}

preflight_check() {
  echo -e "${INFO}Checking system..."
  grep -q "Ubuntu\|Debian" /etc/os-release 2>/dev/null || echo -e "${WARN}Only Ubuntu/Debian tested"
  local ports=("443" "${XRAY_TCP_PORT}" "${SUB_PORT}")
  for p in "${ports[@]}"; do
    if ss -tlnp | grep -q ":${p} "; then
      local proc=$(ss -tlnp | grep ":${p} " | awk '{print $7}' | tr -d '"')
      echo -e "${WARN}Port ${p} in use by ${proc:-?} — auto-releasing"
      local pid=$(ss -tlnp | grep ":${p} " | grep -oP 'pid=\K[0-9]+')
      [[ -n "$pid" ]] && kill -9 "$pid" 2>/dev/null && echo -e "${OK}Port ${p} freed"
    fi
  done
  nslookup google.com >/dev/null 2>&1 || dig google.com >/dev/null 2>&1 || {
    echo -e "${WARN}DNS not working — setting 8.8.8.8"
    echo "nameserver 8.8.8.8" > /etc/resolv.conf 2>/dev/null
    sleep 2
  }
  ping -4 -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 || echo -e "${WARN}Network check failed (ignoring)"
  echo -e "${OK}System ready"
}

install_dependencies() {
  echo -e "${INFO}Installing dependencies..."
  apt-get update -y 2>/dev/null | tail -1
  apt-get install -y wget curl unzip uuid-runtime jq qrencode certbot \
    nginx-extras logrotate bc netcat-openbsd dnsutils python3 python3-pip sqlite3 figlet 2>/dev/null | tail -1
  pip3 install python-telegram-bot requests --break-system-packages -q 2>/dev/null || true
  echo -e "${OK}Dependencies installed"
}

system_tuning() {
  echo -e "${INFO}System tuning..."
  if [[ "$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')" != "bbr" ]]; then
    modprobe tcp_bbr 2>/dev/null
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.d/99-realityghost.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.d/99-realityghost.conf
  fi
  cat >> /etc/sysctl.d/99-realityghost.conf <<SYSCTLEOF
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.core.rmem_default=262144
net.core.wmem_default=262144
net.core.netdev_budget=600
net.core.somaxconn=65535
net.core.optmem_max=65536
net.ipv4.tcp_rmem=4096 131072 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_max_syn_backlog=65535
net.ipv4.tcp_max_tw_buckets=2000000
net.ipv4.ip_local_port_range=1024 65535
net.ipv4.tcp_notsent_lowat=16384
net.ipv4.udp_rmem_min=8192
net.ipv4.udp_wmem_min=8192
SYSCTLEOF
  sysctl -p /etc/sysctl.d/99-realityghost.conf > /dev/null 2>&1
  grep -q "nofile" /etc/security/limits.conf 2>/dev/null || cat >> /etc/security/limits.conf <<LIMITSEOF
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
LIMITSEOF
  mkdir -p /etc/systemd/system/xray.service.d
  cat > /etc/systemd/system/xray.service.d/limits.conf <<SYSEOF
[Service]
LimitNOFILE=1048576
LimitNPROC=infinity
CPUAccounting=yes
MemoryAccounting=yes
SYSEOF
  systemctl daemon-reload
}

generate_uuid() {
  command -v uuidgen &>/dev/null && uuidgen || cat /proc/sys/kernel/random/uuid
}

generate_reality_keys() {
  /usr/local/bin/xray x25519 2>/dev/null || {
    /usr/local/share/xray/xray x25519 2>/dev/null || {
      echo "ERROR:no"
      return 1
    }
  }
}

install_xray() {
  echo -e "${INFO}Installing Xray..."
  mkdir -p "$INSTALL_DIR" "$CONFIG_DIR"
  if command -v /usr/local/bin/xray &>/dev/null; then
    echo -e "${OK}Xray already installed"
    return 0
  fi
  local url=$(curl -sL https://api.github.com/repos/XTLS/Xray-core/releases/latest 2>/dev/null | jq -r '.assets[] | select(.name | test("linux-64")) | .browser_download_url' 2>/dev/null | head -1)
  [[ -z "$url" ]] && { echo -e "${ERR}Failed to download Xray${NC}"; exit 1; }
  curl -sL "$url" -o /tmp/xray.zip
  unzip -qo /tmp/xray.zip -d /tmp/xray-core 2>/dev/null
  cp /tmp/xray-core/xray "$INSTALL_DIR/xray"
  ln -sf "$INSTALL_DIR/xray" /usr/local/bin/xray
  chmod +x /usr/local/bin/xray
  rm -rf /tmp/xray.zip /tmp/xray-core
  cat > /etc/systemd/system/xray.service <<SERVEOF
[Unit]
Description=Xray Service
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/xray run -config ${CONFIG_DIR}/config.json
Restart=always
RestartSec=3
User=root
[Install]
WantedBy=multi-user.target
SERVEOF
  systemctl daemon-reload
  echo -e "${OK}Xray $(/usr/local/bin/xray version 2>/dev/null | head -1) installed"
}

install_certbot() {
  if [[ -z "$DOMAIN" ]]; then
    echo -ne "${BOLD}Domain (your-domain.com): ${NC}"; read -r DOMAIN
  fi
  if [[ -z "$EMAIL" ]]; then
    echo -ne "${BOLD}Email (for Let's Encrypt): ${NC}"; read -r EMAIL
  fi
  if [[ -d "/etc/letsencrypt/live/${DOMAIN}" ]]; then
    echo -e "${OK}SSL already exists"
    return 0
  fi
  echo -e "${INFO}Verifying DNS points to this server..."
  SERVER_IP=$(curl -4 -s --max-time 5 https://api.ipify.org 2>/dev/null)
  # Wait up to 5 min for DNS to propagate correctly
  local waited=0
  while [[ $waited -lt 300 ]]; do
    DOMAIN_IP=$(dig +short "${DOMAIN}" 2>/dev/null | tail -1)
    if [[ "$SERVER_IP" == "$DOMAIN_IP" ]]; then
      echo -e "${OK}DNS OK: ${DOMAIN} → ${SERVER_IP}"
      break
    fi
    echo -e "${YELLOW}Waiting for DNS... (${waited}s) domain→${DOMAIN_IP:-none}, server→${SERVER_IP}${NC}"
    sleep 15
    waited=$((waited+15))
  done
  if [[ "$SERVER_IP" != "$DOMAIN_IP" ]]; then
    echo -e "${ERR}DNS still not pointing to this server after 5 min.${NC}"
    echo -e "${ERR}Set your DNS A record: ${DOMAIN} → ${SERVER_IP}${NC}"
    echo -e "${ERR}Then run: bash RealityGhostPro.sh renew-ssl${NC}"
  fi
  echo -e "${INFO}Getting SSL from Let's Encrypt..."
  systemctl stop nginx 2>/dev/null
  certbot certonly --standalone --non-interactive --agree-tos -d "${DOMAIN}" -m "${EMAIL}" 2>/dev/null
  systemctl start nginx 2>/dev/null
  if [[ -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]]; then
    echo -e "${OK}SSL obtained"
    (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet --post-hook 'systemctl reload nginx'") | crontab -
  else
    echo -e "${YELLOW}SSL failed. Using self-signed cert (domain may not point to this IP)${NC}"
    mkdir -p /etc/nginx/ssl
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
      -keyout /etc/nginx/ssl/panel.key \
      -out /etc/nginx/ssl/panel.crt \
      -subj "/CN=${DOMAIN}" 2>/dev/null
    SSL_CERT="/etc/nginx/ssl/panel.crt"
    SSL_KEY="/etc/nginx/ssl/panel.key"
    echo -e "${OK}Self-signed cert created at $SSL_CERT"
  fi
}

configure_nginx() {
  echo -e "${INFO}Configuring NGINX (SNI routing: 443 → panel/xray)..."
  cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup 2>/dev/null
  [[ -z "$SSL_CERT" ]] && SSL_CERT="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
  [[ -z "$SSL_KEY" ]] && SSL_KEY="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"
  # Install stream module if missing
  apt-get install -y libnginx-mod-stream >/dev/null 2>&1
  ln -sf /usr/share/nginx/modules-available/mod-stream.conf /etc/nginx/modules-enabled/50-mod-stream.conf 2>/dev/null
  cat > /etc/nginx/nginx.conf <<NGINXEOF
load_module modules/ngx_stream_module.so;
user www-data;
worker_processes auto;
pid /run/nginx.pid;

events {
    worker_connections 16384;
    multi_accept on;
    use epoll;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    sendfile on;
    keepalive_timeout 65;

    server {
        listen 127.0.0.1:8444 ssl;
        server_name ${DOMAIN};
        ssl_certificate ${SSL_CERT};
        ssl_certificate_key ${SSL_KEY};
        ssl_protocols TLSv1.2 TLSv1.3;
        location /status/ {
            alias ${STATUS_DIR}/;
            index index.html;
            try_files \$uri \$uri/ /status/index.html;
        }
        location /sub {
            alias ${SUB_DIR}/sub.txt;
            default_type text/plain;
        }
    }
}

stream {
    map \$ssl_preread_server_name \$backend {
        ${DOMAIN}    127.0.0.1:8444;
        default      127.0.0.1:${XRAY_TCP_PORT};
    }
    server {
        listen 0.0.0.0:443;
        ssl_preread on;
        proxy_pass \$backend;
    }
}
NGINXEOF
  nginx -t 2>/dev/null && systemctl restart nginx
  echo -e "${OK}NGINX configured (port 443 shared by panel + Xray via SNI)"
}

configure_xray() {
  echo -e "${INFO}Configuring Xray..."
  local uuid=$(generate_uuid)
  local keys=$(generate_reality_keys)
  local private_key=$(echo "$keys" | grep -oE "Private(Key)?: ?\S+" | head -1 | grep -oE "\S+$")
  local public_key=$(echo "$keys" | grep -oE "(PublicKey|Password \(PublicKey\)): ?\S+" | head -1 | grep -oE "\S+$")
  local sids=(); local snis_json=""; local sids_json=""; local i=0
  for entry in "${SNI_LIST[@]}"; do
    IFS=':' read -r sni label label_url <<< "$entry"
    while true; do
      local sid=$(openssl rand -hex 8)
      local dup=false
      for existing in "${sids[@]}"; do [[ "$existing" == "$sid" ]] && { dup=true; break; }; done
      $dup && continue
      [[ ${#sid} -eq 16 && "$sid" =~ ^[0-9a-f]+$ ]] && break
    done
    sids+=("$sid")
    [[ $i -gt 0 ]] && snis_json+=","; snis_json+="\"$sni\""
    [[ $i -gt 0 ]] && sids_json+=","; sids_json+="\"$sid\""
    i=$((i+1))
  done
  local extra_snis='["googleadservices.com","google-analytics.com","googletagmanager.com","googleapis.com"]'
  cat <<XRAYEOF | tee "$CONFIG_DIR/config.json" > /dev/null
{
  "log": { "loglevel": "info", "access": "${LOG_DIR}/access.log", "error": "${LOG_DIR}/error.log" },
  "inbounds": [{
    "port": ${XRAY_TCP_PORT}, "listen": "0.0.0.0", "protocol": "vless",
    "settings": {
      "clients": [{ "id": "${uuid}", "flow": "xtls-rprx-vision", "level": 0, "email": "user@${DOMAIN}" }],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp", "security": "reality",
      "realitySettings": {
        "show": false, "dest": "www.gstatic.com:443", "xver": 0,
        "serverNames": [${snis_json},"googleadservices.com","google-analytics.com","googletagmanager.com","googleapis.com"],
        "privateKey": "${private_key}",
        "shortIds": [${sids_json}]
      }
    },
    "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"], "routeOnly": true },
    "allocate": { "strategy": "always", "refresh": 5, "concurrency": 8 }
  }],
  "outbounds": [{ "protocol": "freedom", "settings": {} }]
}
XRAYEOF
  chmod 600 "$CONFIG_DIR/config.json"
  mkdir -p "$LOG_DIR"; chown -R nobody:nogroup "$LOG_DIR" 2>/dev/null
  cat <<INFOEOF | tee "$CONFIG_DIR/client_info.txt" > /dev/null
═══════════ RealityGhost PRO ═══════════
Domain: ${DOMAIN}
UUID: ${uuid}
Public Key: ${public_key}
Port: 443 (SNI Passthrough)
INFOEOF
  local idx=0
  for entry in "${SNI_LIST[@]}"; do
    IFS=':' read -r sni label label_url <<< "$entry"
    local real_sid=$(jq -r ".inbounds[0].streamSettings.realitySettings.shortIds[$idx]" "$CONFIG_DIR/config.json" 2>/dev/null)
    [[ -z "$real_sid" || "$real_sid" == "null" ]] && real_sid="${sids[$idx]}"
    local link="vless://${uuid}@${DOMAIN}:443?flow=xtls-rprx-vision&encryption=none&security=reality&sni=${sni}&fp=chrome&spx=%2F&pbk=${public_key}&sid=${real_sid}&allowinsecure=0&type=tcp&headerType=none#${FLAG}%20${label_url}"
    echo "$link" >> "$CONFIG_DIR/client_info.txt"
    idx=$((idx+1))
  done
  echo -e "${OK}Xray configured"
}

build_subscription() {
  local uuid=$(jq -r '.inbounds[0].settings.clients[0].id' "$CONFIG_DIR/config.json" 2>/dev/null)
  local pbk=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$CONFIG_DIR/config.json" 2>/dev/null)
  [[ -z "$uuid" || -z "$pbk" ]] && { echo -e "${ERR}Error reading config${NC}"; return 1; }
  local pubkey=""
  local keys=$(/usr/local/bin/xray x25519 -i "$pbk" 2>/dev/null)
  pubkey=$(echo "$keys" | grep -oE "(PublicKey|Password \(PublicKey\)): ?\S+" | head -1 | grep -oE "\S+$")
  [[ -z "$pubkey" ]] && echo -e "${WARN}Warning: could not derive public key from private key${NC}"
  mkdir -p "$SUB_DIR"
  local lines=()
  local idx=0
  for entry in "${SNI_LIST[@]}"; do
    IFS=':' read -r sni label label_url <<< "$entry"
    local real_sid=$(jq -r ".inbounds[0].streamSettings.realitySettings.shortIds[$idx]" "$CONFIG_DIR/config.json" 2>/dev/null)
    [[ -z "$real_sid" || "$real_sid" == "null" ]] && real_sid="0000000000000000"
    lines+=("vless://${uuid}@${DOMAIN}:443?flow=xtls-rprx-vision&encryption=none&security=reality&sni=${sni}&fp=chrome&spx=%2F&pbk=${pubkey}&sid=${real_sid}&allowinsecure=0&type=tcp&headerType=none#${FLAG}%20${label_url}")
    idx=$((idx+1))
  done
  printf '%s\n' "${lines[@]}" | base64 -w 0 > "$SUB_DIR/sub.txt"
  chown www-data:www-data "$SUB_DIR/sub.txt" 2>/dev/null
  echo -e "${OK}Subscription built (6 configs)"
}

build_panel() {
  local uuid=$(jq -r '.inbounds[0].settings.clients[0].id' "$CONFIG_DIR/config.json" 2>/dev/null)
  local pbk=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$CONFIG_DIR/config.json" 2>/dev/null)
  local pubkey_line=$(/usr/local/bin/xray x25519 -i "$pbk" 2>/dev/null | grep -oE "(PublicKey|Password \(PublicKey\)): ?\S+" | head -1 | grep -oE "\S+$")
  [[ -z "$pubkey_line" ]] && pubkey_line="$pbk"
  local SERVER_IP=$(curl -4 -s --max-time 3 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')

  # Build configs array in the panel's CS format: {s,l,e,i}
  local configs_js="" idx=0; local emojis=("🟢" "🟣" "🟠" "🔴" "🟤" "🔵")
  for entry in "${SNI_LIST[@]}"; do
    IFS=':' read -r sni label label_url <<< "$entry"
    local real_sid=$(jq -r ".inbounds[0].streamSettings.realitySettings.shortIds[$idx]" "$CONFIG_DIR/config.json" 2>/dev/null)
    [[ -z "$real_sid" || "$real_sid" == "null" ]] && real_sid="0000000000000000"
    [[ $idx -gt 0 ]] && configs_js+=","
    configs_js+="{s:'${sni}', l:'${FLAG_RAW} ${label}', e:'${emojis[$idx]}', i:'${real_sid}'}"
    idx=$((idx+1))
  done

  mkdir -p "$STATUS_DIR"
  cat > "$STATUS_DIR/index.html" <<'PANEOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta http-equiv="refresh" content="">
<title>RG PRO · Dashboard</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<style>
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800;900&display=swap');
:root{
  --bg:#080814; --glass:rgba(255,255,255,0.045); --glass2:rgba(255,255,255,0.07);
  --stroke:rgba(255,255,255,0.09); --stroke2:rgba(255,255,255,0.14);
  --t:#eef0ff; --t2:#9aa0c8; --t3:#6b7099;
  --p:#8b7bff; --p2:#a99bff; --pg:#6c4cf0;
  --g:#2fe0a6; --y:#ffc36b; --r:#ff6b81; --bl:#5aa6ff;
  --rad:22px; --rad2:16px; --rad3:12px;
  --shadow:0 10px 40px rgba(0,0,0,0.45), inset 0 1px 0 rgba(255,255,255,0.08);
  --blur:blur(22px) saturate(160%);
  --trans:all .25s cubic-bezier(.22,1,.36,1);
}
*{margin:0;padding:0;box-sizing:border-box}
html{scroll-behavior:smooth}
body{
  font-family:'Inter',system-ui,-apple-system,'Segoe UI',sans-serif;
  background:var(--bg); color:var(--t); min-height:100vh;
  position:relative; overflow-x:hidden; -webkit-font-smoothing:antialiased;
}
/* animated glass background blobs */
.bg{position:fixed;inset:0;z-index:0;overflow:hidden;pointer-events:none}
.blob{position:absolute;border-radius:50%;filter:blur(90px);opacity:.55;animation:float 22s ease-in-out infinite}
.blob.a{width:520px;height:520px;background:radial-gradient(circle,#7c5cfc,transparent 70%);top:-160px;left:-120px}
.blob.b{width:480px;height:480px;background:radial-gradient(circle,#4a9eff,transparent 70%);top:10%;right:-160px;animation-delay:-6s}
.blob.c{width:440px;height:440px;background:radial-gradient(circle,#00d68f,transparent 70%);bottom:-180px;left:20%;animation-delay:-12s;opacity:.4}
.blob.d{width:360px;height:360px;background:radial-gradient(circle,#ff6bce,transparent 70%);bottom:5%;right:15%;animation-delay:-3s;opacity:.35}
@keyframes float{0%,100%{transform:translate(0,0) scale(1)}33%{transform:translate(40px,-30px) scale(1.08)}66%{transform:translate(-30px,25px) scale(.95)}}
.grain{position:fixed;inset:0;z-index:1;pointer-events:none;opacity:.025;
  background-image:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='120' height='120'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='3'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E")}
.w{position:relative;z-index:2;max-width:1400px;margin:0 auto;padding:26px 22px 40px}
/* glass primitives */
.glass{background:var(--glass);backdrop-filter:var(--blur);-webkit-backdrop-filter:var(--blur);border:1px solid var(--stroke);border-radius:var(--rad);box-shadow:var(--shadow)}
/* header */
.hd{display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:14px;padding:18px 24px;margin-bottom:22px}
.hd-l{display:flex;align-items:center;gap:15px}
.logo{width:46px;height:46px;border-radius:14px;display:grid;place-items:center;font-size:24px;background:linear-gradient(135deg,rgba(124,92,252,.35),rgba(74,158,255,.15));border:1px solid var(--stroke2);box-shadow:inset 0 1px 0 rgba(255,255,255,.15)}
.hd-tt h1{font-size:19px;font-weight:800;letter-spacing:-.4px;line-height:1.1}
.hd-tt h1 b{background:linear-gradient(135deg,var(--p2),var(--bl));-webkit-background-clip:text;background-clip:text;-webkit-text-fill-color:transparent}
.hd-tt .sub{display:flex;align-items:center;gap:8px;margin-top:4px;font-size:12px;color:var(--t2)}
.hd-tt .sub .flag{font-size:14px}
.hd-tt .sub #dm{color:var(--p2);font-weight:600;direction:ltr}
.hd-r{display:flex;align-items:center;gap:10px}
.pill{display:flex;align-items:center;gap:8px;padding:9px 16px;border-radius:100px;font-size:12px;font-weight:700;background:rgba(47,224,166,.1);color:var(--g);border:1px solid rgba(47,224,166,.22);backdrop-filter:blur(8px)}
.pill.off{background:rgba(255,107,129,.1);color:var(--r);border-color:rgba(255,107,129,.22)}
.dot{width:8px;height:8px;border-radius:50%;background:var(--g);box-shadow:0 0 10px var(--g);animation:pulse 1.6s ease infinite}
.dot.off{background:var(--r);box-shadow:0 0 10px var(--r)}
@keyframes pulse{0%,100%{opacity:1;transform:scale(1)}50%{opacity:.35;transform:scale(.65)}}
.ghost-btn{display:grid;place-items:center;width:40px;height:40px;border-radius:12px;background:var(--glass2);border:1px solid var(--stroke);color:var(--t2);cursor:pointer;font-size:16px;transition:var(--trans)}
.ghost-btn:hover{background:rgba(124,92,252,.16);color:var(--p2);border-color:rgba(124,92,252,.3);transform:translateY(-2px)}
/* stat cards */
.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(158px,1fr));gap:16px;margin-bottom:20px}
.stat{padding:18px 20px;position:relative;overflow:hidden}
.stat::after{content:'';position:absolute;top:0;left:0;right:0;height:1px;background:linear-gradient(90deg,transparent,rgba(255,255,255,.18),transparent)}
.stat .ic{width:38px;height:38px;border-radius:11px;display:grid;place-items:center;font-size:18px;background:var(--glass2);border:1px solid var(--stroke);margin-bottom:12px}
.stat .lb{font-size:10.5px;text-transform:uppercase;letter-spacing:1px;color:var(--t3);font-weight:700}
.stat .vl{font-size:25px;font-weight:800;letter-spacing:-.6px;margin-top:3px;display:flex;align-items:baseline;gap:5px}
.stat .vl small{font-size:12px;font-weight:500;color:var(--t2)}
.stat .mini{height:5px;border-radius:100px;background:rgba(255,255,255,.06);overflow:hidden;margin-top:12px}
.stat .mini i{display:block;height:100%;border-radius:100px;width:0;transition:width 1.1s cubic-bezier(.22,1,.36,1)}
.fp{background:linear-gradient(90deg,var(--pg),var(--p2))}
.fg{background:linear-gradient(90deg,#16b98a,var(--g))}
.fy{background:linear-gradient(90deg,#e0982f,var(--y))}
.fr{background:linear-gradient(90deg,#e0455c,var(--r))}
/* main grid */
.grid{display:grid;grid-template-columns:1.55fr 1fr;gap:20px;margin-bottom:20px}
.grid2{display:grid;grid-template-columns:1fr 1fr;gap:20px;margin-bottom:20px}
.card{padding:22px 24px}
.card-h{display:flex;align-items:center;justify-content:space-between;margin-bottom:18px;padding-bottom:14px;border-bottom:1px solid var(--stroke)}
.card-h h2{font-size:14.5px;font-weight:700;display:flex;align-items:center;gap:9px}
.card-h .badge{font-size:11px;color:var(--t2);font-weight:500}
/* resource rows */
.res{display:flex;flex-direction:column;gap:18px}
.res-row .top{display:flex;justify-content:space-between;align-items:center;margin-bottom:8px;font-size:12.5px}
.res-row .top .nm{display:flex;align-items:center;gap:8px;color:var(--t2);font-weight:500}
.res-row .top .vv{font-weight:700;direction:ltr;font-variant-numeric:tabular-nums}
.bar{height:8px;border-radius:100px;background:rgba(255,255,255,.05);overflow:hidden}
.bar i{display:block;height:100%;border-radius:100px;width:0;transition:width 1.1s cubic-bezier(.22,1,.36,1)}
/* services */
.svc{display:grid;grid-template-columns:1fr 1fr;gap:10px}
.svc-i{display:flex;align-items:center;gap:10px;padding:13px 14px;border-radius:var(--rad3);background:var(--glass2);border:1px solid var(--stroke);font-size:12.5px;font-weight:600;transition:var(--trans)}
.svc-i .d{width:8px;height:8px;border-radius:50%;flex:0 0 auto}
.svc-i.on .d{background:var(--g);box-shadow:0 0 8px var(--g)}
.svc-i.off .d{background:var(--r);box-shadow:0 0 8px var(--r)}
.svc-i .nm{flex:1;text-transform:capitalize}
.svc-i .st{font-size:10.5px;color:var(--t3);font-weight:600}
.svc-i.on .st{color:var(--g)}
/* info rows */
.info{display:flex;flex-direction:column}
.info-r{display:flex;justify-content:space-between;align-items:center;gap:12px;padding:11px 0;font-size:12.5px;border-bottom:1px solid rgba(255,255,255,.05)}
.info-r:last-child{border-bottom:none}
.info-r .k{color:var(--t2);display:flex;align-items:center;gap:8px}
.info-r .v{font-weight:600;direction:ltr;text-align:right;word-break:break-word;font-variant-numeric:tabular-nums}
.info-r .v.ok{color:var(--g)}
.info-r .v.warn{color:var(--y)}
/* configs */
.cfg{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:12px}
.cfg-i{display:flex;align-items:center;gap:12px;padding:13px 15px;border-radius:var(--rad3);background:var(--glass2);border:1px solid var(--stroke);cursor:pointer;transition:var(--trans)}
.cfg-i:hover{background:rgba(124,92,252,.1);border-color:rgba(124,92,252,.28);transform:translateY(-2px)}
.cfg-i .em{font-size:20px}
.cfg-i .tx{flex:1;min-width:0}
.cfg-i .tx b{display:block;font-size:12.5px;font-weight:600}
.cfg-i .tx span{display:block;font-size:10px;color:var(--p2);direction:ltr;font-family:'Menlo',monospace;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.cfg-i .cp{flex:0 0 auto;width:32px;height:32px;border-radius:9px;display:grid;place-items:center;background:rgba(255,255,255,.05);border:1px solid var(--stroke);color:var(--t2);font-size:13px;transition:var(--trans)}
.cfg-i:hover .cp{background:rgba(124,92,252,.2);color:var(--p2)}
/* subscription */
.sub-box{display:flex;gap:10px;flex-wrap:wrap;align-items:center}
.sub-in{flex:1;min-width:200px;padding:13px 16px;border-radius:var(--rad3);background:rgba(0,0,0,.25);border:1px solid var(--stroke);color:var(--t);font-size:12px;direction:ltr;font-family:'Menlo',monospace;outline:none}
.btn{display:inline-flex;align-items:center;gap:7px;padding:12px 18px;border-radius:var(--rad3);font-size:12.5px;font-weight:700;cursor:pointer;border:1px solid transparent;transition:var(--trans);white-space:nowrap}
.btn.pri{background:linear-gradient(135deg,var(--pg),var(--p));color:#fff;box-shadow:0 6px 20px rgba(108,76,240,.4)}
.btn.pri:hover{transform:translateY(-2px);box-shadow:0 8px 26px rgba(108,76,240,.55)}
.btn.gl{background:var(--glass2);border-color:var(--stroke);color:var(--t2)}
.btn.gl:hover{background:rgba(124,92,252,.14);color:var(--p2);border-color:rgba(124,92,252,.3);transform:translateY(-2px)}
.qa{display:flex;gap:10px;flex-wrap:wrap;margin-top:14px}
/* mini stat trio */
.trio{display:grid;grid-template-columns:repeat(3,1fr);gap:12px}
.trio-i{text-align:center;padding:16px 10px;border-radius:var(--rad3);background:var(--glass2);border:1px solid var(--stroke)}
.trio-i .v{font-size:20px;font-weight:800;direction:ltr;letter-spacing:-.4px}
.trio-i .l{font-size:10.5px;color:var(--t3);margin-top:5px;font-weight:600;text-transform:uppercase;letter-spacing:.6px}
/* footer */
.ft{display:flex;justify-content:center;align-items:center;gap:20px;flex-wrap:wrap;padding:22px;margin-top:26px;font-size:11.5px;color:var(--t3)}
.ft a{color:var(--p2);text-decoration:none;transition:var(--trans);display:inline-flex;align-items:center;gap:6px}
.ft a:hover{color:var(--p)}
.ft .sep{width:4px;height:4px;border-radius:50%;background:var(--t3);opacity:.5}
/* toast */
.toast{position:fixed;bottom:28px;left:50%;transform:translateX(-50%) translateY(90px);z-index:999;padding:13px 24px;border-radius:14px;font-size:12.5px;font-weight:700;color:var(--g);background:rgba(12,12,24,.85);backdrop-filter:blur(16px);border:1px solid rgba(47,224,166,.28);box-shadow:0 10px 40px rgba(0,0,0,.5);opacity:0;transition:all .4s cubic-bezier(.22,1,.36,1);pointer-events:none}
.toast.show{opacity:1;transform:translateX(-50%) translateY(0)}
/* responsive */
@media(max-width:960px){.grid,.grid2{grid-template-columns:1fr}}
@media(max-width:560px){.w{padding:18px 14px 32px}.stats{grid-template-columns:repeat(2,1fr)}.svc{grid-template-columns:1fr}.hd-tt h1{font-size:17px}.card{padding:18px 16px}}
@media(max-width:380px){.stats{grid-template-columns:1fr}}
@media(prefers-reduced-motion:reduce){*{animation:none!important;transition:none!important}}
</style>
</head>
<body>
<div class="bg"><span class="blob a"></span><span class="blob b"></span><span class="blob c"></span><span class="blob d"></span></div>
<div class="grain"></div>
<div class="w">

  <!-- Header -->
  <header class="hd glass">
    <div class="hd-l">
      <div class="logo">👻</div>
      <div class="hd-tt">
        <h1>RealityGhost <b>PRO</b></h1>
        <div class="sub"><span class="flag" id="flag">🌍</span><span id="dm">${DOMAIN}</span></div>
      </div>
    </div>
    <div class="hd-r">
      <div class="pill" id="statusPill"><span class="dot" id="statusDot"></span><span id="statusTxt">Online</span></div>
      <button class="ghost-btn" onclick="ALL()" title="Refresh">↻</button>
    </div>
  </header>

  <!-- Stat cards -->
  <section class="stats" id="statCards"></section>

  <!-- Main grid: resources + services -->
  <section class="grid">
    <div class="card glass">
      <div class="card-h"><h2>🖥️ System Resources</h2><span class="badge" id="uptimeBadge">—</span></div>
      <div class="res" id="resList"></div>
    </div>
    <div class="card glass">
      <div class="card-h"><h2>🔧 Services</h2></div>
      <div class="svc" id="svcList"></div>
      <div class="card-h" style="margin-top:20px"><h2>📡 Server</h2></div>
      <div class="info" id="srvInfo"></div>
    </div>
  </section>

  <!-- Configs -->
  <section class="card glass" style="margin-bottom:20px">
    <div class="card-h"><h2>🔗 Configs</h2><span class="badge">Tap to copy</span></div>
    <div class="cfg" id="cfgList"></div>
  </section>

  <!-- Subscription + traffic/load -->
  <section class="grid2">
    <div class="card glass">
      <div class="card-h"><h2>📥 Subscription</h2></div>
      <div class="sub-box">
        <input class="sub-in" id="subIn" readonly value="">
        <button class="btn pri" onclick="copySub()">📋 Copy Link</button>
      </div>
      <div class="qa">
        <button class="btn gl" onclick="copyAll()">📄 Copy All Configs</button>
        <button class="btn gl" onclick="ALL()">🔄 Refresh</button>
      </div>
    </div>
    <div class="card glass">
      <div class="card-h"><h2>📊 Traffic</h2><span class="badge">since install</span></div>
      <div class="trio" id="trafList"></div>
      <div class="card-h" style="margin-top:18px"><h2>🌐 Load Average</h2></div>
      <div class="trio" id="loadList"></div>
    </div>
  </section>

  <!-- Footer -->
  <footer class="ft glass">
    <span>👻 RealityGhost PRO</span>
    <span class="sep"></span>
    <a href="https://github.com/sheshocked/RealityGhostPro" target="_blank">⭐ GitHub</a>
    <span class="sep"></span>
    <span>Xray VLESS + Reality · <span id="xvFooter">—</span></span>
  </footer>

</div>
<div class="toast" id="toast"></div>

<script>
var D='${DOMAIN}', U='${uuid}', P='${pubkey_line}', SIP='${SERVER_IP}';
var CS=[/*CONFIGS*/];
var S={};

function esc(x){return (''+x).replace(/[&<>"']/g,function(c){return{'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]})}
function lk(c){return 'vless://'+U+'@'+D+':443?encryption=none&flow=xtls-rprx-vision&security=reality&fp=chrome&type=tcp&headerType=none&sni='+c.s+'&pbk='+P+'&sid='+c.i+'#'+encodeURIComponent(c.l)}
function toast(m){var t=document.getElementById('toast');t.textContent=m;t.classList.add('show');clearTimeout(t._t);t._t=setTimeout(function(){t.classList.remove('show')},2000)}
function copy(txt,msg){navigator.clipboard&&navigator.clipboard.writeText(txt);toast(msg)}
function fmtBytes(b){if(b==null)return'—';b=Number(b);if(!b)return'0 B';var u=['B','KB','MB','GB','TB'],i=0;while(b>=1024&&i<u.length-1){b/=1024;i++}return b.toFixed(i<2?0:1)+' '+u[i]}
function num(x){return typeof x==='string'?parseFloat(x)||0:(x||0)}
function barColor(p){return p>=85?'fr':p>=60?'fy':'fp'}

async function fetchStats(){try{var r=await fetch('./stats.json?t='+Date.now());S=r.ok?await r.json():{}}catch(e){S={}}}

function renderStatus(){
  var on=!!S.online || (S.services&&S.services.xray==='active');
  document.getElementById('statusTxt').textContent=on?'Online':'Offline';
  document.getElementById('statusDot').className='dot'+(on?'':' off');
  document.getElementById('statusPill').className='pill'+(on?'':' off');
}
function renderStats(){
  var r=S.ram||{}, c=S.cpu, d=S.disk||{}, on=(S.services&&S.services.xray==='active')||S.online;
  var cpuU=num(c&&c.usage!=null?c.usage:c), cores=(c&&c.cores)?c.cores:(S.cores||'—');
  var ramU=num(r.usage), diskU=num(d.usage);
  var cards=[
    {ic:on?'✅':'⛔',lb:'Status',v:on?'Online':'Offline',bar:null},
    {ic:'🧠',lb:'RAM',v:ramU.toFixed(0)+'<small>%</small>',sub:(r.total?r.total+' MB':''),bar:ramU},
    {ic:'⚙️',lb:'CPU',v:cpuU.toFixed(0)+'<small>%</small>',sub:(cores!=='—'?cores+' cores':''),bar:cpuU},
    {ic:'💾',lb:'Disk',v:diskU.toFixed(0)+'<small>%</small>',sub:((d.used||'')+' / '+(d.total||'')),bar:diskU},
    {ic:'🔗',lb:'Connections',v:(S.connections!=null?S.connections:0),bar:null},
    {ic:'🚀',lb:'Xray',v:'<small>v</small>'+esc(S.xray_version||'—').replace('v',''),bar:null}
  ];
  var h='';
  cards.forEach(function(x){
    h+='<div class="stat glass"><div class="ic">'+x.ic+'</div><div class="lb">'+x.lb+'</div><div class="vl">'+x.v+'</div>';
    if(x.bar!=null){h+='<div class="mini"><i class="'+barColor(x.bar)+'" data-w="'+Math.min(x.bar,100)+'"></i></div>';}
    h+='</div>';
  });
  document.getElementById('statCards').innerHTML=h;
  animateBars();
}
function renderResources(){
  var r=S.ram||{}, c=S.cpu, d=S.disk||{};
  var cpuU=num(c&&c.usage!=null?c.usage:c), ramU=num(r.usage), diskU=num(d.usage);
  var rows=[
    {nm:'💾 Disk',vv:(d.used||'—')+' / '+(d.total||'—'),p:diskU},
    {nm:'🧠 Memory',vv:(r.used!=null?r.used+' / '+(r.total||'?')+' MB':'—'),p:ramU},
    {nm:'⚙️ CPU',vv:cpuU.toFixed(1)+' %'+((c&&c.cores)?' · '+c.cores+' cores':''),p:cpuU}
  ];
  var h='';
  rows.forEach(function(x){
    h+='<div class="res-row"><div class="top"><span class="nm">'+x.nm+'</span><span class="vv">'+esc(x.vv)+'</span></div><div class="bar"><i class="'+barColor(x.p)+'" data-w="'+Math.min(x.p,100)+'"></i></div></div>';
  });
  document.getElementById('resList').innerHTML=h;
  document.getElementById('uptimeBadge').textContent=S.uptime?'⏱ Up '+S.uptime:'—';
  animateBars();
}
function renderServices(){
  var c=S.services||{}, keys=Object.keys(c);
  if(!keys.length)keys=['nginx','xray','monitor'];
  var h='';
  keys.forEach(function(k){
    var on=c[k]==='active';
    h+='<div class="svc-i '+(on?'on':'off')+'"><span class="d"></span><span class="nm">'+esc(k)+'</span><span class="st">'+(on?'Active':'Down')+'</span></div>';
  });
  document.getElementById('svcList').innerHTML=h;
}
function renderServer(){
  var rows=[
    {k:'🌐 IP',v:SIP||'—',cls:''},
    {k:'🚀 Xray',v:'v'+esc((S.xray_version||'—').replace(/^v/,'')),cls:''},
    {k:'⚡ TCP',v:'BBR',cls:''},
    {k:'🔒 SSL',v:S.dns_ok?'Active':'Pending',cls:S.dns_ok?'ok':'warn'},
    {k:'⏱ Uptime',v:S.uptime||'—',cls:''}
  ];
  var h='';
  rows.forEach(function(x){h+='<div class="info-r"><span class="k">'+x.k+'</span><span class="v '+x.cls+'">'+esc(x.v)+'</span></div>';});
  document.getElementById('srvInfo').innerHTML=h;
}
function renderConfigs(){
  var h='';
  CS.forEach(function(c,i){
    h+='<div class="cfg-i" onclick="copyCfg('+i+')"><span class="em">'+(c.e||'🔵')+'</span><span class="tx"><b>'+esc(c.l)+'</b><span>'+esc(c.s)+'</span></span><span class="cp">📋</span></div>';
  });
  document.getElementById('cfgList').innerHTML=h||'<div style="color:var(--t3);font-size:12px">No configs</div>';
}
function renderTraffic(){
  var t=S.traffic||{};
  var items=[{v:fmtBytes(t.today),l:'Today'},{v:fmtBytes(t.month),l:'Month'},{v:fmtBytes(t.total),l:'Total'}];
  document.getElementById('trafList').innerHTML=items.map(function(x){return '<div class="trio-i"><div class="v">'+x.v+'</div><div class="l">'+x.l+'</div></div>';}).join('');
}
function renderLoad(){
  var l=S.load||{};
  var items=[{v:l['1m']!=null?l['1m']:'—',l:'1 min'},{v:l['5m']!=null?l['5m']:'—',l:'5 min'},{v:l['15m']!=null?l['15m']:'—',l:'15 min'}];
  document.getElementById('loadList').innerHTML=items.map(function(x){return '<div class="trio-i"><div class="v">'+x.v+'</div><div class="l">'+x.l+'</div></div>';}).join('');
}
function renderSub(){document.getElementById('subIn').value=S.sub_link||(location.protocol+'//'+D+'/sub');document.getElementById('xvFooter').textContent=S.xray_version?('v'+(''+S.xray_version).replace(/^v/,'')):'—';}

function copyCfg(i){copy(lk(CS[i]),'✓ Copied · '+CS[i].l)}
function copyAll(){var all=CS.map(lk).join('\n');copy(S.sub||all,'✓ Copied all configs')}
function copySub(){copy(document.getElementById('subIn').value,'✓ Subscription link copied')}

function animateBars(){requestAnimationFrame(function(){document.querySelectorAll('[data-w]').forEach(function(el){el.style.width=el.getAttribute('data-w')+'%';});});}

async function ALL(){
  await fetchStats();
  renderStatus();renderStats();renderResources();renderServices();renderServer();renderConfigs();renderTraffic();renderLoad();renderSub();
}
ALL();setInterval(ALL,3000);
</script>
</body>
</html>

PANEOF

  # Safely inject dynamic values (python avoids sed escaping issues with / & ')
  python3 - "$STATUS_DIR/index.html" "$DOMAIN" "$uuid" "$pubkey_line" "$SERVER_IP" "$configs_js" <<'PYEOF'
import sys
f, dom, uid, pbk, sip, cfg = sys.argv[1:7]
s = open(f, encoding="utf-8").read()
s = (s.replace("${DOMAIN}", dom)
      .replace("${uuid}", uid)
      .replace("${pubkey_line}", pbk)
      .replace("${SERVER_IP}", sip)
      .replace("/*CONFIGS*/", cfg))
open(f, "w", encoding="utf-8").write(s)
PYEOF

  chown -R www-data:www-data "$STATUS_DIR" 2>/dev/null
  echo -e "${OK}Panel built (glassmorphism)"
}

install_monitor() {
  echo -e "${INFO}Installing monitor..."
  cat > "$MONITOR_SCRIPT" <<'MONEOF'
#!/bin/bash
S=/var/www/html/status
mkdir -p "$S"
while true; do
  T=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  CPU=$(top -bn1 | grep "Cpu(s)" | awk '{printf "%.1f", $2+$4}')
  L=$(awk '{print $1","$2","$3}' /proc/loadavg)
  L1=$(echo $L | cut -d, -f1); L5=$(echo $L | cut -d, -f2); L15=$(echo $L | cut -d, -f3)
  MT=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)
  MA=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)
  MU=$((MT-MA))
  MP=$(awk -v mt=$MT -v ma=$MA "BEGIN{printf \"%.1f\", (mt-ma)/mt*100}")
  CORES=$(nproc)
  DT=$(df -h / | awk 'NR==2{print $2}')
  DU=$(df -h / | awk 'NR==2{print $3}')
  DA=$(df -h / | awk 'NR==2{print $4}')
  DP=$(df / | awk 'NR==2{print $5+0}')
  UT=$(awk '{print int($1)}' /proc/uptime)
  UP=$(printf "%dd %dh %dm" $((UT/86400)) $((UT%86400/3600)) $((UT%3600/60)))
  NG=$(systemctl is-active nginx)
  XR=$(systemctl is-active xray)
  MON=$(systemctl is-active realityghost-monitor)
  XV=$(/usr/local/bin/xray version 2>/dev/null | head -1 | awk '{print $2}')
  CN=$(ss -tn state established | grep -c ':443 ')
  cat > $S/stats.json << JSONEOF
{"timestamp":"$T","cpu":"$CPU","load":{"1m":$L1,"5m":$L5,"15m":$L15},"ram":{"total":$MT,"used":$MU,"usage":$MP},"cores":$CORES,"disk":{"total":"$DT","used":"$DU","avail":"$DA","usage":$DP},"uptime":"$UP","uptime_secs":$UT,"services":{"nginx":"$NG","xray":"$XR","monitor":"$MON"},"xray_version":"$XV","connections":$CN,"dns_ok":true,"traffic":{"today":0,"month":0,"total":0}}
JSONEOF
  chown www-data:www-data $S/stats.json 2>/dev/null
  sleep 3
done
MONEOF
  chmod +x "$MONITOR_SCRIPT"
  cat > /etc/systemd/system/realityghost-monitor.service <<SERVEOF
[Unit]
Description=RealityGhost Monitor
After=network.target
[Service]
Type=simple
ExecStart=/bin/bash ${MONITOR_SCRIPT}
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
SERVEOF
  systemctl daemon-reload
  systemctl enable realityghost-monitor 2>/dev/null
  systemctl restart realityghost-monitor 2>/dev/null
  echo -e "${OK}Monitor installed"
}

show_info() {
  clear
  local uuid=$(jq -r '.inbounds[0].settings.clients[0].id' "$CONFIG_DIR/config.json" 2>/dev/null)
  local pbk=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$CONFIG_DIR/config.json" 2>/dev/null)
  echo -e "${CYAN}══════════════════════════════════════${NC}"
  echo -e "${CYAN}   ${FLAG_RAW} ${LOC} • ${DOMAIN}${NC}"
  echo -e "${CYAN}══════════════════════════════════════${NC}"
  echo ""
  echo -e "${INFO}UUID: ${uuid}${NC}"
  echo -e "${INFO}Public Key: $(/usr/local/bin/xray x25519 -i "$pbk" 2>/dev/null | grep -oE "(PublicKey|Password \(PublicKey\)): ?\S+" | head -1 | grep -oE "\S+$")${NC}"
  echo ""
  local idx=0
  for entry in "${SNI_LIST[@]}"; do
    IFS=':' read -r sni label label_url <<< "$entry"
    local sid=$(jq -r ".inbounds[0].streamSettings.realitySettings.shortIds[$idx]" "$CONFIG_DIR/config.json" 2>/dev/null)
    echo -e "  ${FLAG_RAW} ${label} → ${sni} sid: ${sid:0:16}.."
    idx=$((idx+1))
  done
  echo ""
  echo -e "${CYAN}📊 Panel:${NC} https://${DOMAIN}/status/"
  echo -e "${CYAN}📥 Subscription:${NC} https://${DOMAIN}/sub"
  echo ""
}

# ─── Menus ───────────────────────────────────────────────────────────

port_manager() {
  while true; do
    clear
    echo -e "${CYAN}══════════════════════════${NC}"
    echo -e "${CYAN}   🔌 Port Manager${NC}"
    echo -e "${CYAN}══════════════════════════${NC}"
    echo "1. Show open ports (iptables)"
    echo "2. Open port"
    echo "3. Close port"
    echo "4. Show listening ports"
    echo "0. Back"
    echo -ne "${BOLD}Choice: ${NC}"
    read -r opt
    case $opt in
      1) iptables -L INPUT -n --line-numbers 2>/dev/null | grep ACCEPT | grep -E "tcp|udp"
         echo -ne "\n${YELLOW}Enter...${NC}"; read -r ;;
      2) echo -ne "Port: "; read -r port
         [[ -z "$port" ]] && continue
         iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
         echo -e "${OK}Port $port opened"
         netfilter-persistent save 2>/dev/null
         echo -ne "\n${YELLOW}Enter...${NC}"; read -r ;;
      3) echo -ne "Port: "; read -r port
         [[ -z "$port" ]] && continue
         iptables -D INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null && echo -e "${OK}Port $port closed"
         netfilter-persistent save 2>/dev/null
         echo -ne "\n${YELLOW}Enter...${NC}"; read -r ;;
      4) ss -tlnp | grep -E ':(443|80|8443|8444) '
         echo -ne "\n${YELLOW}Enter...${NC}"; read -r ;;
      0) return ;;
    esac
  done
}

config_manager() {
  while true; do
    clear
    echo -e "${CYAN}══════════════════════════${NC}"
    echo -e "${CYAN}   ⚙️ Config Manager${NC}"
    echo -e "${CYAN}══════════════════════════${NC}"
    echo "1. Show current configs"
    echo "2. Rebuild subscription"
    echo "3. Rotate Short IDs"
    echo "4. Show UUID & Public Key"
    echo "5. QR for first config"
    echo "0. Back"
    echo -ne "${BOLD}Choice: ${NC}"
    read -r opt
    case $opt in
      1) show_info; echo -ne "\n${YELLOW}Enter...${NC}"; read -r ;;
      2) build_subscription; echo -ne "\n${YELLOW}Enter...${NC}"; read -r ;;
      3) for i in $(seq 0 5); do
           local ns=$(openssl rand -hex 8)
           jq --argjson idx "$i" --arg sid "$ns" '.inbounds[0].streamSettings.realitySettings.shortIds[$idx] = $sid' "$CONFIG_DIR/config.json" > "$CONFIG_DIR/config.json.tmp"
           mv "$CONFIG_DIR/config.json.tmp" "$CONFIG_DIR/config.json"
         done
         systemctl restart xray
         build_subscription; build_panel
         echo -e "${OK}Short IDs rotated${NC}"
         echo -ne "\n${YELLOW}Enter...${NC}"; read -r ;;
      4) local u4=$(jq -r '.inbounds[0].settings.clients[0].id' "$CONFIG_DIR/config.json")
         local pk4=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$CONFIG_DIR/config.json")
         local pub4=$(/usr/local/bin/xray x25519 -i "$pk4" 2>/dev/null | grep -oE "(PublicKey|Password \(PublicKey\)): ?\S+" | head -1 | grep -oE "\S+$")
         echo -e "UUID: ${u4}"; echo -e "Public Key: ${pub4}"
         echo -ne "\n${YELLOW}Enter...${NC}"; read -r ;;
      5) local u=$(jq -r '.inbounds[0].settings.clients[0].id' "$CONFIG_DIR/config.json")
         local pk5=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$CONFIG_DIR/config.json")
         local pub5=$(/usr/local/bin/xray x25519 -i "$pk5" 2>/dev/null | grep -oE "(PublicKey|Password \(PublicKey\)): ?\S+" | head -1 | grep -oE "\S+$")
         local sid5=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$CONFIG_DIR/config.json")
         local l="vless://${u}@${DOMAIN}:443?flow=xtls-rprx-vision&encryption=none&security=reality&sni=www.gstatic.com&fp=chrome&pbk=${pub5}&sid=${sid5}&spx=%2F&type=tcp&headerType=none#RG-PRO"
         echo "$l" | qrencode -t ANSIUTF8
         echo -ne "\n${YELLOW}Enter...${NC}"; read -r ;;
      0) return ;;
    esac
  done
}

setup_rotation() {
  cat > /etc/cron.d/realityghost-rotate <<CRONEOF
0 5 */3 * * root bash ${CONFIG_DIR}/RealityGhostPro.sh manual-rotate
CRONEOF
  chmod +x /etc/cron.d/realityghost-rotate
  echo -e "${OK}Rotation set for every 3 days"
}

manual_rotate() {
  for i in $(seq 0 5); do
    local new_sid=$(openssl rand -hex 8)
    jq --argjson idx "$i" --arg sid "$new_sid" '.inbounds[0].streamSettings.realitySettings.shortIds[$idx] = $sid' "$CONFIG_DIR/config.json" > "$CONFIG_DIR/config.json.tmp"
    mv "$CONFIG_DIR/config.json.tmp" "$CONFIG_DIR/config.json"
  done
  systemctl restart xray
  build_subscription
  build_panel
  echo -e "${OK}Short Ids rotated"
}

pull_update() {
  echo -e "${INFO}Checking for updates..."
  local repo_url="https://github.com/sheshocked/RealityGhostPro.git"
  local script_dir="$(cd "$(dirname "$0")" && pwd)"
  local backup_dir="/tmp/realityghost-backup-$(date +%s)"
  if ! command -v git &>/dev/null; then apt-get install -y git 2>/dev/null || {
    echo -e "${ERR}git not installed${NC}"; return 1; }; fi
  cd "$script_dir" || return 1
  if [[ ! -d .git ]]; then
    echo -e "${WARN}.git folder not found. Cloning..."
    cd /tmp || return 1; rm -rf RealityGhostPro-tmp
    git clone "$repo_url" RealityGhostPro-tmp 2>&1 || { echo -e "${ERR}Clone failed${NC}"; return 1; }
    cp -r "$script_dir" "$backup_dir" 2>/dev/null
    cp -rf /tmp/RealityGhostPro-tmp/* "$script_dir/"; rm -rf /tmp/RealityGhostPro-tmp
    chmod +x "$script_dir/RealityGhostPro.sh"
    echo -e "${OK}Updated! Backup: ${backup_dir}${NC}"
    return 0
  fi
  cp -r "$script_dir" "$backup_dir" 2>/dev/null
  git stash 2>/dev/null
  local old_hash=$(git rev-parse HEAD)
  git pull origin main 2>&1 || { echo -e "${ERR}Pull failed${NC}"; return 1; }
  local new_hash=$(git rev-parse HEAD)
  local changes=$(git rev-list --count "$old_hash..$new_hash" 2>/dev/null)
  echo -e "${OK}Updated (${changes:-?} changes)"
  echo -e "${INFO}${old_hash:0:8} → ${new_hash:0:8}${NC}"
  chmod +x "$script_dir/RealityGhostPro.sh"
}

bot_setup() {
  echo -e "${INFO}Installing Telegram bot..."
  [[ -f /usr/local/bin/rg-bot.py ]] || install_bot_script
  chmod +x /usr/local/bin/rg-bot.py
  /usr/local/bin/rg-bot.py init
  echo -ne "${BOLD}Bot token (from BotFather): ${NC}"
  read -r bot_token
  [[ -z "$bot_token" ]] && { echo -e "${WARN}No token, bot disabled${NC}"; return; }
  mkdir -p /etc/realityghost
  echo "{\"enabled\":true,\"token\":\"$bot_token\",\"domain\":\"$DOMAIN\",\"admin_ids\":[]}" > /etc/realityghost/bot_config.json
  cat > /etc/systemd/system/realityghost-bot.service <<BOTEOF
[Unit]
Description=RealityGhost Bot
After=network.target xray.service
[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/rg-bot.py runbot
Restart=always
RestartSec=5
User=root
[Install]
WantedBy=multi-user.target
BOTEOF
  systemctl daemon-reload
  systemctl enable realityghost-bot 2>/dev/null
  systemctl restart realityghost-bot 2>/dev/null
  sleep 2
  systemctl is-active realityghost-bot &>/dev/null && echo -e "${OK}🤖 Bot activated!" || echo -e "${WARN}Bot failed to start. journalctl -u realityghost-bot${NC}"
}

bot_menu() {
  while true; do
    clear
    echo -e "${CYAN}══════════════════════════${NC}"
    echo -e "${CYAN}   🤖 Bot Manager${NC}"
    echo -e "${CYAN}══════════════════════════${NC}"
    local s="Disabled ❌"
    systemctl is-active realityghost-bot &>/dev/null && s="Active ✅"
    echo -e "Status: $s"
    [[ -f /etc/realityghost/bot_config.json ]] && jq -r '.token // ""' /etc/realityghost/bot_config.json | grep -q . && echo -e "Token: ${s}"
    echo "1. Restart Bot"
    echo "2. Set New Token"
    echo "3. List Users"
    echo "4. Add User"
    echo "5. Delete User"
    echo "6. Stats"
    echo "7. Setup / Enable Bot (set token)"
    echo "0. Back"
    echo -ne "${BOLD}Choice: ${NC}"; read -r opt
    case $opt in
      1) systemctl restart realityghost-bot; echo -e "${OK}Bot restarted${NC}"; sleep 2 ;;
      2) echo -ne "Token: "; read -r tk
         [[ -n "$tk" ]] && jq --arg t "$tk" '.token = $t | .enabled = true' /etc/realityghost/bot_config.json > /tmp/botcfg.json && mv /tmp/botcfg.json /etc/realityghost/bot_config.json
         systemctl restart realityghost-bot; sleep 2 ;;
      3) /usr/local/bin/rg-bot.py list 2>&1; echo -ne "\n${YELLOW}Enter...${NC}"; read -r ;;
      4) echo -ne "Name: "; read -r n; echo -ne "Traffic MB (0=∞): "; read -r l; echo -ne "Days (0=∞): "; read -r d
         /usr/local/bin/rg-bot.py adduser "$n" "${l:-0}" "${d:-0}"; echo -ne "\n${YELLOW}Enter...${NC}"; read -r ;;
      5) echo -ne "User ID: "; read -r id
        /usr/local/bin/rg-bot.py deluser "$id" 2>&1 || echo "❌"
        echo -ne "\n${YELLOW}Enter...${NC}"; read -r ;;
      6) /usr/local/bin/rg-bot.py stats 2>&1; echo -ne "\n${YELLOW}Enter...${NC}"; read -r ;;
      7) bot_setup; echo -ne "\n${YELLOW}Enter...${NC}"; read -r ;;
      0) return ;;
    esac
  done
}

uninstall() {
  echo -e "${WARN}⚠ Full uninstall of RealityGhost PRO${NC}"
  echo -ne "Are you sure? Type 'yes': "
  read -r ans
  [[ "$ans" != "yes" ]] && { echo -e "${INFO}Cancelled${NC}"; return; }
  systemctl stop xray nginx realityghost-monitor realityghost-bot 2>/dev/null
  systemctl disable xray realityghost-monitor realityghost-bot 2>/dev/null
  rm -rf "$INSTALL_DIR" "$CONFIG_DIR" "$STATUS_DIR" "$STATE_DIR" "$SUB_DIR"
  rm -f /etc/systemd/system/xray.service /etc/systemd/system/realityghost-monitor.service /etc/systemd/system/realityghost-bot.service
  rm -f "$MONITOR_SCRIPT" /etc/cron.d/realityghost-rotate /etc/nginx/nginx.conf
  cp /etc/nginx/nginx.conf.backup /etc/nginx/nginx.conf 2>/dev/null
  rm -f /etc/sysctl.d/99-realityghost.conf /etc/realityghost/bot_config.json /etc/realityghost/users.db
  systemctl daemon-reload
  systemctl restart nginx 2>/dev/null
  echo -e "${OK}Uninstall complete"
}

renew_ssl() {
  echo -e "${INFO}Renewing SSL certificate..."
  if [[ -z "$DOMAIN" ]]; then
    echo -ne "${BOLD}Domain: ${NC}"; read -r DOMAIN
  fi
  systemctl stop nginx 2>/dev/null
  certbot certonly --standalone --non-interactive --agree-tos -d "${DOMAIN}" -m "${EMAIL:-admin@${DOMAIN}}" 2>/dev/null
  systemctl start nginx 2>/dev/null
  if [[ -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]]; then
    echo -e "${OK}SSL renewed for ${DOMAIN}"
  else
    echo -e "${ERR}SSL renewal failed. Check DNS: ${DOMAIN} must point to this server.${NC}"
  fi
}

# ─── Main ────────────────────────────────────────────────────────────

optimize_dns() {
  echo -e "${INFO}Optimizing DNS resolvers..."
  if grep -q "nameserver 1.1.1.1" /etc/resolv.conf 2>/dev/null; then
    echo -e "${OK}DNS already optimized"
    return 0
  fi
  cat > /etc/resolv.conf <<'RESOLVEOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 9.9.9.9
options edns0
RESOLVEOF
  echo -e "${OK}DNS optimized (1.1.1.1 / 8.8.8.8 / 9.9.9.9)"
}

install_bot_script() {
  echo -e "${INFO}Installing Telegram bot manager..."
  mkdir -p /etc/realityghost
  cat > /usr/local/bin/rg-bot.py <<'RGBOTEOF'
#!/usr/bin/env python3
# RealityGhost PRO - Telegram management bot
# Self-contained: uses only the Python standard library + requests.
# CLI: init | adduser <name> [mb] [days] | deluser <id> | list | stats | enforce | runbot
import os
import sys
import json
import time
import uuid as uuidlib
import sqlite3
import subprocess
import urllib.parse
import datetime

CONFIG_DIR = "/usr/local/etc/xray"
XRAY_CONFIG = os.path.join(CONFIG_DIR, "config.json")
BOT_DIR = "/etc/realityghost"
BOT_CONFIG = os.path.join(BOT_DIR, "bot_config.json")
USERS_DB = os.path.join(BOT_DIR, "users.db")
XRAY_BIN = "/usr/local/bin/xray"

SNI_LIST = [
    ("www.gstatic.com", "Google Static"),
    ("ajax.googleapis.com", "Google AJAX"),
    ("storage.googleapis.com", "Google Storage"),
    ("fonts.gstatic.com", "Google Fonts"),
    ("fonts.googleapis.com", "Google Fonts API"),
    ("www.google.com", "Google"),
]

HELP = (
    "RealityGhost PRO bot\n"
    "/status - server status\n"
    "/list - list users\n"
    "/add <name> [days] [mb] - add a user\n"
    "/del <id> - remove a user\n"
    "/info <id> - show a user's configs\n"
)

API = "https://api.telegram.org/bot{token}/{method}"


def log(msg):
    print("[rg-bot] {}".format(msg), flush=True)


def load_bot_config():
    try:
        with open(BOT_CONFIG) as f:
            return json.load(f)
    except Exception:
        return {"enabled": False, "token": "", "domain": "", "admin_ids": []}


def save_bot_config(cfg):
    os.makedirs(BOT_DIR, exist_ok=True)
    with open(BOT_CONFIG, "w") as f:
        json.dump(cfg, f, indent=2)


def db():
    os.makedirs(BOT_DIR, exist_ok=True)
    conn = sqlite3.connect(USERS_DB)
    conn.execute(
        "CREATE TABLE IF NOT EXISTS users("
        "id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "name TEXT NOT NULL,"
        "uuid TEXT NOT NULL UNIQUE,"
        "created TEXT NOT NULL,"
        "days INTEGER DEFAULT 0,"
        "limit_mb INTEGER DEFAULT 0)"
    )
    conn.commit()
    return conn


def load_xray():
    with open(XRAY_CONFIG) as f:
        return json.load(f)


def save_xray(cfg):
    tmp = XRAY_CONFIG + ".tmp"
    with open(tmp, "w") as f:
        json.dump(cfg, f, indent=2)
    os.replace(tmp, XRAY_CONFIG)
    try:
        os.chmod(XRAY_CONFIG, 0o600)
    except Exception:
        pass


def restart_xray():
    subprocess.run(["systemctl", "restart", "xray"], check=False)


def get_domain():
    cfg = load_bot_config()
    if cfg.get("domain"):
        return cfg["domain"]
    try:
        xc = load_xray()
        email = xc["inbounds"][0]["settings"]["clients"][0].get("email", "")
        return email.split("@", 1)[1] if "@" in email else ""
    except Exception:
        return ""


def get_public_key():
    try:
        xc = load_xray()
        priv = xc["inbounds"][0]["streamSettings"]["realitySettings"]["privateKey"]
        out = subprocess.run(
            [XRAY_BIN, "x25519", "-i", priv],
            capture_output=True, text=True,
        ).stdout
        for line in out.splitlines():
            for tag in ("Password:", "PublicKey:", "Public key:"):
                if tag in line:
                    return line.split(tag, 1)[1].strip()
    except Exception as exc:
        log("pubkey error: {}".format(exc))
    return ""


def user_links(user_uuid):
    xc = load_xray()
    rs = xc["inbounds"][0]["streamSettings"]["realitySettings"]
    sids = rs.get("shortIds", ["0000000000000000"]) or ["0000000000000000"]
    pbk = get_public_key()
    domain = get_domain()
    links = []
    for i, (sni, label) in enumerate(SNI_LIST):
        sid = sids[i] if i < len(sids) else sids[0]
        tag = urllib.parse.quote("RG {}".format(label))
        links.append(
            "vless://{uuid}@{domain}:443?flow=xtls-rprx-vision&encryption=none"
            "&security=reality&sni={sni}&fp=chrome&pbk={pbk}&sid={sid}"
            "&spx=%2F&type=tcp&headerType=none#{tag}".format(
                uuid=user_uuid, domain=domain, sni=sni, pbk=pbk, sid=sid, tag=tag
            )
        )
    return links


def cmd_init():
    os.makedirs(BOT_DIR, exist_ok=True)
    db().close()
    if not os.path.exists(BOT_CONFIG):
        save_bot_config({"enabled": False, "token": "", "domain": get_domain(), "admin_ids": []})
    log("initialized")


def add_user(name, limit_mb=0, days=0):
    name = (name or "user").strip() or "user"
    new_uuid = str(uuidlib.uuid4())
    xc = load_xray()
    clients = xc["inbounds"][0]["settings"]["clients"]
    domain = get_domain()
    clients.append({
        "id": new_uuid,
        "flow": "xtls-rprx-vision",
        "level": 0,
        "email": "{}-{}@{}".format(name, new_uuid[:8], domain or "local"),
    })
    save_xray(xc)
    restart_xray()
    conn = db()
    conn.execute(
        "INSERT INTO users(name,uuid,created,days,limit_mb) VALUES(?,?,?,?,?)",
        (name, new_uuid, datetime.datetime.utcnow().isoformat(), int(days or 0), int(limit_mb or 0)),
    )
    conn.commit()
    uid = conn.execute("SELECT id FROM users WHERE uuid=?", (new_uuid,)).fetchone()[0]
    conn.close()
    return uid, new_uuid


def del_user(ident):
    conn = db()
    row = conn.execute(
        "SELECT id,uuid FROM users WHERE id=? OR uuid=?", (ident, ident)
    ).fetchone()
    if not row:
        conn.close()
        return False
    uid, user_uuid = row
    conn.execute("DELETE FROM users WHERE id=?", (uid,))
    conn.commit()
    conn.close()
    xc = load_xray()
    clients = xc["inbounds"][0]["settings"]["clients"]
    xc["inbounds"][0]["settings"]["clients"] = [c for c in clients if c.get("id") != user_uuid]
    save_xray(xc)
    restart_xray()
    return True


def list_users():
    conn = db()
    rows = conn.execute(
        "SELECT id,name,uuid,created,days,limit_mb FROM users ORDER BY id"
    ).fetchall()
    conn.close()
    return rows


def is_expired(row):
    created, days = row[3], row[4]
    if not days:
        return False
    try:
        start = datetime.datetime.fromisoformat(created)
    except Exception:
        return False
    return datetime.datetime.utcnow() > start + datetime.timedelta(days=int(days))


def cmd_enforce():
    removed = 0
    for row in list_users():
        if is_expired(row):
            if del_user(row[0]):
                removed += 1
    log("enforce removed {} expired user(s)".format(removed))


def server_status():
    def sc(cmd):
        try:
            return subprocess.run(cmd, capture_output=True, text=True).stdout.strip()
        except Exception:
            return "?"
    nginx = sc(["systemctl", "is-active", "nginx"])
    xray = sc(["systemctl", "is-active", "xray"])
    users = len(list_users())
    return "Domain: {}\nnginx: {}\nxray: {}\nusers: {}".format(
        get_domain(), nginx, xray, users
    )


def tg(token, method, **params):
    import requests
    try:
        resp = requests.post(API.format(token=token, method=method), json=params, timeout=65)
        return resp.json()
    except Exception as exc:
        log("tg error: {}".format(exc))
        return {}


def handle(cfg, token, msg):
    chat = msg["chat"]["id"]
    frm = msg.get("from", {}).get("id")
    text = (msg.get("text") or "").strip()
    if not text:
        return
    # The first person to message the bot becomes the admin.
    if not cfg.get("admin_ids"):
        cfg["admin_ids"] = [frm]
        save_bot_config(cfg)
        tg(token, "sendMessage", chat_id=chat, text="You are now the bot admin.")
    if frm not in cfg.get("admin_ids", []):
        tg(token, "sendMessage", chat_id=chat, text="Not authorized.")
        return
    parts = text.split()
    cmd = parts[0].lower().lstrip("/").split("@")[0]
    args = parts[1:]
    if cmd in ("start", "help"):
        tg(token, "sendMessage", chat_id=chat, text=HELP)
    elif cmd == "status":
        tg(token, "sendMessage", chat_id=chat, text=server_status())
    elif cmd == "list":
        rows = list_users()
        if not rows:
            tg(token, "sendMessage", chat_id=chat, text="No users yet. /add <name> [days] [mb]")
        else:
            lines = [
                "#{} {} - {} (days: {})".format(r[0], r[1], r[2][:8], r[4] or "unlimited")
                for r in rows
            ]
            tg(token, "sendMessage", chat_id=chat, text="\n".join(lines))
    elif cmd == "add":
        if not args:
            tg(token, "sendMessage", chat_id=chat, text="Usage: /add <name> [days] [mb]")
            return
        name = args[0]
        days = int(args[1]) if len(args) > 1 and args[1].isdigit() else 0
        mb = int(args[2]) if len(args) > 2 and args[2].isdigit() else 0
        uid, user_uuid = add_user(name, mb, days)
        links = "\n".join(user_links(user_uuid))
        tg(token, "sendMessage", chat_id=chat,
           text="Added #{} {}\nUUID: {}\n\n{}".format(uid, name, user_uuid, links))
    elif cmd in ("del", "delete", "rm"):
        if not args:
            tg(token, "sendMessage", chat_id=chat, text="Usage: /del <id>")
            return
        ok = del_user(args[0])
        tg(token, "sendMessage", chat_id=chat, text="Deleted." if ok else "Not found.")
    elif cmd in ("info", "sub"):
        if not args:
            tg(token, "sendMessage", chat_id=chat, text="Usage: /info <id>")
            return
        conn = db()
        row = conn.execute(
            "SELECT id,name,uuid FROM users WHERE id=? OR uuid=?", (args[0], args[0])
        ).fetchone()
        conn.close()
        if not row:
            tg(token, "sendMessage", chat_id=chat, text="Not found.")
            return
        links = "\n".join(user_links(row[2]))
        tg(token, "sendMessage", chat_id=chat,
           text="#{} {}\nUUID: {}\n\n{}".format(row[0], row[1], row[2], links))
    else:
        tg(token, "sendMessage", chat_id=chat, text="Unknown command. /help")


def run_bot():
    import requests
    cfg = load_bot_config()
    token = cfg.get("token", "")
    if not token:
        log("no token configured")
        sys.exit(1)
    log("bot polling started")
    offset = None
    while True:
        try:
            params = {"timeout": 60}
            if offset is not None:
                params["offset"] = offset
            resp = requests.get(
                API.format(token=token, method="getUpdates"), params=params, timeout=65
            )
            data = resp.json()
            for upd in data.get("result", []):
                offset = upd["update_id"] + 1
                cfg = load_bot_config()
                msg = upd.get("message") or upd.get("edited_message")
                if msg:
                    handle(cfg, token, msg)
        except Exception as exc:
            log("loop error: {}".format(exc))
            time.sleep(5)


def main():
    if len(sys.argv) < 2:
        print("usage: rg-bot.py {init|adduser|deluser|list|stats|enforce|runbot}")
        return
    cmd = sys.argv[1]
    if cmd == "init":
        cmd_init()
    elif cmd == "adduser":
        name = sys.argv[2] if len(sys.argv) > 2 else "user"
        mb = sys.argv[3] if len(sys.argv) > 3 else "0"
        days = sys.argv[4] if len(sys.argv) > 4 else "0"
        uid, user_uuid = add_user(name, mb, days)
        print("Added user #{} ({}) uuid={}".format(uid, name, user_uuid))
        for link in user_links(user_uuid):
            print(link)
    elif cmd == "deluser":
        if len(sys.argv) < 3:
            print("need id")
            return
        print("deleted" if del_user(sys.argv[2]) else "not found")
    elif cmd == "list":
        for r in list_users():
            print("#{} {} {} days={} mb={}".format(r[0], r[1], r[2], r[4] or 0, r[5] or 0))
    elif cmd == "stats":
        print(server_status())
    elif cmd == "enforce":
        cmd_enforce()
    elif cmd == "runbot":
        run_bot()
    else:
        print("unknown: {}".format(cmd))


if __name__ == "__main__":
    main()
RGBOTEOF
  chmod +x /usr/local/bin/rg-bot.py
  /usr/local/bin/rg-bot.py init 2>/dev/null || true
  echo "0 * * * * root /usr/local/bin/rg-bot.py enforce >/dev/null 2>&1" > /etc/cron.d/realityghost-bot-enforce
  echo -e "${OK}Bot manager installed (configure it via: manage -> Bot)"
}


main_install() {
  echo ""
  echo -e "${PURPLE}   _____   _____   _____  _____   ____  ${NC}"
  echo -e "${PURPLE}  |  __ \ / ____| |  __ \|  __ \ / __ \ ${NC}"
  echo -e "${PURPLE}  | |__) | |  __  | |__) | |__) | |  | |${NC}"
  echo -e "${PURPLE}  |  _  /| | |_ | |  ___/|  _  /| |  | |${NC}"
  echo -e "${PURPLE}  | | \ \| |__| | | |    | | \ \| |__| |${NC}"
  echo -e "${PURPLE}  |_|  \_\\_____| |_|    |_|  \_\\____/ ${NC}"
  echo -e "${PURPLE}                                       ${NC}"
  echo -e "${PURPLE}                                       ${NC}"
  echo -e "${PURPLE}  ─────────────────────────────────────────────${NC}"
  echo -e "${PURPLE}  RG PRO — Xray VLESS+Reality Installer${NC}"
  echo -e "${PURPLE}  ─────────────────────────────────────────────${NC}"
  check_root
  detect_location
  echo -e "${INFO}${FLAG_RAW} ${LOC}${NC}"
  if [[ -z "$DOMAIN" ]]; then
    if [[ -n "${2:-}" ]]; then DOMAIN="$2"
    else echo -ne "${BOLD}Domain (your-domain.com): ${NC}"; read -r DOMAIN; fi
  fi
  if [[ -z "$EMAIL" ]]; then
    if [[ -n "${3:-}" ]]; then EMAIL="$3"
    else echo -ne "${BOLD}Email (for SSL): ${NC}"; read -r EMAIL; fi
  fi
  preflight_check
  install_dependencies
  system_tuning
  install_xray
  install_certbot
  configure_nginx
  configure_xray
  build_subscription
  build_panel
  install_monitor
  install_bot_script
  setup_rotation
  for p in 443 80 8443; do
    iptables -C INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null || iptables -A INPUT -p tcp --dport "$p" -j ACCEPT
  done
  netfilter-persistent save 2>/dev/null
  # v6.0: Optimize DNS
  optimize_dns
  # v6.0: Apply high-scale kernel params
  sysctl -w net.core.somaxconn=131072 2>/dev/null
  sysctl -w net.ipv4.tcp_max_syn_backlog=262144 2>/dev/null
  sysctl -w net.ipv4.tcp_max_tw_buckets=4000000 2>/dev/null
  # Restart
  systemctl restart nginx xray realityghost-monitor
  echo -e "${GREEN}╔═══════════════════════════════╗${NC}"
  echo -e "${GREEN}║   Installation Complete! 🎉    ║${NC}"
  echo -e "${GREEN}╚═══════════════════════════════╝${NC}"
  echo -e "  📊 Panel:  https://${DOMAIN}/status/"
  echo -e "  📥 Sub:    https://${DOMAIN}/sub"
  show_info
}

manage_menu() {
  while true; do
    clear
    echo -e "${PURPLE}   _____   _____   _____  _____   ____  ${NC}"
    echo -e "${PURPLE}  |  __ \ / ____| |  __ \|  __ \ / __ \ ${NC}"
    echo -e "${PURPLE}  | |__) | |  __  | |__) | |__) | |  | |${NC}"
    echo -e "${PURPLE}  |  _  /| | |_ | |  ___/|  _  /| |  | |${NC}"
    echo -e "${PURPLE}  | | \ \| |__| | | |    | | \ \| |__| |${NC}"
    echo -e "${PURPLE}  |_|  \_\\_____| |_|    |_|  \_\\____/ ${NC}"
    echo -e "${PURPLE}                                       ${NC}"
    echo -e "${PURPLE}                                       ${NC}"
    echo -e "${PURPLE}  ─────────────────────────────────────────────${NC}"
    echo -e "${PURPLE}  ${FLAG_RAW} ${LOC} • ${DOMAIN}${NC}"
    echo -e "${PURPLE}  ─────────────────────────────────────────────${NC}"
    [[ -f "$CONFIG_DIR/config.json" ]] && DOMAIN=$(jq -r '.inbounds[0].settings.clients[0].email' "$CONFIG_DIR/config.json" 2>/dev/null | sed 's/user@//')
    [[ -z "$DOMAIN" || "$DOMAIN" == "null" ]] && DOMAIN="your-domain.com"
    echo "1. 📋 Connection Info"
    echo "2. ⚙️ Config Manager"
    echo "3. 🔌 Port Manager"
    echo "4. 🔄 Rotate Short IDs"
    echo "5. 🏗️ Rebuild Sub & Panel"
    echo "6. 🔄 Restart Services"
    echo "7. 🤖 Bot"
    echo "8. 🔄 Update"
    echo "9. 💾 Backup"
    echo "10. 🏥 Health"
    echo "11. ⚡ Speed Test"
    echo "12. 🔧 Auto Heal"
    echo "13. 🗑️ Uninstall"
    echo "0. Exit"
    echo -ne "${BOLD}Choice: ${NC}"; read -r opt
    case $opt in
      1) show_info; echo -ne "\n${YELLOW}Enter...${NC}"; read -r ;;
      2) config_manager ;;
      3) port_manager ;;
      4) manual_rotate; echo -ne "\n${YELLOW}Enter...${NC}"; read -r ;;
      5) build_subscription; build_panel; echo -e "${OK}Rebuilt${NC}"; echo -ne "\n${YELLOW}Enter...${NC}"; read -r ;;
      6) systemctl restart nginx xray realityghost-monitor; echo -e "${OK}Restarted${NC}"; echo -ne "\n${YELLOW}Enter...${NC}"; read -r ;;
      7) bot_menu ;;
      8) pull_update; echo -ne "\n${YELLOW}Enter...${NC}"; read -r ;;
      9) auto_backup; echo -ne "\n${YELLOW}Enter...${NC}"; read -r ;;
      10) health_check; echo -ne "\n${YELLOW}Enter...${NC}"; read -r ;;
      11) speed_test; echo -ne "\n${YELLOW}Enter...${NC}"; read -r ;;
      12) auto_heal; echo -ne "\n${YELLOW}Enter...${NC}"; read -r ;;
      13) uninstall; break ;;
      0) exit 0 ;;
      *) echo -e "${WARN}Invalid${NC}"; sleep 1 ;;
    esac
  done
}

# Quick entry: if script is named 'p' or arg is 'p'/'manage', go to manage menu
if [[ "${0##*/}" == "p" || "${1:-}" == "p" ]]; then
  manage_menu
  exit 0
fi

# ██████╗ ██████╗ ███████╗███╗   ███╗██╗██╗   ██╗███╗   ███╗
# ██╔══██╗██╔══██╗██╔════╝████╗ ████║██║██║   ██║████╗ ████║
# ██████╔╝██████╔╝█████╗  ██╔████╔██║██║██║   ██║██╔████╔██║
# ██╔═══╝ ██╔══██╗██╔══╝  ██║╚██╔╝██║██║██║   ██║██║╚██╔╝██║
# ██║     ██║  ██║███████╗██║ ╚═╝ ██║██║╚██████╔╝██║ ╚═╝ ██║
# ╚═╝     ╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝╚═╝ ╚═════╝ ╚═╝     ╚═╝
# Premium features

auto_backup() {
  local bak_dir="/var/backups/realityghost"
  mkdir -p "$bak_dir"
  local ts=$(date +%Y%m%d_%H%M%S)
  cp "$CONFIG_DIR/config.json" "$bak_dir/config_$ts.json" 2>/dev/null
  cp /etc/nginx/nginx.conf "$bak_dir/nginx_$ts.conf" 2>/dev/null
  # Keep only last 10 backups
  ls -t "$bak_dir"/*.json 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null
  echo -e "${OK}Backup saved: $bak_dir/config_$ts.json${NC}"
}

health_check() {
  echo -e "${INFO}Health check...${NC}"
  local issues=0
  for svc in nginx xray realityghost-monitor; do
    if systemctl is-active --quiet "$svc"; then
      echo -e "  ${GREEN}✓${NC} $svc"
    else
      echo -e "  ${RED}✗${NC} $svc"
      issues=$((issues+1))
    fi
  done
  # Check panel
  if curl -sk --max-time 3 "https://127.0.0.1:8444/status/" > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} Panel (8444)"
  else
    echo -e "  ${RED}✗${NC} Panel (8444)"
    issues=$((issues+1))
  fi
  # Check 443
  if timeout 3 openssl s_client -connect 127.0.0.1:443 -servername www.gstatic.com -quiet 2>&1 | grep -q "depth=2"; then
    echo -e "  ${GREEN}✓${NC} Xray (443)"
  else
    echo -e "  ${RED}✗${NC} Xray (443)"
    issues=$((issues+1))
  fi
  # Check DNS
  if cat /etc/resolv.conf | grep -q "nameserver"; then
    echo -e "  ${GREEN}✓${NC} DNS"
  else
    echo -e "  ${RED}✗${NC} DNS"
    issues=$((issues+1))
  fi
  echo -e "${INFO}Issues: ${issues}${NC}"
  [[ $issues -eq 0 ]] && echo -e "${GREEN}All systems healthy!${NC}"
  return $issues
}

speed_test() {
  echo -e "${INFO}Speed test (5s sample)...${NC}"
  # Use iperf3 if available, else simple download test
  if command -v iperf3 &>/dev/null; then
    iperf3 -c iperf.he.net -t 5 2>&1 | grep -E "sender|receiver" | tail -1
  else
    # Test download speed
    local start=$(date +%s%N)
    curl -sk --max-time 5 -o /dev/null -w "%{speed_download}" "https://realityghost.ir/1mb.bin" 2>/dev/null ||     curl -sk --max-time 5 -o /dev/null -w "%{speed_download}" "https://speedtest.tele2.net/1MB.zip" 2>/dev/null ||     echo "N/A"
    local end=$(date +%s%N)
    local bytes=1048576
    local elapsed=$(( (end-start)/1000000 ))
    [[ $elapsed -gt 0 ]] && echo -e "${OK}Speed: $((bytes/elapsed)) KB/s${NC}" || echo -e "${WARN}Speed test failed${NC}"
  fi
}

auto_heal() {
  local fixed=0
  for svc in nginx xray; do
    if ! systemctl is-active --quiet "$svc"; then
      echo -e "${WARN}$svc is down! Restarting...${NC}"
      systemctl restart "$svc"
      fixed=$((fixed+1))
    fi
  done
  # Check port 443
  if ! ss -tlnp | grep -q ':443 '; then
    echo -e "${WARN}Port 443 is down! Restarting services...${NC}"
    systemctl restart nginx xray
    fixed=$((fixed+1))
  fi
  [[ $fixed -gt 0 ]] && echo -e "${OK}Auto-healed $fixed issue(s)${NC}"
  return $fixed
}


case "${1:-}" in
  install) DOMAIN="$2"; EMAIL="$3"; main_install ;;
  renew-ssl) check_root; renew_ssl ;;
  manage) check_root; detect_location; manage_menu ;;
  manual-rotate) check_root; manual_rotate ;;
  pull) check_root; pull_update ;;
  uninstall) check_root; uninstall ;;
  *)
    echo ""
    echo -e "${PURPLE}   _____   _____   _____  _____   ____  ${NC}"
    echo -e "${PURPLE}  |  __ \ / ____| |  __ \|  __ \ / __ \ ${NC}"
    echo -e "${PURPLE}  | |__) | |  __  | |__) | |__) | |  | |${NC}"
    echo -e "${PURPLE}  |  _  /| | |_ | |  ___/|  _  /| |  | |${NC}"
    echo -e "${PURPLE}  | | \ \| |__| | | |    | | \ \| |__| |${NC}"
    echo -e "${PURPLE}  |_|  \_\\_____| |_|    |_|  \_\\____/ ${NC}"
    echo -e "${PURPLE}                                       ${NC}"
    echo -e "${PURPLE}                                       ${NC}"
    echo -e "${PURPLE}  RG PRO — Xray VLESS+Reality Installer${NC}"
    echo -e "${PURPLE}  ─────────────────────────────────────────────${NC}"
    echo ""
    echo -e "  ${GREEN}install${NC}     — Install Xray Reality (auto setup)"
    echo -e "  ${GREEN}manage${NC}      — Management menu"
    echo -e "  ${GREEN}manual-rotate${NC}— Rotate Short IDs manually"
    echo -e "  ${GREEN}pull${NC}         — Update from GitHub"
    echo -e "  ${GREEN}uninstall${NC}   — Remove everything"
    echo ""
    ;;
esac
