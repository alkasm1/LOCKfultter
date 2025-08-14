#!/bin/bash
echo "بناء تطبيق Keynova Lock..."

# تثبيت المتطلبات
npm install

# بناء التطبيق
npm run build

# إعداد Capacitor
npx cap sync

echo "لإنشاء APK، قم بتشغيل:"
echo "npx cap open android"
