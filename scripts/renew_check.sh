#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

require_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "[ERROR] please run as root" >&2
    exit 1
  fi
}

sync_nginx_cert_if_changed() {
  local cert_name=$1
  local fullchain
  fullchain="$(cert_dir "$cert_name")/fullchain.pem"
  local new_fp old_fp
  new_fp=$(current_cert_fingerprint "$fullchain")
  old_fp=$(cat "$(state_file_for "$cert_name")" 2>/dev/null || true)

  if [[ "$new_fp" != "$old_fp" ]]; then
    log "Detected new nginx certificate fingerprint for $cert_name"
    install -m 600 "$(cert_dir "$cert_name")/key.pem" "$NGINX_SSL_DIR/${cert_name}.key"
    install -m 644 "$(cert_dir "$cert_name")/fullchain.pem" "$NGINX_SSL_DIR/${cert_name}.crt"
    reload_nginx
    echo "$new_fp" > "$(state_file_for "$cert_name")"
  else
    log "Nginx certificate unchanged: $cert_name"
  fi
}

mail_if_changed() {
  local cert_name=$1
  local domain_label=$2
  local fullchain
  fullchain="$(cert_dir "$cert_name")/fullchain.pem"
  local new_fp old_fp
  new_fp=$(current_cert_fingerprint "$fullchain")
  old_fp=$(cat "$(state_file_for "$cert_name")" 2>/dev/null || true)

  if [[ "$new_fp" != "$old_fp" ]]; then
    log "Detected new certificate fingerprint for $cert_name"
    echo "$new_fp" > "$(state_file_for "$cert_name")"
    "$SCRIPT_DIR/send_cert_mail.sh" "$cert_name" "$domain_label"
  else
    log "Certificate unchanged: $cert_name"
  fi
}

main() {
  require_root
  install_acme

  log "Running acme.sh cron renewal check"
  "$ACME_HOME/acme.sh" --cron --home "$ACME_HOME"

  sync_nginx_cert_if_changed "$NGINX_CERT_NAME"
  mail_if_changed "$CDN_CERT_NAME" "$CDN_DOMAIN"
  mail_if_changed "$WECHAT_CERT_NAME" "$WECHAT_DOMAIN"

  log "Renew check completed"
}

main "$@"
