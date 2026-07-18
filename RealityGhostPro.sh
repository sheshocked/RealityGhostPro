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
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y 2>/dev/null | tail -1
  apt-get install -y wget curl unzip uuid-runtime jq qrencode certbot \
    nginx-extras logrotate bc netcat-openbsd dnsutils python3 python3-pip sqlite3 figlet \
    fail2ban apache2-utils iptables-persistent openssl 2>/dev/null | tail -1
  pip3 install requests --break-system-packages -q 2>/dev/null || pip3 install requests -q 2>/dev/null || true
  echo -e "${OK}Dependencies installed"
}

setup_fail2ban() {
  command -v fail2ban-server &>/dev/null || return 0
  cat > /etc/fail2ban/jail.local <<'F2BEOF'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
backend = systemd

[sshd]
enabled = true
port = ssh
maxretry = 4
bantime = 2h
F2BEOF
  systemctl enable fail2ban >/dev/null 2>&1
  systemctl restart fail2ban >/dev/null 2>&1
  echo -e "${OK}fail2ban enabled (SSH brute-force protection)"
}

setup_panel_auth() {
  mkdir -p /etc/realityghost
  [[ -f /etc/realityghost/panel_auth.txt ]] && return 0
  local pw
  pw=$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c 16)
  printf 'user: admin\npass: %s\n' "$pw" > /etc/realityghost/panel_auth.txt
  chmod 600 /etc/realityghost/panel_auth.txt
  echo -e "${OK}Panel login created (admin / ${pw})"
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
  "stats": {},
  "api": { "tag": "api", "services": ["HandlerService", "StatsService"] },
  "policy": { "levels": { "0": { "statsUserUplink": true, "statsUserDownlink": true } }, "system": { "statsInboundUplink": true, "statsInboundDownlink": true } },
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
  }, { "listen": "127.0.0.1", "port": 10085, "protocol": "dokodemo-door", "settings": { "address": "127.0.0.1" }, "tag": "api" }],
  "outbounds": [{ "protocol": "freedom", "settings": {} }],
  "routing": { "rules": [{ "type": "field", "inboundTag": ["api"], "outboundTag": "api" }] }
}
XRAYEOF
  chmod 600 "$CONFIG_DIR/config.json"
  mkdir -p "$LOG_DIR"; chown -R nobody:nogroup "$LOG_DIR" 2>/dev/null
  mkdir -p "$STATE_DIR"; echo chrome > "$STATE_DIR/fp"
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
  local fp=$(cat "$STATE_DIR/fp" 2>/dev/null || echo chrome)
  local lines=()
  local idx=0
  for entry in "${SNI_LIST[@]}"; do
    IFS=':' read -r sni label label_url <<< "$entry"
    local real_sid=$(jq -r ".inbounds[0].streamSettings.realitySettings.shortIds[$idx]" "$CONFIG_DIR/config.json" 2>/dev/null)
    [[ -z "$real_sid" || "$real_sid" == "null" ]] && real_sid="0000000000000000"
    lines+=("vless://${uuid}@${DOMAIN}:443?flow=xtls-rprx-vision&encryption=none&security=reality&sni=${sni}&fp=${fp}&spx=%2F&pbk=${pubkey}&sid=${real_sid}&allowinsecure=0&type=tcp&headerType=none#${FLAG}%20${label_url}")
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
  [[ -f /etc/realityghost/panel_auth.txt ]] || setup_panel_auth
  local PANEL_USER PANEL_PASS PANEL_HASH
  PANEL_USER=$(grep '^user:' /etc/realityghost/panel_auth.txt 2>/dev/null | awk '{print $2}'); PANEL_USER="${PANEL_USER:-admin}"
  PANEL_PASS=$(grep '^pass:' /etc/realityghost/panel_auth.txt 2>/dev/null | cut -d' ' -f2-)
  PANEL_HASH=$(printf '%s' "$PANEL_PASS" | sha256sum | awk '{print $1}')
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
<style>
#rg-login{position:fixed;inset:0;z-index:99999;display:flex;align-items:center;justify-content:center;background:radial-gradient(1200px 800px at 50% -10%,rgba(80,90,200,.25),transparent),#080814;font-family:'Inter',system-ui,sans-serif}
#rg-login .card{width:min(92vw,380px);padding:34px 30px;border-radius:22px;background:rgba(255,255,255,.06);backdrop-filter:blur(22px) saturate(140%);-webkit-backdrop-filter:blur(22px) saturate(140%);border:1px solid rgba(255,255,255,.12);box-shadow:0 20px 60px rgba(0,0,0,.5)}
#rg-login h1{margin:0 0 4px;font-size:22px;font-weight:800;color:#fff;text-align:center;letter-spacing:.5px}
#rg-login p{margin:0 0 22px;font-size:13px;color:#9aa4c4;text-align:center}
#rg-login label{display:block;font-size:12px;color:#9aa4c4;margin:14px 0 6px;font-weight:600}
#rg-login input{width:100%;box-sizing:border-box;padding:13px 15px;border-radius:13px;border:1px solid rgba(255,255,255,.14);background:rgba(255,255,255,.05);color:#fff;font-size:15px;outline:none;transition:.2s}
#rg-login input:focus{border-color:rgba(120,140,255,.7);background:rgba(255,255,255,.09)}
#rg-login button{width:100%;margin-top:22px;padding:14px;border:0;border-radius:13px;cursor:pointer;font-size:15px;font-weight:700;color:#fff;background:linear-gradient(135deg,#5b6cff,#7d3cff);transition:.2s;box-shadow:0 10px 30px rgba(91,108,255,.35)}
#rg-login button:hover{filter:brightness(1.1);transform:translateY(-1px)}
#rg-login .err{margin-top:14px;font-size:13px;color:#ff7a90;text-align:center;min-height:18px}
#rg-login .logo{font-size:34px;text-align:center;margin-bottom:8px}
</style>
<script>
(function(){
  var AUTH={user:"__PANEL_USER__",hash:"__PANEL_HASH__"};
  if(sessionStorage.getItem("rg_auth")===AUTH.hash)return;
  var o=document.createElement("div");o.id="rg-login";
  o.innerHTML='<div class="card"><div class="logo">\ud83d\udee1\ufe0f</div><h1>RG PRO</h1><p>Sign in to your dashboard</p>'+
    '<label>Username</label><input id="rgu" autocomplete="username" autocapitalize="none" spellcheck="false">'+
    '<label>Password</label><input id="rgp" type="password" autocomplete="current-password">'+
    '<button id="rgb">Login</button><div class="err" id="rge"></div></div>';
  document.body.appendChild(o);
  var u=o.querySelector("#rgu"),p=o.querySelector("#rgp"),b=o.querySelector("#rgb"),e=o.querySelector("#rge");
  async function sha(t){var d=await crypto.subtle.digest("SHA-256",new TextEncoder().encode(t));return Array.from(new Uint8Array(d)).map(function(x){return x.toString(16).padStart(2,"0")}).join("")}
  async function go(){
    e.textContent="";
    try{
      var h=await sha(p.value);
      if(u.value.trim()===AUTH.user && h===AUTH.hash){sessionStorage.setItem("rg_auth",AUTH.hash);o.remove();}
      else{e.textContent="Wrong username or password";p.value="";p.focus();}
    }catch(x){e.textContent="Secure context required (use HTTPS)";}
  }
  b.addEventListener("click",go);
  p.addEventListener("keydown",function(ev){if(ev.key==="Enter")go()});
  u.addEventListener("keydown",function(ev){if(ev.key==="Enter")p.focus()});
  setTimeout(function(){u.focus()},50);
})();
</script>
</body>
</html>

PANEOF

  # Safely inject dynamic values (python avoids sed escaping issues with / & ')
  python3 - "$STATUS_DIR/index.html" "$DOMAIN" "$uuid" "$pubkey_line" "$SERVER_IP" "$configs_js" "$PANEL_USER" "$PANEL_HASH" <<'PYEOF'
import sys
f, dom, uid, pbk, sip, cfg, puser, phash = sys.argv[1:9]
s = open(f, encoding="utf-8").read()
s = (s.replace("${DOMAIN}", dom)
      .replace("${uuid}", uid)
      .replace("${pubkey_line}", pbk)
      .replace("${SERVER_IP}", sip)
      .replace("/*CONFIGS*/", cfg)
      .replace("__PANEL_USER__", puser)
      .replace("__PANEL_HASH__", phash))
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

_show_panel_login() {
  [[ -f /etc/realityghost/panel_auth.txt ]] || return 0
  echo -e "${CYAN}Panel login:${NC}"
  cat /etc/realityghost/panel_auth.txt
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
  # SAFE rotation (default): rotate client TLS fingerprint + APPEND new shortIds
  # (keep old ones as a grace pool) so NO active client is dropped.
  # HARD rotation (ROTATE_KEYS=1): also rotate Reality keys (drops all clients).
  mkdir -p "$STATE_DIR"
  local fps=(chrome firefox safari edge ios randomized)
  local newfp="${fps[$((RANDOM % ${#fps[@]}))]}"
  echo "$newfp" > "$STATE_DIR/fp"
  python3 - "$CONFIG_DIR/config.json" <<'PYROT'
import json, sys, secrets
p = sys.argv[1]
c = json.load(open(p))
rs = c["inbounds"][0]["streamSettings"]["realitySettings"]
sids = rs.get("shortIds", [])
ACTIVE, GRACE_MAX = 6, 18
active, grace = sids[:ACTIVE], sids[ACTIVE:]
new_active = [secrets.token_hex(8) for _ in range(ACTIVE)]
grace = (active + grace)[:GRACE_MAX]
rs["shortIds"] = new_active + grace
json.dump(c, open(p, "w"), indent=2)
PYROT
  if [[ "${ROTATE_KEYS:-0}" == "1" ]]; then
    echo -e "${WARN}HARD rotation: rotating Reality keys (all active clients will drop)${NC}"
    local keys newpriv
    keys=$(generate_reality_keys)
    newpriv=$(echo "$keys" | grep -oE "Private(Key)?: ?\S+" | head -1 | grep -oE "\S+$")
    python3 - "$CONFIG_DIR/config.json" "$newpriv" <<'PYKEY'
import json, sys
p = sys.argv[1]
c = json.load(open(p))
c["inbounds"][0]["streamSettings"]["realitySettings"]["privateKey"] = sys.argv[2]
json.dump(c, open(p, "w"), indent=2)
PYKEY
  fi
  systemctl restart xray
  build_subscription
  build_panel
  echo -e "${OK}SAFE rotation done (fp=${newfp}, new shortIds appended, active clients preserved)${NC}"
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
  systemctl stop fail2ban 2>/dev/null
  rm -f "$MONITOR_SCRIPT" /etc/cron.d/realityghost-rotate /etc/cron.d/realityghost-bot-enforce /etc/nginx/nginx.conf /etc/nginx/.rgpanel /usr/local/bin/rg-bot.py
  cp /etc/nginx/nginx.conf.backup /etc/nginx/nginx.conf 2>/dev/null
  rm -f /etc/sysctl.d/99-realityghost.conf /etc/systemd/resolved.conf.d/99-realityghost.conf /etc/fail2ban/jail.local
  rm -rf /etc/realityghost
  sysctl --system >/dev/null 2>&1
  systemctl restart systemd-resolved 2>/dev/null
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
  echo -e "${INFO}Optimizing DNS (DNS-over-TLS when available)..."
  if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
    mkdir -p /etc/systemd/resolved.conf.d
    cat > /etc/systemd/resolved.conf.d/99-realityghost.conf <<'RESOLVEDEOF'
[Resolve]
DNS=1.1.1.1#cloudflare-dns.com 8.8.8.8#dns.google
FallbackDNS=9.9.9.9#dns.quad9.net
DNSOverTLS=opportunistic
DNSSEC=allow-downgrade
Cache=yes
RESOLVEDEOF
    systemctl restart systemd-resolved 2>/dev/null
    echo -e "${OK}DNS-over-TLS configured (Cloudflare/Google, leak-resistant)"
    return 0
  fi
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
# RealityGhost PRO - Telegram management bot (raw Telegram HTTP API, no external SDK).
# Features: inline keyboards, QR images, add/remove/suspend/resume users,
# real per-user traffic accounting via Xray Stats API, quota enforcement, expiry reminders.
import json
import os
import sqlite3
import subprocess
import sys
import time
import uuid as uuidlib
from datetime import datetime, timedelta

try:
    import requests
except Exception:
    requests = None

ETC = "/etc/realityghost"
CONFIG_FILE = os.path.join(ETC, "bot_config.json")
DB_FILE = os.path.join(ETC, "users.db")
XRAY_CONFIG = "/usr/local/etc/xray/config.json"
XRAY_BIN = "/usr/local/bin/xray"
API_ADDR = "127.0.0.1:10085"
API = "https://api.telegram.org/bot{token}/{method}"

# (sni, human label) pairs used to build subscription links.
SNI_LIST = [
    ("www.gstatic.com", "Gstatic"),
    ("ajax.googleapis.com", "Ajax-Google"),
    ("storage.googleapis.com", "Google-Storage"),
    ("fonts.gstatic.com", "Fonts-Gstatic"),
    ("fonts.googleapis.com", "Google-Fonts"),
    ("www.google.com", "Google"),
]


# ---------------- config / db ----------------
def load_config():
    try:
        with open(CONFIG_FILE, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {"enabled": False, "token": "", "domain": "", "admin_ids": []}


def save_config(cfg):
    os.makedirs(ETC, exist_ok=True)
    with open(CONFIG_FILE, "w", encoding="utf-8") as f:
        json.dump(cfg, f)


def db():
    os.makedirs(ETC, exist_ok=True)
    conn = sqlite3.connect(DB_FILE)
    conn.execute(
        """CREATE TABLE IF NOT EXISTS users(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT, uuid TEXT, email TEXT UNIQUE,
            mb_limit INTEGER DEFAULT 0, days INTEGER DEFAULT 0,
            created TEXT, expiry TEXT, disabled INTEGER DEFAULT 0,
            offset_bytes INTEGER DEFAULT 0, last_seen INTEGER DEFAULT 0)"""
    )
    conn.commit()
    return conn


# ---------------- xray helpers ----------------
def load_xray():
    with open(XRAY_CONFIG, encoding="utf-8") as f:
        return json.load(f)


def save_xray(cfg):
    with open(XRAY_CONFIG, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2)


def restart_xray():
    subprocess.run(["systemctl", "restart", "xray"], capture_output=True)


def reality():
    return load_xray()["inbounds"][0]["streamSettings"]["realitySettings"]


def get_public_key():
    cfg = load_xray()
    priv = cfg["inbounds"][0]["streamSettings"]["realitySettings"]["privateKey"]
    try:
        out = subprocess.run(
            [XRAY_BIN, "x25519", "-i", priv], capture_output=True, text=True
        ).stdout
        for line in out.splitlines():
            for key in ("Password (PublicKey):", "PublicKey:", "Public key:", "Password:"):
                if key in line:
                    return line.split(key, 1)[1].strip().split()[0]
    except Exception:
        pass
    return ""


def current_fp():
    try:
        with open("/var/lib/realityghost/fp", encoding="utf-8") as f:
            v = f.read().strip()
            return v or "chrome"
    except Exception:
        return "chrome"


def add_xray_client(user_uuid, email):
    cfg = load_xray()
    clients = cfg["inbounds"][0]["settings"]["clients"]
    if any(c.get("email") == email for c in clients):
        return False
    clients.append(
        {"id": user_uuid, "flow": "xtls-rprx-vision", "level": 0, "email": email}
    )
    save_xray(cfg)
    restart_xray()
    return True


def remove_xray_client(email):
    cfg = load_xray()
    inbound = cfg["inbounds"][0]["settings"]
    before = len(inbound["clients"])
    inbound["clients"] = [c for c in inbound["clients"] if c.get("email") != email]
    if len(inbound["clients"]) != before:
        save_xray(cfg)
        restart_xray()
        return True
    return False


def build_links(user_uuid, domain):
    pbk = get_public_key()
    rs = reality()
    sids = rs.get("shortIds", [])
    fp = current_fp()
    links = []
    for i, (sni, label) in enumerate(SNI_LIST):
        sid = sids[i] if i < len(sids) else ""
        links.append(
            "vless://{u}@{d}:443?flow=xtls-rprx-vision&encryption=none"
            "&security=reality&sni={sni}&fp={fp}&spx=%2F&pbk={pbk}&sid={sid}"
            "&allowinsecure=0&type=tcp&headerType=none#RG-{label}".format(
                u=user_uuid, d=domain, sni=sni, fp=fp, pbk=pbk, sid=sid, label=label
            )
        )
    return links


# ---------------- traffic (Xray Stats API) ----------------
def query_traffic():
    """Return {email: current_bytes} summed uplink+downlink since last xray restart."""
    result = {}
    try:
        out = subprocess.run(
            [XRAY_BIN, "api", "statsquery", "--server=" + API_ADDR, "-pattern", "user>>>"],
            capture_output=True, text=True, timeout=10,
        ).stdout
        data = json.loads(out or "{}")
        for item in data.get("stat", []) or []:
            name = item.get("name", "")
            val = int(item.get("value", 0) or 0)
            parts = name.split(">>>")
            if len(parts) >= 2:
                result[parts[1]] = result.get(parts[1], 0) + val
    except Exception:
        pass
    return result


def accumulate_traffic():
    """Update cumulative usage in DB, handling xray restarts (counter resets)."""
    live = query_traffic()
    conn = db()
    totals = {}
    for row in conn.execute("SELECT email, offset_bytes, last_seen FROM users").fetchall():
        email, offset_bytes, last_seen = row
        cur = live.get(email, 0)
        if cur < last_seen:  # xray was restarted -> counter reset
            offset_bytes += last_seen
        total = offset_bytes + cur
        conn.execute(
            "UPDATE users SET offset_bytes=?, last_seen=? WHERE email=?",
            (offset_bytes, cur, email),
        )
        totals[email] = total
    conn.commit()
    conn.close()
    return totals


def human_bytes(n):
    n = float(n)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024 or unit == "TB":
            return "%.2f %s" % (n, unit)
        n /= 1024


# ---------------- telegram api ----------------
def tg(method, token, **params):
    if requests is None:
        return {}
    try:
        r = requests.post(API.format(token=token, method=method), data=params, timeout=35)
        return r.json()
    except Exception:
        return {}


def tg_photo(token, chat_id, png_bytes, caption=""):
    if requests is None:
        return {}
    try:
        r = requests.post(
            API.format(token=token, method="sendPhoto"),
            data={"chat_id": chat_id, "caption": caption},
            files={"photo": ("qr.png", png_bytes, "image/png")},
            timeout=35,
        )
        return r.json()
    except Exception:
        return {}


def qr_png(text):
    try:
        p = subprocess.run(
            ["qrencode", "-o", "-", "-t", "PNG", "-s", "6", "-m", "2", text],
            capture_output=True, timeout=10,
        )
        return p.stdout or None
    except Exception:
        return None


def kb(rows):
    return json.dumps({"inline_keyboard": rows})


def main_menu():
    return kb([
        [{"text": "\U0001F465 Users", "callback_data": "users"},
         {"text": "\u2795 Add User", "callback_data": "add"}],
        [{"text": "\U0001F4CA Traffic", "callback_data": "traffic"},
         {"text": "\U0001F5A5 Server", "callback_data": "stats"}],
        [{"text": "\U0001F504 Refresh", "callback_data": "menu"}],
    ])


# ---------------- user operations ----------------
def create_user(name, mb=0, days=0):
    cfg = load_config()
    domain = cfg.get("domain", "")
    u = str(uuidlib.uuid4())
    email = "%s-%s@%s" % (name, u[:8], domain)
    now = datetime.utcnow()
    expiry = (now + timedelta(days=days)).isoformat() if days else ""
    conn = db()
    conn.execute(
        "INSERT INTO users(name,uuid,email,mb_limit,days,created,expiry,disabled)"
        " VALUES(?,?,?,?,?,?,?,0)",
        (name, u, email, int(mb), int(days), now.isoformat(), expiry),
    )
    conn.commit()
    conn.close()
    add_xray_client(u, email)
    return u, email, domain


def set_disabled(email, disabled):
    conn = db()
    conn.execute("UPDATE users SET disabled=? WHERE email=?", (1 if disabled else 0, email))
    conn.commit()
    row = conn.execute("SELECT uuid FROM users WHERE email=?", (email,)).fetchone()
    conn.close()
    if not row:
        return False
    if disabled:
        remove_xray_client(email)
    else:
        add_xray_client(row[0], email)
    return True


def delete_user(email):
    remove_xray_client(email)
    conn = db()
    conn.execute("DELETE FROM users WHERE email=?", (email,))
    conn.commit()
    conn.close()


def list_users():
    conn = db()
    rows = conn.execute(
        "SELECT id,name,email,uuid,mb_limit,expiry,disabled FROM users ORDER BY id"
    ).fetchall()
    conn.close()
    return rows


def enforce():
    """Disable users past expiry or over quota. Returns list of (email, reason)."""
    totals = accumulate_traffic()
    now = datetime.utcnow()
    disabled = []
    conn = db()
    rows = conn.execute(
        "SELECT email,mb_limit,expiry,disabled FROM users"
    ).fetchall()
    conn.close()
    for email, mb_limit, expiry, is_disabled in rows:
        if is_disabled:
            continue
        reason = None
        if expiry:
            try:
                if now > datetime.fromisoformat(expiry):
                    reason = "expired"
            except Exception:
                pass
        if not reason and mb_limit and totals.get(email, 0) >= int(mb_limit) * 1024 * 1024:
            reason = "quota exceeded"
        if reason:
            set_disabled(email, True)
            disabled.append((email, reason))
    return disabled


def expiring_soon(days=3):
    now = datetime.utcnow()
    soon = []
    for _id, name, email, _u, _mb, expiry, dis in list_users():
        if dis or not expiry:
            continue
        try:
            exp = datetime.fromisoformat(expiry)
        except Exception:
            continue
        left = (exp - now).days
        if 0 <= left <= days:
            soon.append((name, email, left))
    return soon


def notify_admins(text):
    cfg = load_config()
    token = cfg.get("token", "")
    if not token:
        return
    for a in cfg.get("admin_ids", []):
        tg("sendMessage", token, chat_id=a, text=text)


# ---------------- bot loop ----------------
PENDING = {}


def is_admin(cfg, uid):
    return uid in cfg.get("admin_ids", [])


def user_detail_kb(email):
    return kb([
        [{"text": "\U0001F517 Links + QR", "callback_data": "qr:" + email}],
        [{"text": "\u23F8 Suspend", "callback_data": "sus:" + email},
         {"text": "\u25B6 Resume", "callback_data": "res:" + email}],
        [{"text": "\U0001F5D1 Delete", "callback_data": "del:" + email},
         {"text": "\u2B05 Back", "callback_data": "users"}],
    ])


def render_users():
    rows = list_users()
    if not rows:
        return "No users yet.", kb([[{"text": "\u2795 Add User", "callback_data": "add"}],
                                    [{"text": "\u2B05 Back", "callback_data": "menu"}]])
    buttons = []
    for _id, name, email, _u, _mb, _exp, dis in rows:
        mark = "\u26D4" if dis else "\u2705"
        buttons.append([{"text": "%s %s" % (mark, name), "callback_data": "u:" + email}])
    buttons.append([{"text": "\u2B05 Back", "callback_data": "menu"}])
    return "Select a user:", kb(buttons)


def handle_callback(cfg, token, cq):
    data = cq.get("data", "")
    msg = cq.get("message", {})
    chat_id = msg.get("chat", {}).get("id")
    uid = cq.get("from", {}).get("id")
    tg("answerCallbackQuery", token, callback_query_id=cq.get("id"))
    if not is_admin(cfg, uid):
        return
    if data == "menu":
        tg("sendMessage", token, chat_id=chat_id, text="\U0001F47B RG PRO Control Panel", reply_markup=main_menu())
    elif data == "users":
        text, markup = render_users()
        tg("sendMessage", token, chat_id=chat_id, text=text, reply_markup=markup)
    elif data == "add":
        PENDING[uid] = "await_name"
        tg("sendMessage", token, chat_id=chat_id,
           text="Send new user as: name [quota_MB] [days]\nExample: ali 50000 30")
    elif data == "stats":
        tg("sendMessage", token, chat_id=chat_id, text=server_stats())
    elif data == "traffic":
        tg("sendMessage", token, chat_id=chat_id, text=traffic_report())
    elif data.startswith("u:"):
        email = data[2:]
        tg("sendMessage", token, chat_id=chat_id, text="User: " + email, reply_markup=user_detail_kb(email))
    elif data.startswith("qr:"):
        email = data[3:]
        send_user_config(token, chat_id, email)
    elif data.startswith("sus:"):
        set_disabled(data[4:], True)
        tg("sendMessage", token, chat_id=chat_id, text="\u23F8 Suspended: " + data[4:])
    elif data.startswith("res:"):
        set_disabled(data[4:], False)
        tg("sendMessage", token, chat_id=chat_id, text="\u25B6 Resumed: " + data[4:])
    elif data.startswith("del:"):
        delete_user(data[4:])
        tg("sendMessage", token, chat_id=chat_id, text="\U0001F5D1 Deleted: " + data[4:])


def send_user_config(token, chat_id, email):
    conn = db()
    row = conn.execute("SELECT uuid FROM users WHERE email=?", (email,)).fetchone()
    conn.close()
    if not row:
        tg("sendMessage", token, chat_id=chat_id, text="User not found.")
        return
    cfg = load_config()
    links = build_links(row[0], cfg.get("domain", ""))
    tg("sendMessage", token, chat_id=chat_id, text="\n\n".join(links))
    png = qr_png(links[0])
    if png:
        tg_photo(token, chat_id, png, caption="QR: " + email)


def server_stats():
    try:
        with open("/var/www/html/status/stats.json", encoding="utf-8") as f:
            s = json.load(f)
        return ("\U0001F5A5 Server\nCPU: {cpu}\nRAM: {ram}%\nUptime: {up}\n"
                "Connections: {con}").format(
            cpu=s.get("cpu", "?"), ram=s.get("ram", {}).get("usage", "?"),
            up=s.get("uptime", "?"), con=s.get("connections", "?"))
    except Exception:
        return "Server stats unavailable."


def traffic_report():
    totals = accumulate_traffic()
    rows = list_users()
    if not rows:
        return "No users."
    lines = ["\U0001F4CA Traffic per user:"]
    for _id, name, email, _u, mb, _exp, dis in rows:
        used = totals.get(email, 0)
        cap = ("/" + human_bytes(int(mb) * 1024 * 1024)) if mb else ""
        lines.append("%s %s: %s%s" % ("\u26D4" if dis else "\u2705", name, human_bytes(used), cap))
    return "\n".join(lines)


def handle_message(cfg, token, m):
    chat = m.get("chat", {})
    chat_id = chat.get("id")
    uid = m.get("from", {}).get("id")
    text = (m.get("text") or "").strip()
    # First user to talk becomes admin if none set.
    if not cfg.get("admin_ids"):
        cfg["admin_ids"] = [uid]
        save_config(cfg)
        tg("sendMessage", token, chat_id=chat_id, text="\u2705 You are now the admin.")
    if not is_admin(cfg, uid):
        tg("sendMessage", token, chat_id=chat_id, text="\u26D4 Not authorized.")
        return
    if PENDING.get(uid) == "await_name" and not text.startswith("/"):
        PENDING.pop(uid, None)
        parts = text.split()
        name = parts[0]
        mb = int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else 0
        days = int(parts[2]) if len(parts) > 2 and parts[2].isdigit() else 0
        u, email, _ = create_user(name, mb, days)
        tg("sendMessage", token, chat_id=chat_id,
           text="\u2705 Created %s\nQuota: %s MB  Days: %s" % (name, mb or "\u221E", days or "\u221E"))
        send_user_config(token, chat_id, email)
        return
    if text in ("/start", "/menu"):
        tg("sendMessage", token, chat_id=chat_id, text="\U0001F47B RG PRO Control Panel", reply_markup=main_menu())
    elif text == "/traffic":
        tg("sendMessage", token, chat_id=chat_id, text=traffic_report())
    elif text == "/stats":
        tg("sendMessage", token, chat_id=chat_id, text=server_stats())
    else:
        tg("sendMessage", token, chat_id=chat_id, text="Send /menu to open the control panel.")


def runbot():
    cfg = load_config()
    token = cfg.get("token", "")
    if not cfg.get("enabled") or not token:
        print("Bot disabled or no token.")
        return
    offset = None
    while True:
        try:
            params = {"timeout": 30}
            if offset is not None:
                params["offset"] = offset
            resp = tg("getUpdates", token, **params)
            for upd in resp.get("result", []) or []:
                offset = upd["update_id"] + 1
                cfg = load_config()
                if "callback_query" in upd:
                    handle_callback(cfg, token, upd["callback_query"])
                elif "message" in upd:
                    handle_message(cfg, token, upd["message"])
        except Exception as e:
            print("loop error:", e)
            time.sleep(3)


# ---------------- CLI ----------------
def main():
    args = sys.argv[1:]
    cmd = args[0] if args else ""
    if cmd == "init":
        db()
        print("Initialized.")
    elif cmd == "adduser":
        name = args[1]
        mb = int(args[2]) if len(args) > 2 else 0
        days = int(args[3]) if len(args) > 3 else 0
        u, email, domain = create_user(name, mb, days)
        print("Created", email)
        for link in build_links(u, domain):
            print(link)
    elif cmd == "deluser":
        delete_user(args[1])
        print("Deleted", args[1])
    elif cmd == "suspend":
        set_disabled(args[1], True)
        print("Suspended", args[1])
    elif cmd == "resume":
        set_disabled(args[1], False)
        print("Resumed", args[1])
    elif cmd == "list":
        for row in list_users():
            print(row)
    elif cmd == "stats":
        print(server_stats())
    elif cmd == "traffic":
        print(traffic_report())
    elif cmd == "enforce":
        disabled = enforce()
        for email, reason in disabled:
            notify_admins("\u26D4 Disabled %s (%s)" % (email, reason))
        print("Enforced. Disabled:", len(disabled))
    elif cmd == "notify":
        soon = expiring_soon(3)
        if soon:
            msg = "\u23F3 Expiring soon:\n" + "\n".join(
                "%s (%s) - %sd left" % (n, e, d) for n, e, d in soon)
            notify_admins(msg)
        print("Reminders sent:", len(soon))
    elif cmd == "runbot":
        runbot()
    else:
        print("Usage: rg-bot.py {init|adduser|deluser|suspend|resume|list|stats|traffic|enforce|notify|runbot}")


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
  setup_fail2ban
  install_xray
  install_certbot
  setup_panel_auth
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

set_panel_login() {
  mkdir -p /etc/realityghost
  echo -ne "${BOLD}New panel username [admin]: ${NC}"; read -r pu
  pu="${pu:-admin}"
  echo -ne "${BOLD}New panel password: ${NC}"; read -r pp
  if [[ -z "$pp" ]]; then echo -e "${WARN}Cancelled (empty password)${NC}"; return; fi
  printf 'user: %s\npass: %s\n' "$pu" "$pp" > /etc/realityghost/panel_auth.txt
  chmod 600 /etc/realityghost/panel_auth.txt
  build_panel
  echo -e "${OK}Panel login updated (user: ${pu})${NC}"
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
    echo "14. 🔐 Panel Login (user/pass)"
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
      14) set_panel_login; echo -ne "\n${YELLOW}Enter...${NC}"; read -r ;;
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

rg_alert() {
  local msg="$1"
  local cfg=/etc/realityghost/bot_config.json
  [[ -f "$cfg" ]] || return 0
  local token admins
  token=$(jq -r '.token // empty' "$cfg" 2>/dev/null)
  admins=$(jq -r '.admin_ids[]? // empty' "$cfg" 2>/dev/null)
  [[ -z "$token" || -z "$admins" ]] && return 0
  local a
  for a in $admins; do
    curl -s --max-time 8 "https://api.telegram.org/bot${token}/sendMessage" \
      --data-urlencode "chat_id=${a}" --data-urlencode "text=\xf0\x9f\x9a\xa8 RG PRO: ${msg}" >/dev/null 2>&1
  done
}

auto_heal() {
  local fixed=0
  for svc in nginx xray; do
    if ! systemctl is-active --quiet "$svc"; then
      echo -e "${WARN}$svc is down! Restarting...${NC}"
      systemctl restart "$svc"; rg_alert "$svc was down and has been restarted"
      fixed=$((fixed+1))
    fi
  done
  if ! ss -tlnp | grep -q ':443 '; then
    echo -e "${WARN}Port 443 is down! Restarting services...${NC}"
    systemctl restart nginx xray; rg_alert "Port 443 was down; services restarted"
    fixed=$((fixed+1))
  fi
  local cert="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
  if [[ -n "$DOMAIN" && -f "$cert" ]]; then
    local exp_epoch now_epoch days
    exp_epoch=$(date -d "$(openssl x509 -enddate -noout -in "$cert" 2>/dev/null | cut -d= -f2)" +%s 2>/dev/null)
    now_epoch=$(date +%s)
    if [[ -n "$exp_epoch" ]]; then
      days=$(( (exp_epoch - now_epoch) / 86400 ))
      if [[ $days -lt 7 ]]; then
        echo -e "${WARN}TLS cert expires in ${days}d - renewing...${NC}"
        renew_ssl; rg_alert "TLS certificate expiring in ${days}d; renewal attempted"
        fixed=$((fixed+1))
      fi
    fi
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
