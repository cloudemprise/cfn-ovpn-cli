#!/bin/bash

aws s3 cp dh.cform.openvpn.yaml s3://dh.cform-templates/openvpn/
aws s3 cp dh.cform.openvpn-vpc.yaml s3://dh.cform-templates/openvpn/
aws s3 cp dh.cform.openvpn-nacl.yaml s3://dh.cform-templates/openvpn/
aws s3 cp dh.cform.openvpn-sg.yaml s3://dh.cform-templates/openvpn/
aws s3 cp dh.cform.openvpn-launch-priv.yaml s3://dh.cform-templates/openvpn/
aws s3 cp dh.cform.openvpn-launch-pub.yaml s3://dh.cform-templates/openvpn/

aws cloudformation create-stack --stack-name OpenVPNTest01 --template-url https://s3.eu-central-1.amazonaws.com/dh.cform-templates/openvpn/dh.cform.openvpn.yaml --tags Key=Name,Value=OpenVPN-Test
