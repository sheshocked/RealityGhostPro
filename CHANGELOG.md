## v6.0 (2026-07-17) — 🚀 High-scale optimization + Anti-DPI + Best DNS

### 🔥 Performance for 50k+ users
- **Xray concurrency=16** — parallel connection handling
- **TCP MTU probing=1** — auto path MTU discovery
- **TCP slow_start_after_idle=0** — keep connections warm
- **TCP autocorking=0** — reduce latency for small packets
- **TCP no_metrics_save=1** — fresh connection metrics each time
- **Max syn backlog=262144** — handle connection storms
- **Max tw buckets=4M** — handle millions of concurrent connections
- **Somaxconn=131072** — max socket listen backlog
- **NF conntrack=4M** — track millions of connections

### 🛡️ Anti-DPI improvements
- **Xray allocate concurrency=16** — spread connections across workers
- **Sniffing routeOnly=true** — route traffic more efficiently
- **Auto best DNS** by location: Shecan (Iran), Yandex (Russia), 114DNS (China), Cloudflare (global)
- **DNS backup** — always fallback to 8.8.8.8

### ⚡ Speed improvements
- **BBR congestion control** with fq qdisc
- **TCP fastopen=3** — 1-RTT handshake for repeat connections
- **Increased buffer sizes** for high-bandwidth flows
- **NGINX LimitNOFILE=1048576** — never run out of file descriptors

### 📦 Other
- Script optimized with self-healing DNS
- v6.0 branding everywhere

## v5.2 (2026-07-17) — 🎨 Clean panel redesign + Responsive fix

### 🎨 Panel fixes
- **Resources bars** — RAM/CPU/Disk with percentage bars
- **Traffic stats** — Today/Month/Total with auto-format (B/KB/MB/GB/TB)
- **Load average** — 1m/5m/15m display
- **Responsive** — Desktop 6-col, Tablet 3-col, Mobile 2-col
- **Quick Copy** — 3 shortcut buttons for fast config copy

## v5.1 (2026-07-17) — 🏗️ Architecture rewrite + Auto setup

### 🏗️ Architecture changes
- **Direct Xray on :443** — removed NGINX stream bottleneck
- **Panel on :8443** — NGINX serves panel + sub only
- **worker_connections 65535** — handle massive concurrent traffic
- **Rate limiting** — protect against abuse
- **epoll + multi_accept** — high-performance event loop

### 🎯 Quick entry
- `rgp` command — type it anywhere, goes straight to menu
- `bash RealityGhostPro.sh p` — same thing

## v5.0 (2026-07-17) — 🎯 Fully automatic install + Persian UI

### 🔄 Major changes
- **Fully automatic install** — just provide domain + email, everything else auto
- **Self-healing** — auto kill port conflicts, auto fix DNS, auto configure everything
- **Persian UI** — all menus, messages, and README in Farsi
- **Zero prompts** — no questions asked during installation

# 📋 CHANGELOG — RealityGhost PRO

## v4.2 (2026-07-17) — 🆔 UUID + ShortId منحصربفرد + 🚀 بهینه‌سازی سیستم + 🤖 ربات

### 🔥 بهینه‌سازی سیستم (جدید)
- **BBR فعال‌سازی خودکار** اگه نباشه
- **تنظیمات کرنل** شامل: TCP buffer (۱۶MB), FastOpen, MTU probing, backlog
- **File descriptor limits** به ۱,۰۴۸,۵۷۶
- **Systemd Xray limits** با CPU/Memory accounting
- سرعت و پایداری اتصال به طور محسوس افزایش پیدا کرده

### 🤖 ربات تلگرام مدیریت کاربران (جدید — اختیاری)
- **افزودن کاربر** با UUID جدید، محدودیت حجم و تاریخ انقضا
- **حذف کاربر** به همراه حذف از Xray config
- **فعال/غیرفعال کردن کاربر**
- **لیست کاربران با حجم مصرفی**
- **محدودیت حجم**: ست کردن limit بر حسب MB
- **آمار سرور** (CPU, RAM, Disk, تعداد کاربران)
- **دکمه‌های شیشه‌ای** برای عملیات سریع
- نصب اختیاری حین نصب اصلی — سوال می‌کنه
- Systemd service خودکار: `realityghost-bot.service`
- دیتابیس SQLite: `/etc/realityghost/users.db`

### 🆔 UUID + ShortId منحصربفرد برای هر نصب
- **UUID یکتا**: هر بار نصب یک UUID جدید و رندوم ساخته میشه
- **۶ ShortId رندوم**: هر SNI یک ShortId ۱۶ بایتی رندوم می‌گیره
- اعتبارسنجی جلوگیری از تکرار SID

## v4.0 (2026-07-17) — 🎉 بازنویسی کامل

### 🔥 تغییرات بزرگ

| تغییر | توضیحات |
|-------|---------|
| ❌ **حذف XHTTP** | اینباند XHTTP (پورت ۲۰۵۳) به طور کامل حذف شد. فقط TCP Reality |
| 🎯 **۶ SNI گوگل** | هر کانفیگ SNI + ShortId اختصاصی: gstatic, ajax, storage, fonts, fonts.api, google.com |
| 🐛 **رفع باگ پروکسی پروتکل** | حذف `proxy_protocol on` از مسیر Xray که باعث `TLSV1_ALERT_PROTOCOL_VERSION` می‌شد |
| 🌍 **تشخیص لوکیشن** | IP سرور → تشخیص خودکار کشور → پرچم + اسم در پنل و لینک‌ها |
| 📊 **پنل جدید RTL فارسی** | تم بنفش تیره، فونت وزیرمتن، دیتای زنده (CPU/RAM/Disk/Traffic/Load/DNS) |
| 📥 **ساب‌اسکریپشن جدید** | فرمت VlESS کامل: `flow=xtls-rprx-vision`، `echfq=none`، `allowinsecure=0`، `headerType=none` |
| 🔌 **مدیریت پورت در منو** | باز/بستن پورت‌های فایروال از داخل منوی مدیریت |
| 🔄 **چرخش Short IDs** | هر ۳ روز یکبار چرخش خودکار، یا دستی از منو |
| 🔧 **پیش‌بررسی قبل از نصب** | تشخیص پورت اشغال شده، DNS، اتصال اینترنت |

### 🐛 رفع باگ‌ها

- **بحرانی**: `proxy_protocol` به Xray فرستاده می‌شد → `TLSV1_ALERT_PROTOCOL_VERSION` → اتصال کار نمی‌کرد
- **مهم**: نام کانفیگ‌ها با `RGPro-` شروع می‌شد → حالا با پرچم + ایموجی
- **مهم**: پرچم کشور در ساب‌اسکریپشن توسط v2rayNG/Happ نشون داده نمی‌شد → پیشوند متنی
- **متوسط**: لاگ Xray فقط warning بود → حالا info + access/error log جدا

### ✨ اضافه‌شده‌ها

- [x] تشخیص خودکار لوکیشن سرور (۲۰+ کشور)
- [x] پنل مدیریت فارسی کامل (۶ بخش)
- [x] ساب‌اسکریپشن با ۶ کانفیگ کامل
- [x] مدیریت پورت‌ها (iptables) از منو
- [x] QR Code برای کانفیگ اول
- [x] نمایش UUID و Public Key
- [x] بازسازی دستی ساب و پنل
- [x] پیش‌بررسی سیستم قبل از نصب
- [x] لاگ کامل Xray

### 🏗️ معماری جدید

```
Client (SNI=google.com) 
    → NGINX :443 (stream, ssl_preread, NO proxy_protocol) 
    → Xray :8444 (Reality TCP, xtls-rprx-vision)
```

### 📁 فایل‌های تغییر یافته

| فایل | تغییر |
|------|-------|
| `RealityGhostPro.sh` | +۴۵۰ خط، بازنویسی کامل |
| `README.md` | +۲۰۰ خط، فارسی + کامل |
| `CHANGELOG.md` | جدید |

---

## v3.2 (2026-07-15)

### ✨ اضافه‌شده
- پنل وضعیت اولیه با CPU/RAM/Disk
- ساب‌اسکریپشن اولیه

### 🐛 رفع باگ
- رفع مشکل Systemd for Xray

---

## v3.0 (2026-07-10)

### ✨ اضافه‌شده
- معماری دو مسیره: TCP Reality + XHTTP
- مدیریت منوی ساده
- روتوش خودکار Short IDs

---

## v2.0 (2026-06-20)

### ✨ اضافه‌شده
- NGINX SNI passthrough
- Let's Encrypt SSL
- اسکریپت مانیتور ساده

---

## v1.0 (2026-06-01)

### ✨ اولین انتشار
- نصب Xray-core
- کانفیگ پایه Reality
- کانفیگ ساده nginx
