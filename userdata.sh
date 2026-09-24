#!/bin/bash
  dnf install -y nginx
  ...strona index.html z hostnameem instancji...
  ...echo "boot $(hostname) $(date)" | aws s3 cp - s3://BUCKET/boot-$(hostname).txt
  systemctl enable --now nginx
