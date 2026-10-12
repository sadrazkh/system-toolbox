# جعبه‌ابزار سیستم

مجموعه‌ای از ابزارهای کاربردی برای OpenWrt و Linux؛ ابزارهای Ubuntu هم می‌توانند بعداً به همین مخزن اضافه شوند.

## تنظیم DNS در OpenWrt

این فرمان را داخل **ترمینال SSH روتر با کاربر root** اجرا کن. ابزار فعلی مخصوص OpenWrt است.

اجرای تعاملی؛ انتخاب Cloudflare، Google، Quad9 یا DNS دلخواه:

```sh
wget -qO /tmp/system-toolbox-dns.sh https://raw.githubusercontent.com/sadrazkh/system-toolbox/main/openwrt/dns.sh && sh /tmp/system-toolbox-dns.sh
```

اجرای مستقیم با DNS دلخواه؛ دو IP آخر را عوض کن:

```sh
wget -qO /tmp/system-toolbox-dns.sh https://raw.githubusercontent.com/sadrazkh/system-toolbox/main/openwrt/dns.sh && sh /tmp/system-toolbox-dns.sh 1.1.1.1 8.8.8.8
```

بعد از دانلود، تغییر مجدد DNS، نمایش وضعیت یا بازگرداندن تنظیمات قبلی:

```sh
sh /tmp/system-toolbox-dns.sh 9.9.9.9 149.112.112.112
sh /tmp/system-toolbox-dns.sh --show
sh /tmp/system-toolbox-dns.sh --restore
```

ابزار DNSهای بالادستی را نادیده می‌گیرد و لیست جدید را در `/etc/config/dhcp` ذخیره می‌کند. قبل از تغییر، پشتیبان خصوصی می‌گیرد و بعد از راه‌اندازی مجدد dnsmasq، پاسخ DNS را آزمایش می‌کند. اگر DNS پاسخ ندهد، تنظیمات قبلی برمی‌گردد. با هر اجرای جدید، پشتیبان قبلی با وضعیت قبل از همان اجرا جایگزین می‌شود. بازیابی فقط دو گزینهٔ DNS را تغییر می‌دهد و تنظیمات دیگر DHCP را نگه می‌دارد.

IPهای IPv4 و IPv6 و قالب `IP#port` پذیرفته می‌شوند. لینک‌های DoH مثل `https://…/dns-query` برای این ابزار مناسب نیستند؛ آن‌ها به کلاینت جدا نیاز دارند. اگر در LuCI تغییر ذخیره‌نشده‌ای برای DHCP/DNS داری، اول آن را ذخیره یا لغو کن.

این ابزار DNS خود OpenWrt را تغییر می‌دهد. DNS داخل برنامهٔ VPN جداست و مسیر درخواست‌ها همچنان تابع قوانین تونل است. سرویس VPN ری‌استارت نمی‌شود.
