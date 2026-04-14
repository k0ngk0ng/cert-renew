# Ubuntu 22.04 证书自动申请与续签部署说明

## 1. 部署目录

建议部署到 `/opt/cert-manager`：

```bash
sudo mkdir -p /opt/cert-manager
sudo cp -r config.env.example scripts systemd /opt/cert-manager/
cd /opt/cert-manager
sudo cp config.env.example config.env
```

## 2. 编辑配置

至少修改以下配置项：

- `ACME_ACCOUNT_EMAIL`
- `ALIYUN_ACCESS_KEY_ID`
- `ALIYUN_ACCESS_KEY_SECRET`
- `SMTP_HOST`
- `SMTP_PORT`
- `SMTP_USERNAME`
- `SMTP_PASSWORD`
- `SMTP_FROM`
- `SMTP_TO`
- `ZIP_PASSWORD`

## 3. 授权脚本

```bash
sudo chmod +x /opt/cert-manager/scripts/*.sh
sudo chmod +x /opt/cert-manager/scripts/*.py
```

## 4. 首次签发并部署

```bash
cd /opt/cert-manager
sudo CONFIG_FILE=/opt/cert-manager/config.env /opt/cert-manager/scripts/issue_and_deploy.sh
```

首次执行会：

- 安装依赖与 `acme.sh`
- 通过阿里云 DNS API 申请 3 张证书
- 把 Nginx 证书部署到 `/etc/nginx/ssl`
- 检查并 reload Nginx
- 将 CDN / 微信证书打包为加密 zip 后通过 SMTP 发给多个邮箱

## 5. systemd 定时续签

```bash
sudo cp /opt/cert-manager/systemd/cert-renew.service /etc/systemd/system/
sudo cp /opt/cert-manager/systemd/cert-renew.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now cert-renew.timer
sudo systemctl list-timers --all | grep cert-renew
```

## 6. 手工触发续签检查

```bash
sudo systemctl start cert-renew.service
sudo journalctl -u cert-renew.service -n 200 --no-pager
```

## 7. Nginx 配置参考

Nginx 站点里引用：

```nginx
ssl_certificate     /etc/nginx/ssl/nginx-yunhongfu.crt;
ssl_certificate_key /etc/nginx/ssl/nginx-yunhongfu.key;
```

## 8. 自动续签行为说明

- 定时任务每日执行一次
- `acme.sh --cron` 仅在临近到期时才真正续签
- 若 Nginx 证书发生变化，则自动覆盖并 reload Nginx
- 若 CDN / 微信证书发生变化，则仅对“新证书”发送一次邮件
- 邮件附件为加密 zip，密码不进邮件正文，由 `ZIP_PASSWORD` 控制

## 9. 建议先用测试环境验证

把 `ACME_STAGING=1` 先跑通流程，确认 DNS、SMTP、Nginx reload 都正常后，再改回 `0` 申请正式证书。
