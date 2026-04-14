#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BASE_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
CONFIG_FILE=${CONFIG_FILE:-$BASE_DIR/config.env}

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "[ERROR] config file not found: $CONFIG_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

required_vars=(
  ACME_ACCOUNT_EMAIL
  ALIYUN_ACCESS_KEY_ID
  ALIYUN_ACCESS_KEY_SECRET
  ACME_HOME
  CERT_HOME
  STATE_DIR
  WORK_DIR
  NGINX_SSL_DIR
  NGINX_SERVICE_NAME
  NGINX_RELOAD_CMD
  SMTP_HOST
  SMTP_PORT
  SMTP_USERNAME
  SMTP_PASSWORD
  SMTP_FROM
  SMTP_TO
  ZIP_PASSWORD
)

for var_name in "${required_vars[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    echo "[ERROR] missing config: $var_name" >&2
    exit 1
  fi
done

mkdir -p "$CERT_HOME" "$STATE_DIR" "$WORK_DIR" "$NGINX_SSL_DIR"

export Ali_Key="$ALIYUN_ACCESS_KEY_ID"
export Ali_Secret="$ALIYUN_ACCESS_KEY_SECRET"
export LE_WORKING_DIR="$ACME_HOME"

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

split_csv_to_array() {
  local input=$1
  local -n out_arr=$2
  IFS=',' read -r -a out_arr <<< "$input"
}

cert_dir() {
  local cert_name=$1
  printf '%s/%s' "$CERT_HOME" "$cert_name"
}

state_file_for() {
  local cert_name=$1
  printf '%s/%s.last_fingerprint' "$STATE_DIR" "$cert_name"
}

mail_marker_for() {
  local cert_name=$1
  printf '%s/%s.last_mailed_fingerprint' "$STATE_DIR" "$cert_name"
}

current_cert_fingerprint() {
  local fullchain=$1
  openssl x509 -in "$fullchain" -noout -fingerprint -sha256 | awk -F= '{print $2}' | tr -d ':'
}

current_cert_enddate() {
  local fullchain=$1
  openssl x509 -in "$fullchain" -noout -enddate | cut -d= -f2-
}

install_deps() {
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl git socat openssl jq unzip p7zip-full python3 python3-venv

  if ! command -v python3 >/dev/null 2>&1; then
    echo "[ERROR] python3 not found after install" >&2
    exit 1
  fi
}

install_acme() {
  if [[ ! -x "$ACME_HOME/acme.sh" ]]; then
    log "Installing acme.sh to $ACME_HOME"
    mkdir -p "$ACME_HOME"
    local tmp_dir
    tmp_dir=$(mktemp -d)
    git clone --depth 1 https://github.com/acmesh-official/acme.sh.git "$tmp_dir/acme.sh"
    pushd "$tmp_dir/acme.sh" >/dev/null
    if [[ -n "${ACME_ACCOUNT_EMAIL:-}" ]]; then
      ./acme.sh --install --home "$ACME_HOME" --accountemail "$ACME_ACCOUNT_EMAIL"
    else
      ./acme.sh --install --home "$ACME_HOME"
    fi
    popd >/dev/null
    rm -rf "$tmp_dir"
  fi

  "$ACME_HOME/acme.sh" --set-default-ca --server "$ACME_CA"
}

acme_issue_dns_aliyun() {
  local cert_name=$1
  shift
  local domains=("$@")
  local cmd=("$ACME_HOME/acme.sh" --issue --dns dns_ali --keylength ec-256 --cert-home "$CERT_HOME" --home "$ACME_HOME" --server "$ACME_CA")

  if [[ "${ACME_STAGING:-0}" == "1" ]]; then
    cmd+=(--staging)
  fi

  for domain in "${domains[@]}"; do
    cmd+=(-d "$domain")
  done

  cmd+=(--cert-file "$(cert_dir "$cert_name")/cert.pem" \
        --key-file "$(cert_dir "$cert_name")/key.pem" \
        --ca-file "$(cert_dir "$cert_name")/ca.pem" \
        --fullchain-file "$(cert_dir "$cert_name")/fullchain.pem")

  log "Issuing/Renewing certificate: $cert_name (${domains[*]})"
  mkdir -p "$(cert_dir "$cert_name")"
  "${cmd[@]}"
}

reload_nginx() {
  log "Reloading nginx"
  bash -lc "$NGINX_RELOAD_CMD"
}
