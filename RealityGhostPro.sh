#!/bin/bash

# RealityGhost PRO - Production-grade Xray VLESS+Reality Script
# Includes: SNI Passthrough, Status Page with Traffic Stats, Auto-Rotation.

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
INFO="${CYAN}[INFO]${NC}"
OK="${GREEN}[OK]${NC}"
ERR="${RED}[ERROR]${NC}"
WARN="${YELLOW}[WARN]${NC}"

# Environment variables with defaults
DOMAIN=${DOMAIN:-""}
EMAIL=${EMAIL:-""}
XHTTP_PORT=${XHTTP_PORT:-"2053"}
SUB_PORT=${SUB_PORT:-"8443"}
XRAY_TCP_PORT=${XRAY_TCP_PORT:-"8444"}
INSTALL_DIR="/usr/local/share/xray"
CONFIG_DIR="/usr/local/etc/xray"
NGINX_CONF_DIR="/etc/nginx"

# Check if root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${ERR}This script must be run as root${NC}"
        exit 1
    fi
}

# Install dependencies
install_dependencies() {
    echo -e "${INFO}Installing dependencies...${NC}"
    apt-get update -y
    apt-get install -y wget curl unzip uuidgen jq qrencode certbot nginx-extras logrotate bc
}

# Generate UUID
generate_uuid() {
    if command -v uuidgen &> /dev/null; then
        uuidgen
    else
        cat /proc/sys/kernel/random/uuid
    fi
}

# Generate REALITY keys
generate_reality_keys() {
    echo -e "${INFO}Generating REALITY keys...${NC}"
    local keys=$(/usr/local/bin/xray x25519)
    local private_key=$(echo "$keys" | grep "Private" | awk '{print $3}')
    local public_key=$(echo "$keys" | grep "Public" | awk '{print $3}')
    echo "$private_key:$public_key"
}

# Install Xray-core
install_xray() {
    echo -e "${INFO}Installing Xray-core...${NC}"
    
    mkdir -p $INSTALL_DIR $CONFIG_DIR
    
    local xray_version=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases/latest" | grep '"tag_name":' | cut -d '"' -f 4)
    
    if [[ -z "$xray_version" ]]; then
        echo -e "${WARN}Failed to fetch latest version. Using fallback v25.9.11...${NC}"
        xray_version="v25.9.11"
    fi
    
    wget -O /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/download/${xray_version}/Xray-linux-64.zip"
    unzip -o /tmp/xray.zip -d $INSTALL_DIR
    chmod +x $INSTALL_DIR/xray
    ln -sf $INSTALL_DIR/xray /usr/local/bin/xray
    
    cat <<EOF | sudo tee /etc/systemd/system/xray.service
[Unit]
Description=Xray Service
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
EOF
    
    systemctl daemon-reload
    systemctl enable xray
    echo -e "${OK}Xray-core installed successfully${NC}"
}

# Install Let's Encrypt certificate
install_certbot() {
    if [[ -z "$DOMAIN" ]]; then
        read -p "Enter your domain (e.g., sub.example.com): " DOMAIN
    fi
    if [[ -z "$EMAIL" ]]; then
        read -p "Enter your email for Let's Encrypt: " EMAIL
    fi
    
    echo -e "${INFO}Obtaining SSL certificate for $DOMAIN...${NC}"
    systemctl stop nginx 2>/dev/null
    
    certbot certonly --standalone \
        -d "$DOMAIN" \
        -d "sub.$DOMAIN" \
        --non-interactive \
        --agree-tos \
        --email "$EMAIL"
    
    if [[ $? -ne 0 ]]; then
        echo -e "${ERR}Failed to obtain certificate${NC}"
        exit 1
    fi
    echo -e "${OK}Certificate installed successfully${NC}"
}

# Configure Nginx
configure_nginx() {
    echo -e "${INFO}Configuring Nginx...${NC}"
    cp $NGINX_CONF_DIR/nginx.conf $NGINX_CONF_DIR/nginx.conf.backup 2>/dev/null
    
    cat <<EOF | sudo tee $NGINX_CONF_DIR/nginx.conf
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 768;
}

stream {
    map \$ssl_preread_server_name \$backend {
        sub.$DOMAIN nginx_https;
        default xray_tcp;
    }
    
    upstream xray_tcp {
        server 127.0.0.1:$XRAY_TCP_PORT;
    }
    
    upstream nginx_https {
        server 127.0.0.1:$SUB_PORT;
    }
    
    server {
        listen 443;
        proxy_pass \$backend;
        proxy_protocol on;
        ssl_preread on;
    }
}

http {
    server {
        listen 127.0.0.1:$SUB_PORT ssl proxy_protocol;
        server_name sub.$DOMAIN;
        
        ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
        
        location /sub {
            root /var/www/html;
            index sub.txt;
            try_files \$uri \$uri/ =404;
        }
        
        location /status/ {
            alias /var/www/html/status/;
            index index.html;
            try_files \$uri \$uri/ /status/index.html;
            
            location ~* \.json$ {
                add_header 'Content-Type' 'application/json';
            }
        }
    }
}
EOF
    
    mkdir -p /var/www/html
    echo "# Subscription placeholder" > /var/www/html/sub.txt
    
    nginx -t
    if [[ $? -ne 0 ]]; then
        echo -e "${ERR}Nginx configuration test failed${NC}"
        exit 1
    fi
    systemctl restart nginx
    systemctl enable nginx
    echo -e "${OK}Nginx configured successfully${NC}"
}

# Configure Xray
configure_xray() {
    echo -e "${INFO}Configuring Xray...${NC}"
    
    local uuid=$(generate_uuid)
    local keys=$(generate_reality_keys)
    local private_key=$(echo "$keys" | cut -d ':' -f 1)
    local public_key=$(echo "$keys" | cut -d ':' -f 2)
    local short_id=$(openssl rand -hex 8)
    
    cat <<EOF | sudo tee $CONFIG_DIR/config.json
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "port": $XRAY_TCP_PORT,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "$uuid", "flow": "xtls-rprx-vision", "level": 0, "email": "user@$DOMAIN" }],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false, "dest": "www.microsoft.com:443", "xver": 0,
          "serverNames": ["www.microsoft.com", "microsoft.com"],
          "privateKey": "$private_key", "shortIds": ["$short_id"]
        }
      },
      "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"] }
    },
    {
      "port": $XHTTP_PORT,
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "$uuid", "level": 0, "email": "xhttp@$DOMAIN" }],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "xhttpSettings": { "path": "/xh", "host": "www.microsoft.com" },
        "security": "reality",
        "realitySettings": {
          "show": false, "dest": "www.microsoft.com:443", "xver": 0,
          "serverNames": ["www.microsoft.com"],
          "privateKey": "$private_key", "shortIds": ["$short_id"]
        }
      },
      "sniffing": { "enabled": true, "destOverride": ["http", "tls"] }
    }
  ],
  "outbounds": [{ "protocol": "freedom", "settings": {} }]
}
EOF
    
    chmod 600 $CONFIG_DIR/config.json
    
    cat <<EOF | sudo tee $CONFIG_DIR/client_info.txt
===== RealityGhostPro Client Info =====
Domain: $DOMAIN
UUID: $uuid
Public Key: $public_key
Short ID: $short_id
XHTTP Port: $XHTTP_PORT
=======================================
VLESS TCP: vless://$uuid@$DOMAIN:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=$public_key&sid=$short_id&type=tcp#RealityGhostPro-TCP
VLESS XHTTP: vless://$uuid@$DOMAIN:$XHTTP_PORT?encryption=none&security=reality&sni=www.microsoft.com&fp=chrome&pbk=$public_key&sid=$short_id&type=xhttp&path=/xh&host=www.microsoft.com#RealityGhostPro-XHTTP
EOF
    
    echo -e "${OK}Xray configured successfully${NC}"
}

# Setup rotation
setup_rotation() {
    cat <<EOF | sudo tee /etc/cron.d/realityghost-rotate
0 5 */3 * * root $CONFIG_DIR/RealityGhostPro.sh manual-rotate
EOF
    chmod +x /etc/cron.d/realityghost-rotate
}

manual_rotate() {
    echo -e "${INFO}Performing manual rotation...${NC}"
    local short_id=$(openssl rand -hex 8)
    jq --arg sid "$short_id" '.inbounds[].streamSettings.realitySettings.shortIds = [$sid]' $CONFIG_DIR/config.json > $CONFIG_DIR/config.json.tmp
    mv $CONFIG_DIR/config.json.tmp $CONFIG_DIR/config.json
    systemctl restart xray
    echo -e "${OK}Rotation complete. New Short ID: $short_id${NC}"
}

# Install Status Monitor (HTML + Backend Logic Embedded)
install_monitor() {
    echo -e "${INFO}Installing Status Monitor...${NC}"
    mkdir -p /var/www/html/status /var/lib/realityghost
    
    # 1. Backend Monitor Script
    cat <<'EOF' | sudo tee /usr/local/bin/realityghost_monitor.sh > /dev/null
#!/bin/bash
OUTPUT_FILE="/var/www/html/status/stats.json"
STATE_FILE="/var/lib/realityghost/state.json"
IFACE=$(ip route | grep default | awk '{print $5}' | head -n 1)

if [ ! -f "$STATE_FILE" ]; then
    echo '{"today":0, "month":0, "total":0, "last_bytes":0, "last_day":'$(date +%d)', "last_month":'$(date +%m)'}' > "$STATE_FILE"
fi

while true; do
    # System Stats
    cpu_idle=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/")
    cpu_usage=$(awk "BEGIN {print 100 - $cpu_idle}")
    ram_total=$(free -m | awk '/Mem/ {print $2}')
    ram_used=$(free -m | awk '/Mem/ {print $3}')
    ram_usage=$(awk "BEGIN {printf \"%.2f\", ($ram_used/$ram_total)*100}")
    disk_total=$(df -m / | awk 'NR==2 {print $2}')
    disk_used=$(df -m / | awk 'NR==2 {print $3}')
    disk_usage=$(awk "BEGIN {printf \"%.2f\", ($disk_used/$disk_total)*100}")
    uptime_str=$(uptime -p | sed 's/up //')
    xray_status=$(systemctl is-active xray)
    nginx_status=$(systemctl is-active nginx)
    
    # Traffic Stats
    rx_bytes=$(cat /sys/class/net/$IFACE/statistics/rx_bytes)
    tx_bytes=$(cat /sys/class/net/$IFACE/statistics/tx_bytes)
    current_bytes=$((rx_bytes + tx_bytes))
    
    today=$(jq '.today' $STATE_FILE)
    month=$(jq '.month' $STATE_FILE)
    total=$(jq '.total' $STATE_FILE)
    last_bytes=$(jq '.last_bytes' $STATE_FILE)
    last_day=$(jq '.last_day' $STATE_FILE)
    last_month=$(jq '.last_month' $STATE_FILE)
    current_day=$(date +%d)
    current_month=$(date +%m)
    
    delta=$((current_bytes - last_bytes))
    if [ "$delta" -lt 0 ]; then delta=0; fi
    if [ "$current_day" != "$last_day" ]; then today=0; fi
    if [ "$current_month" != "$last_month" ]; then month=0; fi
    
    today=$((today + delta))
    month=$((month + delta))
    total=$((total + delta))
    
    jq -n --argjson t "$today" --argjson m "$month" --argjson tot "$total" --argjson lb "$current_bytes" --argjson ld "$current_day" --argjson lm "$current_month" '{today:$t, month:$m, total:$tot, last_bytes:$lb, last_day:$ld, last_month:$lm}' > $STATE_FILE
    
    jq -n \
      --arg cpu "$cpu_usage" \
      --arg rt "$ram_total" --arg ru "$ram_used" --arg rup "$ram_usage" \
      --arg dt "$disk_total" --arg du "$disk_used" --arg dup "$disk_usage" \
      --arg up "$uptime_str" --arg x "$xray_status" --arg ng "$nginx_status" \
      --argjson t "$today" --argjson m "$month" --argjson tot "$total" \
      '{cpu:$cpu, ram:{t:$rt,u:$ru,p:$rup}, disk:{t:$dt,u:$du,p:$dup}, uptime:$up, xray:$x, nginx:$ng, traffic:{today:$t, month:$m, total:$tot}}' > $OUTPUT_FILE
      
    chown www-data:www-data $OUTPUT_FILE
    sleep 2
done
EOF
    chmod +x /usr/local/bin/realityghost_monitor.sh
    
    # 2. Systemd Service
    cat <<'EOF' | sudo tee /etc/systemd/system/realityghost-monitor.service > /dev/null
[Unit]
Description=RealityGhost Pro Monitor
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash /usr/local/bin/realityghost_monitor.sh
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
EOF

    # 3. Frontend HTML
    cat <<'EOF' | sudo tee /var/www/html/status/index.html > /dev/null
<!DOCTYPE html>
<html lang="fa" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>RealityGhost Pro - Status</title>
    <style>
        :root { --bg: #121212; --card: #1e1e1e; --txt: #fff; --mut: #909090; --blue: #3b82f6; --green: #10b981; --red: #ef4444; --yellow: #f59e0b; }
        * { box-sizing: border-box; }
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: var(--bg); color: var(--txt); margin: 0; padding: 20px; display: flex; justify-content: center; }
        .container { max-width: 900px; width: 100%; }
        .header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 30px; padding-bottom: 20px; border-bottom: 1px solid #333; }
        .header h2 { margin: 0; font-size: 1.5rem; }
        .badges { display: flex; gap: 10px; }
        .badge { padding: 5px 12px; border-radius: 20px; font-size: 0.8rem; font-weight: bold; }
        .vip { background: var(--yellow); color: #000; }
        .proto { background: var(--blue); color: #fff; }
        .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; }
        .card { background: var(--card); padding: 20px; border-radius: 12px; box-shadow: 0 4px 6px rgba(0,0,0,0.3); }
        .card h3 { margin-top: 0; font-size: 1rem; color: var(--mut); display: flex; justify-content: space-between; align-items: center; }
        .val { font-size: 1.6rem; font-weight: bold; margin: 10px 0; }
        .bar { background: #333; height: 6px; border-radius: 3px; overflow: hidden; }
        .fill { height: 100%; transition: width 0.5s; }
        .dot { width: 10px; height: 10px; border-radius: 50%; display: inline-block; }
        .on { background: var(--green); } .off { background: var(--red); }
        .t-grid { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 15px; text-align: center; }
        .t-item span { display: block; color: var(--mut); font-size: 0.8rem; }
        .t-item strong { font-size: 1.1rem; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <div class="user-info">
                <h2>IR amir</h2>
                <span style="color: var(--mut); font-size: 0.9rem;">RealityGhost Pro</span>
            </div>
            <div class="badges">
                <span class="badge vip">VIP</span>
                <span class="badge proto">VLESS Reality</span>
            </div>
        </div>
        
        <div class="grid">
            <div class="card">
                <h3>وضعیت سرویس‌ها</h3>
                <div style="display: flex; flex-direction: column; gap: 10px;">
                    <div style="display:flex; justify-content:space-between;">NGINX <span id="ng" class="dot off"></span></div>
                    <div style="display:flex; justify-content:space-between;">Xray <span id="xr" class="dot off"></span></div>
                </div>
            </div>
            <div class="card">
                <h3>مدت زمان روشن بودن</h3>
                <div class="val" id="up">در حال بارگذاری...</div>
            </div>
            <div class="card">
                <h3>CPU</h3>
                <div class="val" id="cpu-v">0%</div>
                <div class="bar"><div id="cpu-b" class="fill" style="background: var(--blue); width: 0%;"></div></div>
            </div>
            <div class="card">
                <h3>RAM</h3>
                <div class="val" id="ram-v">0%</div>
                <div class="bar"><div id="ram-b" class="fill" style="background: var(--green); width: 0%;"></div></div>
            </div>
            <div class="card">
                <h3>فضای ذخیره‌سازی</h3>
                <div class="val" id="dsk-v">0%</div>
                <div class="bar"><div id="dsk-b" class="fill" style="background: var(--yellow); width: 0%;"></div></div>
            </div>
            <div class="card" style="grid-column: span 2;">
                <h3>ترافیک مصرفی</h3>
                <div class="t-grid">
                    <div class="t-item"><span>امروز</span><strong id="t-today">0 B</strong></div>
                    <div class="t-item"><span>این ماه</span><strong id="t-month">0 B</strong></div>
                    <div class="t-item"><span>کل</span><strong id="t-total">0 B</strong></div>
                </div>
            </div>
        </div>
    </div>

    <script>
        function fmt(b) {
            if(b===0) return '0 B';
            const k=1024, s=['B','KB','MB','GB','TB'];
            const i=Math.floor(Math.log(b)/Math.log(k));
            return parseFloat((b/Math.pow(k,i)).toFixed(2))+' '+s[i];
        }
        async function upd() {
            try {
                const r = await fetch('/status/stats.json?ts='+Date.now());
                if(!r.ok) throw err;
                const d = await r.json();
                
                document.getElementById('up').innerText = d.uptime;
                document.getElementById('ng').className = 'dot ' + (d.nginx==='active'?'on':'off');
                document.getElementById('xr').className = 'dot ' + (d.xray==='active'?'on':'off');
                
                const cpu = parseFloat(d.cpu).toFixed(1);
                document.getElementById('cpu-v').innerText = cpu+'%';
                document.getElementById('cpu-b').style.width = cpu+'%';
                
                const ram = parseFloat(d.ram.p).toFixed(1);
                document.getElementById('ram-v').innerText = ram+'%';
                document.getElementById('ram-b').style.width = ram+'%';
                
                const dsk = parseFloat(d.disk.p).toFixed(1);
                document.getElementById('dsk-v').innerText = dsk+'%';
                document.getElementById('dsk-b').style.width = dsk+'%';
                
                document.getElementById('t-today').innerText = fmt(d.traffic.today);
                document.getElementById('t-month').innerText = fmt(d.traffic.month);
                document.getElementById('t-total').innerText = fmt(d.traffic.total);
                
            } catch(e) { console.error('Stats fetch error', e); }
        }
        setInterval(upd, 2000);
        upd();
    </script>
</body>
</html>
EOF
    chown -R www-data:www-data /var/www/html/status
    
    systemctl daemon-reload
    systemctl enable realityghost-monitor
    systemctl restart realityghost-monitor
    echo -e "${OK}Status Monitor installed successfully${NC}"
}

# Management Menu
manage_menu() {
    clear
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}   RealityGhost PRO Management Menu    ${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo "1. Show Client Info & Links"
    echo "2. Rotate Fingerprint (Safe)"
    echo "3. Restart Services"
    echo "4. Uninstall RealityGhostPro"
    echo "0. Exit"
    echo -n "Select: "
    read opt
    
    case $opt in
        1) cat $CONFIG_DIR/client_info.txt; read ;;
        2) manual_rotate ;;
        3) systemctl restart nginx xray realityghost-monitor; echo "Restarted."; read ;;
        4) uninstall ;;
        0) exit 0 ;;
        *) echo "Invalid"; read ;;
    esac
}

uninstall() {
    echo -e "${WARN}Uninstalling...${NC}"
    systemctl stop xray nginx realityghost-monitor
    systemctl disable xray realityghost-monitor
    rm -rf $INSTALL_DIR $CONFIG_DIR /var/www/html/status /var/lib/realityghost
    rm -f /etc/systemd/system/xray.service /etc/systemd/system/realityghost-monitor.service
    rm -f /usr/local/bin/realityghost_monitor.sh /etc/nginx/nginx.conf /etc/cron.d/realityghost-rotate
    mv $NGINX_CONF_DIR/nginx.conf.backup $NGINX_CONF_DIR/nginx.conf 2>/dev/null
    systemctl daemon-reload
    systemctl restart nginx
    echo -e "${OK}Uninstalled${NC}"
}

case "$1" in
    install)
        check_root
        install_dependencies
        install_xray
        install_certbot
        configure_nginx
        configure_xray
        install_monitor
        setup_rotation
        systemctl restart nginx xray realityghost-monitor
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}  Installation Complete!              ${NC}"
        echo -e "${GREEN}========================================${NC}"
        cat $CONFIG_DIR/client_info.txt
        ;;
    manage) check_root; manage_menu ;;
    manual-rotate) check_root; manual_rotate ;;
    uninstall) check_root; uninstall ;;
    *) echo "Usage: $0 {install|manage|manual-rotate|uninstall}" ;;
esac
