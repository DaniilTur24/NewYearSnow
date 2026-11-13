#!/bin/zsh
# Собирает приложение и упаковывает его в установщик dist/NewYearSnow.dmg
set -e
cd "$(dirname "$0")"
./build.sh

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R build/NewYearSnow.app "$STAGE/"
ln -s /Applications "$STAGE/Программы (Applications)"
cp "installer/Как установить.txt" "$STAGE/"

mkdir -p dist
rm -f dist/NewYearSnow.dmg
hdiutil create -volname "Новогодний снег" -srcfolder "$STAGE" -ov -format UDZO dist/NewYearSnow.dmg >/dev/null
echo "Готово: dist/NewYearSnow.dmg ($(du -h dist/NewYearSnow.dmg | cut -f1))"
