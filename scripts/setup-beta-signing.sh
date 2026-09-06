#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
IDENTITY_NAME="ContextInput Beta Code Signing"

if security find-identity -v -p codesigning | grep -Fq "\"$IDENTITY_NAME\""; then
    echo "Code-signing identity already exists: $IDENTITY_NAME"
    exit 0
fi

temporary_dir=$(mktemp -d)
trap 'rm -rf "$temporary_dir"' EXIT

certificate_path="$temporary_dir/contextinput-beta.crt"
private_key_path="$temporary_dir/contextinput-beta.key"
archive_path="$temporary_dir/contextinput-beta.p12"
archive_password=$(openssl rand -hex 24)
keychain_path=$(security default-keychain -d user | sed -E 's/^[[:space:]]*"(.*)"[[:space:]]*$/\1/')

openssl req -new -newkey rsa:3072 -x509 -sha256 -days 3650 -nodes \
    -config "$PROJECT_DIR/packaging/beta-certificate.cnf" \
    -keyout "$private_key_path" \
    -out "$certificate_path"

openssl pkcs12 -export \
    -inkey "$private_key_path" \
    -in "$certificate_path" \
    -name "$IDENTITY_NAME" \
    -passout "pass:$archive_password" \
    -out "$archive_path"

security import "$archive_path" \
    -k "$keychain_path" \
    -P "$archive_password" \
    -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign \
    -k "$keychain_path" "$certificate_path"

if ! security find-identity -v -p codesigning | grep -Fq "\"$IDENTITY_NAME\""; then
    echo "The certificate was imported but is not a valid code-signing identity." >&2
    exit 1
fi

echo "Created code-signing identity: $IDENTITY_NAME"
echo "Back it up from Keychain Access before releasing to testers."
