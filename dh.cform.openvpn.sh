#!/bin/bash

S3_TEMPLATE_LOCATION="s3://dh.cform-templates/openvpn/"
S3_IPTABLES_LOCATION="s3://dh.scripts/iptables/"
S3_SSH_LOCATION="s3://dh.scripts/ssh/"
S3_OPENVPN_LOCATION="s3://dh.scripts/openvpn/server/"
S3_EASYRSA_LOCATION="s3://dh.scripts/easyrsa/openvpn/gen-reqs/"

BUILDSTAGE="Stage0"

STACK_NAME="openvpn-set1-6"
STACK_ID=""

# Instance IDs of Stack1 Public/Private
INSTANCE_ID_PUB=""
INSTANCE_ID_PRIV=""

AMI_CURRENT=""
AMI_IMAGE_PUB=""
AMI_IMAGE_PRIV=""

#------------
#Upload latest Nested Templates to S3
aws s3 cp cfn-templates/dh.cform.openvpn.yaml $S3_TEMPLATE_LOCATION
aws s3 cp cfn-templates/dh.cform.openvpn-vpc.yaml $S3_TEMPLATE_LOCATION
aws s3 cp cfn-templates/dh.cform.openvpn-nacl.yaml $S3_TEMPLATE_LOCATION
aws s3 cp cfn-templates/dh.cform.openvpn-sg.yaml $S3_TEMPLATE_LOCATION
aws s3 cp cfn-templates/dh.cform.openvpn-ec2-priv.yaml $S3_TEMPLATE_LOCATION
aws s3 cp cfn-templates/dh.cform.openvpn-ec2-pub-stage1.yaml $S3_TEMPLATE_LOCATION
aws s3 cp cfn-templates/dh.cform.openvpn-ec2-pub-stage2.yaml $S3_TEMPLATE_LOCATION

#------------
#Compress & Upload iptables script to S3
tar -zcf - iptables-scripts/dh.cform.openvpn-ec2-pub-iptables.sh | aws s3 cp - ${S3_IPTABLES_LOCATION}dh.cform.openvpn-ec2-pub-iptables.sh.tar.gz
tar -zcf - iptables-scripts/dh.cform.openvpn-ec2-priv-iptables.sh | aws s3 cp - ${S3_IPTABLES_LOCATION}dh.cform.openvpn-ec2-priv-iptables.sh.tar.gz
#Compress & Upload sshd hardening script to S3
tar -zcf - ssh-scripts/dh.cform.openvpn-ec2-harden-ssh.sh | aws s3 cp - ${S3_SSH_LOCATION}dh.cform.openvpn-ec2-harden-ssh.sh.tar.gz
#Compress & Upload openvpn server configs to S3
cd openvpn-configs
tar -zcf - dh.vpn.server.*1194.conf | aws s3 cp - ${S3_OPENVPN_LOCATION}dh.vpn.server.xxx1194.conf.tar.gz
cd ..
#Upload easy-rsa pki keygen configs to S3
cd easyrsa-configs/
tar -zcf - vars.* | aws s3 cp - ${S3_EASYRSA_LOCATION}dh.easyrsa.openvpn.vars.tar.gz
cd ..

#------------
# Grab the latest Amazon_Linux_2 AMI
AMI_CURRENT=$(aws ssm get-parameters --names /aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 --query 'Parameters[0].[Value]' --output text)
echo "The lastest Amazon Linux 2 AMI : $AMI_CURRENT"

#------------
# Create Stage0 Stack
STACK_ID=$(aws cloudformation create-stack --stack-name $STACK_NAME --parameters ParameterKey=BuildStage,ParameterValue=$BUILDSTAGE  ParameterKey=LatestAmi,ParameterValue=$AMI_CURRENT --tags Key=Name,Value=openvpn-stage0 --template-url https://s3.eu-central-1.amazonaws.com/dh.cform-templates/openvpn/dh.cform.openvpn.yaml --on-failure DO_NOTHING --output text)
echo "stack ID : $STACK_ID"
# Wait for Stage0 to complete
aws cloudformation wait stack-create-complete --stack-name $STACK_ID || echo "Error Stack Wait Failed"
echo "Stage0 Stack Creation Complete : $STACK_ID"

#------------
# Update Stack with Stage1 parameters
BUILDSTAGE="Stage1"
aws cloudformation update-stack --stack-name $STACK_ID --parameters ParameterKey=BuildStage,ParameterValue=$BUILDSTAGE  ParameterKey=LatestAmi,ParameterValue=$AMI_CURRENT --tags Key=Name,Value=openvpn-stage1 --template-url https://s3.eu-central-1.amazonaws.com/dh.cform-templates/openvpn/dh.cform.openvpn.yaml
echo "Stage 1 Stack Update Initiated"
# Wait for Stage1 Update to complete
aws cloudformation wait stack-update-complete --stack-name $STACK_ID || echo "Error: Stack Wait Update Failed"
echo "Stage1 Stack Update Complete : $STACK_ID"

#------------
# Grab the IDs of the ec2 instances for further processing
INSTANCE_ID_PUB=$(aws cloudformation describe-stacks --stack-name $STACK_ID --output text --query "Stacks[].Outputs[?OutputKey == 'InstanceIdPubStage1'].OutputValue")
echo "Public Instance ID is : $INSTANCE_ID_PUB"
INSTANCE_ID_PRIV=$(aws cloudformation describe-stacks --stack-name $STACK_ID --output text --query "Stacks[].Outputs[?OutputKey == 'InstanceIdPrivate'].OutputValue")
echo "Private Instance ID is : $INSTANCE_ID_PRIV"

#------------
# Validity Check Here.
# Wait for instance status ok
aws ec2 wait instance-status-ok --instance-ids $INSTANCE_ID_PUB &
P1=$!
aws ec2 wait instance-status-ok --instance-ids $INSTANCE_ID_PRIV &
P2=$!
wait $P1 $P2
echo "Public Instance State: Ok"
echo "Private Instance State: Ok"

