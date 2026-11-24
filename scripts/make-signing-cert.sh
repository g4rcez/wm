#!/usr/bin/env bash
# Makes the certificate that signs every wm release. Run it ONCE and keep the .p12 safe.
#
# macOS keeps the Accessibility and Screen Recording grants of wm by its signature. A release signed with the same certificate
# every time keeps the grants through `brew upgrade wm`. A new certificate means everyone grants the permissions once more.
#
#   scripts/make-signing-cert.sh [output-folder]      (default: ./wm-signing)
#
# Then add two secrets to the repository (Settings > Secrets and variables > Actions):
#   WM_SIGNING_P12            the base64 text printed at the end
#   WM_SIGNING_P12_PASSWORD   the password printed at the end
set -euo pipefail

out="${1:-wm-signing}"
[ ! -e "$out" ] || { echo "error: $out exists; remove it or pick another folder" >&2; exit 1; }
mkdir -p "$out"
chmod 700 "$out"

password="$(openssl rand -base64 24)"
cat > "$out/openssl.cnf" <<'CNF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = wm release signing
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

openssl req -x509 -newkey rsa:2048 -nodes -days 7300 -config "$out/openssl.cnf" -keyout "$out/key.pem" -out "$out/cert.pem" 2>/dev/null
# -legacy: the macOS keychain does not read the newer PKCS#12 encryption of OpenSSL 3.
openssl pkcs12 -export -legacy -inkey "$out/key.pem" -in "$out/cert.pem" -name "wm release signing" -out "$out/wm-signing.p12" -passout "pass:$password" 2>/dev/null \
    || openssl pkcs12 -export -inkey "$out/key.pem" -in "$out/cert.pem" -name "wm release signing" -out "$out/wm-signing.p12" -passout "pass:$password"
rm -f "$out/key.pem" "$out/openssl.cnf"
chmod 600 "$out/wm-signing.p12"

echo "certificate: $out/cert.pem  (SHA-1 $(openssl x509 -in "$out/cert.pem" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d :))"
echo "p12:         $out/wm-signing.p12   <- back this file up; never commit it"
echo
echo "WM_SIGNING_P12_PASSWORD=$password"
echo "WM_SIGNING_P12 is the output of:  base64 -i $out/wm-signing.p12 | pbcopy"
echo "With gh:  base64 -i $out/wm-signing.p12 | gh secret set WM_SIGNING_P12 && gh secret set WM_SIGNING_P12_PASSWORD --body '$password'"
