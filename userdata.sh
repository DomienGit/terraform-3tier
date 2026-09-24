#!/bin/bash
dnf install -y nginx
echo "<h1>Serwer: $(hostname)</h1>" > /usr/share/nginx/html/index.html
echo "boot $(hostname) $(date)" | aws s3 cp - s3://terraform-3tier-domiendev/boot-$(hostname).txt
systemctl enable --now nginx
