#!/bin/sh
# Creates a self-signed code-signing identity in the login keychain, once.
# A stable identity means Keychain (API key) and Privacy (folder access) grants survive rebuilds;
# ad-hoc signatures change every build and macOS treats each build as a new app.
set -e
NAME="DnDCategoriser Dev"
if security find-identity -v -p codesigning | grep -q "$NAME"; then
  echo "identity '$NAME' already exists"
  exit 0
fi
TMP=$(mktemp -d)
cat > "$TMP/openssl.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $NAME
[v3]
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
basicConstraints = critical,CA:false
subjectKeyIdentifier = hash
CNF
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/openssl.cnf" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" -passout pass:dnd
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
security import "$TMP/id.p12" -k "$KEYCHAIN" -P dnd -T /usr/bin/codesign >/dev/null
echo "Trusting the certificate for code signing; macOS asks for your login password once."
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"
rm -rf "$TMP"
security find-identity -v -p codesigning | grep "$NAME"
