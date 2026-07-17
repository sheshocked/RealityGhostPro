# 🚀 RealityGhost PRO v4.2

![Version](https://img.shields.io/badge/version-4.2-purple?style=flat-square)
![Xray](https://img.shields.io/badge/Xray-25.9.11-blue?style=flat-square)
![SSL](https://img.shields.io/badge/SSL-Let's%20Encrypt-green?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-orange?style=flat-square)

**یک ابزار حرفه‌ای و کامل برای نصب و مدیریت Xray VLESS+Reality روی سرورهای اوبونتو/دبیان**

با پنل مدیریت فارسی، تشخیص خودکار لوکیشن سرور، ساب‌اسکریپشن، و مانیتورینگ پیشرفته.

---

## ✨ ویژگی‌ها

| ویژگی | توضیحات |
|-------|---------|
| ⚡ **VLESS+Reality** | پروتکل فوق سریع Xray با TLS 1.3 REALITY |
| 🎯 **۶ SNI گوگل** | هر کانفیگ SNI + ShortId مخصوص خودش |
| 🌍 **تشخیص لوکیشن** | پرچم کشور و نام لوکیشن به صورت خودکار بر اساس IP سرور (۲۱+ کشور) |
| 📊 **پنل وضعیت فارسی** | RTL، دیتای زنده، کارت‌های کپی با پرچم |
| 📦 **ساب‌اسکریپشن** | فرمت VlESS کامل با `allowinsecure=0`، `echfq=none`، `headerType=none` |
| 🔐 **SSL خودکار** | Let's Encrypt با تمدید خودکار |
| 🛡️ **فایروال هوشمند** | باز کردن خودکار پورت‌ها، مدیریت در منو |
| 🔄 **چرخش Short IDs** | هر ۳ روز یکبار تغییر خودکار با SIDهای ۱۶ بایتی منحصربفرد |
| 📉 **مانیتورینگ** | CPU، RAM، Disk، ترافیک، Connections، Load |
| 🗑️ **حذف کامل** | uninstall یکپارچه |
| 🤖 **ربات تلگرام** | مدیریت کاربران، محدودیت حجم، تاریخ انقضا (اختیاری) |
| 🚀 **بهینه‌سازی سیستم** | BBR، TCP buffer 16MB، FastOpen، File Descriptor limits |
| 🆔 **UUID + ShortId یکتا** | هر بار نصب UUID و SIDهای متفاوت و رندوم |

---

## 📥 نصب

### پیش‌نیازها:
- **یک دامنه** با Record A به IP سرور
- **پورت‌های ۸۰ و ۴۴۳** باز روی سرور
- اوبونتو ۲۰.۰۴+ یا دبیان ۱۱+

### روش نصب (۲ دقیقه):

```bash
# دانلود
git clone https://github.com/YOUR_USER/RealityGhostPro.git
cd RealityGhostPro
chmod +x RealityGhostPro.sh

# نصب (دامنه و ایمیل رو می‌پرسه)
sudo bash RealityGhostPro.sh install
```

یا با متغیر محیطی (غیرتعاملی):
```bash
sudo DOMAIN="your-domain.com" EMAIL="your@email.com" bash RealityGhostPro.sh install
```

### بعد از نصب:
```
📊 پنل وضعیت:  https://your-domain.com/status/
📥 ساب:        https://your-domain.com/sub
```

---

## 🎮 مدیریت

```bash
sudo bash RealityGhostPro.sh manage
```

منوی مدیریت شامل:
```
1. 📋 نمایش اطلاعات اتصال
2. ⚙️ مدیریت کانفیگ‌ها
3. 🔌 مدیریت پورت‌ها (فایروال)
4. 🔄 چرخاندن Short IDs
5. 🏗️ بازسازی ساب‌اسکریپشن و پنل
6. 🔄 ری‌استارت سرویس‌ها
7. 🤖 مدیریت ربات تلگرام
8. 🔄 بروزرسانی از گیتهاب
9. 🗑️ حذف کامل
```

---

## 🔗 نمونه کانفیگ

```
vless://YOUR-UUID@YOUR-DOMAIN:443
  ?flow=xtls-rprx-vision
  &encryption=none
  &security=reality
  &sni=ajax.googleapis.com
  &fp=chrome
  &echfq=none
  &pbk=YOUR-PUBLIC-KEY
  &sid=YOUR-SHORT-ID
  &allowinsecure=0
  &type=tcp
  &headerType=none
  #🇱🇻 ✌ Google AJAX
```

---

## 🏗️ معماری

```
┌─────────────┐     ┌───────────────────────────────────┐     ┌───────────┐
│   Client    │────▶│  NGINX :443 (stream/ssl_preread)  │────▶│  Xray     │
│  (VLESS)    │     │  ┌─ SNI=google.com ─▶ Xray TCP ┐  │     │  :8444    │
│             │     │  └─ SNI=your.domain ─▶ HTTP ───┘  │     │  Reality  │
└─────────────┘     └───────────────────────────────────┘     └───────────┘
```

---

## ⚙️ کانفیگ‌های داخلی

| مسیر | توضیحات |
|------|---------|
| `/usr/local/etc/xray/config.json` | کانفیگ اصلی Xray |
| `/usr/local/etc/xray/client_info.txt` | اطلاعات اتصال |
| `/etc/nginx/nginx.conf` | کانفیگ NGINX (stream + HTTP) |
| `/var/www/html/status/index.html` | پنل وضعیت فارسی |
| `/var/www/html/sub/sub.txt` | فایل ساب‌اسکریپشن (Base64) |
| `/usr/local/bin/realityghost_monitor.sh` | اسکریپت مانیتورینگ |
| `/usr/local/bin/rg-bot.py` | ربات تلگرام مدیریت کاربران |
| `/etc/realityghost/users.db` | دیتابیس کاربران (SQLite) |
| `/var/log/xray/access.log` | لاگ دسترسی Xray |
| `/var/log/xray/error.log` | لاگ خطاهای Xray |

---

## 📋 تغییرات نسخه

[مشاهده تغییرات کامل](CHANGELOG.md)

### v4.2
- 🆔 **UUID + ShortId منحصربفرد** برای هر نصب (۶ SID رندوم)
- 🚀 **بهینه‌سازی سیستم**: BBR، TCP buffer 16MB، FastOpen، FD limits 1048576
- 🤖 **ربات تلگرام**: مدیریت کاربران، محدودیت حجم، تاریخ انقضا (اختیاری)
- 🐛 رفع باگ‌های متداول (پورت اشغال، proxy_protocol و...)

### v4.0
- معماری بازنویسی شده: **حذف XHTTP**، فقط TCP Reality با ۶ SNI گوگل
- **رفع باگ بزرگ**: حذف `proxy_protocol` از مسیر Xray
- **تشخیص خودکار لوکیشن**: پرچم و نام کشور بر اساس IP سرور
- **پنل جدید**: RTL فارسی، فونت وزیرمتن، تم بنفش تیره
- **ساب جدید**: فرمت VlESS با `allowinsecure=0`، `echfq=none`، `headerType=none`
- **مدیریت پورت**: باز/بستن پورت‌ها از منو
- **پیش‌بررسی**: تشخیص پورت‌های اشغال شده و DNS
- **لاگ کامل**: `access.log` و `error.log` برای Xray

---

## 🐛 رفع باگ‌های متداول

### پورت ۴۴۳ اشغاله؟
اسکریپت هنگام نصب تشخیص میده و می‌پرسه خودکار آزادش کنه. یا بعداً با `manage → port manager` می‌تونی چک کنی.

### کانفیگ‌ها کار نمی‌کنه؟
چک کن `proxy_protocol` توی nginx نباشه (این باگ بزرگ بود). اسکریپت جدید بدون proxy_protocol می‌سازه.

### ساب در v2rayNG/Happ نشون نمیده؟
فرمت جدید با `allowinsecure=0` و `headerType=none` و `echfq=none` — همه کلاینت‌ها پشتیبانی می‌کنن.

---

## 📜 مجوز

MIT License — آزاد برای استفاده و تغییر.

---

## 🌟 حمایت

اگر پروژه رو مفید دیدی، ستاره ⭐ بده و با بقیه به اشتراک بذار!
