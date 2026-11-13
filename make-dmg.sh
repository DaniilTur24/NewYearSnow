#!/bin/zsh
# Собирает приложение и упаковывает его в установщик dist/NewYearSnow.dmg
# с оформленным окном: фон-подсказка, значок программы и папка «Программы» рядом.
set -e
cd "$(dirname "$0")"
./build.sh

VOL="Новогодний снег"
WORK=$(mktemp -d)
trap 'hdiutil detach "/Volumes/$VOL" -quiet 2>/dev/null || true; rm -rf "$WORK"' EXIT

# Фон (обычный и ретина) → один .tiff
swift tools/make-dmg-bg.swift "$WORK/bg.png" 1
swift tools/make-dmg-bg.swift "$WORK/bg@2x.png" 2
tiffutil -cathidpicheck "$WORK/bg.png" "$WORK/bg@2x.png" -out "$WORK/bg.tiff" >/dev/null 2>&1

STAGE="$WORK/stage"
mkdir -p "$STAGE/.background"
cp -R build/NewYearSnow.app "$STAGE/"
ln -s /Applications "$STAGE/Программы (Applications)"
cp "$WORK/bg.tiff" "$STAGE/.background/bg.tiff"

# Временный записываемый образ, чтобы Finder запомнил вид окна
hdiutil detach "/Volumes/$VOL" -quiet 2>/dev/null || true
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -ov -format UDRW -fs HFS+ "$WORK/rw.dmg" >/dev/null
hdiutil attach "$WORK/rw.dmg" -noautoopen -quiet

if ! osascript <<EOF
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 840, 568}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 96
    set text size of opts to 13
    set background picture of opts to file ".background:bg.tiff"
    set position of item "NewYearSnow.app" of container window to {160, 190}
    set position of item "Программы (Applications)" of container window to {480, 190}
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF
then
  echo "⚠️  Не удалось оформить окно через Finder (нет разрешения на управление Finder?) — будет простое окно."
fi
sync
hdiutil detach "/Volumes/$VOL" -quiet

mkdir -p dist
rm -f dist/NewYearSnow.dmg
hdiutil convert "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -o dist/NewYearSnow.dmg >/dev/null
echo "Готово: dist/NewYearSnow.dmg ($(du -h dist/NewYearSnow.dmg | cut -f1))"
