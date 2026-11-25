#!/usr/bin/env bash
# Makes the certificate that signs every wm release. Run it ONCE, on the Mac that releases wm.
#
# macOS keeps the Accessibility and Screen Recording grants of wm by its signature. A release signed with the same certificate
# every time keeps the grants through `brew upgrade wm`. A new certificate means everyone grants the permissions once more.
#
#   scripts/make-signing-cert.sh [backup-folder]      (default: ~/Library/Application Support/wm-signing)
#
# It imports the certificate into your login keychain, pins it in scripts/signing-cert.sha1 (commit that file) and leaves the
# .p12 and its password in the backup folder. Copy the folder somewhere safe.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
pin="$repo/scripts/signing-cert.sha1"
out="${1:-$HOME/Library/Application Support/wm-signing}"

[ ! -e "$pin" ] || {
    echo "error: a release certificate is already pinned in $pin. Import its backup instead of making a new one:" >&2
    echo "         security import wm-signing.p12 -P \"\$(cat password.txt)\" -T /usr/bin/codesign" >&2
    echo "       A new certificate resets the permissions of every user. To do that anyway, delete the pin first." >&2
    exit 1
}
[ ! -e "$out" ] || { echo "error: $out exists; remove it or pick another folder" >&2; exit 1; }
umask 077
mkdir -p "$out"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

openssl rand -base64 24 > "$out/password.txt"
cat > "$work/openssl.cnf" <<'CNF'
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

openssl req -x509 -newkey rsa:2048 -nodes -days 7300 -config "$work/openssl.cnf" -keyout "$work/key.pem" -out "$out/cert.pem" 2>/dev/null
# -legacy: the macOS keychain does not read the newer PKCS#12 encryption of OpenSSL 3. LibreSSL has no such flag.
pack() { openssl pkcs12 -export "$@" -inkey "$work/key.pem" -in "$out/cert.pem" -name "wm release signing" -out "$out/wm-signing.p12" -passout "file:$out/password.txt"; }
pack -legacy 2>/dev/null || pack

security import "$out/wm-signing.p12" -P "$(cat "$out/password.txt")" -T /usr/bin/codesign
openssl x509 -in "$out/cert.pem" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d : > "$pin"
chmod 644 "$pin"

echo "certificate: SHA-1 $(cat "$pin"), imported into your keychain and pinned in scripts/signing-cert.sha1"
echo "backup:      $out   <- copy it somewhere safe; never commit it"
