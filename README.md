# 👻 RealityGhost PRO

**Fork of [ghostmcf/RealityGhost](https://github.com/ghostmcf/RealityGhost) — Rewritten for zero‑config production use.**

یک اسکریپت **تمام‌اتوماتیک** برای نصب و مدیریت Xray VLESS+Reality. فقط دامنه رو بده، بقیه رو خودش انجام میده.

> 🇮🇷 طراحی شده برای شرایط فیلترینگ ایران، بر اساس مشاهدات میدانی ۱۰۰+ سرور

---

## 🔄 تفاوت با RealityGhost اصلی

پروژه [RealityGhost](https://github.com/ghostmcf/RealityGhost) یک پایه محکم با ایده‌های خوب (SAFE rotation، dual transport) بود. ما رفتیم سراغ **سادگی و اتوماتیک‌سازی**:

| ویژگی | RealityGhost اصلی | RealityGhost PRO |
|-------|------------------|-----------------|
| نصب | دستی — باید پورت، SSL، NGINX رو چک کنی | **یک دستور** — همه چیز خودکار |
| تشخیص لوکیشن | ❌ | ✅ خودکار با پرچم 🇱🇻 |
| فایروال | ❌ دستی | ✅ **خودکار** iptables/UFW |
| SSL | دستی با certbot | ✅ خودکار + تمدید اتوماتیک |
| Conflict پورت | ❌ کاربر باید حل کنه | ✅ **خودکار تشخیص و رفع** |
| منو | فارسی | ✅ **انگلیسی** |
| بنر | متن ساده | ✅ **Figlet 3D** بنفش |

---

## ✨ چیزای جدید PRO

| # | قابلیت |
|---|--------|
| 🚀 | **نصب یک‌دستوری:** `bash script.sh install your-domain.com` — تموم |
| 🔐 | **SSL خودکار** با certbot + cron تمدید |
| 🌐 | **۶ SNI گوگل** برای تنوع camouflage |
| 🔄 | **چرخش خودکار** هر ۳ روز (shortId + fingerprint) بدون قطعی |
| 📊 | **پنل زنده** با آمار منابع، مصرف، وضعیت سرویس‌ها |
| 📥 | **ساب‌اسکریپشن** اتوماتیک (base64) |
| 🛡️ | **فایروال خودکار** باز کردن پورت‌های 80, 443, 8443 |
| 🤖 | **ربات تلگرام** مدیریت کاربران (اختیاری) |
| 🎨 | **بنر 3D بنفش** با figlet |
| 🔧 | **Self-Heal:** مانیتور هر ۳ ثانیه چک میکنه |

---

## 🧠 چرا Reality فیلتر نمیشه؟

DPI ایران چهار چیز رو چک میکنه:

1. **TLS Fingerprint (JA3)** — Xray میزنه `fp=chrome` → درست مثل مرورگر واقعی
2. **SNI** — کانکشن شما میره به **دامنه‌های واقعی گوگل** (gstatic.com, googleapis.com)
3. **الگوی اتصال** — Reality از **TLS handshake واقعی** سایت مقصد استفاده میکنه
4. **پروتکل** — VLESS + Reality = **تشخیص‌ناپذیر**، هیچ بایت پروکسی توی وایر فرمت نیست

> **نکته کلیدی از RealityGhost اصلی:** endpointهایی که بیش از ۷۲ ساعت تغییر نکنن، تدریجاً شناسایی میشن. راه‌حل: چرخش دوره‌ای shortId + fingerprint بدون قطع کردن کلاینت‌ها.

---

## ⚡ نصب

```bash
# یک دستور — همه چیز خودکار
curl -sL https://github.com/sheshocked/RealityGhostPro/raw/main/RealityGhostPro.sh | bash -s install
```

یا دستی:
```bash
git clone https://github.com/sheshocked/RealityGhostPro.git
cd RealityGhostPro
chmod +x RealityGhostPro.sh
./RealityGhostPro.sh install
```

**حین نصب فقط دامنه و ایمیل رو وارد کن — بقیه خودکاره.**

---

## 🎮 مدیریت

```bash
./RealityGhostPro.sh manage
```

منو:
1. 📋 Connection Info
2. ⚙️ Config Manager
3. 🔌 Port Manager
4. 🔄 Rotate Short IDs
5. 🏗️ Rebuild Sub & Panel
6. 🔄 Restart Services
7. 🤖 Bot
8. 🔄 Update
9. 🗑️ Uninstall
0. ❌ Exit

---

## 🏗️ معماری

```
Client → TLS (Google SNI)
  → NGINX :443 (ssl_preread)
    → Xray Reality :8444 (VLESS)

Panel/Sub:
  → NGINX :8443 → /status/ + /sub/

Monitor:
  → systemd → health check هر ۳ ثانیه
```

---

## 🔒 امنیت

- هیچ اطلاعات شخصی تو فایل‌های پابلیک نیست
- UUID + ShortId رندوم برای هر نصب
- فایروال خودکار
- SSL با Let's Encrypt + auto-renew

---

## 📜 License

MIT — Forked from [ghostmcf/RealityGhost](https://github.com/ghostmcf/RealityGhost)

## 🙏 Credits

- **[ghostmcf](https://github.com/ghostmcf)** — RealityGhost اصلی و تحقیقات DPI
- **[XTLS/Xray-core](https://github.com/XTLS/Xray-core)** — موتور اصلی پروکسی
