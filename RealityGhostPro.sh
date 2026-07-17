#!/bin/bash
# RealityGhost PRO v4.2 — Xray VLESS+Reality installer & manager

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; PURPLE='\033[0;35m'; WHITE='\033[1;37m'
BOLD='\033[1m'; NC='\033[0m'
INFO="${CYAN}[ℹ]${NC}"; OK="${GREEN}[✓]${NC}"; ERR="${RED}[✗]${NC}"; WARN="${YELLOW}[⚠]${NC}"

DOMAIN="${DOMAIN:-}"; EMAIL="${EMAIL:-}"
SUB_PORT="8443"; XRAY_TCP_PORT="8444"
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
  local data=$(curl -4 -s --max-time 4 "http://ip-api.com/json/" 2>/dev/null)
  local country=$(echo "$data" | jq -r '.countryCode // "US"' 2>/dev/null)
  local ip=$(echo "$data" | jq -r '.query // ""' 2>/dev/null)
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
  echo -e "${INFO}بررسی سیستم..."
  grep -q "Ubuntu\|Debian" /etc/os-release 2>/dev/null || echo -e "${WARN}فقط اوبونتو/دبیان تست شده"
  local ports=("443" "${XRAY_TCP_PORT}" "${SUB_PORT}")
  for p in "${ports[@]}"; do
    if ss -tlnp | grep -q ":${p} "; then
      local proc=$(ss -tlnp | grep ":${p} " | awk '{print $7}' | tr -d '"')
      echo -e "${WARN}پورت ${p} توسط ${proc:-?} اشغال شده"
      echo -ne "${INFO}آزادش کنم؟ (y/n): "
      read -r ans
      if [[ "$ans" == "y" || "$ans" == "Y" ]]; then
        local pid=$(ss -tlnp | grep ":${p} " | grep -oP 'pid=\K[0-9]+')
        [[ -n "$pid" ]] && kill -9 "$pid" 2>/dev/null
        echo -e "${OK}پورت ${p} آزاد شد"
      else
        echo -e "${ERR}پورت ${p} اشغاله، لطفاً آزادش کن${NC}"
        exit 1
      fi
    fi
  done
  nslookup google.com >/dev/null 2>&1 || dig google.com >/dev/null 2>&1 || {
    echo -e "${WARN}DNS کار نمی‌کنه. ادامه بدیم؟ (y/n): "
    read -r ans
    [[ "$ans" != "y" && "$ans" != "Y" ]] && exit 1
  }
  ping -4 -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 || echo -e "${WARN}IPv4 تأیید نشد"
}

install_dependencies() {
  echo -e "${INFO}نصب پیش‌نیازها..."
  apt-get update -y
  apt-get install -y wget curl unzip uuid-runtime jq qrencode certbot \
    nginx-extras logrotate bc netcat-openbsd dnsutils python3 python3-pip sqlite3 figlet
  pip3 install python-telegram-bot requests --break-system-packages -q 2>/dev/null || \
    echo -e "${WARN}نصب پکیج‌های ربات ناموفق"
  echo -e "${OK}پیش‌نیازها نصب شدن"
}

system_tuning() {
  echo -e "${INFO}بهینه‌سازی سیستم..."
  if [[ "$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')" != "bbr" ]]; then
    modprobe tcp_bbr 2>/dev/null
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.d/99-realityghost.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.d/99-realityghost.conf
    echo -e "${OK}BBR فعال شد"
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
  echo -e "${INFO}نصب Xray..."
  mkdir -p "$INSTALL_DIR" "$CONFIG_DIR"
  if command -v /usr/local/bin/xray &>/dev/null; then
    echo -e "${OK}Xray از قبل نصب بود"
    return 0
  fi
  local url=$(curl -sL https://api.github.com/repos/XTLS/Xray-core/releases/latest 2>/dev/null | jq -r '.assets[] | select(.name | test("linux-64")) | .browser_download_url' 2>/dev/null | head -1)
  [[ -z "$url" ]] && { echo -e "${ERR}دانلود Xray ناموفق${NC}"; exit 1; }
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
  echo -e "${OK}Xray نصب شد ($(/usr/local/bin/xray version 2>/dev/null | head -1))"
}

install_certbot() {
  if [[ -z "$DOMAIN" ]]; then
    echo -ne "${INFO}دامنه (your-domain.com): "; read -r DOMAIN
  fi
  if [[ -z "$EMAIL" ]]; then
    echo -ne "${INFO}ایمیل (برای Let's Encrypt): "; read -r EMAIL
  fi
  if [[ -d "/etc/letsencrypt/live/${DOMAIN}" ]]; then
    echo -e "${OK}SSL از قبل هست"
    return 0
  fi
  echo -e "${INFO}دریافت SSL از Let's Encrypt..."
  systemctl stop nginx 2>/dev/null
  certbot certonly --standalone --non-interactive --agree-tos -d "${DOMAIN}" -m "${EMAIL}" 2>/dev/null
  systemctl start nginx 2>/dev/null
  if [[ -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]]; then
    echo -e "${OK}SSL دریافت شد"
    (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet --post-hook 'systemctl reload nginx'") | crontab -
  else
    echo -e "${ERR}SSL دریافت نشد. مطمئن شو دامنه به IP سرور خورده باشه${NC}"
    exit 1
  fi
}

configure_nginx() {
  echo -e "${INFO}پیکربندی NGINX..."
  cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup 2>/dev/null
  cat > /etc/nginx/nginx.conf <<NGINXEOF
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;
events { worker_connections 768; }
stream {
    map \$ssl_preread_server_name \$backend {
        ${DOMAIN} nginx_https;
        sub.${DOMAIN} nginx_https;
        default xray_tcp;
    }
    upstream xray_tcp { server 127.0.0.1:${XRAY_TCP_PORT}; }
    upstream nginx_https { server 127.0.0.1:${SUB_PORT}; }
    server {
        listen 443;
        proxy_pass \$backend;
        ssl_preread on;
    }
}
http {
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
  echo -e "${OK}NGINX پیکربندی شد"
}

configure_xray() {
  echo -e "${INFO}پیکربندی Xray..."
  local uuid=$(generate_uuid)
  local keys=$(generate_reality_keys)
  local private_key=$(echo "$keys" | cut -d':' -f1)
  local public_key=$(echo "$keys" | cut -d':' -f2)
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
    "port": ${XRAY_TCP_PORT}, "listen": "127.0.0.1", "protocol": "vless",
    "settings": {
      "clients": [{ "id": "${uuid}", "flow": "xtls-rprx-vision", "level": 0, "email": "user@${DOMAIN}" }],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp", "security": "reality",
      "realitySettings": {
        "show": false, "dest": "www.gstatic.com:443", "xver": 0,
        "serverNames": [${snis_json},${extra_snis}],
        "privateKey": "${private_key}",
        "shortIds": [${sids_json}]
      }
    },
    "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"] }
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
  echo -e "${OK}Xray پیکربندی شد"
}

build_subscription() {
  local uuid=$(jq -r '.inbounds[0].settings.clients[0].id' "$CONFIG_DIR/config.json" 2>/dev/null)
  local pbk=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$CONFIG_DIR/config.json" 2>/dev/null)
  [[ -z "$uuid" || -z "$pbk" ]] && { echo -e "${ERR}خطا در خوندن کانفیگ${NC}"; return 1; }
  local pubkey=""
  local keys=$(/usr/local/bin/xray x25519 -i "$pbk" 2>/dev/null)
  pubkey=$(echo "$keys" | grep "Public" | awk '{print $3}')
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
  echo -e "${OK}ساب ساخته شد (۶ کانفیگ)"
}

build_panel() {
  local uuid=$(jq -r '.inbounds[0].settings.clients[0].id' "$CONFIG_DIR/config.json" 2>/dev/null)
  local pbk=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0] // ""' "$CONFIG_DIR/config.json" 2>/dev/null)
  local pubkey_line=$(/usr/local/bin/xray x25519 -i "$pbk" 2>/dev/null | grep "Public" | awk '{print $3}')
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
<!DOCTYPE html><html lang="fa" dir="rtl"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>RG PRO • وضعیت سرور</title>
<style>
*,*::before,*::after{margin:0;padding:0;box-sizing:border-box}
:root{--bg:#07070f;--bg2:#0b0b16;--card:rgba(14,14,40,0.7);--card2:rgba(18,18,50,0.5);--border:rgba(90,110,255,0.08);--text:#dcdcf0;--text2:#7878b0;--purple:#7c5cfc;--purple2:#a078ff;--green:#00d68f;--blue:#4a9eff;--yellow:#f0a030;--red:#f05060;--radius:18px;--radius-sm:12px;--shadow:0 8px 40px rgba(0,0,0,0.6)}
body{font-family:'Vazirmatn',sans-serif;background:var(--bg);color:var(--text);direction:rtl;background-image:radial-gradient(ellipse at 15% 30%,rgba(124,92,252,0.05) 0%,transparent 60%)}
.wrap{max-width:1260px;margin:0 auto;padding:16px}
.hdr{display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:12px;padding:14px 20px;margin-bottom:20px;background:var(--card);border:1px solid var(--border);border-radius:var(--radius);backdrop-filter:blur(16px)}
.hdr-t h1{font-size:17px;font-weight:800}.hdr-t p{font-size:12px;color:var(--text2)}
.hdr-b{padding:4px 12px;border-radius:100px;font-size:10px;font-weight:600;display:inline-flex;align-items:center;gap:4px}
.hdr-b.live{background:rgba(0,214,143,0.1);color:var(--green);border:1px solid rgba(0,214,143,0.15)}
.hdr-dot{display:inline-block;width:6px;height:6px;border-radius:50%;background:var(--green);animation:pulse 2s infinite}
.sr{display:grid;grid-template-columns:repeat(6,1fr);gap:12px;margin-bottom:20px}
.sc{background:var(--card);border:1px solid var(--border);border-radius:var(--radius-sm);padding:14px 16px;min-height:90px}
.sc:hover{background:var(--card2);border-color:var(--border2);transform:translateY(-2px)}
.sc-l{font-size:11px;color:var(--text2)}.sc-v{font-size:22px;font-weight:800;direction:ltr}
.g2{display:grid;grid-template-columns:2.2fr 1fr;gap:20px;margin-bottom:20px}
.sec{background:var(--card);border:1px solid var(--border);border-radius:var(--radius);padding:20px;backdrop-filter:blur(12px)}
.sec-h{display:flex;justify-content:space-between;align-items:center;margin-bottom:16px;padding-bottom:12px;border-bottom:1px solid rgba(90,110,255,0.06)}
.sec-t{font-size:14px;font-weight:700;display:flex;align-items:center;gap:8px}
.rg{display:flex;flex-direction:column;gap:14px}
.ri-bar{height:6px;border-radius:100px;background:rgba(255,255,255,0.03);overflow:hidden}
.ri-fill{height:100%;border-radius:100px;transition:width 1.2s cubic-bezier(0.22,1,0.36,1)}
.ri-fill.b{background:linear-gradient(90deg,#5a3fd4,#7c5cfc)}.ri-fill.g{background:linear-gradient(90deg,#00b87a,#00d68f)}
.ri-fill.y{background:linear-gradient(90deg,#d49020,#f0a030)}.ri-fill.r{background:linear-gradient(90deg,#d04048,#f05060)}
.tg{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin-top:12px}
.ti{text-align:center;padding:12px;border-radius:var(--radius-sm);background:rgba(255,255,255,0.02)}
.sg{display:grid;grid-template-columns:1fr 1fr;gap:10px}
.scd{background:rgba(255,255,255,0.02);border:1px solid rgba(255,255,255,0.04);border-radius:var(--radius-sm);padding:14px;text-align:center}
.scd-s{font-size:11px;font-weight:600}.up{color:var(--green)}.down{color:var(--red)}
.ll{display:flex;flex-direction:column;gap:8px}
.li{display:flex;align-items:center;gap:10px;padding:12px 16px;border-radius:var(--radius-sm);background:rgba(255,255,255,0.02);border:1px solid rgba(255,255,255,0.04);text-decoration:none;color:var(--text);cursor:pointer;flex-wrap:wrap}
.li:hover{background:rgba(124,92,252,0.06);border-color:rgba(124,92,252,0.15)}
.li-t{flex:1;min-width:180px}.li-t strong{display:block;font-size:12px}
.li-sni{font-size:10px;color:var(--purple2);direction:ltr;display:block}
.li-sid{font-size:9px;color:var(--text3);direction:ltr;display:block;font-family:monospace}
.li-c{font-size:10px;padding:3px 10px;border-radius:6px;background:rgba(255,255,255,0.05);color:var(--text2);border:none;cursor:pointer}
.li-c:hover{background:rgba(124,92,252,0.15);color:var(--purple2)}
.chips{display:flex;gap:10px;flex-wrap:wrap;margin-top:14px}
.chip{display:flex;align-items:center;gap:5px;padding:6px 12px;border-radius:100px;font-size:11px;background:rgba(255,255,255,0.02)}
.chip-dot{width:6px;height:6px;border-radius:50%}.chip-dot.ok{background:var(--green)}
.sysg{display:grid;grid-template-columns:repeat(4,1fr);gap:12px}
.sysc{background:rgba(255,255,255,0.02);border:1px solid rgba(255,255,255,0.04);border-radius:var(--radius-sm);padding:14px;text-align:center}
.sysc-v{font-size:19px;font-weight:700;direction:ltr}
.ftr{text-align:center;padding:20px 0;font-size:11px;color:var(--text3);border-top:1px solid rgba(255,255,255,0.02);margin-top:24px}
.toast{position:fixed;bottom:30px;left:50%;transform:translateX(-50%) translateY(80px);background:rgba(14,14,40,0.95);border:1px solid rgba(0,214,143,0.3);border-radius:var(--radius-sm);padding:10px 20px;font-size:13px;color:var(--green);opacity:0;transition:all .35s;z-index:999}
.toast.show{opacity:1;transform:translateX(-50%) translateY(0)}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:0.4}}
@media(max-width:640px){.sr{grid-template-columns:repeat(2,1fr)}.li{flex-direction:column}.g2{grid-template-columns:1fr}}
</style></head><body>
<div class="wrap" id="app">
<header class="hdr"><div class="hdr-t"><h1>RealityGhost <span style="color:var(--purple2)">PRO</span></h1><p>${DOMAIN}</p></div><div class="hdr-l"><span class="hdr-b live"><span class="hdr-dot"></span> آنلاین</span></div></header>
<div class="sr" id="sr">
<div class="sc"><span class="sc-l">📥 دانلود امروز</span><div class="sc-v" id="s-dl">—</div></div>
<div class="sc"><span class="sc-l">📤 آپلود امروز</span><div class="sc-v" id="s-ul">—</div></div>
<div class="sc"><span class="sc-l">📊 مصرف ماه</span><div class="sc-v" id="s-month">—</div></div>
<div class="sc"><span class="sc-l">🔗 اتصالات</span><div class="sc-v" id="s-conn">—</div></div>
<div class="sc"><span class="sc-l">⏱️ آپتایم</span><div class="sc-v" id="s-uptime">—</div></div>
<div class="sc"><span class="sc-l">📡 کل ترافیک</span><div class="sc-v" id="s-total">—</div></div>
</div>
<div class="g2"><div>
<div class="sec" style="margin-bottom:20px"><div class="sec-h"><div class="sec-t">🖥️ منابع</div></div>
<div class="rg">
<div class="ri"><div class="ri-bar"><div class="ri-fill b" id="ram-f" style="width:0%"></div></div></div>
<div class="ri"><div class="ri-bar"><div class="ri-fill g" id="cpu-f" style="width:0%"></div></div></div>
<div class="ri"><div class="ri-bar"><div class="ri-fill y" id="disk-f" style="width:0%"></div></div></div>
</div></div></div><div>
<div class="sec" style="margin-bottom:20px"><div class="sec-h"><div class="sec-t">🔧 سرویس‌ها</div></div>
<div class="sg">
<div class="scd"><div class="scd-s up" id="ns">🌐 NGINX</div></div>
<div class="scd"><div class="scd-s up" id="xs">🚀 Xray</div></div>
<div class="scd"><div class="scd-s up" id="ms">📡 Monitor</div></div>
<div class="scd"><div class="scd-s up" id="ss">🔒 SSL</div></div>
</div></div>
<div class="sec"><div class="sec-h"><div class="sec-t">🔗 لینک‌ها</div><button class="li-c" onclick="cpAll()">📋 کپی همه</button></div>
<div class="ll" id="links-list"></div></div></div></div></div>
<div class="toast" id="toast"></div>
<script>
var D='${DOMAIN}',U='${uuid}',P='${pubkey_line}';
var CONFIGS=[${configs_js}];
function buildLink(c){return 'vless://'+U+'@'+D+':443?encryption=none&flow=xtls-rprx-vision&security=reality&sni='+c.sni+'&fp=chrome&pbk='+P+'&sid='+c.sid+'&type=tcp#RGPro-'+c.label}
function toast(m){var t=document.getElementById('toast');t.textContent=m;t.classList.add('show');setTimeout(function(){t.classList.remove('show')},1800)}
function cp(s){var c=CONFIGS.find(function(x){return x.sni===s});var t=c?buildLink(c):(s==='sub'?'https://'+D+'/sub':'');if(!t)return;navigator.clipboard&&navigator.clipboard.writeText(t).then(function(){toast('✓ کپی شد')})||toast('👆 کپی دستی')}
function cpAll(){var a=CONFIGS.map(function(x){return buildLink(x)}).join('\\n')+'\\nhttps://'+D+'/sub';navigator.clipboard&&navigator.clipboard.writeText(a).then(function(){toast('✓ همه کپی شد')})||toast('👆 کپی دستی')}
function buildLinks(){var b=document.getElementById('links-list');if(!b)return;b.innerHTML='';CONFIGS.forEach(function(c){var e=document.createElement('div');e.className='li';e.onclick=function(){cp(c.sni)};e.innerHTML='<div class="li-t"><strong>'+c.label+'</strong><span class="li-sni">sni: '+c.sni+'</span><span class="li-sid">sid: '+c.sid+'</span></div><span class="li-c" onclick="event.stopPropagation();cp(\''+c.sni+'\')">📋 کپی</span>';b.appendChild(e)})}
function fetchData(){var x=new XMLHttpRequest();x.open('GET','/status/stats.json?t='+Date.now(),true);x.timeout=5000;x.onload=function(){if(x.status===200){try{var d=JSON.parse(x.responseText);var e=document.getElementById('s-dl');if(e)e.textContent=d.dl||'—'}catch(e){}}};x.send()}
buildLinks();fetchData();setInterval(fetchData,3000);
</script></body></html>
HTMLEOF
  chown -R www-data:www-data "$STATUS_DIR" 2>/dev/null
  echo -e "${OK}پنل ساخته شد"
}

install_monitor() {
  echo -e "${INFO}نصب مانیتور..."
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
  echo -e "${OK}مانیتور نصب شد"
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
  echo -e "${INFO}Public Key: $(/usr/local/bin/xray x25519 -i "$pbk" 2>/dev/null | grep Public | awk '{print $3}')${NC}"
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
         echo -e "${OK}Short IDs چرخیدن${NC}"
         echo -ne "\n${YELLOW}Enter...${NC}"; read -r ;;
      4) echo -e "UUID: $(jq -r '.inbounds[0].settings.clients[0].id' "$CONFIG_DIR/config.json")"
         echo -ne "\n${YELLOW}Enter...${NC}"; read -r ;;
      5) local u=$(jq -r '.inbounds[0].settings.clients[0].id' "$CONFIG_DIR/config.json")
         local l="vless://${u}@${DOMAIN}:443?flow=xtls-rprx-vision&encryption=none&security=reality&sni=www.gstatic.com&fp=chrome&pbk=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$CONFIG_DIR/config.json")&sid=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$CONFIG_DIR/config.json")#RGPro"
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
  echo -e "${OK}Short IDs چرخیدن"
}

pull_update() {
  echo -e "${INFO}بررسی بروزرسانی..."
  local repo_url="https://github.com/sheshocked/RealityGhostPro.git"
  local script_dir="$(cd "$(dirname "$0")" && pwd)"
  local backup_dir="/tmp/realityghost-backup-$(date +%s)"
  if ! command -v git &>/dev/null; then apt-get install -y git 2>/dev/null || {
    echo -e "${ERR}git نصب نشد${NC}"; return 1; }; fi
  cd "$script_dir" || return 1
  if [[ ! -d .git ]]; then
    echo -e "${WARN}پوشه .git پیدا نشد. کلون می‌کنم..."
    cd /tmp || return 1; rm -rf RealityGhostPro-tmp
    git clone "$repo_url" RealityGhostPro-tmp 2>&1 || { echo -e "${ERR}کلون ناموفق${NC}"; return 1; }
    cp -r "$script_dir" "$backup_dir" 2>/dev/null
    cp -rf /tmp/RealityGhostPro-tmp/* "$script_dir/"; rm -rf /tmp/RealityGhostPro-tmp
    chmod +x "$script_dir/RealityGhostPro.sh"
    echo -e "${OK}بروزرسانی شد! بکاپ: ${backup_dir}${NC}"
    return 0
  fi
  cp -r "$script_dir" "$backup_dir" 2>/dev/null
  git stash 2>/dev/null
  local old_hash=$(git rev-parse HEAD)
  git pull origin main 2>&1 || { echo -e "${ERR}git pull ناموفق${NC}"; return 1; }
  local new_hash=$(git rev-parse HEAD)
  local changes=$(git rev-list --count "$old_hash..$new_hash" 2>/dev/null)
  echo -e "${OK}بروزرسانی شد (${changes:-?} تغییر)"
  echo -e "${INFO}${old_hash:0:8} → ${new_hash:0:8}${NC}"
  chmod +x "$script_dir/RealityGhostPro.sh"
}

bot_setup() {
  echo -e "${INFO}نصب ربات تلگرام..."
  chmod +x /usr/local/bin/rg-bot.py
  /usr/local/bin/rg-bot.py init
  echo -ne "${BOLD}توکن ربات (از BotFather): ${NC}"
  read -r bot_token
  [[ -z "$bot_token" ]] && { echo -e "${WARN}بدون توکن، ربات فعال نمیشه${NC}"; return; }
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
  echo -e "${PURPLE}  ██████╗  ██████╗     ██████╗ ██████╗  ██████╗ ${NC}"
  echo -e "${PURPLE}  ██╔════╝ ██╔════╝     ██╔══██╗██╔══██╗██╔═══██╗${NC}"
  echo -e "${PURPLE}  ██║  ███╗██████╗      ██████╔╝██████╔╝██║   ██║${NC}"
  echo -e "${PURPLE}  ██║   ██║██╔═══╝      ██╔══██╗██╔═══╝ ██║   ██║${NC}"
  echo -e "${PURPLE}  ╚██████╔╝██████╗      ██║  ██║██║     ╚██████╔╝${NC}"
  echo -e "${PURPLE}   ╚═════╝ ╚═════╝      ╚═╝  ╚═╝╚═╝      ╚═════╝ ${NC}"
  echo -e "${PURPLE}  ─────────────────────────────────────────────${NC}"
  echo -e "${PURPLE}  Xray VLESS+Reality Installer & Manager${NC}"
  echo -e "${PURPLE}  ─────────────────────────────────────────────${NC}"
  check_root
  detect_location
  echo -e "${INFO}${FLAG_RAW} ${LOC}${NC}"
  if [[ -z "$DOMAIN" ]]; then echo -ne "${BOLD}🌐 دامنه (your-domain.com): ${NC}"; read -r DOMAIN; fi
  if [[ -z "$EMAIL" ]]; then echo -ne "${BOLD}📧 ایمیل (برای SSL): ${NC}"; read -r EMAIL; fi
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
  echo -ne "${YELLOW}ربات تلگرام نصب کنم؟ (y/n): ${NC}"; read -r setup_bot
  [[ "$setup_bot" == "y" || "$setup_bot" == "Y" ]] && bot_setup
  systemctl restart nginx xray realityghost-monitor
  echo -e "${GREEN}╔════════════════════════════════╗${NC}"
  echo -e "${GREEN}║   نصب با موفقیت تکمیل شد! 🎉  ║${NC}"
  echo -e "${GREEN}╚════════════════════════════════╝${NC}"
  echo -e "  📊 پنل:  https://${DOMAIN}/status/"
  echo -e "  📥 ساب:  https://${DOMAIN}/sub"
  show_info
}

manage_menu() {
  while true; do
    clear
    echo -e "${PURPLE}  ██████╗  ██████╗     ██████╗ ██████╗  ██████╗ ${NC}"
    echo -e "${PURPLE}  ██╔════╝ ██╔════╝     ██╔══██╗██╔══██╗██╔═══██╗${NC}"
    echo -e "${PURPLE}  ██║  ███╗██████╗      ██████╔╝██████╔╝██║   ██║${NC}"
    echo -e "${PURPLE}  ██║   ██║██╔═══╝      ██╔══██╗██╔═══╝ ██║   ██║${NC}"
    echo -e "${PURPLE}  ╚██████╔╝██████╗      ██║  ██║██║     ╚██████╔╝${NC}"
    echo -e "${PURPLE}   ╚═════╝ ╚═════╝      ╚═╝  ╚═╝╚═╝      ╚═════╝ ${NC}"
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
    echo "9. 🗑️ Uninstall"
    echo "0. Exit"
    echo -ne "${BOLD}Choice: ${NC}"; read -r opt
    case $opt in
      1) show_info; echo -ne "\n${YELLOW}Enter...${NC}"; read -r ;;
      2) config_manager ;;
      3) port_manager ;;
      4) manual_rotate; echo -ne "\n${YELLOW}Enter...${NC}"; read -r ;;
      5) build_subscription; build_panel; echo -e "${OK}بازسازی شد${NC}"; echo -ne "\n${YELLOW}Enter...${NC}"; read -r ;;
      6) systemctl restart nginx xray realityghost-monitor; echo -e "${OK}ری‌استارت شد${NC}"; echo -ne "\n${YELLOW}Enter...${NC}"; read -r ;;
      7) bot_menu ;;
      8) pull_update; echo -ne "\n${YELLOW}Enter...${NC}"; read -r ;;
      9) uninstall; break ;;
      0) exit 0 ;;
      *) echo -e "${WARN}نامعتبر${NC}"; sleep 1 ;;
    esac
  done
}

case "${1:-}" in
  install) main_install ;;
  manage) check_root; detect_location; manage_menu ;;
  manual-rotate) check_root; manual_rotate ;;
  pull) check_root; pull_update ;;
  uninstall) check_root; uninstall ;;
  *)
    echo ""
    echo -e "${PURPLE}  ██████╗  ██████╗     ██████╗ ██████╗  ██████╗ ${NC}"
    echo -e "${PURPLE}  ██╔════╝ ██╔════╝     ██╔══██╗██╔══██╗██╔═══██╗${NC}"
    echo -e "${PURPLE}  ██║  ███╗██████╗      ██████╔╝██████╔╝██║   ██║${NC}"
    echo -e "${PURPLE}  ██║   ██║██╔═══╝      ██╔══██╗██╔═══╝ ██║   ██║${NC}"
    echo -e "${PURPLE}  ╚██████╔╝██████╗      ██║  ██║██║     ╚██████╔╝${NC}"
    echo -e "${PURPLE}   ╚═════╝ ╚═════╝      ╚═╝  ╚═╝╚═╝      ╚═════╝ ${NC}"
    echo -e "${PURPLE}  ─────────────────────────────────────────────${NC}"
    echo -e "${PURPLE}  Xray VLESS+Reality Installer & Manager${NC}"
    echo -e "${PURPLE}  ─────────────────────────────────────────────${NC}"
    echo ""
    echo -e "  ${GREEN}install${NC}     — Install Xray Reality on your server"
    echo -e "  ${GREEN}manage${NC}      — Management menu"
    echo -e "  ${GREEN}manual-rotate${NC}— Rotate Short IDs manually"
    echo -e "  ${GREEN}pull${NC}         — Update from GitHub"
    echo -e "  ${GREEN}uninstall${NC}   — Remove everything"
    echo ""
    ;;
esac
