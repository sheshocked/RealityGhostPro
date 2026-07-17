#!/bin/bash

# ─── RealityGhost PRO v4.2 ───────────────────────────────────────────
#  تولید کننده پیشرفته Xray VLESS+Reality با پنل مدیریت فارسی
#  قابلیت‌ها: ۶ SNI گوگل، ساب‌اسکریپشن، پنل وضعیت، مدیریت پورت،
#             تشخیص خودکار خطاها، تشخیص موقعیت IP
# ─────────────────────────────────────────────────────────────────────

# ─── Colors ──────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; PURPLE='\033[0;35m'; WHITE='\033[1;37m'
BOLD='\033[1m'; NC='\033[0m'
INFO="${CYAN}[ℹ]${NC}"; OK="${GREEN}[✓]${NC}"; ERR="${RED}[✗]${NC}"; WARN="${YELLOW}[⚠]${NC}"

# ─── Default Variables ───────────────────────────────────────────────
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

# ─── Google SNI List (6 targets, each gets a UNIQUE random ShortId per install) ─
SNI_LIST=(
  "www.gstatic.com:Google Static:Google%20Static"
  "ajax.googleapis.com:Google AJAX:Google%20AJAX"
  "storage.googleapis.com:Google Storage:Google%20Storage"
  "fonts.gstatic.com:Google Fonts:Google%20Fonts"
  "fonts.googleapis.com:Google Fonts API:Google%20Fonts%20API"
  "www.google.com:Google:Google"
)

# ─── Detect Server Location & Flag ───────────────────────────────
detect_location() {
  local ip=""
  ip=$(curl -4 -s --max-time 3 https://ifconfig.me 2>/dev/null)
  [[ -z "$ip" ]] && ip=$(curl -4 -s --max-time 3 https://api.ipify.org 2>/dev/null)
  [[ -z "$ip" ]] && ip=$(hostname -I | awk '{print $1}')

  local country=""
  local data=""
  data=$(curl -4 -s --max-time 3 "http://ip-api.com/json/${ip}" 2>/dev/null)
  country=$(echo "$data" | jq -r '.countryCode // "US"' 2>/dev/null)
  [[ -z "$country" || "$country" == "null" ]] && country="US"

  # Map country → flag emoji URL-encoded
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

# ─── Check Root ──────────────────────────────────────────────────────
check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo -e "${ERR}این اسکریپت باید با دسترسی روت اجرا بشه!${NC}"
    echo -e "${INFO}دستور: sudo bash RealityGhostPro.sh install${NC}"
    exit 1
  fi
}

# ─── System Checks ───────────────────────────────────────────────────
preflight_check() {
  echo -e "${INFO}بررسی سیستم در حال انجام..."
  # Detect OS
  if ! grep -q "Ubuntu\|Debian" /etc/os-release 2>/dev/null; then
    echo -e "${WARN}فقط اوبونتو/دبیان تست شده - ادامه می‌دیم..."
  fi

  # Check port conflicts
  local ports=("443" "${XRAY_TCP_PORT}" "${SUB_PORT}")
  for p in "${ports[@]}"; do
    if ss -tlnp | grep -q ":${p} "; then
      local proc=$(ss -tlnp | grep ":${p} " | awk '{print $7}' | tr -d '""')
      echo -e "${WARN}پورت ${p} توسط ${proc:-پروسس ناشناخته} اشغال شده!"
      echo -ne "${INFO}می‌خوای خودکار آزادش کنم؟ (y/n): "
      read -r ans
      if [[ "$ans" == "y" || "$ans" == "Y" ]]; then
        local pid=$(ss -tlnp | grep ":${p} " | grep -oP 'pid=\K[0-9]+')
        [[ -n "$pid" ]] && kill -9 "$pid" 2>/dev/null
        echo -e "${OK}پورت ${p} آزاد شد"
      else
        echo -e "${ERR}پورت ${p} آزاد نیست. لطفاً خودت آزادش کن یا پورت دیگه‌ای انتخاب کن${NC}"
        exit 1
      fi
    fi
  done

  # Check DNS resolution
  if ! nslookup google.com >/dev/null 2>&1; then
    if ! dig google.com >/dev/null 2>&1; then
      echo -e "${WARN}DNS کار نمی‌کنه. مطمئن شو سیستم به اینترنت وصل باشه${NC}"
      echo -ne "${INFO}ادامه می‌دیم؟ (y/n): "
      read -r ans
      [[ "$ans" != "y" && "$ans" != "Y" ]] && exit 1
    fi
  fi

  # Check IPv4
  if ! ping -4 -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
    echo -e "${WARN}اتصال IPv4 تأیید نشد. ممکنه اینترنت نباشه${NC}"
  fi

  echo -e "${OK}پیش‌بررسی کامل شد${NC}"
}

# ─── Install Dependencies ──────────────────────────────────────────
install_dependencies() {
  echo -e "${INFO}نصب پیش‌نیازها..."
  apt-get update -y
  apt-get install -y wget curl unzip uuid-runtime jq qrencode certbot \
    nginx-extras logrotate bc netcat-openbsd dnsutils python3 python3-pip sqlite3
  if [[ $? -ne 0 ]]; then
    echo -e "${ERR}خطا در نصب پیش‌نیازها. اینترنت وصل هست؟${NC}"
    exit 1
  fi

  # Install Python deps for bot
  pip3 install python-telegram-bot requests --break-system-packages -q 2>/dev/null || \
    echo -e "${WARN}نصب پکیج‌های Python (ربات) ناموفق. ادامه می‌دیم${NC}"

  echo -e "${OK}تمامی پیش‌نیازها نصب شدن${NC}"
}

# ─── System Tuning (BBR + sysctl + limits) ─────────────────────────
system_tuning() {
  echo -e "${INFO}بهینه‌سازی سیستم..."

  # 1. Enable BBR if not active
  local cc=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')
  if [[ "$cc" != "bbr" ]]; then
    modprobe tcp_bbr 2>/dev/null
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.d/99-realityghost.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.d/99-realityghost.conf
    echo -e "${OK}BBR فعال شد${NC}"
  else
    echo -e "${OK}BBR از قبل فعاله${NC}"
  fi

  # 2. Kernel network optimizations
  cat >> /etc/sysctl.d/99-realityghost.conf <<SYSCTLEOF
# RealityGhost PRO - Network Performance
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
net.ipv4.tcp_allowed_congestion_control=bbr westwood hybla
net.ipv4.tcp_congestion_control=bbr
net.ipv4.udp_rmem_min=8192
net.ipv4.udp_wmem_min=8192
SYSCTLEOF
  sysctl -p /etc/sysctl.d/99-realityghost.conf > /dev/null 2>&1
  echo -e "${OK}تنظیمات کرنل اعمال شد${NC}"

  # 3. File descriptor limits
  if grep -q "nofile" /etc/security/limits.conf 2>/dev/null; then
    echo -e "${OK}محدودیت فایل از قبل تنظیمه${NC}"
  else
    cat >> /etc/security/limits.conf <<LIMITSEOF
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
LIMITSEOF
    echo -e "${OK}محدودیت فایل به ۱۰۴۸۵۷۶ تنظیم شد${NC}"
  fi

  # 4. Optimize Xray service limits
  mkdir -p /etc/systemd/system/xray.service.d
  cat > /etc/systemd/system/xray.service.d/limits.conf <<SYSEOF
[Service]
LimitNOFILE=1048576
LimitNPROC=infinity
CPUAccounting=yes
MemoryAccounting=yes
SYSEOF
  systemctl daemon-reload
  echo -e "${OK}Xray service limits optimized${NC}"
}
generate_uuid() {
  if command -v uuidgen &>/dev/null; then uuidgen
  else cat /proc/sys/kernel/random/uuid; fi
}

# ─── Generate REALITY Keys ─────────────────────────────────────────
generate_reality_keys() {
  echo -e "${INFO}تولید کلیدهای REALITY..."
  if ! command -v /usr/local/bin/xray &>/dev/null; then
    echo -e "${ERR}Xray هنوز نصب نشده!${NC}"; exit 1
  fi
  local keys=$(/usr/local/bin/xray x25519)
  local private_key=$(echo "$keys" | grep "Private" | awk '{print $3}')
  local public_key=$(echo "$keys" | grep "Public" | awk '{print $3}')
  echo "${private_key}:${public_key}"
}

# ─── Install Xray-core ───────────────────────────────────────────────
install_xray() {
  echo -e "${INFO}نصب Xray-core..."
  mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$LOG_DIR"

  local xray_version
  xray_version=$(curl -s --max-time 10 "https://api.github.com/repos/XTLS/Xray-core/releases/latest" | grep '"tag_name":' | cut -d'"' -f4)
  if [[ -z "$xray_version" ]]; then
    echo -e "${WARN}گرفتن آخرین ورژن ممکن نشد. استفاده از v25.9.11...${NC}"
    xray_version="v25.9.11"
  fi
  echo -e "${INFO}ورژن Xray: ${xray_version}"

  wget -q -O /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/download/${xray_version}/Xray-linux-64.zip"
  if [[ $? -ne 0 || ! -f /tmp/xray.zip ]]; then
    echo -e "${ERR}دانلود Xray-core با شکست مواجه شد. اینترنت رو چک کن${NC}"
    exit 1
  fi

  unzip -o /tmp/xray.zip -d "$INSTALL_DIR" >/dev/null 2>&1
  chmod +x "$INSTALL_DIR/xray"
  ln -sf "$INSTALL_DIR/xray" /usr/local/bin/xray
  rm -f /tmp/xray.zip

  cat <<SERVICE | tee /etc/systemd/system/xray.service > /dev/null
[Unit]
Description=Xray Service — RealityGhost PRO
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
User=nobody
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config ${CONFIG_DIR}/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
SERVICE

  systemctl daemon-reload
  systemctl enable xray
  echo -e "${OK}Xray-core نصب شد${NC}"
}

# ─── Install SSL Certificate ────────────────────────────────────────
install_certbot() {
  if [[ -z "$DOMAIN" ]]; then
    echo -ne "${INFO}دامنه رو وارد کن (مثلاً your-domain.com): "
    read -r DOMAIN
  fi
  if [[ -z "$EMAIL" ]]; then
    echo -ne "${INFO}ایمیل برای Let's Encrypt رو وارد کن: "
    read -r EMAIL
  fi

  echo -e "${INFO}گرفتن گواهی SSL برای ${DOMAIN}..."
  systemctl stop nginx 2>/dev/null

  certbot certonly --standalone -d "$DOMAIN" -d "sub.${DOMAIN}" \
    --non-interactive --agree-tos --email "$EMAIL"
  if [[ $? -ne 0 ]]; then
    echo -e "${ERR}گواهی SSL گرفته نشد. مطمئن شو دامنه به IP سرور اشاره داره${NC}"
    echo -e "${INFO}همچنین پورت ۸۰ و ۴۴۳ باید باز باشه روی سرورت${NC}"
    exit 1
  fi
  echo -e "${OK}گواهی SSL نصب شد${NC}"
}

# ─── Configure Nginx ──────────────────────────────────────────────────
configure_nginx() {
  echo -e "${INFO}پیکربندی NGINX..."
  cp "$NGINX_CONF_DIR/nginx.conf" "$NGINX_CONF_DIR/nginx.conf.backup" 2>/dev/null

  cat <<NGINXEOF | tee "$NGINX_CONF_DIR/nginx.conf" > /dev/null
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 768;
}

stream {
    map \$ssl_preread_server_name \$backend {
        sub.${DOMAIN} nginx_https;
        ${DOMAIN} nginx_https;
        default xray_tcp;
    }

    upstream xray_tcp {
        server 127.0.0.1:${XRAY_TCP_PORT};
    }

    upstream nginx_https {
        server 127.0.0.1:${SUB_PORT};
    }

    server {
        listen 443 reuseport;
        proxy_pass \$backend;
        ssl_preread on;
    }
}

http {
    server {
        listen 127.0.0.1:${SUB_PORT} ssl;
        server_name ${DOMAIN} sub.${DOMAIN};

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

            location ~* \\.json\$ {
                add_header Content-Type application/json;
            }
        }
    }
}
NGINXEOF

  mkdir -p /var/www/html "$SUB_DIR" "$STATUS_DIR"
  chown -R www-data:www-data /var/www/html

  if ! nginx -t 2>/dev/null; then
    echo -e "${ERR}آزمایش NGINX ناموفق بود. چک کن کرون‌بوت نصب باشه${NC}"
    exit 1
  fi
  systemctl restart nginx
  systemctl enable nginx
  echo -e "${OK}NGINX پیکربندی شد${NC}"
}

# ─── Configure Xray ────────────────────────────────────────────────────
configure_xray() {
  echo -e "${INFO}پیکربندی Xray..."

  local uuid=$(generate_uuid)
  local keys=$(generate_reality_keys)
  local private_key=$(echo "$keys" | cut -d':' -f1)
  local public_key=$(echo "$keys" | cut -d':' -f2)

  # ─── Generate 6 UNIQUE random shortIds for each install ───
  local sids=()
  local snis_json=""
  local sids_json=""
  local i=0

  for entry in "${SNI_LIST[@]}"; do
    IFS=':' read -r sni label label_url <<< "$entry"
    # Unique random 8-byte hex shortId
    local sid=""
    while true; do
      sid=$(openssl rand -hex 8)
      # Make sure it's unique among all generated
      local dup=false
      for existing in "${sids[@]}"; do
        [[ "$existing" == "$sid" ]] && { dup=true; break; }
      done
      $dup && continue
      # Validate: VLESS shortId must be 2-16 hex chars, non-zero
      [[ ${#sid} -eq 16 && "$sid" =~ ^[0-9a-f]+$ ]] && break
    done
    sids+=("$sid")

    if [[ $i -gt 0 ]]; then snis_json+=","; fi
    snis_json+="\"$sni\""

    if [[ $i -gt 0 ]]; then sids_json+=","; fi
    sids_json+="\"$sid\""

    i=$((i+1))
  done

  # Extra Google server names for better routing
  local extra_snis='["googleadservices.com","google-analytics.com","googletagmanager.com","googleapis.com"]'

  cat <<XRAYEOF | tee "$CONFIG_DIR/config.json" > /dev/null
{
  "log": {
    "loglevel": "info",
    "access": "${LOG_DIR}/access.log",
    "error": "${LOG_DIR}/error.log"
  },
  "inbounds": [
    {
      "port": ${XRAY_TCP_PORT},
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "${uuid}", "flow": "xtls-rprx-vision", "level": 0, "email": "user@${DOMAIN}" }],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "www.gstatic.com:443",
          "xver": 0,
          "serverNames": [${snis_json},${extra_snis}],
          "privateKey": "${private_key}",
          "shortIds": [${sids_json}]
        }
      },
      "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"] }
    }
  ],
  "outbounds": [{ "protocol": "freedom", "settings": {} }]
}
XRAYEOF

  chmod 600 "$CONFIG_DIR/config.json"
  mkdir -p "$LOG_DIR"
  chown -R nobody:nogroup "$LOG_DIR" 2>/dev/null

  # Save client info
  cat <<INFOEOF | tee "$CONFIG_DIR/client_info.txt" > /dev/null
══════════ RealityGhost PRO ══════════
دامنه: ${DOMAIN}
UUID: ${uuid}
Public Key: ${public_key}
پورت: 443 (SNI Passthrough)

🔗 کانفیگ‌ها:
INFOEOF

  # Build configs
  for entry in "${SNI_LIST[@]}"; do
    IFS=':' read -r sni label label_url <<< "$entry"
    # Read real shortId from config file for this SNI
    local idx=0
    for e2 in "${SNI_LIST[@]}"; do
      IFS=':' read -r s2 l2 l2u <<< "$e2"
      [[ "$s2" == "$sni" ]] && break
      idx=$((idx+1))
    done
    local real_sid=$(jq -r ".inbounds[0].streamSettings.realitySettings.shortIds[$idx]" "$CONFIG_DIR/config.json" 2>/dev/null)
    [[ -z "$real_sid" || "$real_sid" == "null" ]] && real_sid="${sids[$idx]}"
    local encoded_label="${FLAG}%20${label_url}"
    local link="vless://${uuid}@${DOMAIN}:443?flow=xtls-rprx-vision&encryption=none&security=reality&sni=${sni}&fp=chrome&echfq=none&pbk=${public_key}&sid=${real_sid}&allowinsecure=0&type=tcp&headerType=none#${encoded_label}"
    echo "$link" | tee -a "$CONFIG_DIR/client_info.txt" > /dev/null
  done

  echo -e "${OK}Xray پیکربندی شد"
}

# ─── Build Subscription File ──────────────────────────────────────────
build_subscription() {
  echo -e "${INFO}ساخت فایل ساب‌اسکریپشن..."
  local uuid=$(jq -r '.inbounds[0].settings.clients[0].id' "$CONFIG_DIR/config.json" 2>/dev/null)
  local pbk=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$CONFIG_DIR/config.json" 2>/dev/null)
  if [[ -z "$uuid" || -z "$pbk" ]]; then
    echo -e "${ERR}خطا: فایل کانفیگ Xray درست نیست${NC}"
    return 1
  fi
  # Get public key from private key
  local pubkey=""
  local keys=$(/usr/local/bin/xray x25519 -i "$pbk" 2>/dev/null)
  pubkey=$(echo "$keys" | grep "Public" | awk '{print $3}')
  [[ -z "$pubkey" ]] && pubkey=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0] // ""' "$CONFIG_DIR/config.json")

  mkdir -p "$SUB_DIR"

  local lines=()
  for entry in "${SNI_LIST[@]}"; do
    IFS=':' read -r sni label label_url <<< "$entry"
    # Read dynamic shortId from config.json
    local idx=0
    for e2 in "${SNI_LIST[@]}"; do
      IFS=':' read -r s2 l2 l2u <<< "$e2"
      [[ "$s2" == "$sni" ]] && break
      idx=$((idx+1))
    done
    local real_sid=$(jq -r ".inbounds[0].streamSettings.realitySettings.shortIds[$idx]" "$CONFIG_DIR/config.json" 2>/dev/null)
    [[ -z "$real_sid" || "$real_sid" == "null" ]] && real_sid="0000000000000000"
    local encoded_label="${FLAG}%20${label_url}"
    lines+=("vless://${uuid}@${DOMAIN}:443?flow=xtls-rprx-vision&encryption=none&security=reality&sni=${sni}&fp=chrome&echfq=none&pbk=${pubkey}&sid=${real_sid}&allowinsecure=0&type=tcp&headerType=none#${encoded_label}")
  done

  printf '%s\n' "${lines[@]}" | base64 -w 0 > "$SUB_DIR/sub.txt"
  chown www-data:www-data "$SUB_DIR/sub.txt"
  echo -e "${OK}فایل ساب‌اسکریپشن ساخته شد (۶ کانفیگ با ${FLAG_RAW})"
}

# ─── Build Panel HTML (RTL Persian) ──────────────────────────────────
build_panel() {
  echo -e "${INFO}ساخت پنل مدیریت فارسی..."

  local uuid=$(jq -r '.inbounds[0].settings.clients[0].id' "$CONFIG_DIR/config.json" 2>/dev/null)
  local pbk=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0] // ""' "$CONFIG_DIR/config.json" 2>/dev/null)
  local pubkey_line=$(/usr/local/bin/xray x25519 -i "$pbk" 2>/dev/null | grep "Public" | awk '{print $3}')
  [[ -z "$pubkey_line" ]] && pubkey_line="$pbk"

  # Build configs JS array
  local configs_js=""
  local idx=0
  local emojis=("🟢" "🟣" "🟠" "🔴" "🟤" "🔵")
  for entry in "${SNI_LIST[@]}"; do
    IFS=':' read -r sni label label_url <<< "$entry"
    # Read real shortId from config.json (dynamic per install)
    local real_sid=$(jq -r ".inbounds[0].streamSettings.realitySettings.shortIds[$idx]" "$CONFIG_DIR/config.json" 2>/dev/null)
    [[ -z "$real_sid" || "$real_sid" == "null" ]] && real_sid="0000000000000000"
    local emoji="${emojis[$idx]}"
    if [[ $idx -gt 0 ]]; then configs_js+=","; fi
    configs_js+="{sni:'${sni}', label:'${FLAG_RAW} ${label}', emoji:'${emoji}', sid:'${real_sid}'}"
    idx=$((idx+1))
  done

  mkdir -p "$STATUS_DIR"

  cat <<HTMLEOF | tee "$STATUS_DIR/index.html" > /dev/null
<!DOCTYPE html>
<html lang="fa" dir="rtl">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0,maximum-scale=5.0">
<title>${FLAG_RAW} RG PRO • ${LOC}</title>
<style>
*,*::before,*::after{margin:0;padding:0;box-sizing:border-box}
:root{
  --bg:#07070f;--bg2:#0b0b16;--card:rgba(14,14,40,0.7);
  --border:rgba(90,110,255,0.08);--border2:rgba(90,110,255,0.15);
  --text:#dcdcf0;--text2:#7878b0;--text3:#5858a0;
  --purple:#7c5cfc;--purple2:#a078ff;
  --green:#00d68f;--blue:#4a9eff;--yellow:#f0a030;--red:#f05060;
  --radius:18px;--radius-sm:12px;--shadow:0 8px 40px rgba(0,0,0,0.6);
}
html{font-size:15px}
body{
  font-family:'Vazirmatn',-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
  background:var(--bg);color:var(--text);min-height:100vh;direction:rtl;
  background-image:radial-gradient(ellipse at 15% 30%,rgba(124,92,252,0.05) 0%,transparent 60%),
                   radial-gradient(ellipse at 85% 70%,rgba(0,214,143,0.03) 0%,transparent 60%);
}
.wrap{max-width:1260px;margin:0 auto;padding:16px}

.hdr{display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:12px;
  padding:14px 20px;margin-bottom:20px;background:var(--card);border:1px solid var(--border);
  border-radius:var(--radius);backdrop-filter:blur(16px);-webkit-backdrop-filter:blur(16px);}
.hdr-r{display:flex;align-items:center;gap:14px}
.hdr-av{width:44px;height:44px;border-radius:14px;
  background:linear-gradient(135deg,var(--purple),var(--purple2));
  display:flex;align-items:center;justify-content:center;
  font-weight:900;font-size:20px;color:#fff;flex-shrink:0;
  box-shadow:0 4px 16px rgba(124,92,252,0.3);}
.hdr-t h1{font-size:17px;font-weight:800;letter-spacing:-0.3px;line-height:1.3}
.hdr-t p{font-size:12px;color:var(--text2)}
.hdr-l{display:flex;align-items:center;gap:6px;flex-wrap:wrap}
.hdr-b{padding:4px 12px;border-radius:100px;font-size:10px;font-weight:600;
  letter-spacing:0.3px;display:inline-flex;align-items:center;gap:4px;}
.hdr-b.vip{background:linear-gradient(135deg,#f59e0b,#f97316);color:#220500}
.hdr-b.proto{background:rgba(124,92,252,0.15);color:var(--purple2);border:1px solid rgba(124,92,252,0.2)}
.hdr-b.live{background:rgba(0,214,143,0.1);color:var(--green);border:1px solid rgba(0,214,143,0.15)}
.hdr-dot{display:inline-block;width:6px;height:6px;border-radius:50%;background:var(--green);
  box-shadow:0 0 8px rgba(0,214,143,0.5);animation:pulse 2s infinite}

.sr{display:grid;grid-template-columns:repeat(6,1fr);gap:12px;margin-bottom:20px}
.sc{background:var(--card);border:1px solid var(--border);border-radius:var(--radius-sm);
  padding:14px 16px;backdrop-filter:blur(10px);min-height:90px;transition:all .25s;}
.sc:hover{background:var(--card2);border-color:var(--border2);transform:translateY(-2px)}
.sc-i{font-size:18px;margin-bottom:6px;display:block}
.sc-l{font-size:11px;color:var(--text2);margin-bottom:2px}
.sc-v{font-size:22px;font-weight:800;letter-spacing:-0.3px;line-height:1.2;min-height:28px;direction:ltr;text-align:right}
.sc-s{font-size:10px;color:var(--text3);margin-top:4px}
@media(max-width:1000px){.sr{grid-template-columns:repeat(3,1fr)}}
@media(max-width:640px){.sr{grid-template-columns:repeat(2,1fr)}}

.g2{display:grid;grid-template-columns:2.2fr 1fr;gap:20px;margin-bottom:20px}
@media(max-width:960px){.g2{grid-template-columns:1fr}}

.sec{background:var(--card);border:1px solid var(--border);border-radius:var(--radius);
  padding:20px;backdrop-filter:blur(12px);margin-bottom:20px}
.sec-h{display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:8px;
  margin-bottom:16px;padding-bottom:12px;border-bottom:1px solid rgba(90,110,255,0.06)}
.sec-t{font-size:14px;font-weight:700;display:flex;align-items:center;gap:8px}
.sec-t .pdot{display:inline-block;width:7px;height:7px;border-radius:50%;background:var(--green);
  box-shadow:0 0 10px rgba(0,214,143,0.4);animation:pulse 2s infinite}

.rg{display:flex;flex-direction:column;gap:14px}
.ri-hd{display:flex;justify-content:space-between;margin-bottom:5px;font-size:12px}
.ri-l{color:var(--text2);display:flex;align-items:center;gap:5px}
.ri-v{font-weight:600;direction:ltr}
.ri-bar{height:6px;border-radius:100px;background:rgba(255,255,255,0.03);overflow:hidden}
.ri-fill{height:100%;border-radius:100px;transition:width 1.2s cubic-bezier(0.22,1,0.36,1);width:0%}
.ri-fill.b{background:linear-gradient(90deg,#5a3fd4,#7c5cfc)}
.ri-fill.g{background:linear-gradient(90deg,#00b87a,#00d68f)}
.ri-fill.y{background:linear-gradient(90deg,#d49020,#f0a030)}
.ri-fill.r{background:linear-gradient(90deg,#d04048,#f05060)}

.tg{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin-top:12px}
.ti{text-align:center;padding:12px;border-radius:var(--radius-sm);
  background:rgba(255,255,255,0.02);border:1px solid rgba(255,255,255,0.03)}
.ti span{display:block;font-size:11px;color:var(--text2);margin-bottom:3px}
.ti strong{font-size:15px;font-weight:700;direction:ltr;display:inline-block}

.chips{display:flex;gap:10px;flex-wrap:wrap;margin-top:14px}
.chip{display:flex;align-items:center;gap:5px;padding:6px 12px;border-radius:100px;
  font-size:11px;background:rgba(255,255,255,0.02);border:1px solid rgba(255,255,255,0.04)}
.chip-dot{width:6px;height:6px;border-radius:50%}
.chip-dot.ok{background:var(--green);box-shadow:0 0 8px rgba(0,214,143,0.4)}

.ll{display:flex;flex-direction:column;gap:8px;margin-top:12px}
.li{display:flex;align-items:center;gap:10px;padding:12px 16px;border-radius:var(--radius-sm);
  background:rgba(255,255,255,0.02);border:1px solid rgba(255,255,255,0.04);
  text-decoration:none;color:var(--text);transition:all .25s;cursor:pointer;flex-wrap:wrap}
.li:hover{background:rgba(124,92,252,0.06);border-color:rgba(124,92,252,0.15)}
.li-i{width:32px;height:32px;border-radius:8px;display:flex;align-items:center;
  justify-content:center;font-size:14px;flex-shrink:0}
.li-t{flex:1;min-width:0;min-width:180px}
.li-t strong{display:block;font-size:12px}
.li-desc{font-size:10px;color:var(--text3);font-weight:400}
.li-sni{font-size:10px;color:var(--purple2);font-weight:500;margin-top:2px;direction:ltr;display:block}
.li-sid{font-size:9px;color:var(--text3);margin-top:1px;direction:ltr;display:block;font-family:monospace}
.li-c{font-size:10px;padding:3px 10px;border-radius:6px;background:rgba(255,255,255,0.05);
  color:var(--text2);border:none;cursor:pointer;transition:all .2s;flex-shrink:0;white-space:nowrap}
.li-c:hover{background:rgba(124,92,252,0.15);color:var(--purple2)}

@media(max-width:640px){
  .li{flex-direction:column;align-items:stretch;gap:8px;padding:14px}
  .li-t{min-width:0;text-align:center}
  .li-c{width:100%;text-align:center;padding:8px}
}

.ftr{text-align:center;padding:14px 0;font-size:11px;color:var(--text3);margin-top:16px}

@keyframes pulse{0%,100%{opacity:1}50%{opacity:0.4}}
@keyframes spin{to{transform:rotate(360deg)}}
.loader{display:inline-block;width:10px;height:10px;border:2px solid var(--text3);
  border-top-color:var(--purple2);border-radius:50%;animation:spin .7s linear infinite;vertical-align:middle}
.toast{position:fixed;bottom:30px;left:50%;transform:translateX(-50%) translateY(80px);
  background:rgba(14,14,40,0.95);border:1px solid rgba(0,214,143,0.3);
  border-radius:var(--radius-sm);padding:10px 20px;font-size:13px;color:var(--green);
  opacity:0;transition:all .35s;z-index:999;backdrop-filter:blur(16px);pointer-events:none}
.toast.show{opacity:1;transform:translateX(-50%) translateY(0)}
</style>
</head>
<body>
<div class="wrap" id="app">
  <header class="hdr">
    <div class="hdr-r"><div class="hdr-av">${FLAG_RAW}</div>
      <div class="hdr-t"><h1>RealityGhost <span style="color:var(--purple2)">PRO</span></h1>
      <p>${DOMAIN} • ${LOC}</p></div>
    </div>
    <div class="hdr-l">
      <span class="hdr-b vip">✦ VIP</span>
      <span class="hdr-b proto">${FLAG_RAW} ${LOC}</span>
      <span class="hdr-b live"><span class="hdr-dot"></span> آنلاین</span>
    </div>
  </header>

  <div class="sr" id="sr">
    <div class="sc"><span class="sc-i">📥</span><div class="sc-l">دانلود امروز</div><div class="sc-v" id="s-dl">—</div><div class="sc-s">از نیمه‌شب</div></div>
    <div class="sc"><span class="sc-i">📤</span><div class="sc-l">آپلود امروز</div><div class="sc-v" id="s-ul">—</div><div class="sc-s">از نیمه‌شب</div></div>
    <div class="sc"><span class="sc-i">📊</span><div class="sc-l">مصرف ماه</div><div class="sc-v" id="s-month">—</div><div class="sc-s">جاری</div></div>
    <div class="sc"><span class="sc-i">🔗</span><div class="sc-l">اتصالات</div><div class="sc-v" id="s-conn">—</div><div class="sc-s">هم‌زمان</div></div>
    <div class="sc"><span class="sc-i">⏱️</span><div class="sc-l">آپتایم</div><div class="sc-v" id="s-uptime">—</div><div class="sc-s">از ری‌استارت</div></div>
    <div class="sc"><span class="sc-i">📡</span><div class="sc-l">کل ترافیک</div><div class="sc-v" id="s-total">—</div><div class="sc-s">از ابتدا</div></div>
  </div>

  <div class="g2">
    <div>
      <div class="sec">
        <div class="sec-h"><div class="sec-t"><span class="pdot"></span> منابع سرور</div><span style="font-size:10px;color:var(--text3);direction:ltr" id="ts">—</span></div>
        <div class="rg">
          <div class="ri"><div class="ri-hd"><span class="ri-l">🧠 RAM</span><span class="ri-v"><span id="ram-u">—</span> / <span id="ram-t">—</span></span></div><div class="ri-bar"><div class="ri-fill b" id="ram-f" style="width:0%"></div></div></div>
          <div class="ri"><div class="ri-hd"><span class="ri-l">⚡ CPU</span><span class="ri-v" id="cpu-v">—</span></div><div class="ri-bar"><div class="ri-fill g" id="cpu-f" style="width:0%"></div></div></div>
          <div class="ri"><div class="ri-hd"><span class="ri-l">💾 دیسک</span><span class="ri-v"><span id="disk-u">—</span> / <span id="disk-t">—</span></span></div><div class="ri-bar"><div class="ri-fill y" id="disk-f" style="width:0%"></div></div></div>
          <div class="ri"><div class="ri-hd"><span class="ri-l">🔄 Swap</span><span class="ri-v"><span id="swap-u">0</span> MB</span></div><div class="ri-bar"><div class="ri-fill r" id="swap-f" style="width:0%"></div></div></div>
        </div>
        <div class="tg">
          <div class="ti"><span>امروز</span><strong id="t-day">—</strong></div>
          <div class="ti"><span>ماه</span><strong id="t-month">—</strong></div>
          <div class="ti"><span>کل</span><strong id="t-all">—</strong></div>
        </div>
        <div class="chips">
          <div class="chip"><span class="chip-dot ok"></span> Load: <span id="l1">—</span> / <span id="l5">—</span> / <span id="l15">—</span></div>
          <div class="chip">🌐 DNS: <span id="dns">—</span></div>
          <div class="chip">🔋 <span id="xv">—</span></div>
        </div>
      </div>
    </div>
    <div>
      <div class="sec">
        <div class="sec-h"><div class="sec-t">🔧 سرویس‌ها</div></div>
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:10px">
          <div style="background:rgba(255,255,255,0.02);border:1px solid rgba(255,255,255,0.04);border-radius:var(--radius-sm);padding:14px 12px;text-align:center"><div style="width:36px;height:36px;border-radius:10px;margin:0 auto 6px;display:flex;align-items:center;justify-content:center;font-size:16px;background:rgba(0,214,143,0.12);color:var(--green);box-shadow:0 0 16px rgba(0,214,143,0.15)" id="ni">🌐</div><div style="font-size:12px;color:var(--text2);margin-bottom:6px">NGINX</div><div style="font-size:11px;font-weight:600;color:var(--green)" id="ns">⏳</div></div>
          <div style="background:rgba(255,255,255,0.02);border:1px solid rgba(255,255,255,0.04);border-radius:var(--radius-sm);padding:14px 12px;text-align:center"><div style="width:36px;height:36px;border-radius:10px;margin:0 auto 6px;display:flex;align-items:center;justify-content:center;font-size:16px;background:rgba(0,214,143,0.12);color:var(--green);box-shadow:0 0 16px rgba(0,214,143,0.15)" id="xi">🚀</div><div style="font-size:12px;color:var(--text2);margin-bottom:6px">Xray</div><div style="font-size:11px;font-weight:600;color:var(--green)" id="xs">⏳</div></div>
          <div style="background:rgba(255,255,255,0.02);border:1px solid rgba(255,255,255,0.04);border-radius:var(--radius-sm);padding:14px 12px;text-align:center"><div style="width:36px;height:36px;border-radius:10px;margin:0 auto 6px;display:flex;align-items:center;justify-content:center;font-size:16px;background:rgba(0,214,143,0.12);color:var(--green);box-shadow:0 0 16px rgba(0,214,143,0.15)" id="mi">📡</div><div style="font-size:12px;color:var(--text2);margin-bottom:6px">Monitor</div><div style="font-size:11px;font-weight:600;color:var(--green)" id="ms">⏳</div></div>
          <div style="background:rgba(255,255,255,0.02);border:1px solid rgba(255,255,255,0.04);border-radius:var(--radius-sm);padding:14px 12px;text-align:center"><div style="width:36px;height:36px;border-radius:10px;margin:0 auto 6px;display:flex;align-items:center;justify-content:center;font-size:16px;background:rgba(0,214,143,0.12);color:var(--green);box-shadow:0 0 16px rgba(0,214,143,0.15)" id="si">🔒</div><div style="font-size:12px;color:var(--text2);margin-bottom:6px">SSL</div><div style="font-size:11px;font-weight:600;color:var(--green)" id="ss">⏳</div></div>
        </div>
      </div>
      <div class="sec">
        <div class="sec-h">
          <div class="sec-t">🔗 ${FLAG_RAW} ${LOC}</div>
          <button class="li-c" onclick="cpAll()" style="padding:4px 12px">📋 کپی همه</button>
        </div>
        <div class="ll" id="links-list"></div>
      </div>
    </div>
  </div>
  <footer class="ftr">${FLAG_RAW} RealityGhost PRO • <a href="/sub" style="color:var(--purple2);text-decoration:none">📥 ساب‌اسکریپشن</a> • ${DOMAIN}</footer>
</div>
<div class="toast" id="toast">✓ کپی شد</div>

<script>
var D='${DOMAIN}',U='${uuid}',P='${pubkey_line}';
var CONFIGS=[${configs_js}];

function buildLink(c){return 'vless://'+U+'@'+D+':443?flow=xtls-rprx-vision&encryption=none&security=reality&sni='+c.sni+'&fp=chrome&echfq=none&pbk='+P+'&sid='+c.sid+'&allowinsecure=0&type=tcp&headerType=none#'+encodeURIComponent(c.label);}
function fmt(b){if(!b||b===0)return'0 B';var k=1024,s=['B','KB','MB','GB','TB'],i=Math.min(Math.floor(Math.log(Math.abs(b))/Math.log(k)),4);return parseFloat((b/Math.pow(k,i)).toFixed(1))+' '+s[i];}
function byId(id){return document.getElementById(id)}
function toast(m){var t=byId('toast');t.textContent=m||'✓ کپی شد';t.classList.add('show');setTimeout(function(){t.classList.remove('show')},1800);}
function cp(sni){var c=CONFIGS.find(function(x){return x.sni===sni});var t=c?buildLink(c):'https://'+D+'/sub';if(!t)return;if(navigator.clipboard)navigator.clipboard.writeText(t).then(function(){toast('✓ کپی شد')});else toast('👆 کپی دستی');}
function cpAll(){var a=CONFIGS.map(function(c){return buildLink(c)}).join('\\n')+'\\n'+'https://'+D+'/sub';if(navigator.clipboard)navigator.clipboard.writeText(a).then(function(){toast('✓ همه کپی شد')});else toast('👆 کپی دستی');}

function buildLinks(){
  var box=byId('links-list');if(!box)return;box.innerHTML='';
  var emojis=['🟢','🟣','🟠','🔴','🟤','🔵'];
  CONFIGS.forEach(function(c,i){
    var e=document.createElement('div');e.className='li';e.onclick=function(){cp(c.sni)};
    e.innerHTML='<span class="li-i">'+emojis[i%6]+'</span><div class="li-t"><strong>${FLAG_RAW} '+c.label+'</strong><span class="li-desc">پورت ۴۴۳ • فلو vision</span><span class="li-sni">sni: '+c.sni+'</span><span class="li-sid">sid: '+c.sid+'</span></div><span class="li-c" onclick="event.stopPropagation();cp(\\''+c.sni+'\\')">📋 کپی</span>';
    box.appendChild(e);
  });
  var se=document.createElement('div');se.className='li';se.onclick=function(){cp('sub')};
  se.innerHTML='<span class="li-i">📋</span><div class="li-t"><strong>ساب‌اسکریپشن</strong><span class="li-desc">برای کلاینت‌ها</span></div><span class="li-c" onclick="event.stopPropagation();cp(\\'sub\\')">📋 کپی</span>';
  box.appendChild(se);
}

function upd(d){
  try{
    byId('ts').textContent=new Date().toLocaleTimeString('fa-IR')||'—';
    var cpu=Math.min(Math.max(parseFloat(d.cpu)||0,0),100);
    byId('cpu-v').textContent=cpu.toFixed(1)+'%';byId('cpu-f').style.width=cpu+'%';
    var rp=Math.min(Math.max(parseFloat(d.ram&&d.ram.usage)||0,0),100);
    byId('ram-u').textContent=fmt((parseInt(d.ram&&d.ram.used)||0)*1048576);byId('ram-t').textContent=d.ram&&d.ram.total||'—';
    byId('ram-f').style.width=rp+'%';
    var dp=Math.min(Math.max(parseInt(d.disk&&d.disk.usage)||0,0),100);
    byId('disk-u').textContent=d.disk&&d.disk.used||'—';byId('disk-t').textContent=d.disk&&d.disk.total||'—';byId('disk-f').style.width=dp+'%';
    var trf=d.traffic||{};var tDay=parseInt(trf.today)||0,tMon=parseInt(trf.month)||0,tTot=parseInt(trf.total)||0;
    byId('s-dl').textContent=fmt(Math.round(tDay*0.6));byId('s-ul').textContent=fmt(Math.round(tDay*0.4));
    byId('s-month').textContent=fmt(tMon);byId('s-total').textContent=fmt(tTot);
    byId('t-day').textContent=fmt(tDay);byId('t-month').textContent=fmt(tMon);byId('t-all').textContent=fmt(tTot);
    byId('s-uptime').textContent=d.uptime||'—';byId('s-conn').textContent=parseInt(d.connections)||0;
    var lo=d.load||{};byId('l1').textContent=lo['1m']!=null?lo['1m']:'—';byId('l5').textContent=lo['5m']!=null?lo['5m']:'—';byId('l15').textContent=lo['15m']!=null?lo['15m']:'—';
    byId('dns').textContent=d.dns_ok?'✓':'✗';byId('xv').textContent=d.xray_version||'—';
    ['ns','ni','xs','xi','ms','mi','ss','si'].forEach(function(i){var e=byId(i);if(!e)return;});
    var sv=d.services||{};
    ['nginx','xray','monitor'].forEach(function(s){
      ['ns','ni'],['xs','xi'],['ms','mi'];
      var e=byId(s[0]+'s');var ic=byId(s[0]+'i');if(!e||!ic)return;
      if((sv[s]||'inactive')==='active'){e.textContent='فعال';e.style.color='var(--green)';ic.style.background='rgba(0,214,143,0.12)';ic.style.color='var(--green)'}
      else{e.textContent='غیرفعال';e.style.color='var(--red)';ic.style.background='rgba(240,80,96,0.12)';ic.style.color='var(--red)'}
    });
  }catch(e){console.warn(e);}
}

function fetchData(){
  var x=new XMLHttpRequest();
  x.open('GET','/status/stats.json?t='+Date.now(),true);x.timeout=5000;
  x.onload=function(){if(x.status===200)try{upd(JSON.parse(x.responseText))}catch(e){}};
  x.onerror=function(){};x.send();
}
buildLinks();fetchData();setInterval(fetchData,3000);
</script>
</body>
</html>
HTMLEOF

  chown -R www-data:www-data "$STATUS_DIR"
  echo -e "${OK}پنل مدیریت ساخته شد (${STATUS_DIR}/index.html)${NC}"
}

# ─── Install Monitor ──────────────────────────────────────────────────
install_monitor() {
  echo -e "${INFO}نصب مانیتورینگ سیستم..."

  mkdir -p "$STATE_DIR"

  cat <<'MONEYEOF' | tee "$MONITOR_SCRIPT" > /dev/null
#!/bin/bash
OUTPUT_FILE="/var/www/html/status/stats.json"
STATE_FILE="/var/lib/realityghost/state.json"
IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
[[ -z "$IFACE" ]] && IFACE=$(ls /sys/class/net | grep -v lo | head -1)

# Initialize state file if missing
if [[ ! -f "$STATE_FILE" ]]; then
  echo '{"today":0,"month":0,"total":0,"last_bytes":0,"last_day":'$(date +%d)',"last_month":'$(date +%m)'}' > "$STATE_FILE"
fi

while true; do
  # System stats
  CPU=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | head -1)
  CPU_USAGE=$(awk "BEGIN {print 100 - ($CPU)}")
  CPU_IDLE=$(awk "BEGIN {print ($CPU)}")

  RAM_TOTAL=$(free -m | awk '/Mem/ {print $2}')
  RAM_USED=$(free -m | awk '/Mem/ {print $3}')
  RAM_USAGE=$(awk "BEGIN {printf \"%.2f\", ($RAM_USED/$RAM_TOTAL)*100}")

  SWAP_TOTAL=$(free -m | awk '/Swap/ {print $2}')
  SWAP_USED=$(free -m | awk '/Swap/ {print $3}')
  SWAP_USAGE=$(awk "BEGIN {if('$SWAP_TOTAL'>0) printf \"%.2f\", ($SWAP_USED/$SWAP_TOTAL)*100; else print 0}")

  DISK_TOTAL=$(df -m / | awk 'NR==2 {print $2}')
  DISK_USED=$(df -m / | awk 'NR==2 {print $3}')
  DISK_USAGE=$(awk "BEGIN {printf \"%.2f\", ($DISK_USED/$DISK_TOTAL)*100}")

  UPTIME=$(uptime -p | sed 's/up //')
  UPTIME_S=$(awk '{print int($1)}' /proc/uptime)

  # Load
  LOAD=$(cat /proc/loadavg)
  L1=$(echo "$LOAD" | awk '{print $1}')
  L5=$(echo "$LOAD" | awk '{print $2}')
  L15=$(echo "$LOAD" | awk '{print $3}')

  # Services
  XRAY_ST=$(systemctl is-active xray 2>/dev/null || echo "inactive")
  NGINX_ST=$(systemctl is-active nginx 2>/dev/null || echo "inactive")

  # Xray connections from access log
  CONNS=$(cat /var/log/xray/access.log 2>/dev/null | wc -l)

  # Traffic
  RX=$(cat /sys/class/net/$IFACE/statistics/rx_bytes 2>/dev/null || echo 0)
  TX=$(cat /sys/class/net/$IFACE/statistics/tx_bytes 2>/dev/null || echo 0)
  CURRENT=$((RX + TX))

  STATE=$(cat "$STATE_FILE" 2>/dev/null || echo '{"today":0,"month":0,"total":0,"last_bytes":0,"last_day":0,"last_month":0}')
  TODAY=$(echo "$STATE" | jq -r '.today // 0')
  MONTH=$(echo "$STATE" | jq -r '.month // 0')
  TOTAL=$(echo "$STATE" | jq -r '.total // 0')
  LAST_B=$(echo "$STATE" | jq -r '.last_bytes // 0')
  LAST_D=$(echo "$STATE" | jq -r '.last_day // 0')
  LAST_M=$(echo "$STATE" | jq -r '.last_month // 0')

  CUR_D=$(date +%d)
  CUR_M=$(date +%m)

  DELTA=$((CURRENT - LAST_B))
  [[ $DELTA -lt 0 ]] && DELTA=0
  [[ "$CUR_D" != "$LAST_D" ]] && TODAY=0
  [[ "$CUR_M" != "$LAST_M" ]] && MONTH=0

  TODAY=$((TODAY + DELTA))
  MONTH=$((MONTH + DELTA))
  TOTAL=$((TOTAL + DELTA))

  # DNS check
  DNS_OK=$(dig +short google.com @8.8.8.8 2>/dev/null | head -1)
  [[ -n "$DNS_OK" ]] && DNS="ok" || DNS="fail"

  # Xray version
  XV=$(/usr/local/bin/xray version 2>/dev/null | head -1 | awk '{print $2}' || echo "—")

  jq -n \
    --arg cpu "$CPU_USAGE" \
    --arg cpu_temp "—" \
    --argjson ram_total "$RAM_TOTAL" --argjson ram_used "$RAM_USED" --arg ram_usage "$RAM_USAGE" \
    --argjson swap_total "$SWAP_TOTAL" --argjson swap_used "$SWAP_USED" --arg swap_usage "$SWAP_USAGE" \
    --argjson disk_total "$DISK_TOTAL" --argjson disk_used "$DISK_USED" --arg disk_usage "$DISK_USAGE" \
    --arg uptime "$UPTIME" --argjson uptime_seconds "$UPTIME_S" \
    --arg l1 "$L1" --arg l5 "$L5" --arg l15 "$L15" \
    --argjson connections "$CONNS" \
    --arg dns_ok "$DNS" \
    --arg xray_version "$XV" \
    --argjson today "$TODAY" --argjson month "$MONTH" --argjson total "$TOTAL" \
    --arg iface "$IFACE" \
    '{
      cpu: $cpu,
      cpu_temp: $cpu_temp,
      ram: {total: ($ram_total|tostring), used: ($ram_used|tostring), usage: $ram_usage},
      swap: {total: ($swap_total|tostring), used: ($swap_used|tostring), usage: $swap_usage},
      disk: {total: ($disk_total|tostring), used: ($disk_used|tostring), usage: $disk_usage},
      uptime: $uptime,
      uptime_seconds: $uptime_seconds,
      load: {"1m": $l1, "5m": $l5, "15m": $l15},
      connections: $connections,
      dns_ok: $dns_ok,
      xray_version: $xray_version,
      traffic: {today: $today, month: $month, total: $total},
      network: {interface: $iface},
      services: {nginx: "'$NGINX_ST'", xray: "'$XRAY_ST'", monitor: "active"}
    }' > "$OUTPUT_FILE"

  echo "{\"today\":$TODAY,\"month\":$MONTH,\"total\":$TOTAL,\"last_bytes\":$CURRENT,\"last_day\":$CUR_D,\"last_month\":$CUR_M}" > "$STATE_FILE"
  chown www-data:www-data "$OUTPUT_FILE" "$STATE_FILE" 2>/dev/null
  sleep 2
done
MONEYEOF

  chmod +x "$MONITOR_SCRIPT"

  cat <<'SERVICEEOF' | tee /etc/systemd/system/realityghost-monitor.service > /dev/null
[Unit]
Description=RealityGhost PRO Monitor
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash /usr/local/bin/realityghost_monitor.sh
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
SERVICEEOF

  systemctl daemon-reload
  systemctl enable realityghost-monitor
  systemctl restart realityghost-monitor
  echo -e "${OK}مانیتور نصب شد${NC}"
}

# ─── Menu: Show Info ──────────────────────────────────────────────────
show_info() {
  clear
  echo -e "${PURPLE}══════════════════════════════════════${NC}"
  echo -e "${PURPLE}   ${FLAG_RAW} RealityGhost PRO — ${LOC}${NC}"
  echo -e "${PURPLE}══════════════════════════════════════${NC}"
  echo ""

  if [[ -f "$CONFIG_DIR/client_info.txt" ]]; then
    cat "$CONFIG_DIR/client_info.txt"
  fi

  echo ""
  echo -e "${CYAN}📋 ساب‌اسکریپشن: https://${DOMAIN}/sub${NC}"
  echo -e "${CYAN}📊 پنل وضعیت:   https://${DOMAIN}/status/${NC}"
  echo ""

  echo -ne "${YELLOW}برای خروج Enter بزن...${NC}"
  read -r
}

# ─── Menu: Port Management ────────────────────────────────────────────
port_manager() {
  while true; do
    clear
    echo -e "${CYAN}══════════════════════════════════════${NC}"
    echo -e "${CYAN}   🔌 مدیریت پورت‌ها${NC}"
    echo -e "${CYAN}══════════════════════════════════════${NC}"
    echo ""
    echo "1. نمایش پورت‌های باز"
    echo "2. باز کردن پورت در فایروال (iptables)"
    echo "3. بستن پورت در فایروال"
    echo "4. نمایش پورت‌های در حال استفاده (ss)"
    echo "5. تست پورت خارجی (online check)"
    echo "0. برگشت به منوی اصلی"
    echo ""
    echo -ne "${BOLD}انتخاب: ${NC}"
    read -r opt

    case $opt in
      1)
        echo -e "${INFO}پورت‌های باز (iptables):${NC}"
        iptables -L INPUT -n --line-numbers 2>/dev/null | grep "ACCEPT" | grep -E "tcp|udp"
        echo ""
        echo -e "${INFO}پورت‌های در حال Listen:${NC}"
        ss -tlnp | grep -E ':(443|80|8443|8444|2053) '
        echo -ne "\n${YELLOW}Enter بزن برای ادامه...${NC}"; read -r
        ;;
      2)
        echo -ne "${INFO}پورت رو وارد کن: "
        read -r port
        if [[ -z "$port" ]]; then continue; fi
        iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null && \
          echo -e "${OK}پورت ${port} از قبل بازه${NC}" || {
          iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
          echo -e "${OK}پورت ${port} باز شد${NC}"
        }
        # Save (if iptables-persistent exists)
        if command -v netfilter-persistent &>/dev/null; then
          netfilter-persistent save 2>/dev/null
        fi
        echo -ne "\n${YELLOW}Enter بزن...${NC}"; read -r
        ;;
      3)
        echo -ne "${INFO}پورت رو وارد کن: "
        read -r port
        if [[ -z "$port" ]]; then continue; fi
        iptables -D INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null && \
          echo -e "${OK}پورت ${port} بسته شد${NC}" || \
          echo -e "${WARN}پورت ${port} از قبل بسته است یا وجود نداره${NC}"
        if command -v netfilter-persistent &>/dev/null; then
          netfilter-persistent save 2>/dev/null
        fi
        echo -ne "\n${YELLOW}Enter بزن...${NC}"; read -r
        ;;
      4)
        echo -e "${INFO}پورت‌های در حال Listen:${NC}"
        ss -tlnp
        echo -ne "\n${YELLOW}Enter بزن برای ادامه...${NC}"; read -r
        ;;
      5)
        echo -e "${INFO}تست پورت خارجی...${NC}"
        curl -s --max-time 5 "https://portchecker.co/check?port=443" >/dev/null 2>&1
        echo -e "${INFO}پورت ۴۴۳ سرور:${NC}"
        timeout 5 bash -c "cat < /dev/null > /dev/tcp/104.253.43.68/443" 2>/dev/null && \
          echo -e "${OK}پورت ۴۴۳: باز ✅${NC}" || \
          echo -e "${WARN}پورت ۴۴۳: مسدود یا فیلتر شده ❌${NC}"
        echo -ne "\n${YELLOW}Enter بزن...${NC}"; read -r
        ;;
      0) return ;;
    esac
  done
}

# ─── Menu: Config Management ──────────────────────────────────────────
config_manager() {
  while true; do
    clear
    echo -e "${CYAN}══════════════════════════════════════${NC}"
    echo -e "${CYAN}   ⚙️  مدیریت کانفیگ‌ها${NC}"
    echo -e "${CYAN}══════════════════════════════════════${NC}"
    echo ""
    echo "1. نمایش کانفیگ‌های فعلی"
    echo "2. ساخت ساب‌اسکریپشن جدید"
    echo "3. چرخاندن Short IDs (rotate)"
    echo "4. نمایش UUID و Public Key"
    echo "5. نمایش QR Code برای کانفیگ اول"
    echo "6. ری‌استارت سرویس‌ها"
    echo "0. برگشت به منوی اصلی"
    echo ""
    echo -ne "${BOLD}انتخاب: ${NC}"
    read -r opt

    case $opt in
      1)
        show_info
        ;;
      2)
        build_subscription
        echo -ne "\n${YELLOW}Enter بزن...${NC}"; read -r
        ;;
      3)
        echo -e "${INFO}چرخاندن Short IDs..."
        for i in $(seq 0 5); do
          local new_sid=$(openssl rand -hex 8)
          jq --argjson idx "$i" --arg sid "$new_sid" \
            '.inbounds[0].streamSettings.realitySettings.shortIds[$idx] = $sid' \
            "$CONFIG_DIR/config.json" > "$CONFIG_DIR/config.json.tmp"
          mv "$CONFIG_DIR/config.json.tmp" "$CONFIG_DIR/config.json"
        done
        systemctl restart xray
        build_subscription

        # Rebuild panel with new SIDs
        build_panel
        echo -e "${OK}همه Short IDs چرخیده شدن. ساب و پنل آپدیت شدن${NC}"
        echo -ne "\n${YELLOW}Enter بزن...${NC}"; read -r
        ;;
      4)
        echo -e "${INFO}UUID: $(jq -r '.inbounds[0].settings.clients[0].id' "$CONFIG_DIR/config.json")${NC}"
        echo -e "${INFO}Short IDs: $(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[]' "$CONFIG_DIR/config.json" | tr '\n' ' ')${NC}"
        echo -ne "\n${YELLOW}Enter بزن...${NC}"; read -r
        ;;
      5)
        local uuid=$(jq -r '.inbounds[0].settings.clients[0].id' "$CONFIG_DIR/config.json")
        echo -e "${INFO}QR برای کانفیگ اول:${NC}"
        local link="vless://${uuid}@${DOMAIN}:443?flow=xtls-rprx-vision&encryption=none&security=reality&sni=www.gstatic.com&fp=chrome&echfq=none&pbk=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$CONFIG_DIR/config.json")&sid=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$CONFIG_DIR/config.json")&allowinsecure=0&type=tcp&headerType=none#RealityGhost"
        echo "$link" | qrencode -t ANSIUTF8
        echo -ne "\n${YELLOW}Enter بزن...${NC}"; read -r
        ;;
      6)
        systemctl restart nginx xray realityghost-monitor
        echo -e "${OK}سرویس‌ها ری‌استارت شدن${NC}"
        sleep 2
        echo -e "${OK}NGINX: $(systemctl is-active nginx)${NC}"
        echo -e "${OK}Xray: $(systemctl is-active xray)${NC}"
        echo -e "${OK}Monitor: $(systemctl is-active realityghost-monitor)${NC}"
        echo -ne "\n${YELLOW}Enter بزن...${NC}"; read -r
        ;;
      0) return ;;
    esac
  done
}

# ─── Management Menu ──────────────────────────────────────────────────
manage_menu() {
  while true; do
    clear
    echo -e "${PURPLE}══════════════════════════════════════${NC}"
    echo -e "${PURPLE}   ${FLAG_RAW} RealityGhost PRO — ${LOC}${NC}"
    echo -e "${PURPLE}   ${CYAN}${DOMAIN}${NC}"
    echo -e "${PURPLE}══════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${GREEN}1.${NC} 📋 نمایش اطلاعات اتصال"
    echo -e "  ${GREEN}2.${NC} ⚙️  مدیریت کانفیگ‌ها"
    echo -e "  ${GREEN}3.${NC} 🔌 مدیریت پورت‌ها (فایروال)"
    echo -e "  ${GREEN}4.${NC} 🔄 چرخاندن Short IDs"
    echo -e "  ${GREEN}5.${NC} 🏗️  بازسازی ساب‌اسکریپشن و پنل"
    echo -e "  ${GREEN}6.${NC} 🔄 ری‌استارت سرویس‌ها"
    echo -e "  ${GREEN}7.${NC} 🤖 مدیریت ربات تلگرام"
    echo -e "  ${GREEN}8.${NC} 🔄 بروزرسانی از گیتهاب (git pull)"
    echo -e "  ${GREEN}9.${NC} 🗑️  حذف کامل"
    echo -e "  ${GREEN}0.${NC} خروج"
    echo ""
    echo -ne "${BOLD}انتخاب: ${NC}"
    read -r opt

    case $opt in
      1) show_info ;;
      2) config_manager ;;
      3) port_manager ;;
      4)
        echo -e "${INFO}چرخاندن Short IDs..."
        for i in $(seq 0 5); do
          local new_sid=$(openssl rand -hex 8)
          jq --argjson idx "$i" --arg sid "$new_sid" \
            '.inbounds[0].streamSettings.realitySettings.shortIds[$idx] = $sid' \
            "$CONFIG_DIR/config.json" > "$CONFIG_DIR/config.json.tmp"
          mv "$CONFIG_DIR/config.json.tmp" "$CONFIG_DIR/config.json"
        done
        systemctl restart xray
        build_subscription
        build_panel
        echo -e "${OK}همه Short IDs چرخیده شدن${NC}"
        echo -ne "\n${YELLOW}Enter بزن...${NC}"; read -r
        ;;
      5)
        build_subscription
        build_panel
        echo -e "${OK}ساب و پنل بازسازی شدن${NC}"
        echo -ne "\n${YELLOW}Enter بزن...${NC}"; read -r
        ;;
      6)
        systemctl restart nginx xray realityghost-monitor
        echo -e "${OK}سرویس‌ها ری‌استارت شدن${NC}"
        echo -ne "\n${YELLOW}Enter بزن...${NC}"; read -r
        ;;
      7)
        bot_menu
        ;;
      8)
        pull_update
        echo -ne "\n${YELLOW}Enter بزن...${NC}"; read -r
        ;;
      9) uninstall; break ;;
      0) exit 0 ;;
      *) echo -e "${WARN}گزینه نامعتبر${NC}"; sleep 1 ;;
    esac
  done
}

# ─── Rotation (cron) ──────────────────────────────────────────────────
setup_rotation() {
  cat <<CRONEOF | tee /etc/cron.d/realityghost-rotate > /dev/null
0 5 */3 * * root ${CONFIG_DIR}/RealityGhostPro.sh manual-rotate
CRONEOF
  chmod +x /etc/cron.d/realityghost-rotate
  echo -e "${OK}چرخش خودکار هر ۳ روز تنظیم شد${NC}"
}

manual_rotate() {
  echo -e "${INFO}چرخش دستی..."
  for i in $(seq 0 5); do
    local new_sid=$(openssl rand -hex 8)
    jq --argjson idx "$i" --arg sid "$new_sid" \
      '.inbounds[0].streamSettings.realitySettings.shortIds[$idx] = $sid' \
      "$CONFIG_DIR/config.json" > "$CONFIG_DIR/config.json.tmp"
    mv "$CONFIG_DIR/config.json.tmp" "$CONFIG_DIR/config.json"
  done
  systemctl restart xray
  build_subscription
  build_panel
  echo -e "${OK}چرخش کامل شد${NC}"
}

# ─── Pull / Update Self ────────────────────────────────────────────────
pull_update() {
  echo -e "${INFO}بررسی آخرین نسخه از گیتهاب..."
  local repo_url="https://github.com/sheshocked/RealityGhostPro.git"
  local script_dir="$(cd "$(dirname "$0")" && pwd)"
  local backup_dir="/tmp/realityghost-backup-$(date +%s)"

  # Check git is installed
  if ! command -v git &>/dev/null; then
    echo -e "${ERR}git روی سیستم نصب نیست. نصب می‌کنم..."
    apt-get install -y git 2>/dev/null || {
      echo -e "${ERR}نصب git ناموفق. لطفاً دستی نصب کن${NC}"
      return 1
    }
  fi

  # Check if .git exists
  if [[ ! -d "$script_dir/.git" ]]; then
    echo -e "${WARN}پوشه .git پیدا نشد. شاید پروژه با zip دانلود شده${NC}"
    echo -ne "${INFO}می‌خوای کلون تازه کنم؟ (y/n): "
    read -r ans
    if [[ "$ans" == "y" || "$ans" == "Y" ]]; then
      cd /tmp || return 1
      rm -rf RealityGhostPro-tmp
      git clone "$repo_url" RealityGhostPro-tmp 2>&1
      if [[ $? -ne 0 ]]; then
        echo -e "${ERR}کلون ناموفق. اینترنت یا ریپازیتوری رو چک کن${NC}"
        return 1
      fi
      cp -r "$script_dir" "$backup_dir" 2>/dev/null
      cp -rf /tmp/RealityGhostPro-tmp/* "$script_dir/"
      rm -rf /tmp/RealityGhostPro-tmp
      chmod +x "$script_dir/RealityGhostPro.sh"
      echo -e "${OK}بروزرسانی کامل شد! فایل قبلی توی ${backup_dir} بکاپ گرفته شد${NC}"
    fi
    return 0
  fi

  # Backup current
  cp -r "$script_dir" "$backup_dir" 2>/dev/null

  # Try to pull
  cd "$script_dir" || return 1
  local old_hash=$(git rev-parse HEAD 2>/dev/null)
  echo -e "${INFO}در حال دریافت تغییرات..."

  git fetch origin 2>&1
  if [[ $? -ne 0 ]]; then
    echo -e "${ERR}ارتباط با گیتهاب برقرار نشد. اینترنت رو چک کن${NC}"
    return 1
  fi

  local behind=$(git rev-list HEAD..origin/main --count 2>/dev/null)
  if [[ "$behind" -gt 0 ]]; then
    echo -e "${INFO}${behind} تا تغییر جدید پیدا شد${NC}"
    echo -ne "${YELLOW}اعمال تغییرات؟ (y/n): ${NC}"
    read -r ans
    if [[ "$ans" == "y" || "$ans" == "Y" ]]; then
      git stash 2>/dev/null
      git pull origin main 2>&1
      if [[ $? -eq 0 ]]; then
        chmod +x "$script_dir/RealityGhostPro.sh"
        local new_hash=$(git rev-parse HEAD 2>/dev/null)
        echo -e "${OK}بروزرسانی شد!${NC}"
        echo -e "${OK}نسخه قدیمی: ${old_hash:0:8} → نسخه جدید: ${new_hash:0:8}${NC}"
        echo -e "${OK}بکاپ: ${backup_dir}${NC}"
      else
        echo -e "${ERR}بروزرسانی ناموفق. بکاپ توی ${backup_dir}${NC}"
        return 1
      fi
    else
      echo -e "${INFO}بروزرسانی لغو شد${NC}"
    fi
  else
    echo -e "${OK}شما آخرین نسخه رو دارید!${NC}"
  fi
}
uninstall() {
  echo -e "${WARN}حذف کامل RealityGhost PRO...${NC}"
  echo -ne "${RED}مطمئنی؟ (yes/no): ${NC}"
  read -r ans
  [[ "$ans" != "yes" ]] && { echo -e "${INFO}لغو شد${NC}"; return; }

  systemctl stop xray nginx realityghost-monitor 2>/dev/null
  systemctl disable xray realityghost-monitor 2>/dev/null
  rm -rf "$INSTALL_DIR" "$CONFIG_DIR" "$STATUS_DIR" "$STATE_DIR" "$SUB_DIR"
  rm -f /etc/systemd/system/xray.service /etc/systemd/system/realityghost-monitor.service
  rm -f "$MONITOR_SCRIPT" /etc/cron.d/realityghost-rotate
  rm -f /etc/nginx/nginx.conf
  cp /etc/nginx/nginx.conf.backup /etc/nginx/nginx.conf 2>/dev/null
  systemctl daemon-reload
  systemctl restart nginx 2>/dev/null
  echo -e "${OK}حذف کامل شد${NC}"
}

# ─── Bot Setup ────────────────────────────────────────────────────────
bot_setup() {
  echo -e "${INFO}نصب ربات تلگرام مدیریت کاربران..."
  chmod +x /usr/local/bin/rg-bot.py

  # Initialize bot
  /usr/local/bin/rg-bot.py init

  echo -ne "${BOLD}🤖 توکن ربات تلگرامت رو وارد کن (از @BotFather): ${NC}"
  read -r bot_token
  if [[ -z "$bot_token" ]]; then
    echo -e "${WARN}بدون توکن - ربات فعال نمیشه. بعداً می‌تونی با 'manage' ست کنی${NC}"
    return
  fi

  # Save token to config
  local cfg="{\"enabled\": true, \"token\": \"$bot_token\", \"domain\": \"$DOMAIN\", \"admin_ids\": []}"
  mkdir -p /etc/realityghost
  echo "$cfg" > /etc/realityghost/bot_config.json

  # Create systemd service for bot
  cat > /etc/systemd/system/realityghost-bot.service <<BOTEOF
[Unit]
Description=RealityGhost PRO Telegram Bot
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

  if systemctl is-active realityghost-bot &>/dev/null; then
    echo -e "${OK}🤖 ربات فعال شد!"
    echo -e "${INFO}تو تلگرام برو به رباتت و /start بزن${NC}"
  else
    echo -e "${WARN}⚠ ربات استارت نشد. لاگ رو چک کن: journalctl -u realityghost-bot${NC}"
  fi
}

bot_menu() {
  while true; do
    clear
    echo -e "${CYAN}══════════════════════════════════════${NC}"
    echo -e "${CYAN}   🤖 مدیریت ربات تلگرام${NC}"
    echo -e "${CYAN}══════════════════════════════════════${NC}"
    echo ""

    local bot_status="غیرفعال ❌"
    systemctl is-active realityghost-bot &>/dev/null && bot_status="فعال ✅"
    echo -e "  وضعیت ربات: ${bot_status}"

    if [[ -f /etc/realityghost/bot_config.json ]]; then
      local tk=$(jq -r '.token // ""' /etc/realityghost/bot_config.json 2>/dev/null)
      if [[ -n "$tk" && "${#tk}" -gt 10 ]]; then
        echo -e "  توکن: ${tk:0:12}...${tk: -4}"
      else
        echo -e "  ${WARN}توکن تنظیم نشده${NC}"
      fi
    fi
    echo ""

    echo -e "  ${GREEN}1.${NC} 🔄 ری‌استارت ربات"
    echo -e "  ${GREEN}2.${NC} 🔑 تنظیم توکن جدید"
    echo -e "  ${GREEN}3.${NC} 📋 نمایش کاربران"
    echo -e "  ${GREEN}4.${NC} ➕ افزودن کاربر"
    echo -e "  ${GREEN}5.${NC} ❌ حذف کاربر"
    echo -e "  ${GREEN}6.${NC} 📊 آمار ربات"
    echo -e "  ${GREEN}0.${NC} برگشت"
    echo ""
    echo -ne "${BOLD}انتخاب: ${NC}"
    read -r opt

    case $opt in
      1)
        systemctl restart realityghost-bot
        echo -e "${OK}ربات ری‌استارت شد${NC}"
        sleep 2;;
      2)
        echo -ne "${BOLD}توکن جدید: ${NC}"
        read -r new_tk
        if [[ -n "$new_tk" ]]; then
          jq --arg t "$new_tk" '.token = $t | .enabled = true' /etc/realityghost/bot_config.json > /tmp/botcfg.json && mv /tmp/botcfg.json /etc/realityghost/bot_config.json
          systemctl restart realityghost-bot
          echo -e "${OK}توکن ذخیره و ربات ری‌استارت شد${NC}"
        fi
        sleep 2;;
      3)
        /usr/local/bin/rg-bot.py list 2>&1
        echo -ne "\n${YELLOW}Enter بزن...${NC}"; read -r;;
      4)
        echo -ne "نام کاربر: "; read -r uname
        echo -ne "حجم محدودیت (MB, 0 = بی‌محدود): "; read -r ulimit
        echo -ne "تعداد روز (0 = نامحدود): "; read -r udays
        /usr/local/bin/rg-bot.py adduser "$uname" "${ulimit:-0}" "${udays:-0}"
        echo -ne "\n${YELLOW}Enter بزن...${NC}"; read -r;;
      5)
        echo -ne "آیدی کاربر: "; read -r uid
        /usr/local/bin/rg-bot.py deluser "$uid" 2>&1 || echo "❌ خطا"
        echo -ne "\n${YELLOW}Enter بزن...${NC}"; read -r;;
      6)
        /usr/local/bin/rg-bot.py stats 2>&1
        echo -ne "\n${YELLOW}Enter بزن...${NC}"; read -r;;
      0) return;;
    esac
  done
}

# ─── Main Installation ────────────────────────────────────────────────
main_install() {
  echo ""
  echo -e "${PURPLE}╔══════════════════════════════════════╗${NC}"
  echo -e "${PURPLE}║   ${WHITE}RealityGhost PRO v4.2${NC}              ${PURPLE}║${NC}"
  echo -e "${PURPLE}║   ${CYAN}Xray VLESS+Reality Installer${NC}       ${PURPLE}║${NC}"
  echo -e "${PURPLE}╚══════════════════════════════════════╝${NC}"
  echo ""

  check_root
  detect_location
  echo -e "${INFO}سرور شما: ${FLAG_RAW} ${LOC}${NC}"
  echo ""

  # Get domain + email
  if [[ -z "$DOMAIN" ]]; then
    echo -ne "${BOLD}🌐 دامنه رو وارد کن (مثلاً your-domain.com): ${NC}"
    read -r DOMAIN
  fi
  if [[ -z "$EMAIL" ]]; then
    echo -ne "${BOLD}📧 ایمیل برای SSL: ${NC}"
    read -r EMAIL
  fi

  echo ""
  echo -e "${INFO}شروع نصب با:${NC}"
  echo -e "  ${CYAN}دامنه:${NC} ${DOMAIN}"
  echo -e "  ${CYAN}ایمیل:${NC} ${EMAIL}"
  echo -e "  ${CYAN}لوکیشن:${NC} ${FLAG_RAW} ${LOC}"
  echo ""
  echo -ne "${YELLOW}ادامه می‌دیم؟ (y/n): ${NC}"
  read -r ans
  [[ "$ans" != "y" && "$ans" != "Y" ]] && { echo -e "${INFO}لغو شد${NC}"; exit 0; }

  # Run steps
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

  # Firewall - open ports
  echo -e "${INFO}باز کردن پورت‌های فایروال..."
  for p in 443 80; do
    iptables -C INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null || {
      iptables -A INPUT -p tcp --dport "$p" -j ACCEPT
    }
  done
  if command -v netfilter-persistent &>/dev/null; then
    netfilter-persistent save 2>/dev/null
  fi

  # Ask for bot setup
  echo ""
  echo -ne "${YELLOW}آیا می‌خوای ربات تلگرام برای مدیریت کاربران نصب کنی؟ (y/n): ${NC}"
  read -r setup_bot
  if [[ "$setup_bot" == "y" || "$setup_bot" == "Y" ]]; then
    bot_setup
  fi

  # Restart all
  systemctl restart nginx xray realityghost-monitor

  echo ""
  echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║   نصب با موفقیت تکمیل شد! 🎉        ║${NC}"
  echo -e "${GREEN}║   ${FLAG_RAW} ${LOC} — ${DOMAIN}        ${NC}"
  echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  ${CYAN}📊 پنل وضعیت:${NC}  https://${DOMAIN}/status/"
  echo -e "  ${CYAN}📥 ساب:${NC}       https://${DOMAIN}/sub"
  echo ""
  show_info
}

# ─── Entry Point ──────────────────────────────────────────────────────
case "${1,,}" in
  install)
    main_install
    ;;
  manage)
    check_root
    detect_location
    # Load existing config
    if [[ -f "$CONFIG_DIR/config.json" ]]; then
      DOMAIN=$(jq -r '.inbounds[0].settings.clients[0].email' "$CONFIG_DIR/config.json" 2>/dev/null | sed 's/user@//')
      [[ -z "$DOMAIN" || "$DOMAIN" == "null" ]] && DOMAIN="your-domain.com"
    else
      DOMAIN="${DOMAIN:-your-domain.com}"
    fi
    manage_menu
    ;;
  manual-rotate)
    check_root
    manual_rotate
    ;;
  pull)
    check_root
    pull_update
    ;;
  uninstall)
    check_root
    uninstall
    ;;
  *)
    echo ""
    echo -e "${PURPLE}RealityGhost PRO v4.0${NC}"
    echo -e "${CYAN}Xray VLESS+Reality Installer & Manager${NC}"
    echo ""
    echo -e "${BOLD}دستورات:${NC}"
    echo -e "  ${GREEN}bash RealityGhostPro.sh install${NC}     — نصب کامل"
    echo -e "  ${GREEN}bash RealityGhostPro.sh manage${NC}      — منوی مدیریت"
    echo -e "  ${GREEN}bash RealityGhostPro.sh manual-rotate${NC}— چرخش دستی Short IDs"
    echo -e "  ${GREEN}bash RealityGhostPro.sh pull${NC}         — بروزرسانی از گیتهاب"
    echo -e "  ${GREEN}bash RealityGhostPro.sh uninstall${NC}   — حذف کامل"
    echo ""
    ;;
esac
