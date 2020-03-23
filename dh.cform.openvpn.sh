#!/bin/bash

S3_TEMPLATE_LOCATION="s3://dh.cform-templates/openvpn/"
S3_IPTABLES_LOCATION="s3://dh.scripts/iptables/"
S3_SSH_LOCATION="s3://dh.scripts/ssh/"
S3_OPENVPN_LOCATION="s3://dh.scripts/openvpn/server/"
S3_EASYRSA_LOCATION="s3://dh.scripts/easyrsa/openvpn/gen-reqs/"

BUILDSTAGE="Stage0"

STACK_NAME="openvpn-set1-3"
STACK_ID=""

# Instance IDs of Stack1 Public/Private
INSTANCE_ID_PUB1=""
INSTANCE_ID_PUB2=""
INSTANCE_ID_PRIV=""

AMI_CURRENT=""
AMI_IMAGE_PUB1=""
AMI_IMAGE_PUB2=""
AMI_IMAGE_PRIV=""

AWS_ACC_ID=""
SNAPSHOT_PUB1=""

#------------
#Upload latest Nested Templates to S3
aws s3 cp cfn-templates/dh.cform.openvpn.yaml $S3_TEMPLATE_LOCATION
aws s3 cp cfn-templates/dh.cform.openvpn-vpc.yaml $S3_TEMPLATE_LOCATION
aws s3 cp cfn-templates/dh.cform.openvpn-nacl.yaml $S3_TEMPLATE_LOCATION
aws s3 cp cfn-templates/dh.cform.openvpn-sg.yaml $S3_TEMPLATE_LOCATION
aws s3 cp cfn-templates/dh.cform.openvpn-ec2-priv.yaml $S3_TEMPLATE_LOCATION
aws s3 cp cfn-templates/dh.cform.openvpn-ec2-pub-stage1.yaml $S3_TEMPLATE_LOCATION
aws s3 cp cfn-templates/dh.cform.openvpn-ec2-pub-stage2.yaml $S3_TEMPLATE_LOCATION
aws s3 cp cfn-templates/dh.cform.openvpn-ec2-lt.yaml $S3_TEMPLATE_LOCATION
aws s3 cp cfn-templates/dh.cform.openvpn-ec2-asg.yaml $S3_TEMPLATE_LOCATION


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
STACK_ID=$(aws cloudformation create-stack --stack-name $STACK_NAME --parameters ParameterKey=BuildStage,ParameterValue=$BUILDSTAGE  ParameterKey=CurrentAmi,ParameterValue=$AMI_CURRENT --tags Key=Name,Value=openvpn-stage0 --template-url https://s3.eu-central-1.amazonaws.com/dh.cform-templates/openvpn/dh.cform.openvpn.yaml --on-failure DO_NOTHING --output text)
echo "Cloudformation Stack ID : $STACK_ID"
# Wait for Stage0 to complete
if (aws cloudformation wait stack-create-complete --stack-name $STACK_ID)
then echo "Stage0 Stack Update is now Complete : $STACK_ID"
else echo "Error: Stack Wait Update Failed : $STACK_ID"
fi

#------------
# Update Stack with Stage1 parameters
BUILDSTAGE="Stage1"
aws cloudformation update-stack --stack-name $STACK_ID --parameters ParameterKey=BuildStage,ParameterValue=$BUILDSTAGE  ParameterKey=CurrentAmi,ParameterValue=$AMI_CURRENT --tags Key=Name,Value=openvpn-stage1 --template-url https://s3.eu-central-1.amazonaws.com/dh.cform-templates/openvpn/dh.cform.openvpn.yaml > /dev/null
echo "Stage1 Stack Update has now been Initiated..."
# Wait for Stage1 Update to complete
if (aws cloudformation wait stack-update-complete --stack-name $STACK_ID)
then echo "Stage1 Stack Update is now Complete : $STACK_ID"
else echo "Error: Stack Wait Update Failed : $STACK_ID"
fi

#------------
# Grab the IDs of the ec2 instances for further processing
INSTANCE_ID_PUB1=$(aws cloudformation describe-stacks --stack-name $STACK_ID --output text --query "Stacks[].Outputs[?OutputKey == 'InstanceIdPubStage1'].OutputValue")
echo "Public Stage1 Instance ID is : $INSTANCE_ID_PUB1"
INSTANCE_ID_PRIV=$(aws cloudformation describe-stacks --stack-name $STACK_ID --output text --query "Stacks[].Outputs[?OutputKey == 'InstanceIdPrivate'].OutputValue")
echo "Private Instance ID is : $INSTANCE_ID_PRIV"

#------------
# Validity Check Here.
# Wait for instance status ok
aws ec2 wait instance-status-ok --instance-ids $INSTANCE_ID_PUB1 &
P1=$!
aws ec2 wait instance-status-ok --instance-ids $INSTANCE_ID_PRIV &
P2=$!
wait $P1 $P2
echo "Public Stage1 Instance State: Ok..."
echo "Private Instance State: Ok..."

#------------
# Create IMAGE AMIs
AMI_IMAGE_PUB1=$(aws ec2 create-image --instance-id $INSTANCE_ID_PUB1 --name $(echo "openvpn-public-1-$INSTANCE_ID_PUB1") --description "Public OpenVPN AMI" --output text)
echo "Public Stage1 AMI creation has now been initiated : $AMI_IMAGE_PUB1"
AMI_IMAGE_PRIV=$(aws ec2 create-image --instance-id $INSTANCE_ID_PRIV --name $(echo "openvpn-private-$INSTANCE_ID_PRIV") --description "Private OpenVPN AMI" --output text)
echo "Private AMI creation has now been initiated : $AMI_IMAGE_PRIV"

# Wait for new AMIs to become available
aws ec2 wait image-available --image-ids $AMI_IMAGE_PUB1 &
P1=$!
aws ec2 wait image-available --image-ids $AMI_IMAGE_PRIV &
P2=$!
wait $P1 $P2
echo "Public Stage1 AMI is now available : $AMI_IMAGE_PUB1 "
echo "Private AMI is now available : $AMI_IMAGE_PRIV"

# Terminate the instances - no longer needed.
aws ec2 terminate-instances --instance-ids $INSTANCE_ID_PUB1 $INSTANCE_ID_PRIV > /dev/null
echo "Stage1 Instances have now terminated..."

#------------
# Update Stack with Stage2 parameters
BUILDSTAGE="Stage2"
aws cloudformation update-stack --stack-name $STACK_ID --parameters ParameterKey=BuildStage,ParameterValue=$BUILDSTAGE  ParameterKey=CurrentAmi,ParameterValue=$AMI_IMAGE_PUB1 --tags Key=Name,Value=openvpn-stage2 --template-url https://s3.eu-central-1.amazonaws.com/dh.cform-templates/openvpn/dh.cform.openvpn.yaml > /dev/null
echo "Stage2 Stack Update has now been Initiated..."
# Wait for Stage2 Update to complete
if (aws cloudformation wait stack-update-complete --stack-name $STACK_ID)
then echo "Stage2 Stack Update is now Complete : $STACK_ID"
else echo "Error: Stack Wait Update Failed : $STACK_ID"
fi

#------------
# Grab the IDs of the ec2 instances for further processing
INSTANCE_ID_PUB2=$(aws cloudformation describe-stacks --stack-name $STACK_ID --output text --query "Stacks[].Outputs[?OutputKey == 'InstanceIdPubStage2'].OutputValue")
echo "Public Stage2 Instance ID is : $INSTANCE_ID_PUB2"

#------------
# Validity Check Here.
# Wait for instance status ok
aws ec2 wait instance-status-ok --instance-ids $INSTANCE_ID_PUB2 &
P1=$!
wait $P1
echo "Public Stage2 Instance State: Ok..."

#------------
# Create IMAGE AMIs
AMI_IMAGE_PUB2=$(aws ec2 create-image --instance-id $INSTANCE_ID_PUB2 --name $(echo "openvpn-public-2-$INSTANCE_ID_PUB2") --description "Public 2 OpenVPN AMI" --output text)
echo "Public Stage2 AMI creation has now been initiated : $AMI_IMAGE_PUB2"
# Wait for new AMIs to become available
aws ec2 wait image-available --image-ids $AMI_IMAGE_PUB2 &
P1=$!
wait $P1
echo "Public Stage2 AMI is now available : $AMI_IMAGE_PUB2"

# Terminate Public Stage2 instance - no longer needed.
aws ec2 terminate-instances --instance-ids $INSTANCE_ID_PUB2 > /dev/null
echo "Stage2 Instances have now terminated..."

#------------
# Delete AMI + snapshot of Stage1
# Get Account ID
AWS_ACC_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account ID : $AWS_ACC_ID"

# Get snapshot ID Public Stage1 AMI
SNAPSHOT_PUB1=$(aws ec2 describe-images --image-ids $AMI_IMAGE_PUB1 --query "Images[].BlockDeviceMappings[].Ebs[].SnapshotId" --output text)
echo "Public Stage1 Snapshot ID : $SNAPSHOT_PUB1"

# Deregister Public Stage1 image
if (aws ec2 deregister-image --image-id $AMI_IMAGE_PUB1)
then echo "Deregistering Public Stage1 AMI : $AMI_IMAGE_PUB1"
else echo "echo "Error: Failed to Deregister $AMI_IMAGE_PUB1""
fi

# Deleting Public Stage1 snapshot
if (aws ec2 delete-snapshot --snapshot-id $SNAPSHOT_PUB1)
then echo "Deleting Public Stage1 AMI Snapshot : $SNAPSHOT_PUB1"
else echo "Error: Failed to Delete Snapshot $AMI_IMAGE_PUB1"
fi

#------------
# Create Launch Template for AutoScaling Group
# Update Stack with Stage3 parameters
BUILDSTAGE="Stage3"
aws cloudformation update-stack --stack-name $STACK_ID --parameters ParameterKey=BuildStage,ParameterValue=$BUILDSTAGE  ParameterKey=CurrentAmi,ParameterValue=$AMI_IMAGE_PUB2 --tags Key=Name,Value=openvpn-stage3 --template-url https://s3.eu-central-1.amazonaws.com/dh.cform-templates/openvpn/dh.cform.openvpn.yaml > /dev/null
echo "Stage3 Stack Update has now been Initiated..."
# Wait for Stage3 Update to complete
if (aws cloudformation wait stack-update-complete --stack-name $STACK_ID)
then echo "Stage3 Stack Update is now Complete : $STACK_ID"
else echo "Error: Stack Wait Update Failed : $STACK_ID"
fi
