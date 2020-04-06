#!/bin/bash

#!! COMMENT BEGIN
: <<'END'
#!! COMMENT BEGIN

#!! COMMENT END
END
#!! COMMENT END


S3_TEMPLATE_LOCATION="s3://dh.cfn-templates/openvpn/"
S3_IPTABLES_LOCATION="s3://dh.scripts/iptables/"
S3_SSH_LOCATION="s3://dh.scripts/ssh/"
S3_OPENVPN_LOCATION="s3://dh.scripts/openvpn/"
S3_EASYRSA_LOCATION="s3://dh.scripts/easyrsa/openvpn/gen-reqs/"

BUILDSTAGE="Stage0"

STACK_NAME="openvpn-set1-4"
STACK_ID=""

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
#Upload Latest (Nested) Templates to S3
echo "Uploading Cloudformation Templates to S3 location: $S3_TEMPLATE_LOCATION"
cd cfn-templates
for file in $(ls *.yaml); do [ -f $file ] && aws s3 cp $file $S3_TEMPLATE_LOCATION || echo "Failed to upload : $file"; done
cd ..


#------------
#Compress & Upload iptables script to S3
tar -zcf - iptables-scripts/dh.cfn.openvpn-ec2-pub-iptables.sh | aws s3 cp - ${S3_IPTABLES_LOCATION}dh.cfn.openvpn-ec2-pub-iptables.sh.tar.gz
tar -zcf - iptables-scripts/dh.cfn.openvpn-ec2-priv-iptables.sh | aws s3 cp - ${S3_IPTABLES_LOCATION}dh.cfn.openvpn-ec2-priv-iptables.sh.tar.gz
#Compress & Upload sshd hardening script to S3
tar -zcf - ssh-scripts/dh.cfn.openvpn-ec2-harden-ssh.sh | aws s3 cp - ${S3_SSH_LOCATION}dh.cfn.openvpn-ec2-harden-ssh.sh.tar.gz
#Compress & Upload openvpn server configs to S3
cd openvpn-configs
tar -zcf - dh.vpn.server.*1194.conf | aws s3 cp - ${S3_OPENVPN_LOCATION}server/dh.vpn.server.xxx1194.conf.tar.gz
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
echo "$BUILDSTAGE"
STACK_ID=$(aws cloudformation create-stack --stack-name $STACK_NAME --parameters ParameterKey=BuildStage,ParameterValue=$BUILDSTAGE  ParameterKey=CurrentAmi,ParameterValue=$AMI_CURRENT --tags Key=Name,Value=openvpn-stage0 --template-url https://s3.eu-central-1.amazonaws.com/dh.cfn-templates/openvpn/dh.cfn.openvpn.yaml --on-failure DO_NOTHING --output text)
echo "$BUILDSTAGE Stack has now been Initiated..."
echo "Cloudformation Stack ID : $STACK_ID"
# Wait for Stage0 to complete
if (aws cloudformation wait stack-create-complete --stack-name $STACK_ID)
then echo "$BUILDSTAGE Stack Update is now Complete : $STACK_ID"
else echo "Error: Stack Wait Update Failed : $STACK_ID"
fi


#------------
# Update Stack with Stage1 parameters
BUILDSTAGE="Stage1"
echo "$BUILDSTAGE"
aws cloudformation update-stack --stack-name $STACK_ID --parameters ParameterKey=BuildStage,ParameterValue=$BUILDSTAGE  ParameterKey=CurrentAmi,ParameterValue=$AMI_CURRENT --tags Key=Name,Value=openvpn-stage1 --template-url https://s3.eu-central-1.amazonaws.com/dh.cfn-templates/openvpn/dh.cfn.openvpn.yaml > /dev/null
echo "$BUILDSTAGE Stack has now been Initiated..."
# Wait for Stage1 Update to complete
if (aws cloudformation wait stack-update-complete --stack-name $STACK_ID)
then echo "$BUILDSTAGE Stack Update is now Complete : $STACK_ID"
else echo "Error: Stack Wait Update Failed : $STACK_ID"
fi

#------------
# Grab the IDs of the ec2 instances for further processing
INSTANCE_ID_PUB1=$(aws cloudformation describe-stacks --stack-name $STACK_ID --output text --query "Stacks[].Outputs[?OutputKey == 'InstanceIdPublic1'].OutputValue")
echo "Public $BUILDSTAGE Instance ID is : $INSTANCE_ID_PUB1"
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
echo "Public $BUILDSTAGE Instance State: Ok..."
echo "Private Instance State: Ok..."

#------------
# Create IMAGE AMIs
AMI_IMAGE_PUB1=$(aws ec2 create-image --instance-id $INSTANCE_ID_PUB1 --name $(echo "openvpn-pub1-$INSTANCE_ID_PUB1") --description "openvpn-pub1-ami" --output text)
echo "Public $BUILDSTAGE AMI creation has now been initiated : $AMI_IMAGE_PUB1"
AMI_IMAGE_PRIV=$(aws ec2 create-image --instance-id $INSTANCE_ID_PRIV --name $(echo "openvpn-priv-$INSTANCE_ID_PRIV") --description "openvpn-priv-ami" --output text)
echo "Private AMI creation has now been initiated : $AMI_IMAGE_PRIV"

# Wait for new AMIs to become available
aws ec2 wait image-available --image-ids $AMI_IMAGE_PUB1 &
P1=$!
aws ec2 wait image-available --image-ids $AMI_IMAGE_PRIV &
P2=$!
wait $P1 $P2
echo "Public $BUILDSTAGE AMI is now available : $AMI_IMAGE_PUB1 "
echo "Private AMI is now available : $AMI_IMAGE_PRIV"

# Terminate the instances - no longer needed.
aws ec2 terminate-instances --instance-ids $INSTANCE_ID_PUB1 $INSTANCE_ID_PRIV > /dev/null
echo "$BUILDSTAGE Instances have now terminated..."

#------------
# Update Stack with Stage2 parameters
BUILDSTAGE="Stage2"
echo "$BUILDSTAGE"
aws cloudformation update-stack --stack-name $STACK_ID --parameters ParameterKey=BuildStage,ParameterValue=$BUILDSTAGE  ParameterKey=CurrentAmi,ParameterValue=$AMI_IMAGE_PUB1 --tags Key=Name,Value=openvpn-stage2 --template-url https://s3.eu-central-1.amazonaws.com/dh.cfn-templates/openvpn/dh.cfn.openvpn.yaml > /dev/null
echo "$BUILDSTAGE Stack has now been Initiated..."
# Wait for Stage2 Update to complete
if (aws cloudformation wait stack-update-complete --stack-name $STACK_ID)
then echo "$BUILDSTAGE Stack Update is now Complete : $STACK_ID"
else echo "Error: Stack Wait Update Failed : $STACK_ID"
fi

#------------
# Grab the IDs of the ec2 instances for further processing
INSTANCE_ID_PUB2=$(aws cloudformation describe-stacks --stack-name $STACK_ID --output text --query "Stacks[].Outputs[?OutputKey == 'InstanceIdPublic2'].OutputValue")
echo "Public $BUILDSTAGE Instance ID is : $INSTANCE_ID_PUB2"

#------------
# Validity Check Here.
# Wait for instance status ok
aws ec2 wait instance-status-ok --instance-ids $INSTANCE_ID_PUB2 &
P1=$!
wait $P1
echo "Public $BUILDSTAGE Instance State: Ok..."

#------------
# Create IMAGE AMIs
AMI_IMAGE_PUB2=$(aws ec2 create-image --instance-id $INSTANCE_ID_PUB2 --name $(echo "openvpn-pub2-$INSTANCE_ID_PUB2") --description "openvpn-pub2-ami" --output text)
echo "Public $BUILDSTAGE AMI creation has now been initiated : $AMI_IMAGE_PUB2"
# Wait for new AMIs to become available
aws ec2 wait image-available --image-ids $AMI_IMAGE_PUB2 &
P1=$!
wait $P1
echo "Public $BUILDSTAGE AMI is now available : $AMI_IMAGE_PUB2"

# Terminate Public Stage2 instance - no longer needed.
aws ec2 terminate-instances --instance-ids $INSTANCE_ID_PUB2 > /dev/null
echo "$BUILDSTAGE Instances have now terminated..."

#------------
# Delete AMI + snapshot of Stage1
# Get Account ID
AWS_ACC_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account ID : $AWS_ACC_ID"

# Get snapshot ID Public Stage1 AMI
SNAPSHOT_PUB1=$(aws ec2 describe-images --image-ids $AMI_IMAGE_PUB1 --query "Images[].BlockDeviceMappings[].Ebs[].SnapshotId" --output text)
echo "Public $BUILDSTAGE Snapshot ID : $SNAPSHOT_PUB1"

# Deregister Public Stage1 image
if (aws ec2 deregister-image --image-id $AMI_IMAGE_PUB1)
then echo "Deregistering Public Stage1 AMI : $AMI_IMAGE_PUB1"
else echo "Error: Failed to Deregister $AMI_IMAGE_PUB1"
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
echo "$BUILDSTAGE"
aws cloudformation update-stack --stack-name $STACK_ID --parameters ParameterKey=BuildStage,ParameterValue=$BUILDSTAGE  ParameterKey=CurrentAmi,ParameterValue=$AMI_IMAGE_PUB2 --tags Key=Name,Value=openvpn-stage3 --template-url https://s3.eu-central-1.amazonaws.com/dh.cfn-templates/openvpn/dh.cfn.openvpn.yaml > /dev/null
echo "$BUILDSTAGE Stack has now been Initiated..."
# Wait for Stage3 Update to complete
if (aws cloudformation wait stack-update-complete --stack-name $STACK_ID)
then echo "$BUILDSTAGE Stack Update is now Complete : $STACK_ID"
else echo "Error: Stack Wait Update Failed : $STACK_ID"
fi

# Copy client configuration files locally
cd openvpn-configs
if (aws s3 sync s3://dh.scripts/openvpn/client/ . --exclude "*" --include "*.tar.gz")
then echo "OpenVPN client files successfully copied locally: "
else echo "OpenVPN client files failed to copy locally"
fi
cd ..
