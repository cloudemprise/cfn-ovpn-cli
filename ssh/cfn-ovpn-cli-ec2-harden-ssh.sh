#!/bin/bash
#--
# Script to harden sshd config for bastion host
# To test use sshd -T | sort | grep blabla
for i in $(ls /etc/ssh/*_config); do cp $i "$i.bak"; done
sed -i '/^[[:blank:]]*#/d;s/#.*//;/^[[:space:]]*$/d' /etc/ssh/sshd_config
sed -i '/sftp/d' /etc/ssh/sshd_config
grep -q '.*PermitRootLogin.*' /etc/ssh/sshd_config && sed -i 's/.*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config || echo "PermitRootLogin no" >> /etc/ssh/sshd_config
grep -q '.*PasswordAuthentication.*' /etc/ssh/sshd_config && sed -i 's/.*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config || echo "PasswordAuthentication no" >> /etc/ssh/sshd_config
grep -q '.*AuthenticationMethods.*' /etc/ssh/sshd_config && sed -i 's/.*AuthenticationMethods.*/AuthenticationMethods publickey/' /etc/ssh/sshd_config || echo "AuthenticationMethods publickey" >> /etc/ssh/sshd_config
grep -q '.*PubkeyAuthentication.*' /etc/ssh/sshd_config && sed -i 's/.*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config || echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config
grep -q '.*X11Forwarding.*' /etc/ssh/sshd_config && sed -i 's/.*X11Forwarding.*/X11Forwarding no/' /etc/ssh/sshd_config || echo "X11Forwarding no" >> /etc/ssh/sshd_config
grep -q '.*ClientAliveInterval.*' /etc/ssh/sshd_config && sed -i 's/.*ClientAliveInterval.*/ClientAliveInterval 600/' /etc/ssh/sshd_config || echo "ClientAliveInterval 600" >> /etc/ssh/sshd_config
grep -q '.*ClientAliveCountMax.*' /etc/ssh/sshd_config && sed -i 's/.*ClientAliveCountMax.*/ClientAliveCountMax 0/' /etc/ssh/sshd_config || echo "ClientAliveCountMax 0" >> /etc/ssh/sshd_config
grep -q '.*IgnoreRhosts.*' /etc/ssh/sshd_config && sed -i 's/.*IgnoreRhosts.*/IgnoreRhosts yes/' /etc/ssh/sshd_config || echo "IgnoreRhosts yes" >> /etc/ssh/sshd_config
grep -q '.*AllowUsers.*' /etc/ssh/sshd_config && sed -i 's/.*AllowUsers.*/AllowUsers ec2-user/' /etc/ssh/sshd_config || echo "AllowUsers ec2-user" >> /etc/ssh/sshd_config
grep -q '.*LogLevel.*' /etc/ssh/sshd_config && sed -i 's/.*LogLevel.*/LogLevel VERBOSE/' /etc/ssh/sshd_config || echo "LogLevel VERBOSE" >> /etc/ssh/sshd_config
awk '$5 >= 3071' /etc/ssh/moduli > /etc/ssh/moduli.tmp && mv /etc/ssh/moduli.tmp /etc/ssh/moduli