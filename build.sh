#!/bin/zsh
# Собирает build/NewYearSnow.app — одно приложение для всех Mac (Apple Silicon и Intel).
set -e
cd "$(dirname "$0")"
APP=build/NewYearSnow.app
OBJ=build/obj
rm -rf "$APP" "$OBJ"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$OBJ"

for arch in arm64 x86_64; do
  echo "Сборка для $arch…"
  swiftc -O -swift-version 5 -target $arch-apple-macos14.0 Sources/*.swift \
    -o "$OBJ/NewYearSnow-$arch" \
    -framework Cocoa -framework QuartzCore -framework AVFoundation -framework SwiftUI -framework ServiceManagement
done
lipo -create "$OBJ"/NewYearSnow-* -output "$APP/Contents/MacOS/NewYearSnow"
rm -rf "$OBJ"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Если в связке ключей есть сертификат «NewYearSnow Dev» (см. make-cert.sh), подписываем им:
# тогда разрешение «Универсальный доступ» переживает пересборки.
# Иначе — бесплатная ad-hoc подпись.
CERT="NewYearSnow Dev"
if security find-identity -p codesigning 2>/dev/null | grep -q "$CERT" \
   && codesign --force --sign "$CERT" "$APP" 2>/dev/null; then
  echo "Подписано сертификатом «$CERT»"
else
  codesign --force --sign - "$APP" >/dev/null 2>&1
  echo "Подписано ad-hoc"
fi
echo "Готово: $APP"
