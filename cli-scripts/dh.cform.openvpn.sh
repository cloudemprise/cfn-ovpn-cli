#!/bin/bash

S3_TEMPLATE_LOCATION="s3://dh.cform-templates/openvpn/"
S3_IPTABLES_LOCATION="s3://dh.scripts/iptables/"
S3_SSH_LOCATION="s3://dh.scripts/ssh/"
S3_OPENVPN_LOCATION="s3://dh.scripts/openvpn/server/"
S3_EASYRSA_LOCATION="s3://dh.scripts/easyrsa/openvpn/gen-reqs/"



#Upload latest Nested Templates to S3
aws s3 cp dh.cform.openvpn.yaml $S3_TEMPLATE_LOCATION
aws s3 cp dh.cform.openvpn-vpc.yaml $S3_TEMPLATE_LOCATION
aws s3 cp dh.cform.openvpn-nacl.yaml $S3_TEMPLATE_LOCATION
aws s3 cp dh.cform.openvpn-sg.yaml $S3_TEMPLATE_LOCATION
aws s3 cp dh.cform.openvpn-ec2-pub.yaml $S3_TEMPLATE_LOCATION
aws s3 cp dh.cform.openvpn-ec2-priv.yaml $S3_TEMPLATE_LOCATION
#aws s3 cp dh.cform.openvpn-ec2-priv.yaml $S3_TEMPLATE_LOCATION

#Compress & Upload iptables script to S3
# Public instance script
# Private instance script
cd iptables-scripts/
tar -zcf - dh.cform.openvpn-ec2-pub-iptables.sh | aws s3 cp - ${S3_IPTABLES_LOCATION}dh.cform.openvpn-ec2-pub-iptables.sh.tar.gz
tar -zcf - dh.cform.openvpn-ec2-priv-iptables.sh | aws s3 cp - ${S3_IPTABLES_LOCATION}dh.cform.openvpn-ec2-priv-iptables.sh.tar.gz
cd ..


#Compress & Upload sshd hardening script to S3
# Use for both public & private instances
cd ssh-scripts/
tar -zcf - dh.cform.openvpn-ec2-harden-ssh.sh | aws s3 cp - ${S3_SSH_LOCATION}dh.cform.openvpn-ec2-harden-ssh.sh.tar.gz
cd ..

#Compress & Upload openvpn server configs to S3
# Both udp & tcp server configs
cd openvpn-configs/
tar -zcf - dh.vpn.server.*1194.conf | aws s3 cp - ${S3_OPENVPN_LOCATION}dh.vpn.server.xxx1194.conf.tar.gz
cd ..

#Upload easy-rsa pki keygen configs to S3
cd easyrsa-configs/
tar -zcf - vars.* | aws s3 cp - ${S3_EASYRSA_LOCATION}dh.easyrsa.openvpn.vars.tar.gz
cd ..

#Create cloudformation stack
aws cloudformation create-stack --stack-name OpenVPNTest01 --template-url https://s3.eu-central-1.amazonaws.com/dh.cform-templates/openvpn/dh.cform.openvpn.yaml --tags Key=Name,Value=OpenVPN-Test --on-failure DO_NOTHING
