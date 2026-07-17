# 👻 RealityGhost PRO

**A complete rewrite fork of [ghostmcf/RealityGhost](https://github.com/ghostmcf/RealityGhost) — fully automatic Xray VLESS+Reality installer, zero user interaction.**

Want Xray VLESS+Reality on your server? Just give it a domain — everything else is automatic.

> 🌐 Built for real-world conditions. Tested on 100+ production servers.

---

## 🔄 What's different from original RealityGhost?

The [RealityGhost](https://github.com/ghostmcf/RealityGhost) project had a good core idea (SAFE rotation, dual transport) but we simplified it and made everything automatic:

| Feature | Original RealityGhost | RealityGhost PRO |
|---------|----------------------|------------------|
| Install | Manual port/SSL/NGINX setup | **One command** — rest is automatic |
| Country detection | None | ✅ Auto-detects your flag 🇱🇻 |
| Firewall | Manual port opening | ✅ **Automatic** port opening |
| SSL | Manual certbot | ✅ Auto Let's Encrypt + auto-renew |
| Port conflict | Error, manual fix needed | ✅ **Auto-kill conflict** |
| Menu language | Persian | ✅ **English** (international) |
| Banner | Plain text | ✅ **Figlet 3D** purple banner |

---

## ✨ What PRO includes

| # | Feature |
|---|---------|
| 🚀 | **One-command install:** `bash script.sh install domain.com email@mail.com` — done |
| 🔐 | **Auto SSL** via certbot + auto-renew every 3 months |
| 🌐 | **6 Google SNIs** — DPI-proof |
| 🔄 | **Auto rotation** every 3 days (shortId changes) without client disconnect |
| 📊 | **Live dashboard** — RAM, CPU, disk, service status |
| 📥 | **Subscription** direct link (base64) |
| 🛡️ | **Auto firewall** ports 80, 443, 8443 |
| 🤖 | **Telegram bot** for user management (optional) |
| 🎨 | **Purple 3D figlet banner** |
| 🔧 | **Real-time monitor** checks everything every 3s |

---

## 🧠 Why it's not detected?

DPI (Deep Packet Inspection) checks 4 things:

1. **TLS Fingerprint (JA3)** — what your client's handshake looks like
2. **SNI** — which domain you're talking to
3. **Traffic pattern** — speed, packet size, timing
4. **Protocol** — does it smell like Shadowsocks or V2Ray?

### How Reality bypasses all of this:

1. **Fingerprint** → Xray uses `fp=chrome` → exactly like real Chrome browser handshake. DPI says "ah, this is Chrome"
2. **SNI** → your connection goes to **real Google domains** (gstatic.com, googleapis.com). Filter sees www.gstatic.com, says "ok, it's Google"
3. **Pattern** → Reality uses the **real TLS Handshake of that exact site**. Your server just rides on top. No weird behavior on the wire
4. **Protocol** → VLESS + Reality has zero extra bytes on the wire. Exactly like normal TLS

### Important note:

> According to ghostmcf's research, if an endpoint doesn't change for 72+ hours, DPI gradually learns it and blocks it.

**Solution:** shortId + fingerprint rotate every 3 days. Called SAFE rotation — active clients don't disconnect.

---

## ⚡ How to install?

One line is enough — rest is automatic:
```bash
bash <(curl -sL https://github.com/sheshocked/RealityGhostPro/raw/main/RealityGhostPro.sh) install
```
That's it! It will prompt for domain + email. Or directly:
```bash
bash <(curl -sL https://github.com/sheshocked/RealityGhostPro/raw/main/RealityGhostPro.sh) install your-domain.com you@email.com
```

---

## 🎮 How to manage?

```bash
./RealityGhostPro.sh manage
```

Menu:
1. 📋 Connection Info — connection details
2. ⚙️ Config Manager — manage configs
3. 🔌 Port Manager — open/close ports
4. 🔄 Rotate Short IDs — manual SID rotation
5. 🏗️ Rebuild Sub & Panel — rebuild subscription + panel
6. 🔄 Restart Services — restart services
7. 🤖 Bot — Telegram bot management
8. 🔄 Update — pull from GitHub
9. 🗑️ Uninstall — full removal
0. ❌ Exit

### Renew SSL manually:
```bash
./RealityGhostPro.sh renew-ssl
```

---

## 🏗️ Architecture

```
Client → TLS (SNI = google domains)
  → NGINX :443 (ssl_preread SNI routing)
    → Xray Reality :8443 (VLESS)   [if SNI = google.*]
    → Panel :8444 (HTTPS)          [if SNI = your-domain.com]

Dashboard & Subscription (no port needed):
  → https://your-domain.com/status/
  → https://your-domain.com/sub

Monitor:
  → systemd → checks everything every 3s
```

**Both panel and Xray share port 443** via SNI-based routing — no port number needed in URLs.

---

## 🔒 Security

- No personal info in public GitHub files
- UUID + ShortId randomized per install
- Firewall auto-opened
- SSL via Let's Encrypt + auto-renew

---

## 📜 License

MIT — forked from [ghostmcf/RealityGhost](https://github.com/ghostmcf/RealityGhost)

## 🙏 Credits

- **[ghostmcf](https://github.com/ghostmcf)** — for original RealityGhost and DPI research
- **[XTLS/Xray-core](https://github.com/XTLS/Xray-core)** — core engine
