# جعبه‌ابزار سیستم

ابزارهای کاربردی OpenWrt و Linux برای تنظیم DNS، عیب‌یابی شبکه و بررسی وضعیت سیستم.

## اجرای منوی همهٔ ابزارها با یک فرمان

داخل ترمینال Linux یا SSH روتر:

```sh
wget -qO /tmp/system-toolbox.sh https://raw.githubusercontent.com/sadrazkh/system-toolbox/main/toolbox.sh && sh /tmp/system-toolbox.sh
```

اگر wget نداری، به‌جای آن:

```sh
curl -fLsS -o /tmp/system-toolbox.sh https://raw.githubusercontent.com/sadrazkh/system-toolbox/main/toolbox.sh && sh /tmp/system-toolbox.sh
```

| ابزار | کاربرد |
| --- | --- |
| DNS | تشخیص مدیر شبکه، انتخاب DNS دلخواه، پشتیبان و بازیابی تنظیمات |
| عیب‌یابی شبکه | بررسی مسیر اینترنت، DNS، ارتباط IP و HTTPS |
| سلامت سیستم | نمایش CPU، RAM، فضای دیسک و سرویس‌های ناموفق |
| پورت‌ها | نمایش پورت‌های TCP/UDP در حال گوش‌دادن |

فقط ابزار DNS تنظیمات را تغییر می‌دهد؛ بقیه فقط اطلاعات را نمایش می‌دهند. برای DNS روی Linux در صورت نیاز sudo درخواست می‌شود؛ روی OpenWrt با root اجرا کن.

## تغییر مستقیم DNS

برای Ubuntu، Debian، Fedora، Arch، openSUSE و سیستم‌های Linux با مدیر DNS پشتیبانی‌شده:

```sh
wget -qO /tmp/system-toolbox-dns.sh https://raw.githubusercontent.com/sadrazkh/system-toolbox/main/dns.sh && sudo sh /tmp/system-toolbox-dns.sh 1.1.1.1 8.8.8.8
```

برای OpenWrt یا وقتی از قبل کاربر root هستی، همان فرمان را بدون sudo اجرا کن. دو IP آخر را با DNS خودت عوض کن؛ اگر حذفشان کنی، منوی انتخاب باز می‌شود.

بعد از دانلود، نمایش تنظیمات، بازیابی یا انتخاب اتصال خاص:

```sh
sh /tmp/system-toolbox-dns.sh --show
sh /tmp/system-toolbox-dns.sh --restore
sh /tmp/system-toolbox-dns.sh --interface eth0 9.9.9.9 149.112.112.112
```

روی Linux در صورت نیاز sudo اضافه کن. گزینهٔ interface برای NetworkManager و networkd است. این فایل دانلودشده امکان بازیابی آفلاین دارد؛ منوی مرکزی برای اجرای ابزارها از GitHub دانلود می‌کند. فایل‌های /tmp بعد از ری‌استارت پاک می‌شوند.

## پشتیبانی DNS

به‌جای اسم توزیع، مدیر واقعی DNS تشخیص داده می‌شود: OpenWrt/UCI، NetworkManager، systemd-networkd همراه resolved، خود systemd-resolved، resolvconf/openresolv و فایل resolv.conf مدیریت‌نشده.

در NetworkManager تنظیمات پروفایل اتصال اصلی تغییر می‌کند و پروفایل VPN خودکار انتخاب نمی‌شود. در networkd و resolved تنظیمات ماندگار اضافه می‌شوند. در resolvconf سرورهای دلخواه اولویت می‌گیرند ولی رکوردهای DHCP/VPN حذف نمی‌شوند. مسیرهای DNS اختصاصی VPN و اتصال‌های دیگر همچنان می‌توانند روی نتیجه اثر بگذارند.

تغییرات قبل از اجرا پشتیبان دارند و بعد از اجرا با پرس‌وجوی واقعی DNS بررسی می‌شوند. اگر اعمال تنظیمات یا پاسخ DNS شکست بخورد، ابزار برای بازگرداندن وضعیت قبلی تلاش می‌کند. فایل‌های تولیدشدهٔ WSL/کانتینر یا مدیر ناشناخته بدون دست‌کاری متوقف می‌شوند. روی چند اتصال فعال، interface موردنظر را مشخص کن.

IPهای IPv4 و IPv6 پذیرفته می‌شوند؛ IP#port مخصوص OpenWrt است. لینک‌های DoH برای این ابزار مناسب نیستند و DNS داخل برنامهٔ VPN جداست.

پشتیبان Linux در /var/lib/system-toolbox/dns و پشتیبان OpenWrt در /etc/system-toolbox/dns قرار دارد. ابزارهای تشخیصی گزارش را خودکار جایی آپلود نمی‌کنند؛ اگر اطلاعات شبکه یا پردازش‌ها را به اشتراک می‌گذاری، اول آن را بررسی کن.

## اجرای ابزارها جداگانه

```sh
sh /tmp/system-toolbox.sh network wikipedia.org
sh /tmp/system-toolbox.sh system
sh /tmp/system-toolbox.sh ports
```

تست‌های مدیرهای Linux در محیط جدا و شبیه‌سازی‌شده اجرا می‌شوند؛ سرویس شبکهٔ واقعی سیستم آزمایش تغییر نمی‌کند. GitHub Actions تست‌ها را روی Ubuntu اجرا می‌کند و تشخیص OpenWrt و ابزارهای تشخیصی روی AX3200 هم بررسی شده‌اند. این به معنی تست واقعی روی تمام توزیع‌ها و تمام تنظیمات ممکن نیست.
