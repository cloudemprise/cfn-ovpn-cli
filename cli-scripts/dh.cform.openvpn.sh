#!/bin/bash

S3_TEMPLATE_LOCATION="s3://dh.cform-templates/openvpn/"
S3_IPTABLES_LOCATION="s3://dh.scripts/iptables/"

#Upload latest Nested Templates to S3
aws s3 cp dh.cform.openvpn.yaml $S3_TEMPLATE_LOCATION
aws s3 cp dh.cform.openvpn-vpc.yaml $S3_TEMPLATE_LOCATION
aws s3 cp dh.cform.openvpn-nacl.yaml $S3_TEMPLATE_LOCATION
aws s3 cp dh.cform.openvpn-sg.yaml $S3_TEMPLATE_LOCATION
aws s3 cp dh.cform.openvpn-ec2-pub.yaml $S3_TEMPLATE_LOCATION
#aws s3 cp dh.cform.openvpn-ec2-priv.yaml $S3_TEMPLATE_LOCATION

#Compress & Upload iptables script to S3
#aws s3 cp dh.cform.openvpn-ec2-pub-iptables.tar.gz $S3_IPTABLES_LOCATION
#tar -cf - dh.cform.openvpn-ec2-pub-iptables.sh | aws s3 cp - s3://dh.scripts/iptables/dh.cform.openvpn-ec2-pub-iptables.sh.tar
#gzip -c dh.cform.openvpn-ec2-pub-iptables.sh | aws s3 cp - ${S3_IPTABLES_LOCATION}dh.cform.openvpn-ec2-pub-iptables.sh.gz
cd iptables-scripts/
tar -zcf - dh.cform.openvpn-ec2-pub-iptables.sh | aws s3 cp - ${S3_IPTABLES_LOCATION}dh.cform.openvpn-ec2-pub-iptables.sh.tar.gz
cd ..


#Create cloudformation stack
aws cloudformation create-stack --stack-name OpenVPNTest02 --template-url https://s3.eu-central-1.amazonaws.com/dh.cform-templates/openvpn/dh.cform.openvpn.yaml --tags Key=Name,Value=OpenVPN-Test --on-failure DO_NOTHING
