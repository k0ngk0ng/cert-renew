# cert-renew

A small Bash-based certificate automation toolkit for Ubuntu servers.

It uses `acme.sh` with Alibaba Cloud DNS (`dns_ali`) to issue and renew certificates, deploys the Nginx certificate locally, and emails password-protected certificate packages for CDN and WeChat usage.

## Features

- Issue certificates through `acme.sh` + Alibaba Cloud DNS API
- Deploy the Nginx certificate to a local SSL directory
- Reload Nginx automatically after certificate updates
- Run daily renewal checks with `systemd`
- Send password-protected ZIP attachments by SMTP when non-Nginx certificates change
- Track certificate fingerprints to avoid duplicate deployments and emails

## Project Structure

- `config.env.example` - example configuration file
- `scripts/common.sh` - shared helpers and configuration loading
- `scripts/issue_and_deploy.sh` - first-time issuance and deployment
- `scripts/renew_check.sh` - scheduled renewal check entrypoint
- `scripts/send_cert_mail.sh` - package and email certificates
- `scripts/send_mail.py` - SMTP mail sender
- `systemd/cert-renew.service` - systemd service unit
- `systemd/cert-renew.timer` - systemd timer unit
- `DEPLOY.md` - deployment notes in Chinese

## Requirements

- Ubuntu 22.04 or a compatible Linux distribution
- Root access for deployment and Nginx reload
- Alibaba Cloud DNS API credentials
- A working SMTP account for certificate delivery
- An Nginx server using PEM certificate files

## Configuration

Copy the sample config and adjust it for your environment:

```bash
cp config.env.example config.env
```

Important settings include:

- `ACME_ACCOUNT_EMAIL`
- `ALIYUN_ACCESS_KEY_ID`
- `ALIYUN_ACCESS_KEY_SECRET`
- `ACME_HOME`
- `CERT_HOME`
- `STATE_DIR`
- `WORK_DIR`
- `NGINX_SSL_DIR`
- `NGINX_RELOAD_CMD`
- `SMTP_HOST`
- `SMTP_PORT`
- `SMTP_USERNAME`
- `SMTP_PASSWORD`
- `SMTP_FROM`
- `SMTP_TO`
- `ZIP_PASSWORD`

## First-Time Issuance

Run the initial setup and deployment as root:

```bash
sudo CONFIG_FILE=$(pwd)/config.env ./scripts/issue_and_deploy.sh
```

This script will:

- install required packages
- install `acme.sh` if needed
- issue certificates
- deploy the Nginx certificate
- reload Nginx
- email CDN / WeChat certificates if configured

## Renewal

Manual renewal check:

```bash
sudo CONFIG_FILE=$(pwd)/config.env ./scripts/renew_check.sh
```

With `systemd`:

```bash
sudo cp systemd/cert-renew.service /etc/systemd/system/
sudo cp systemd/cert-renew.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now cert-renew.timer
```

## Notes

- `acme.sh --cron` only renews certificates when they are close to expiration.
- Nginx is reloaded only when the deployed certificate fingerprint changes.
- Email notifications are sent only once per new certificate fingerprint.
- ZIP attachments are encrypted with the configured `ZIP_PASSWORD`.
- You can test the full workflow with staging by setting `ACME_STAGING=1` first.

## License

This project currently does not include an explicit license.
