رفع خطای GitHub Actions: tools/prepare_android.py یافت نشد

1) این ZIP را در ریشه مخزن sameni-vpn استخراج کنید؛ یعنی کنار pubspec.yaml و پوشه lib.
2) مطمئن شوید مسیر زیر وجود دارد:
   tools/prepare_android.py
3) در PowerShell از ریشه پروژه اجرا کنید:
   git add tools/prepare_android.py
   git commit -m "Add Android preparation script for CI"
   git push origin main
4) سپس GitHub > Actions را باز کنید و اجرای جدید را بررسی کنید.

این بسته فقط فایل گمشده را اضافه می‌کند و سورس برنامه یا تنظیمات آن را جایگزین نمی‌کند.
