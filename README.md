# 🧠 ابزار تنظیم آسان DNS برای عبور از تحریم‌ها

### بازنشانی شبکه با گزینهٔ ۳

گزینهٔ ۳ در `run-dns-scripts.bat`، DNS کارت‌های شبکهٔ قابل‌مشاهده (حتی کارت‌های قطع‌شده) را خودکار می‌کند، IPv6 را در صورت غیرفعال‌بودن فعال می‌کند، تغییرات رجیستری DNS این برنامه را حذف می‌کند و کش DNS ویندوز را پاک می‌کند. این مسیر سریع معمولاً به ری‌استارت ویندوز نیاز ندارد و IP ثابت را تغییر نمی‌دهد. فعال‌شدن IPv6 ممکن است اتصال را لحظه‌ای قطع کند. اگر برنامه‌ای هنوز نتیجهٔ قدیمی DNS را نگه داشته، آن را ببندید و دوباره باز کنید. اثر بعضی تغییرات رجیستری ممکن است تا ری‌استارت بعدی به تأخیر بیفتد.

فقط در صورت نیاز به تعمیر عمیق اتصال، در PowerShell با دسترسی Administrator و از پوشهٔ برنامه اجرا کنید:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\restore-dns-settings.ps1 -FullNetworkReset
```

این حالت TCP/IP، IPv6 و Winsock را بازنشانی می‌کند و IPv4 کارت‌های فیزیکی را به DHCP برمی‌گرداند؛ شبکه باید DHCP داشته باشد و پس از اجرا باید ویندوز را ری‌استارت کنید. پیش از بازنشانی عمیق، گزارشی از IP، مسیرها، DNS و اتصال پروتکل‌ها در `%LOCALAPPDATA%\akaDns\Backups` ذخیره می‌شود؛ این گزارش ابزار بازگردانی خودکار نیست. خطای هر مرحله نمایش داده می‌شود و اجرای ناقص موفق گزارش نمی‌شود. تنظیمات دستی IP ممکن است با بازنشانی TCP/IP حذف شوند؛ این موضوع می‌تواند روی VPN و شبکه‌های مجازی نیز اثر بگذارد.

این گزینه نصب مجدد کارت شبکه یا بازنشانی کارخانه‌ای تمام تنظیمات ویندوز نیست: پروکسی، فایروال، فایل hosts، پروفایل‌های Wi-Fi، سیاست‌های سازمانی و DNS اختصاصی مرورگر را تغییر نمی‌دهد. اجرای `restore-dns-settings.ps1` بدون پارامتر همان مسیر سریع گزینهٔ ۳ است. گزینهٔ بازیابی رابط گرافیکی همچنان مسیر جداگانهٔ قبلی را دارد.

با این ابزار فوق‌العاده ساده و کاربردی، فقط با چند کلیک می‌تونی از سد تحریم‌های برنامه‌نویسی، هوش مصنوعی و گیمینگ عبور کنی — بدون نیاز به VPN یا تنظیمات پیچیده!

## 📥 دانلود آخرین نسخه

[دانلود مستقیم akaDns.zip](https://github.com/mirbehnam/akaDns/releases/latest/download/akaDns.zip)

فایل ZIP به‌صورت خودکار از آخرین نسخه شاخه `main` ساخته و در بخش Releases منتشر می‌شود.

## ✨ ساخته شده توسط: [Behnam Tajadini](https://www.youtube.com/@aka_techno)

📺 آموزش کامل استفاده از ابزار در یوتیوب:  
🔗 [مشاهده آموزش](https://www.youtube.com/watch?v=8eT6NKyRyR8)

---

## 🚀 ویژگی‌ها

- ✅ تنظیم آسان و خودکار DNSهای مخصوص دور زدن تحریم
- 🖥️ رابط گرافیکی (GUI) برای راحتی بیشتر
---

## 📘 آموزش گام به گام استفاده

1. ابتدا گزینه `3` را انتخاب کنید تا تنظیمات DNS به حالت پیش‌فرض بازگردد.
2. سپس گزینه `1` را انتخاب کنید تا DNSهای هوشمند ست شوند.
3. حالا می‌توانید از سایر گزینه‌ها برای تست، بررسی یا استفاده از نسخه گرافیکی ابزار استفاده کنید.

🔁 **در صورت باز نشدن برخی سایت‌ها:**
- مرورگر را کامل ببندید و دوباره باز کنید.
- کش مرورگر را پاک کنید.
- مراحل بالا را مجدد تکرار کنید.

---

## 🌐 لیست سایت‌های محبوب تحریم‌شده

### 💻 حوزه برنامه‌نویسی و هوش مصنوعی:
- [ChatGPT](https://chat.openai.com)
- [GitHub Copilot](https://github.com/features/copilot)
- [OpenAI](https://openai.com)
- [Hugging Face](https://huggingface.co)
- [Replit](https://replit.com)
- [CodeSandbox](https://codesandbox.io)

### 🧑‍🔬 دیتاشیت و مهندسی:
- [DigiKey](https://www.digikey.com)
- [AllDatasheet](https://www.alldatasheet.com)
- [Octopart](https://www.octopart.com)
- [Mouser](https://www.mouser.com)

### 🎮 پلتفرم‌های گیمینگ:
- [Steam](https://store.steampowered.com)
- [Epic Games](https://www.epicgames.com)
- [Battle.net](https://www.blizzard.com)
- [Rockstar Games](https://www.rockstargames.com)

### 🧩 خدمات توسعه‌دهنده گوگل:
- [Gemini](https://gemini.google.com)
- [Android Developers](https://developer.android.com)
- [Google Colab](https://colab.research.google.com)
- [Google AI Studio](https://makersuite.google.com)
- [Google Cloud Console](https://console.cloud.google.com)

> 🔐 **توجه:** این ابزار مخصوص عبور از **تحریم‌ها** است، نه فیلترینگ.  
> مثلاً سایت‌هایی مثل **یوتیوب فیلتر هستند، نه تحریم شده**، پس با این ابزار باز نمی‌شوند.

---

## 🖥️ اجرای ابزار

فایل `run-dns-scripts.bat` را اجرا کنید و یکی از گزینه‌های زیر را انتخاب نمایید:

```
1. Set Custom DNS Servers        → تنظیم DNS هوشمند
2. Verify DNS Settings           → بررسی وضعیت تنظیمات DNS
3. Restore Default Settings      → بازگردانی تنظیمات پیش‌فرض
4. Test DNS Servers with URL     → تست DNS با آدرس دلخواه
5. Open DNS Configuration GUI    → باز کردن ابزار گرافیکی
6. Exit                          → خروج
```

---

## ❤️ حمایت از توسعه‌دهنده

اگر این ابزار برات مفید بود، لطفاً کانال یوتیوب من رو دنبال کن تا بتونی از ابزارهای کاربردی بعدی هم بهره‌مند بشی:

🔗 https://www.youtube.com/@aka_techno

---
