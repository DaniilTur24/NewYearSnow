#!/bin/zsh
# Создаёт самоподписанный сертификат «NewYearSnow Dev» для подписи кода
# и кладёт его в вашу связку ключей «Вход» (login).
# Запускать один раз, вручную. После этого ./build.sh будет подписывать им приложение,
# и разрешение «Универсальный доступ» перестанет слетать после пересборки.
set -e
NAME="NewYearSnow Dev"
if security find-identity -p codesigning 2>/dev/null | grep -q "$NAME"; then
  echo "Сертификат «$NAME» уже есть."
  exit 0
fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
"${OPENSSL_REQ:-/usr/bin/openssl}" req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
# Системный openssl (LibreSSL) делает файл, который macOS понимает. Если в PATH стоит свежий OpenSSL 3+
# (например, из Homebrew), он шифрует файл по-новому, и «security import» его не читает, поэтому берём системный.
OPENSSL=/usr/bin/openssl
[ -x "$OPENSSL" ] || OPENSSL=openssl
"$OPENSSL" pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
  -out "$TMP/cert.p12" -passout pass:newyear 2>/dev/null
security import "$TMP/cert.p12" -k ~/Library/Keychains/login.keychain-db -P newyear -T /usr/bin/codesign
echo "Готово: сертификат «$NAME» добавлен в связку ключей «Вход»."
echo "Теперь пересоберите приложение: ./build.sh"
