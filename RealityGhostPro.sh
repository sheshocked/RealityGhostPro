#!/bin/bash
# RealityGhost PRO v6.0 — Fully automatic Xray VLESS+Reality installer

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; PURPLE='\033[0;35m'; WHITE='\033[1;37m'
BOLD='\033[1m'; NC='\033[0m'
INFO="${CYAN}[ℹ]${NC}"; OK="${GREEN}[✓]${NC}"; ERR="${RED}[✗]${NC}"; WARN="${YELLOW}[⚠]${NC}"

DOMAIN="${DOMAIN:-}"; EMAIL="${EMAIL:-}"
SUB_PORT="8443"; XRAY_TCP_PORT="443"
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
  local data country ip
  # Try multiple geolocation APIs with fallback
  data=$(curl -4 -s --max-time 3 "https://ipapi.co/json/" 2>/dev/null)
  country=$(echo "$data" | jq -r '.country_code // ""' 2>/dev/null)
  ip=$(echo "$data" | jq -r '.ip // ""' 2>/dev/null)
  if [[ -z "$country" || "$country" == "null" || ${#country} -gt 3 ]]; then
    data=$(curl -4 -s --max-time 3 "http://ip-api.com/json/" 2>/dev/null)
    country=$(echo "$data" | jq -r '.countryCode // ""' 2>/dev/null)
    ip=$(echo "$data" | jq -r '.query // ""' 2>/dev/null)
  fi
  if [[ -z "$country" || "$country" == "null" ]]; then
    data=$(curl -4 -s --max-time 3 "https://ipinfo.io/json" 2>/dev/null)
    country=$(echo "$data" | jq -r '.country // ""' 2>/dev/null)
    ip=$(echo "$data" | jq -r '.ip // ""' 2>/dev/null)
  fi
  [[ -z "$country" || "$country" == "null" ]] && country="US"
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
    *)  FLAG="%F0%9F%87%BA%F0%9F%87%B8"; FLAG_RAW="🇺🇸"; LOC="Unknown" ;;
  esac
}

check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo -e "${ERR}این اسکریپت باید با دسترسی روت اجرا بشه${NC}"
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
  echo -e "${INFO}Getting SSL from Let's Encrypt..."
  systemctl stop nginx 2>/dev/null
  certbot certonly --standalone --non-interactive --agree-tos -d "${DOMAIN}" -m "${EMAIL}" 2>/dev/null
  systemctl start nginx 2>/dev/null
  if [[ -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]]; then
    echo -e "${OK}SSL obtained"
    (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet --post-hook 'systemctl reload nginx'") | crontab -
  else
    echo -e "${ERR}SSL failed. Make sure domain points to this server IP${NC}"
    exit 1
  fi
}

configure_nginx() {
  echo -e "${INFO}Configuring NGINX..."
  cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup 2>/dev/null
  cat > /etc/nginx/nginx.conf <<NGINXEOF
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/modules-enabled/*.conf;

events {
    worker_connections 16384;
    multi_accept on;
    use epoll;
}

http {
    limit_conn_zone \$binary_remote_addr zone=addr:10m;
    limit_req_zone \$binary_remote_addr zone=one:10m rate=30r/s;

    server {
        listen 127.0.0.1:${SUB_PORT} ssl;
        server_name ${DOMAIN};
        ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
        location = /sub {
            default_type text/plain;
            add_header Content-Disposition 'attachment; filename="sub.txt"';
            alias ${SUB_DIR}/sub.txt;
        }
        location /status/ {
            alias ${STATUS_DIR}/;
            index index.html;
            try_files \$uri \$uri/ /status/index.html;
        }
    }
}
NGINXEOF
  nginx -t 2>/dev/null && systemctl reload nginx
  echo -e "${OK}NGINX configured"
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
══════════ RealityGhost PRO ══════════
دامنه: ${DOMAIN}
UUID: ${uuid}
Public Key: ${public_key}
پورت: 443 (SNI Passthrough)
INFOEOF
  local idx=0
  for entry in "${SNI_LIST[@]}"; do
    IFS=':' read -r sni label label_url <<< "$entry"
    local real_sid=$(jq -r ".inbounds[0].streamSettings.realitySettings.shortIds[$idx]" "$CONFIG_DIR/config.json" 2>/dev/null)
    [[ -z "$real_sid" || "$real_sid" == "null" ]] && real_sid="${sids[$idx]}"
    local link="vless://${uuid}@${DOMAIN}:443?flow=xtls-rprx-vision&encryption=none&security=reality&sni=${sni}&fp=chrome&echfq=none&pbk=${public_key}&sid=${real_sid}&allowinsecure=0&type=tcp&headerType=none#${FLAG}%20${label_url}"
    echo "$link" >> "$CONFIG_DIR/client_info.txt"
    idx=$((idx+1))
  done
  echo -e "${OK}Xray configured"
}

build_subscription() {
  local uuid=$(jq -r '.inbounds[0].settings.clients[0].id' "$CONFIG_DIR/config.json" 2>/dev/null)
  local pbk=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$CONFIG_DIR/config.json" 2>/dev/null)
  [[ -z "$uuid" || -z "$pbk" ]] && { echo -e "${ERR}خطا در خوندن کانفیگ${NC}"; return 1; }
  local pubkey=""
  local keys=$(/usr/local/bin/xray x25519 -i "$pbk" 2>/dev/null)
  pubkey=$(echo "$keys" | grep -oE "(PublicKey|Password \(PublicKey\)): ?\S+" | head -1 | grep -oE "\S+$")
  [[ -z "$pubkey" ]] && pubkey=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0] // ""' "$CONFIG_DIR/config.json")
  mkdir -p "$SUB_DIR"
  local lines=()
  local idx=0
  for entry in "${SNI_LIST[@]}"; do
    IFS=':' read -r sni label label_url <<< "$entry"
    local real_sid=$(jq -r ".inbounds[0].streamSettings.realitySettings.shortIds[$idx]" "$CONFIG_DIR/config.json" 2>/dev/null)
    [[ -z "$real_sid" || "$real_sid" == "null" ]] && real_sid="0000000000000000"
    lines+=("vless://${uuid}@${DOMAIN}:443?flow=xtls-rprx-vision&encryption=none&security=reality&sni=${sni}&fp=chrome&echfq=none&pbk=${pubkey}&sid=${real_sid}&allowinsecure=0&type=tcp&headerType=none#${FLAG}%20${label_url}")
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
  local configs_js=""; local idx=0; local emojis=("🟢" "🟣" "🟠" "🔴" "🟤" "🔵")
  for entry in "${SNI_LIST[@]}"; do
    IFS=':' read -r sni label label_url <<< "$entry"
    local real_sid=$(jq -r ".inbounds[0].streamSettings.realitySettings.shortIds[$idx]" "$CONFIG_DIR/config.json" 2>/dev/null)
    [[ -z "$real_sid" || "$real_sid" == "null" ]] && real_sid="0000000000000000"
    [[ $idx -gt 0 ]] && configs_js+=","
    configs_js+="{sni:'${sni}', label:'${FLAG_RAW} ${label}', emoji:'${emojis[$idx]}', sid:'${real_sid}'}"
    idx=$((idx+1))
  done
  mkdir -p "$STATUS_DIR"
  cat > "$STATUS_DIR/index.html" <<HTMLEOF
<!DOCTYPE html><html lang="fa" dir="rtl"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0"><title>RG PRO · Dashboard</title>
<style>
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap');
:root{--b:#14141f;--s:#1a1a2e;--s2:#22223a;--br:rgba(130,140,255,0.07);--t:#d0d0e8;--t2:#7878a8;--p:#7c5cfc;--p2:#9775ff;--g:#00d68f;--y:#f0a030;--r:#f05060;--bl:#4a9eff;--rad:14px;--rs:9px}
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:'Inter',system-ui,sans-serif;background:var(--b);color:var(--t)}
.w{max-width:1440px;margin:0 auto;padding:14px}
.hd{display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:10px;padding:12px 16px;background:var(--s);border:1px solid var(--br);border-radius:var(--rad);margin-bottom:14px}
.hd-l{display:flex;align-items:center;gap:10px}.hd-l h1{font-size:15px;font-weight:800}.hd-l span{color:var(--p2)}
.hd-l small{font-size:10px;background:rgba(124,92,252,0.1);padding:2px 6px;border-radius:100px;color:var(--p2)}
.hd-r{display:flex;align-items:center;gap:6px}
.stt{display:flex;align-items:center;gap:4px;padding:5px 10px;border-radius:100px;font-size:10px;font-weight:600;background:rgba(0,214,143,0.08);color:var(--g);border:1px solid rgba(0,214,143,0.12)}
.stt.r{background:rgba(240,80,96,0.08);color:var(--r);border-color:rgba(240,80,96,0.12)}
.dot{width:4px;height:4px;border-radius:50%;background:var(--g);animation:pl 1.8s infinite}.dot.r{background:var(--r)}
@keyframes pl{0%,100%{opacity:1}50%{opacity:0.2}}
.g{display:grid;gap:10px;margin-bottom:12px}
.gx{grid-template-columns:repeat(auto-fit,minmax(170px,1fr))}
.g2{grid-template-columns:1.5fr 1fr}
.g3{grid-template-columns:1fr 1fr 1fr}
.g4{grid-template-columns:repeat(auto-fit,minmax(220px,1fr))}
.cd{background:var(--s);border:1px solid var(--br);border-radius:var(--rad);padding:10px 12px}
.cd-l{font-size:9px;color:var(--t2);text-transform:uppercase;letter-spacing:.4px;font-weight:600;margin-bottom:2px}
.cd-v{font-size:18px;font-weight:800;letter-spacing:-.3px;display:flex;align-items:baseline;gap:3px}
.cd-v small{font-size:10px;font-weight:500;color:var(--t2)}
.cd-v.xs{font-size:13px}
.sec{background:var(--s);border:1px solid var(--br);border-radius:var(--rad);padding:14px;height:100%}
.sec-h{display:flex;justify-content:space-between;align-items:center;margin-bottom:10px;padding-bottom:6px;border-bottom:1px solid rgba(130,140,255,0.04)}
.sec-h h2{font-size:12px;font-weight:700;display:flex;align-items:center;gap:5px}
.bc{height:4px;border-radius:100px;background:rgba(255,255,255,0.04);overflow:hidden;margin-top:4px}
.bf{height:100%;border-radius:100px;transition:width 1s}
.p{background:linear-gradient(90deg,#5a3fd4,#7c5cfc)}.gr{background:linear-gradient(90deg,#00b87a,#00d68f)}.yl{background:linear-gradient(90deg,#d49020,#f0a030)}.or{background:linear-gradient(90deg,#e07020,#ff8c42)}
.rs{display:flex;flex-direction:column;gap:8px}
.rl{display:flex;justify-content:space-between;font-size:10px;color:var(--t2);margin-bottom:2px}.rl b{color:var(--t);font-weight:600}
.tg{display:grid;grid-template-columns:repeat(3,1fr);gap:6px}
.ti{text-align:center;padding:8px;border-radius:var(--rs);background:rgba(255,255,255,0.02);border:1px solid rgba(255,255,255,0.04)}
.ti-v{font-size:14px;font-weight:700;direction:ltr}.ti-l{font-size:9px;color:var(--t2);margin-top:1px}
.sv{display:grid;grid-template-columns:1fr 1fr;gap:6px}
.svc{display:flex;align-items:center;gap:5px;padding:6px 8px;border-radius:6px;background:rgba(255,255,255,0.02);font-size:10px;font-weight:600;border:1px solid rgba(255,255,255,0.05)}
.svc.o{color:var(--g);border-color:rgba(0,214,143,0.12)}.svc.x{color:var(--t2)}
.cl{display:grid;grid-template-columns:1fr 1fr;gap:4px}
.ci{display:flex;align-items:center;gap:5px;padding:5px 7px;border-radius:5px;background:rgba(255,255,255,0.02);border:1px solid rgba(255,255,255,0.04);cursor:pointer;transition:all .1s}
.ci:hover{background:rgba(124,92,252,0.06);border-color:rgba(124,92,252,0.12)}
.ci-l{flex:1;min-width:0}.ci-l strong{display:block;font-size:9px;font-weight:600}
.ci-s{font-size:7px;color:var(--p2);direction:ltr;font-family:monospace;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.ci-b{font-size:6px;padding:2px 4px;border-radius:3px;background:rgba(255,255,255,0.05);border:none;cursor:pointer;color:var(--t2)}
.lg{display:flex;gap:5px}
.lgi{flex:1;text-align:center;padding:8px;border-radius:var(--rs);background:rgba(255,255,255,0.02)}
.lgi-v{font-size:14px;font-weight:700}.lgi-l{font-size:9px;color:var(--t2);margin-top:1px}
.ch{display:flex;gap:5px;flex-wrap:wrap}
.chp{padding:4px 8px;border-radius:100px;font-size:9px;background:rgba(255,255,255,0.02);border:1px solid rgba(255,255,255,0.04);cursor:pointer}
.chp:hover{background:rgba(124,92,252,0.08);border-color:rgba(124,92,252,0.15)}
.ir{display:flex;flex-direction:column;gap:6px}
.irow{display:flex;justify-content:space-between;align-items:center;padding:5px 0;font-size:10px}
.irow:not(:last-child){border-bottom:1px solid rgba(130,140,255,0.03)}
.irow-l{color:var(--t2)}.irow-v{font-weight:500;direction:ltr;font-size:10px;text-align:left;word-break:break-all}
.qa{display:flex;gap:6px;flex-wrap:wrap}
.qab{padding:5px 10px;border-radius:var(--rs);font-size:9px;font-weight:600;border:1px solid rgba(124,92,252,0.15);background:rgba(124,92,252,0.06);color:var(--p2);cursor:pointer}
.ft{padding:14px;text-align:center;font-size:9px;color:var(--t2);border-top:1px solid rgba(255,255,255,0.02);margin-top:14px;display:flex;justify-content:center;gap:10px;flex-wrap:wrap}
.ft a{color:var(--p2);text-decoration:none}
.ts{position:fixed;bottom:20px;left:50%;transform:translateX(-50%) translateY(70px);background:rgba(26,26,46,0.96);border:1px solid rgba(0,214,143,0.2);border-radius:var(--rs);padding:8px 16px;font-size:10px;color:var(--g);opacity:0;transition:all .3s;z-index:999}
.ts.s{opacity:1;transform:translateX(-50%) translateY(0)}
@media(max-width:1024px){.g2{grid-template-columns:1fr}.g3{grid-template-columns:1fr 1fr}}
@media(max-width:700px){.g3{grid-template-columns:1fr}.gx{grid-template-columns:repeat(2,1fr)}}
@media(max-width:450px){.gx{grid-template-columns:1fr}.w{padding:8px}}
</style></head><body>
<div class=w>
<div class=hd><div class=hd-l><h1>👻 RG <span>PRO</span></h1></div><div class=hd-r><span class=stt id=stb><span class=dot id=std></span><span id=stl>Online</span></span></div></div>

<div class="g gx" id=rw1></div>

<div class="g g3">
<div class=sec><div class=sec-h><h2>🖥 System</h2><span id=upt style=font-size:10px;color:var(--t2)>—</span></div>
<div class=rs id=sys_rs></div></div>

<div class=sec><div class=sec-h><h2>📊 Traffic</h2></div>
<div class=tg><div><div class=ti-v id=td>—</div><div class=ti-l>Today</div></div><div><div class=ti-v id=mo>—</div><div class=ti-l>Month</div></div><div><div class=ti-v id=tot>—</div><div class=ti-l>Total</div></div></div>
<div class=sec-h style=margin:12px 0 6px><h2>🌐 Load</h2></div>
<div class=lg><div class=lgi><div class=lgi-v id=l1>—</div><div class=lgi-l>1m</div></div><div class=lgi><div class=lgi-v id=l5>—</div><div class=lgi-l>5m</div></div><div class=lgi><div class=lgi-v id=l15>—</div><div class=lgi-l>15m</div></div></div>
</div>

<div class=sec><div class=sec-h><h2>📡 Server</h2></div>
<div class=ir id=srv_ir></div></div>
</div>

<div class="g g2">
<div><div class=sec style=margin-bottom:10px><div class=sec-h><h2>🔗 Configs</h2><button class=ci-b onclick=cpA() style=padding:2px6px>📋 All</button></div>
<div class=cl id=cf></div></div>
<div class=sec><div class=sec-h><h2>📄 Subscription</h2></div>
<div style="display:grid;grid-template-columns:1fr;gap:6px">
<div class=ti style="text-align:left;padding:10px"><div class=ti-l style="margin-bottom:4px">🔗 Sub Link</div><div style="display:flex;gap:4px"><input readonly id=su value="—" style="flex:1;background:rgba(255,255,255,0.03);border:1px solid rgba(255,255,255,0.06);border-radius:5px;padding:6px 8px;color:var(--t2);font-size:9px;direction:ltr;font-family:monospace" onclick=this.select()><button class=ci-b onclick="navigator.clipboard.writeText(document.getElementById('su').value);to('✓ Copied')">Copy</button></div></div>
</div></div>

<div class=sec><div class=sec-h><h2>🔧 Services</h2><span style=font-size:9px;color:var(--t2) id=svc></span></div>
<div class=sv id=sv></div>
<div class=sec-h style=margin:12px 0 6px><h2>⚡ Actions</h2></div>
<div class=qa><span class=qab onclick=cpA()>📋 Copy All</span><span class=qab onclick=window.open('https://'+D+'/sub')>📥 Sub</span><span class=qab onclick=window.location.reload()>🔄 Refresh</span></div>
</div>

<div class="g g4">
<div class=sec><div class=sec-h><h2>🏷️ Links</h2></div>
<div class=ch id=qa></div></div>
<div class=sec><div class=sec-h><h2>💾 Storage</h2></div>
<div class=ir id=sto_ir></div></div>
<div class=sec><div class=sec-h><h2>🌍 Network</h2></div>
<div class=ir id=net_ir></div></div>
</div>

<footer class=ft><span>👻 RG PRO</span><span>🔗 <a href=https://github.com/sheshocked/RealityGhostPro target=_blank>GitHub</a></span><span>⚡ <span id=ftr>—</span></span></footer></div>
<div class=ts id=t></div>

<script>
var D='${DOMAIN}',U='${uuid}',P='${pubkey_line}';
var CS=[{s:'www.gstatic.com',l:'Google Static',e:'🟢',i:'6c17063bbbc2815f'},{s:'ajax.googleapis.com',l:'Google AJAX',e:'🟣',i:'45b782b0ab099836'},{s:'storage.googleapis.com',l:'Google Storage',e:'🟠',i:'2a24f880f00bd81c'},{s:'fonts.gstatic.com',l:'Google Fonts',e:'🔴',i:'5e477f536f9d3d13'},{s:'fonts.googleapis.com',l:'Google Fonts API',e:'🟤',i:'faf18e55b6abd0e5'},{s:'www.google.com',l:'Google',e:'🔵',i:'f3eb44acd99a0125'}];
function lk(c){return 'vless://'+U+'@'+D+':443?encryption=none&flow=xtls-rprx-vision&security=reality&fp=chrome&type=tcp&headerType=none&sni='+c.s+'&pbk='+P+'&sid='+c.i+'#'+encodeURIComponent(c.l)}
function to(m){var t=document.getElementById('t');t.textContent=m;t.classList.add('s');setTimeout(function(){t.classList.remove('s')},1400)}
function cp(s){var c=CS.find(function(x){return x.s===s});if(!c)return;navigator.clipboard.writeText(lk(c)).then(function(){to('✓ '+c.l)})||to('👆 Manual')}
function cpA(){var a=CS.map(function(x){return lk(x)}).join('\n')+'\nhttps://'+D+'/sub';navigator.clipboard.writeText(a).then(function(){to('✓ All copied')})||to('👆 Manual')}
function bd(){var h=document.getElementById('cf');h.innerHTML='';CS.forEach(function(c){var e=document.createElement('div');e.className='ci';e.onclick=function(){cp(c.s)};e.innerHTML='<div class=ci-l><strong>'+c.e+' '+c.l+'</strong><span class=ci-s>'+c.s+'</span></div><button class=ci-b onclick="event.stopPropagation();cp(\''+c.s+'\')">Copy</button>';h.appendChild(e)});var q=document.getElementById('qa');q.innerHTML='';CS.forEach(function(c){var e=document.createElement('span');e.className='chp';e.textContent=c.e+' '+c.l;e.onclick=function(){cp(c.s)};q.appendChild(e)});document.getElementById('su').value='https://'+D+'/sub'}
function fmt(b){if(!b||b==0)return'0 B';var u=['B','KB','MB','GB','TB'];var i=0;var n=Number(b);while(n>=1024&&i<u.length-1){n/=1024;i++}return n.toFixed(i==0?0:1)+' '+u[i]}
function fd(){var x=new XMLHttpRequest();x.open('GET','/status/stats.json?t='+Date.now(),true);x.timeout=5000;x.onload=function(){if(x.status!==200)return;try{var d=JSON.parse(x.responseText);
var r1=document.getElementById('rw1');r1.innerHTML='<div class=cd><div class=cd-l>🧠 RAM</div><div class=cd-v>'+d.ram.used+'<small>/'+d.ram.total+'MB</small></div></div><div class=cd><div class=cd-l>⚡ CPU</div><div class=cd-v>'+d.cpu+'<small>%</small></div></div><div class=cd><div class=cd-l>💾 Disk</div><div class=cd-v>'+d.disk.used+'<small>/'+d.disk.total+'</small></div></div><div class=cd><div class=cd-l>🔗 Connections</div><div class=cd-v>'+(d.connections||0)+'</div></div><div class=cd><div class=cd-l>🌐 Load 1m</div><div class=cd-v class=xs>'+d.load['1m']+'</div></div><div class=cd><div class=cd-l>🚀 Xray</div><div class=cd-v class=xs>'+d.xray_version+'</div></div>';
document.getElementById('upt').textContent='⏱ '+d.uptime;
document.getElementById('sys_rs').innerHTML='<div class=ri><div class=rl><span>RAM</span><span id=rp>—</span></div><div class=bc><div class="bf p" id=rf style=width:0%></div></div></div><div class=ri><div class=rl><span>CPU</span><span id=cp>—</span></div><div class=bc><div class="bf gr" id=cf style=width:0%></div></div></div><div class=ri><div class=rl><span>Disk</span><span id=dp>—</span></div><div class=bc><div class="bf yl" id=df style=width:0%></div></div></div><div class=ri><div class=rl><span>SWAP</span><span id=sp>—</span></div><div class=bc><div class="bf or" id=_sf style=width:0%></div></div></div>';
document.getElementById('rp').textContent=d.ram.usage.toFixed(0)+'%';document.getElementById('rf').style.width=Math.min(d.ram.usage,100)+'%';document.getElementById('cp').textContent=d.cpu+'%';document.getElementById('cf').style.width=Math.min(parseFloat(d.cpu)||0,100)+'%';document.getElementById('dp').textContent=d.disk.usage+'%';document.getElementById('df').style.width=Math.min(parseInt(d.disk.usage)||0,100)+'%';document.getElementById('sp').textContent='0%';document.getElementById('_sf').style.width='0%';
document.getElementById('td').textContent=fmt(d.traffic.today);document.getElementById('mo').textContent=fmt(d.traffic.month);document.getElementById('tot').textContent=fmt(d.traffic.total);
document.getElementById('l1').textContent=d.load['1m'];document.getElementById('l5').textContent=d.load['5m'];document.getElementById('l15').textContent=d.load['15m'];
document.getElementById('srv_ir').innerHTML='<div class=irow><span class=irow-l>🌐 IP</span><span class=irow-v style=color:var(--p2) id=sip>—</span></div><div class=irow><span class=irow-l>🧠 OS</span><span class=irow-v id=sos>Linux</span></div><div class=irow><span class=irow-l>⚡ CPU</span><span class=irow-v id=scpu>—</span></div><div class=irow><span class=irow-l>⏱ Uptime</span><span class=irow-v style=color:var(--g) id=sut>—</span></div><div class=irow><span class=irow-l>🚀 Xray</span><span class=irow-v style=color:var(--p2) id=sxr>—</span></div><div class=irow><span class=irow-l>🕐 Updated</span><span class=irow-v id=s_upd>—</span></div>';
document.getElementById('sut').textContent=d.uptime;document.getElementById('sxr').textContent=d.xray_version;document.getElementById('sip').textContent='${SERVER_IP}';document.getElementById('scpu').textContent='3 Cores';document.getElementById('sos').textContent='Ubuntu 24.04';
document.getElementById('s_upd').textContent=d.timestamp.slice(11,16)+' UTC';
var sv=document.getElementById('sv');s=d.services;sv.innerHTML='<div class="svc '+(s.nginx==='active'?'o':'x')+'">🌐 NGINX</div><div class="svc '+(s.xray==='active'?'o':'x')+'">🚀 Xray</div><div class="svc '+(s.monitor==='active'?'o':'x')+'">📡 Monitor</div><div class="svc '+(d.dns_ok?'o':'x')+'">🔒 SSL</div>';
var ct=Object.values(s).filter(function(v){return v==='active'}).length;document.getElementById('svc').textContent=ct+'/3';
var a=ct===3&&d.dns_ok;document.getElementById('stl').textContent=a?'Online':'⚠ Issues';document.getElementById('stb').className='stt'+(a?'':' r');document.getElementById('std').className='dot'+(a?'':' r');
document.getElementById('sto_ir').innerHTML='<div class=irow><span class=irow-l>Total</span><span class=irow-v id=_dkt style=color:var(--g)>—</span></div><div class=irow><span class=irow-l>Used</span><span class=irow-v id=_dku>—</span></div><div class=irow><span class=irow-l>Free</span><span class=irow-v style=color:var(--g) id=_dka>—</span></div>';
document.getElementById('_dkt').textContent=d.disk.total;document.getElementById('_dku').textContent=d.disk.used;document.getElementById('_dka').textContent=d.disk.avail;
document.getElementById('net_ir').innerHTML='<div class=irow><span class=irow-l>IPv4</span><span class=irow-v style=color:var(--p2)>${SERVER_IP}</span></div><div class=irow><span class=irow-l>DNS</span><span class=irow-v>9.9.9.9, 9.9.9.12</span></div><div class=irow><span class=irow-l>TCP CC</span><span class=irow-v style=color:var(--g)>BBR</span></div><div class=irow><span class=irow-l>Interface</span><span class=irow-v>eth0</span></div>';
document.getElementById('ftr').textContent='Updated '+d.timestamp.slice(11,16)+' UTC'}catch(e){}};x.send()}
bd();fd();setInterval(fd,5000);
</script></body></html>

HTMLEOF
  chown -R www-data:www-data "$STATUS_DIR" 2>/dev/null
  echo -e "${OK}Panel built"
}

install_monitor() {
  echo -e "${INFO}Installing monitor..."
  cat > "$MONITOR_SCRIPT" <<'MONEOF'
#!/bin/bash
S="/var/www/html/status/stats.json"; D="/usr/local/etc/xray"; X="/usr/local/bin/xray"; L="/var/log/xray"
mkdir -p /var/www/html/status
while true; do
  ram=$(free -m | awk '/Mem:/{printf "{\"total\":%d,\"used\":%d,\"usage\":%.1f}",$2,$3,$3/$2*100}')
  cpu=$(top -bn1 | grep "Cpu(s)" | awk '{printf "%.1f", $2+$4}')
  disk=$(df -m / | awk 'NR==2{printf "{\"total\":%d,\"used\":%d,\"usage\":%.1f}",$2,$4,$4/$2*100}')
  swap=$(free -m | awk '/Swap:/{printf "{\"total\":%d,\"used\":%d,\"usage\":%.1f}",$2,$3,$2>0?$3/$2*100:0}')
  load=$(uptime | awk -F'load average:' '{print $2}' | awk '{printf "{\"1m\":%s,\"5m\":%s,\"15m\":%s}",$1,$2,$3}')
  uptime_s=$(awk '{print int($1)}' /proc/uptime 2>/dev/null)
  dns=$(nslookup google.com >/dev/null 2>&1 && echo true || echo false)
  xv=$($X version 2>/dev/null | head -1 || echo "—")
  iface=$(ip route | grep default | awk '{print $5}' | head -1)
  stat=$(ss -tn | grep -c "ESTAB" 2>/dev/null)
  nginx_s=$(systemctl is-active nginx 2>/dev/null)
  xray_s=$(systemctl is-active xray 2>/dev/null)
  mon_s=$(systemctl is-active realityghost-monitor 2>/dev/null)
  cat > "$S" <<JSONEOF
{"ram":$ram,"cpu":$cpu,"disk":$disk,"swap":$swap,"load":$load,"uptime":$uptime_s,"dns_ok":$dns,"xray_version":"$xv","network":{"interface":"$iface"},"connections":$stat,"services":{"nginx":"$nginx_s","xray":"$xray_s","monitor":"$mon_s"}}
JSONEOF
  chmod 644 "$S"
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
  echo -e "${INFO}Public Key: $(/usr/local/bin/xray x25519 -i "$pbk" 2>/dev/null | grep -oP '(?<=Password: )\S+')${NC}"
  echo ""
  local idx=0
  for entry in "${SNI_LIST[@]}"; do
    IFS=':' read -r sni label label_url <<< "$entry"
    local sid=$(jq -r ".inbounds[0].streamSettings.realitySettings.shortIds[$idx]" "$CONFIG_DIR/config.json" 2>/dev/null)
    echo -e "  ${FLAG_RAW} ${label} → ${sni} sid: ${sid:0:16}.."
    idx=$((idx+1))
  done
  echo ""
  echo -e "${CYAN}📊 پنل:${NC} https://${DOMAIN}/status/"
  echo -e "${CYAN}📥 ساب:${NC} https://${DOMAIN}/sub"
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
      4) echo -e "UUID: $(jq -r '.inbounds[0].settings.clients[0].id' "$CONFIG_DIR/config.json")"
         echo -ne "\n${YELLOW}Enter...${NC}"; read -r ;;
      5) local u=$(jq -r '.inbounds[0].settings.clients[0].id' "$CONFIG_DIR/config.json")
         local l="vless://${u}@${DOMAIN}:443?flow=xtls-rprx-vision&encryption=none&security=reality&sni=www.gstatic.com&fp=chrome&pbk=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$CONFIG_DIR/config.json")&sid=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$CONFIG_DIR/config.json")#RG PRO"
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
  echo -e "${OK}چرخش هر ۳ روز تنظیم شد"
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
  chmod +x /usr/local/bin/rg-bot.py
  /usr/local/bin/rg-bot.py init
  echo -ne "${BOLD}Bot token (from BotFather): ${NC}"
  read -r bot_token
  [[ -z "$bot_token" ]] && { echo -e "${WARN}No token, bot disabled${NC}"; return; }
  mkdir -p /etc/realityghost
  echo "{\"enabled\":true,\"token\":\"$bot_token\",\"domain\":\"$DOMAIN\",\"admin_ids\":[]}" > /etc/realityghost/bot_config.json
  cat > /etc/systemd/system/realityghost-bot.service <<BOTEOF
[Unit]Description=RealityGhost Bot
After=network.target xray.service
[Service]Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/rg-bot.py runbot
Restart=always;RestartSec=5;User=root
[Install]WantedBy=multi-user.target
BOTEOF
  systemctl daemon-reload
  systemctl enable realityghost-bot 2>/dev/null
  systemctl restart realityghost-bot 2>/dev/null
  sleep 2
  systemctl is-active realityghost-bot &>/dev/null && echo -e "${OK}🤖 ربات فعال شد!" || echo -e "${WARN}ربات استارت نشد. journalctl -u realityghost-bot${NC}"
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
      5) echo -ne "آیدی: "; read -r id
         /usr/local/bin/rg-bot.py deluser "$id" 2>&1 || echo "❌"
         echo -ne "\n${YELLOW}Enter...${NC}"; read -r ;;
      6) /usr/local/bin/rg-bot.py stats 2>&1; echo -ne "\n${YELLOW}Enter...${NC}"; read -r ;;
      0) return ;;
    esac
  done
}

uninstall() {
  echo -e "${WARN}⚠ حذف کامل RealityGhost PRO${NC}"
  echo -ne "آیا مطمئنی؟ تایپ کن 'yes': "
  read -r ans
  [[ "$ans" != "yes" ]] && { echo -e "${INFO}لغو شد${NC}"; return; }
  systemctl stop xray nginx realityghost-monitor realityghost-bot 2>/dev/null
  systemctl disable xray realityghost-monitor realityghost-bot 2>/dev/null
  rm -rf "$INSTALL_DIR" "$CONFIG_DIR" "$STATUS_DIR" "$STATE_DIR" "$SUB_DIR"
  rm -f /etc/systemd/system/xray.service /etc/systemd/system/realityghost-monitor.service /etc/systemd/system/realityghost-bot.service
  rm -f "$MONITOR_SCRIPT" /etc/cron.d/realityghost-rotate /etc/nginx/nginx.conf
  cp /etc/nginx/nginx.conf.backup /etc/nginx/nginx.conf 2>/dev/null
  rm -f /etc/sysctl.d/99-realityghost.conf /etc/realityghost/bot_config.json /etc/realityghost/users.db
  systemctl daemon-reload
  systemctl restart nginx 2>/dev/null
  echo -e "${OK}حذف کامل شد"
}

# ─── Main ────────────────────────────────────────────────────────────

main_install() {
  echo ""
  if command -v figlet &>/dev/null; then
    while IFS= read -r line; do printf "${PURPLE}%s${NC}\n" "$line"; done < <(figlet -f slant "RG PRO" 2>/dev/null)
  else
    echo -e "${PURPLE}  ██████╗  ██████╗     ██████╗ ██████╗  ██████╗ ${NC}"
    echo -e "${PURPLE}  ██╔════╝ ██╔════╝     ██╔══██╗██╔══██╗██╔═══██╗${NC}"
    echo -e "${PURPLE}  ██║  ███╗██████╗      ██████╔╝██████╔╝██║   ██║${NC}"
    echo -e "${PURPLE}  ██║   ██║██╔═══╝      ██╔══██╗██╔═══╝ ██║   ██║${NC}"
    echo -e "${PURPLE}  ╚██████╔╝██████╗      ██║  ██║██║     ╚██████╔╝${NC}"
    echo -e "${PURPLE}   ╚═════╝ ╚═════╝      ╚═╝  ╚═╝╚═╝      ╚═════╝ ${NC}"
  fi
  echo -e "${PURPLE}  ─────────────────────────────────────────────${NC}"
  echo -e "${PURPLE}  Xray VLESS+Reality — Install & Manage${NC}"
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
  setup_rotation
  for p in 443 80; do
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
  echo -e "${GREEN}║  نصب با موفقیت تموم شد! 🎉   ║${NC}"
  echo -e "${GREEN}╚═══════════════════════════════╝${NC}"
  echo -e "  📊 پنل:  https://${DOMAIN}/status/"
  echo -e "  📥 ساب:  https://${DOMAIN}/sub"
  show_info
}

manage_menu() {
  while true; do
    clear
    if command -v figlet &>/dev/null; then
      while IFS= read -r line; do printf "${PURPLE}%s${NC}\n" "$line"; done < <(figlet -f slant "RG PRO" 2>/dev/null)
    else
      echo -e "${PURPLE}  ██████╗  ██████╗     ██████╗ ██████╗  ██████╗ ${NC}"
      echo -e "${PURPLE}  ██╔════╝ ██╔════╝     ██╔══██╗██╔══██╗██╔═══██╗${NC}"
      echo -e "${PURPLE}  ██║  ███╗██████╗      ██████╔╝██████╔╝██║   ██║${NC}"
      echo -e "${PURPLE}  ██║   ██║██╔═══╝      ██╔══██╗██╔═══╝ ██║   ██║${NC}"
      echo -e "${PURPLE}  ╚██████╔╝██████╗      ██║  ██║██║     ╚██████╔╝${NC}"
      echo -e "${PURPLE}   ╚═════╝ ╚═════╝      ╚═╝  ╚═╝╚═╝      ╚═════╝ ${NC}"
    fi
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
  if curl -sk --max-time 3 "https://127.0.0.1:8443/status/" > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} Panel (8443)"
  else
    echo -e "  ${RED}✗${NC} Panel (8443)"
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
  manage) check_root; detect_location; manage_menu ;;
  manual-rotate) check_root; manual_rotate ;;
  pull) check_root; pull_update ;;
  uninstall) check_root; uninstall ;;
  *)
    echo ""
    if command -v figlet &>/dev/null; then
      while IFS= read -r line; do printf "${PURPLE}%s${NC}\n" "$line"; done < <(figlet -f slant "RG PRO" 2>/dev/null)
    else
      echo -e "${PURPLE}  ██████╗  ██████╗     ██████╗ ██████╗  ██████╗ ${NC}"
      echo -e "${PURPLE}  ██╔════╝ ██╔════╝     ██╔══██╗██╔══██╗██╔═══██╗${NC}"
      echo -e "${PURPLE}  ██║  ███╗██████╗      ██████╔╝██████╔╝██║   ██║${NC}"
      echo -e "${PURPLE}  ██║   ██║██╔═══╝      ██╔══██╗██╔═══╝ ██║   ██║${NC}"
      echo -e "${PURPLE}  ╚██████╔╝██████╗      ██║  ██║██║     ╚██████╔╝${NC}"
      echo -e "${PURPLE}   ╚═════╝ ╚═════╝      ╚═╝  ╚═╝╚═╝      ╚═════╝ ${NC}"
    fi
    echo -e "${PURPLE}  ─────────────────────────────────────────────${NC}"
    echo -e "${PURPLE}  Xray VLESS+Reality — Install & Manage${NC}"
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
