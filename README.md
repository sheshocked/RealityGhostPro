# RealityGhost PRO

اسکریپت production-grade و stealth-محور برای راه‌اندازی و مدیریت **Xray VLESS+Reality** با دو مسیر همزمان (TCP و XHTTP)، صفحه‌ی ساب‌اسکریپشن HTTPS واقعی، و rotation دوره‌ی امن — بدون نیاز به CDN.

این پروژه یه **fork اصلاح‌شده** از [ghostmcf/RealityGhost](https://github.com/ghostmcf/RealityGhost) است. نسخه‌ی اصلی چند باگ معماری جدی داشت که باعث می‌شد کانفیگ‌ها زود لو برن یا اصلاً درست بالا نیان؛ همه‌شون اینجا ریشه‌ای رفع شدن (توضیح کامل هرکدوم پایین همین فایل و در `CHANGELOG.md`).

## نصب

```bash
cd && sudo git clone https://github.com/<YOUR-USERNAME>/RealityGhostPro.git && cd RealityGhostPro && sudo chmod +x RealityGhostPro.sh && sudo ./RealityGhostPro.sh install
```

پیش‌نیاز: یه دامنه که رکورد A ش مستقیم (بدون CDN، ابر خاکستری/DNS-only) به IP سرورت اشاره کنه.

نصب می‌تونه interactive باشه (ازت domain و email می‌پرسه) یا کاملاً خودکار:

```bash
DOMAIN=sub.example.com EMAIL=you@example.com sudo -E ./RealityGhostPro.sh install
```

## مدیریت

```bash
sudo realityghost manage
```

منوی مدیریت شامل: نمایش ساب‌اسکریپشن/QR، rotate امن/سخت، تعویض IP، تعویض UUID، سوییچ ترنسپورت پیش‌فرض، health check و آنینستال.

## معماری (چرا دیگه به CDN نیاز نداری و چرا پورت ۴۴۳ دیگه تداخل نداره)

```
                         ┌────────────────────────────┐
 کلاینت (SNI = دامنه) ──▶│  nginx  :443  (stream/      │──▶ nginx :8443 (لوکال، TLS واقعی)
                         │  ssl_preread — بدون          │      سرو می‌کنه فقط فایل ساب‌اسکریپشن
 کلاینت (SNI = کاموفلاژ)─▶│  ترمیناِیت‌کردن TLS)          │──▶ Xray reality-tcp :8444 (لوکال)
                         └────────────────────────────┘      خودِ Xray هندشیک Reality رو انجام می‌ده

 کلاینت (XHTTP) ─────────────────────────────────────────▶ Xray reality-xhttp :2053 (پابلیک، مستقیم)
```

نکته‌ی کلیدی: nginx هیچ‌وقت TLS مربوط به Reality رو ترمینیت نمی‌کنه (فقط SNI رو با `ssl_preread` می‌خونه و بایت خام رو پاس می‌ده)، پس هندشیک واقعی Reality همیشه دست خود Xray می‌مونه و کاموفلاژش دست‌نخورده باقی می‌مونه.

## چیزهایی که در نسخه‌ی اصلی خراب بود و اینجا درست شد

| # | مشکل در نسخه‌ی اصلی | راه‌حل در این fork |
|---|---|---|
| 1 | **تصادم پورت ۴۴۳**: هم Xray (`0.0.0.0:443`) هم nginx (`listen 443 ssl`) هم‌زمان می‌خواستن همون پورت رو بگیرن؛ اسکریپت با `fuser -k 443/tcp` هرکدوم می‌رسید رو می‌کشت | nginx با `stream { ssl_preread on; }` روی ۴۴۳ فقط SNI رو می‌خونه و بدون ترمینیت، بایت خام رو به Xray یا به vhost لوکال ساب‌اسکریپشن پاس می‌ده |
| 2 | XHTTP از پشت `proxy_pass` در لایه‌ی HTTP نginx رد می‌شد → یعنی nginx با گواهی Let's Encrypt واقعی TLS رو ترمینیت می‌کرد، که کاموفلاژ Reality رو کاملاً بی‌اثر می‌کرد | XHTTP-Reality الان مستقیم و بدون واسطه روی پورت اختصاصی (۲۰۵۳ پیش‌فرض) گوش می‌ده |
| 3 | `certbot certonly --nginx` وقتی nginx دستی متوقف شده بود اجرا می‌شد (شکست می‌خورد)؛ fallback به webroot هم چون وب‌سرور روشن نبود بی‌فایده بود | چون طراحی جدید اصلاً پورت ۸۰ رو با nginx اشغال نمی‌کنه، `certbot certonly --standalone` همیشه بدون تداخل کار می‌کنه — even روی رینیو |
| 4 | UUID پیش‌فرض هاردکد شده بود؛ اگه کاربر Enter می‌زد همون UUID مشترک همه فعال می‌شد | هر نصب همیشه یه UUID تصادفی تازه با `uuidgen` می‌سازه |
| 5 | نسخه‌ی Xray هاردکد و قدیمی بود | آخرین ریلیز از GitHub API در لحظه‌ی نصب گرفته می‌شه (با fallback اگه API در دسترس نبود) |
| 6 | فقط `google.com` به‌عنوان مقصد کاموفلاژ Reality استفاده می‌شد که رفتار edge گوگل بعضی‌وقتا با Reality سازگار نیست | لیست چند دامنه‌ی پرترافیک قبل نصب با `openssl s_client` تست می‌شن و اولین موردی که هندشیک TLS1.3 تمیز بده انتخاب می‌شه |
| 7 | فایل‌های حساس (کلید خصوصی، config.json) به‌صورت پیش‌فرض قابل‌خوندن توسط بقیه بودن | `chmod 600/700` روی همه‌ی فایل‌ها و دایرکتوری‌های حساس |
| 8 | لاگ Xray بدون rotate رشد نامحدود داشت | پالیسی logrotate هفتگی نصب می‌شه |
| 9 | فقط interactive بود؛ اتوماسیون/CI سخت بود | متغیرهای محیطی `DOMAIN` / `EMAIL` / `XHTTP_PORT` نصب بی‌صدا رو ممکن می‌کنن |

## چرا Rotation دوره‌ای لازمه

DPIهای پیشرفته اول IP یا دامنه رو هدف نمی‌گیرن؛ چیزی که واقعاً fingerprint می‌شه TLS fingerprint، shortId و پترن هندشیکه که اگه بیشتر از ~۷۲ ساعت ثابت بمونه، به‌مرور شناسایی می‌شه. یه cronjob پیش‌فرض هر ۳ روز یه‌بار (`0 5 */3 * * root realityghost manual-rotate`) fingerprint رو عوض و shortId جدید اضافه می‌کنه — بدون قطع کلاینت‌های فعال، چون کلید Reality و مسیر XHTTP دست نمی‌خورن مگر با `ROTATE_KEYS=1` / `ROTATE_PATH=1` صریحاً بخوای.

## مجوز

MIT — مثل ریپوی اصلی.
