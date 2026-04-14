#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

cert_name=${1:?cert_name required}
domain_label=${2:?domain label required}

cert_path=$(cert_dir "$cert_name")
fullchain="$cert_path/fullchain.pem"
keyfile="$cert_path/key.pem"
mail_marker=$(mail_marker_for "$cert_name")

if [[ ! -f "$fullchain" || ! -f "$keyfile" ]]; then
  log "Skip mail for $cert_name: certificate files not found"
  exit 0
fi

fingerprint=$(current_cert_fingerprint "$fullchain")
if [[ -f "$mail_marker" ]] && [[ "$(cat "$mail_marker")" == "$fingerprint" ]]; then
  log "Skip mail for $cert_name: fingerprint already mailed"
  exit 0
fi

package_dir="$WORK_DIR/${cert_name}_package"
rm -rf "$package_dir"
mkdir -p "$package_dir"
cp "$fullchain" "$package_dir/fullchain.pem"
cp "$keyfile" "$package_dir/key.pem"

enddate=$(current_cert_enddate "$fullchain")
zip_file="$WORK_DIR/${cert_name}_${fingerprint:0:12}.zip"
rm -f "$zip_file"
7z a -tzip -p"$ZIP_PASSWORD" -mem=AES256 "$zip_file" "$package_dir"/* >/dev/null

subject="${SMTP_SUBJECT_PREFIX:-[cert]} ${domain_label} certificate updated"
body=$(cat <<MAIL
证书已更新，请查收附件。

标识: ${domain_label}
证书名称: ${cert_name}
到期时间: ${enddate}
SHA256 指纹: ${fingerprint}

附件为加密 zip 压缩包，密码按预设配置线下传递。
MAIL
)

python3 "$SCRIPT_DIR/send_mail.py" \
  --host "$SMTP_HOST" \
  --port "$SMTP_PORT" \
  --username "$SMTP_USERNAME" \
  --password "$SMTP_PASSWORD" \
  --from-addr "$SMTP_FROM" \
  --to-addrs "$SMTP_TO" \
  --subject "$subject" \
  --body "$body" \
  --attachment "$zip_file" \
  --use-ssl "${SMTP_USE_SSL:-true}"

echo "$fingerprint" > "$mail_marker"
log "Certificate mail sent: $cert_name -> $SMTP_TO"
