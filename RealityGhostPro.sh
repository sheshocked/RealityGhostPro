#!/bin/bash

# RealityGhost PRO - Production-grade Xray VLESS+Reality Script
# Fork of ghostmcf/RealityGhost with critical architectural fixes.

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
    apt-get install -y wget curl unzip uuidgen jq qrencode certbot nginx logrotate
    
    # Ensure nginx stream module is available (usually built-in on Debian/Ubuntu)
    if ! nginx -V 2>&1 | grep -q "stream"; then
        echo -e "${ERR}Nginx does not have the stream module compiled in. Please install nginx-extras or standard nginx.${NC}"
        exit 1
    fi
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
    
    # Create directories
    mkdir -p $INSTALL_DIR
    mkdir -p $CONFIG_DIR
    
    # Try to get latest version from GitHub API
    local xray_version=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases/latest" | grep '"tag_name":' | cut -d '"' -f 4)
    
    if [[ -z "$xray_version" ]]; then
        echo -e "${WARN}Failed to fetch latest version from GitHub API. Using fallback version v25.9.11...${NC}"
        xray_version="v25.9.11"
    fi
    
    local download_url="https://github.com/XTLS/Xray-core/releases/download/${xray_version}/Xray-linux-64.zip"
    
    # Download and extract
    wget -O /tmp/xray.zip "$download_url"
    if [[ $? -ne 0 ]]; then
        echo -e "${ERR}Failed to download Xray-core${NC}"
        exit 1
    fi
    
    unzip -o /tmp/xray.zip -d $INSTALL_DIR
    if [[ $? -ne 0 ]]; then
        echo -e "${ERR}Failed to extract Xray-core${NC}"
        exit 1
    fi
    
    chmod +x $INSTALL_DIR/xray
    ln -sf $INSTALL_DIR/xray /usr/local/bin/xray
    
    # Create systemd service
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
    
    # Stop nginx to free port 80
    systemctl stop nginx 2>/dev/null
    
    # Obtain certificate using standalone mode
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

# Configure Nginx as SNI Passthrough Proxy
configure_nginx() {
    echo -e "${INFO}Configuring Nginx...${NC}"
    
    # Backup original nginx.conf
    cp $NGINX_CONF_DIR/nginx.conf $NGINX_CONF_DIR/nginx.conf.backup
    
    # Write new nginx.conf with stream block
    cat <<EOF | sudo tee $NGINX_CONF_DIR/nginx.conf
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 768;
}

# Stream block for SNI Passthrough (Port 443)
stream {
    map \$ssl_preread_server_name \$backend {
        sub.$DOMAIN nginx_https;
        default xray_tcp; # All other SNIs go to Xray Reality
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

# HTTP block for Subscription Page (Local Port)
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
    }
}
EOF
    
    # Create subscription directory
    mkdir -p /var/www/html
    echo "# Subscription placeholder" > /var/www/html/sub.txt
    
    # Test and restart Nginx
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
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $XRAY_TCP_PORT,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$uuid",
            "flow": "xtls-rprx-vision",
            "level": 0,
            "email": "user@$DOMAIN"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "www.microsoft.com:443",
          "xver": 0,
          "serverNames": [
            "www.microsoft.com",
            "microsoft.com"
          ],
          "privateKey": "$private_key",
          "shortIds": [
            "$short_id"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
      }
    },
    {
      "port": $XHTTP_PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$uuid",
            "level": 0,
            "email": "xhttp@$DOMAIN"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "xhttpSettings": {
          "path": "/xh",
          "host": "www.microsoft.com"
        },
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "www.microsoft.com:443",
          "xver": 0,
          "serverNames": [
            "www.microsoft.com"
          ],
          "privateKey": "$private_key",
          "shortIds": [
            "$short_id"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF
    
    chmod 600 $CONFIG_DIR/config.json
    
    # Setup logrotate for Xray
    cat <<EOF | sudo tee /etc/logrotate.d/xray
/var/log/xray/*.log {
    weekly
    rotate 7
    missingok
    notifempty
    compress
    delaycompress
    sharedscripts
    postrotate
        systemctl reload xray > /dev/null 2>&1 || true
    endscript
}
EOF
    
    # Save client info
    cat <<EOF | sudo tee $CONFIG_DIR/client_info.txt
===== RealityGhostPro Client Info =====
Domain: $DOMAIN
UUID: $uuid
Public Key: $public_key
Short ID: $short_id
XHTTP Port: $XHTTP_PORT
XHTTP Path: /xh
=======================================
VLESS TCP Link:
vless://$uuid@$DOMAIN:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=$public_key&sid=$short_id&type=tcp#RealityGhostPro-TCP

VLESS XHTTP Link:
vless://$uuid@$DOMAIN:$XHTTP_PORT?encryption=none&security=reality&sni=www.microsoft.com&fp=chrome&pbk=$public_key&sid=$short_id&type=xhttp&path=/xh&host=www.microsoft.com#RealityGhostPro-XHTTP
EOF
    
    echo -e "${OK}Xray configured successfully${NC}"
}

# Setup cron job for rotation
setup_rotation() {
    echo -e "${INFO}Setting up periodic rotation cron job...${NC}"
    cat <<EOF | sudo tee /etc/cron.d/realityghost-rotate
# Rotate Reality fingerprint every 3 days at 5 AM
0 5 */3 * * root $CONFIG_DIR/RealityGhostPro.sh manual-rotate
EOF
    chmod +x /etc/cron.d/realityghost-rotate
}

# Manual rotation function
manual_rotate() {
    echo -e "${INFO}Performing manual fingerprint rotation...${NC}"
    local short_id=$(openssl rand -hex 8)
    
    # Update shortId in config
    jq --arg sid "$short_id" '.inbounds[].streamSettings.realitySettings.shortIds = [$sid]' $CONFIG_DIR/config.json > $CONFIG_DIR/config.json.tmp
    mv $CONFIG_DIR/config.json.tmp $CONFIG_DIR/config.json
    
    systemctl restart xray
    echo -e "${OK}Rotation complete. New Short ID: $short_id${NC}"
}

# Management menu
manage_menu() {
    clear
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}   RealityGhost PRO Management Menu    ${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo "1. Show Client Info & Links"
    echo "2. Rotate Fingerprint (Safe)"
    echo "3. Restart Services"
    echo "4. View Xray Logs"
    echo "5. View Nginx Logs"
    echo "6. Uninstall RealityGhostPro"
    echo "0. Exit"
    echo -n "Select an option: "
    read opt
    
    case $opt in
        1)
            cat $CONFIG_DIR/client_info.txt
            echo -e "\nPress Enter to continue..."
            read
            ;;
        2)
            manual_rotate
            ;;
        3)
            systemctl restart nginx xray
            echo -e "${OK}Services restarted${NC}"
            ;;
        4)
            journalctl -u xray -e
            ;;
        5)
            tail -f /var/log/nginx/error.log
            ;;
        6)
            uninstall
            ;;
        0)
            exit 0
            ;;
        *)
            echo -e "${ERR}Invalid option${NC}"
            ;;
    esac
}

# Uninstall function
uninstall() {
    echo -e "${WARN}Uninstalling RealityGhostPro...${NC}"
    systemctl stop xray nginx
    systemctl disable xray
    
    rm -rf $INSTALL_DIR $CONFIG_DIR
    rm -f /etc/systemd/system/xray.service
    rm -f /etc/nginx/nginx.conf
    mv $NGINX_CONF_DIR/nginx.conf.backup $NGINX_CONF_DIR/nginx.conf
    rm -f /etc/cron.d/realityghost-rotate
    
    systemctl daemon-reload
    systemctl restart nginx
    
    echo -e "${OK}Uninstall complete${NC}"
}

# Main execution
case "$1" in
    install)
        check_root
        install_dependencies
        install_xray
        install_certbot
        configure_nginx
        configure_xray
        setup_rotation
        systemctl restart nginx xray
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}  Installation Complete!              ${NC}"
        echo -e "${GREEN}========================================${NC}"
        cat $CONFIG_DIR/client_info.txt
        ;;
    manage)
        check_root
        manage_menu
        ;;
    manual-rotate)
        check_root
        manual_rotate
        ;;
    uninstall)
        check_root
        uninstall
        ;;
    *)
        echo "Usage: $0 {install|manage|manual-rotate|uninstall}"
        echo "Or run with environment variables:"
        echo "DOMAIN=sub.example.com EMAIL=you@example.com sudo -E $0 install"
        exit 1
        ;;
esac
