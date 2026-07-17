# 👻 RealityGhost PRO

**یه فورک از [ghostmcf/RealityGhost](https://github.com/ghostmcf/RealityGhost) که بکلی بازنویسی شده — نصب خودکار، بدون دخالت کاربر.**

میخوای Xray VLESS+Reality رو سرورت بالا بیاری؟ فقط دامنه بده، بقیه با من.

> 🇮🇷 واسه شرایط ایران ساخته شده. ۱۰۰+ تا سرور واقعی روش تست شده.

---

## 🔄 چه فرقی با RealityGhost اصلی داره؟

پروژه [RealityGhost](https://github.com/ghostmcf/RealityGhost) فکر اصلیش خوب بود (SAFE rotation و dual transport) ولی اومدیم سادش کردیم و همه چی رو اتوماتیک：

| چی | RealityGhost اصلی | RealityGhost PRO |
|----|------------------|-----------------|
| نصب | باید خودت پورت، SSL، NGINX رو چک کنی | **یک دستور** — بقیه با من |
| تشخیص کشور | نداشت | ✅ خودکار میزنه پرچمت 🇱🇻 |
| فایروال | باید دستی باز کنی | ✅ **خودکار** باز میکنه |
| SSL | دستی با certbot | ✅ خودکار میگیره + تمدید اتوماتیک |
| پورت اشغال | ارور میداد باید خودت حل میکردی | ✅ **خودکار kill میکنه** |
| زبان منو | فارسی | ✅ **انگلیسی** (بین‌المللی) |
| بنر | متن ساده | ✅ **Figlet 3D** بنفش خوشگل |

---

## ✨ چیزایی که PRO داره

| # | چی هست |
|---|--------|
| 🚀 | **نصب یک‌دستوری:** `bash script.sh install domain.com email@mail.com` — تموم |
| 🔐 | **SSL خودکار** با certbot + تمدید هر ۳ ماه |
| 🌐 | **۶ تا SNI گوگل** که DPI نره تو شک |
| 🔄 | **چرخش خودکار** هر ۳ روز (shortId عوض میشه) بدون قطعی کلاینت |
| 📊 | **پنل زنده** — مصرف رم، سیپیو، دیسک، وضعیت سرویس‌ها |
| 📥 | **ساب‌اسکریپشن** لینک مستقیم (base64) |
| 🛡️ | **فایروال خودکار** پورت‌های 80, 443, 8443 |
| 🤖 | **ربات تلگرام** برای مدیریت کاربرا (اگه بخوای) |
| 🎨 | **بنر بنفش 3D** با figlet |
| 🔧 | **مانیتور لحظه‌ای** هر ۳ ثانیه چک میکنه همه چی اوکیه |

---

## 🧠 چرا اصلاً فیلتر نمیشه؟

خب ببین. DPI یا همون سیستم فیلترینگ ایران چهار تا چیز رو چک میکنه:

1. **TLS Fingerprint (JA3)** — کلاینتت چه شکلی handshake میزنه
2. **SNI** — کدوم دامنه داری باهاش حرف میزنی
3. **الگوی اتصال** — سرعت، اندازه پکت‌ها، زمان‌بندی
4. **پروتکل** — بوی Shadowsocks یا V2Ray میده یا نه

### Reality چطور اینا رو دور میزنه؟

1. **Fingerprint** → Xray رو میذاریم `fp=chrome` → ینی دقیقاً مثل مرورگر کروم واقعی handshake میزنه. DPI میگه "آها این کرومه"
2. **SNI** → کانکشن تو میره سمت **دامنه‌های واقعی گوگل** (gstatic.com, googleapis.com). فیلترچی میبینه www.gstatic.com، میگه "اوکی گوگله"
3. **الگو** → Reality از **TLS Handshake واقعی همون سایت** استفاده میکنه. سرور تو فقط سوارش میشه. هیچ رفتار عجیبی تو وایر نیست
4. **پروتکل** → VLESS + Reality تو وایر فرمت هیچ بایت اضافه‌ای نداره. دقیقاً شبیه TLS معمولیه

### یه نکته مهم:

> طبق تحقیقات ghostmcf، اگه endpoint بیشتر از ۷۲ ساعت تغییر نکنه، DPI تدریجاً میشناسدش و میندازتش.

**راه‌حل:** هر ۳ روز shortId و fingerprint عوض میشه. به این میگن SAFE rotation — چون کلاینت‌های فعال قطع نمیشن.

---

## ⚡ چجوری نصب کنم؟

یکی خط کافیه — بقیه با منه:
```bash
bash <(curl -sL https://github.com/sheshocked/RealityGhostPro/raw/main/RealityGhostPro.sh) install
```
همین! بقیه رو ازت می‌پرسه. یا اگه خواستی مستقیم:
```bash
bash <(curl -sL https://github.com/sheshocked/RealityGhostPro/raw/main/RealityGhostPro.sh) install your-domain.com you@email.com
```
```

---

## 🎮 چجوری مدیریت کنم؟

```bash
./RealityGhostPro.sh manage
```

منو:
1. 📋 Connection Info — اطلاعات اتصال
2. ⚙️ Config Manager — مدیریت کانفیگ
3. 🔌 Port Manager — باز و بستن پورت
4. 🔄 Rotate Short IDs — چرخش دستی SID
5. 🏗️ Rebuild Sub & Panel — بازسازی ساب و پنل
6. 🔄 Restart Services — ری‌استارت سرویس‌ها
7. 🤖 Bot — مدیریت ربات تلگرام
8. 🔄 Update — آپدیت از گیتهاب
9. 🗑️ Uninstall — حذف کامل
0. ❌ Exit

---

## 🏗️ معماری چجوریه؟

```
Client → TLS (با SNI گوگل)
  → NGINX :443 (ssl_preread)
    → Xray Reality :8444 (VLESS)
    
پنل و ساب:
  → NGINX :8443 → /status/ + /sub/
  
مانیتور:
  → systemd → هر ۳ ثانیه چک میکنه همه چی اوکیه
```

---

## 🔒 امنیت

- هیچکدوم از اطلاعات شخصی تو فایل‌های عمومی گیتهاب نیست
- UUID + ShortId برای هر نصب رندوم میزنه
- فایروال خودکار باز میشه
- SSL با Let's Encrypt + تمدید خودکار

---

## 📜 مجوز

MIT — فورک شده از [ghostmcf/RealityGhost](https://github.com/ghostmcf/RealityGhost)

## 🙏 تشکر

- **[ghostmcf](https://github.com/ghostmcf)** — برای RealityGhost اصلی و تحقیقات DPI
- **[XTLS/Xray-core](https://github.com/XTLS/Xray-core)** — موتور اصلی
