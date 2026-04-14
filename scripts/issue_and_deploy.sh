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

sync_nginx_cert() {
  local cert_name=$1
  local src_dir
  src_dir=$(cert_dir "$cert_name")
  install -m 600 "$src_dir/key.pem" "$NGINX_SSL_DIR/${cert_name}.key"
  install -m 644 "$src_dir/fullchain.pem" "$NGINX_SSL_DIR/${cert_name}.crt"
}

record_fingerprint() {
  local cert_name=$1
  local fullchain
  fullchain="$(cert_dir "$cert_name")/fullchain.pem"
  current_cert_fingerprint "$fullchain" > "$(state_file_for "$cert_name")"
}

main() {
  require_root
  install_deps
  install_acme

  local nginx_domains
  split_csv_to_array "$NGINX_DOMAINS" nginx_domains

  acme_issue_dns_aliyun "$NGINX_CERT_NAME" "${nginx_domains[@]}"
  sync_nginx_cert "$NGINX_CERT_NAME"
  reload_nginx
  record_fingerprint "$NGINX_CERT_NAME"

  acme_issue_dns_aliyun "$CDN_CERT_NAME" "$CDN_DOMAIN"
  record_fingerprint "$CDN_CERT_NAME"

  acme_issue_dns_aliyun "$WECHAT_CERT_NAME" "$WECHAT_DOMAIN"
  record_fingerprint "$WECHAT_CERT_NAME"

  IFS=',' read -r -a targets <<< "${MAIL_CERT_TARGETS:-cdn,wechat}"
  for target in "${targets[@]}"; do
    case "$target" in
      cdn)
        "$SCRIPT_DIR/send_cert_mail.sh" "$CDN_CERT_NAME" "$CDN_DOMAIN"
        ;;
      wechat)
        "$SCRIPT_DIR/send_cert_mail.sh" "$WECHAT_CERT_NAME" "$WECHAT_DOMAIN"
        ;;
      *)
        log "Unknown mail target ignored: $target"
        ;;
    esac
  done

  log "Initial issue and deployment completed"
}

main "$@"
