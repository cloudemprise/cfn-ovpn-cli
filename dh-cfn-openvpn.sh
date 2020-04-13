#!/bin/bash
set -e 

#!! COMMENT BEGIN
: <<'END'
#!! COMMENT BEGIN

#!! COMMENT END
END
#!! COMMENT END


# Name given to entire Project
# must be compatible with s3bucket name restrictions
PROJECT_NAME="dh-scripts"
[[ ! $PROJECT_NAME =~ (^[a-z0-9]([a-z0-9-]*(\.[a-z0-9])?)*$) ]] && { echo "Invalid Project Name "; exit 1; } || { echo "Project Name: $PROJECT_NAME"; }



# S3 project directory structure
S3_LOCATION_TEMPLATES="s3://$PROJECT_NAME/cfn-templates/"
S3_LOCATION_IPTABLES="s3://$PROJECT_NAME/iptables/"
S3_LOCATION_SSH="s3://$PROJECT_NAME/ssh/"
S3_LOCATION_OPENVPN="s3://$PROJECT_NAME/openvpn/"
#S3_LOCATION_EASYRSA="s3://$PROJECT_NAME/easy-rsa/openvpn/gen-reqs/"
S3_LOCATION_EASYRSA="s3://$PROJECT_NAME/easy-rsa/"


BUILD_COUNTER="Stage0"

# Name given to Cloudformation Stack
STACK_NAME="openvpn-set1-7"
STACK_ID=""

INSTANCE_ID_PUB=""
INSTANCE_ID_PRIV=""

AMI_CURRENT=""
AMI_IMAGE_PUB=""
AMI_IMAGE_PRIV=""

AWS_ACC_ID=""

EC2_ROLE_NAME="dh.instprofile.managed.sysadmin"
EC2_ROLE_ID=""

#------------
# Get Account ID
AWS_ACC_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account ID : $AWS_ACC_ID"

#------------
# Get aws:userid of EC2-Role
EC2_ROLE_ID=$(aws iam get-role --role-name $EC2_ROLE_NAME --query "Role.RoleId" --output text)
echo "EC2-Role userid : $EC2_ROLE_ID"


#------------
#Upload Latest (Nested) Templates to S3
echo "Uploading Cloudformation Templates to S3 location: $S3_LOCATION_TEMPLATES"
cd cfn-templates
for file in $(ls *.yaml); do [ -f $file ] && aws s3 cp $file $S3_LOCATION_TEMPLATES || echo "Failed to upload : $file"; done
cd ..


set -x
#------------
#Compress & Upload iptables script to S3
tar -zcf - iptables/dh.cfn.openvpn-ec2-pub-iptables.sh | aws s3 cp - ${S3_LOCATION_IPTABLES}dh.cfn.openvpn-ec2-pub-iptables.sh.tar.gz
tar -zcf - iptables/dh.cfn.openvpn-ec2-priv-iptables.sh | aws s3 cp - ${S3_LOCATION_IPTABLES}dh.cfn.openvpn-ec2-priv-iptables.sh.tar.gz
#Compress & Upload sshd hardening script to S3
tar -zcf - ssh/dh.cfn.openvpn-ec2-harden-ssh.sh | aws s3 cp - ${S3_LOCATION_SSH}dh.cfn.openvpn-ec2-harden-ssh.sh.tar.gz
#Compress & Upload openvpn server configs to S3
tar -zcf - openvpn/dh.vpn.server.*1194.conf | aws s3 cp - ${S3_LOCATION_OPENVPN}server/dh.vpn.server.xxx1194.conf.tar.gz
#Upload easy-rsa pki keygen configs to S3
tar -zcf - easy-rsa/vars.* | aws s3 cp - ${S3_LOCATION_EASYRSA}gen-reqs/dh.easyrsa.openvpn.vars.tar.gz
unset -x


#------------
# Grab the latest Amazon_Linux_2 AMI
AMI_CURRENT=$(aws ssm get-parameters --names /aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 --query 'Parameters[0].[Value]' --output text)
echo "The lastest Amazon Linux 2 AMI : $AMI_CURRENT"

#------------
# Create Stage0 Stack
echo "$BUILD_COUNTER"
STACK_ID=$(aws cloudformation create-stack --stack-name $STACK_NAME --parameters ParameterKey=ProjectName,ParameterValue=$PROJECT_NAME ParameterKey=BuildStage,ParameterValue=$BUILD_COUNTER  ParameterKey=CurrentAmi,ParameterValue=$AMI_CURRENT --tags Key=Name,Value=openvpn-stage0 --template-url "https://$PROJECT_NAME.s3.eu-central-1.amazonaws.com/cfn-templates/dh-openvpn-cfn.yaml" --on-failure DO_NOTHING --output text)
echo "$BUILD_COUNTER Stack has now been Initiated..."
echo "Cloudformation Stack ID : $STACK_ID"
# Wait for Stage0 to complete
if (aws cloudformation wait stack-create-complete --stack-name $STACK_ID)
then echo "$BUILD_COUNTER Stack Update is now Complete : $STACK_ID"
else echo "Error: Stack Wait Update Failed : $STACK_ID"
fi





#------------
# Update Stack with Stage1 parameters
BUILD_COUNTER="Stage1"
echo "$BUILD_COUNTER"
aws cloudformation update-stack --stack-name $STACK_ID --parameters ParameterKey=ProjectName,ParameterValue=$PROJECT_NAME ParameterKey=BuildStage,ParameterValue=$BUILD_COUNTER  ParameterKey=CurrentAmi,ParameterValue=$AMI_CURRENT --tags Key=Name,Value=openvpn-stage1 --use-previous-template > /dev/null
echo "$BUILD_COUNTER Stack has now been Initiated..."
# Wait for Stage1 Update to complete
if (aws cloudformation wait stack-update-complete --stack-name $STACK_ID)
then echo "$BUILD_COUNTER Stack Update is now Complete : $STACK_ID"
else echo "Error: Stack Wait Update Failed : $STACK_ID"
fi

#------------
# Grab the IDs of the ec2 instances for further processing
INSTANCE_ID_PUB=$(aws cloudformation describe-stacks --stack-name $STACK_ID --output text --query "Stacks[].Outputs[?OutputKey == 'InstanceIdPublic1'].OutputValue")
echo "Public $BUILD_COUNTER Instance ID is : $INSTANCE_ID_PUB"
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
echo "Public $BUILD_COUNTER Instance State: Ok..."
echo "Private Instance State: Ok..."




#------------
# Create IMAGE AMIs
AMI_IMAGE_PUB=$(aws ec2 create-image --instance-id $INSTANCE_ID_PUB --name $(echo "openvpn-pub1-$INSTANCE_ID_PUB") --description "openvpn-pub1-ami" --output text)
echo "Public $BUILD_COUNTER AMI creation has now been initiated : $AMI_IMAGE_PUB"
AMI_IMAGE_PRIV=$(aws ec2 create-image --instance-id $INSTANCE_ID_PRIV --name $(echo "openvpn-priv-$INSTANCE_ID_PRIV") --description "openvpn-priv-ami" --output text)
echo "Private AMI creation has now been initiated : $AMI_IMAGE_PRIV"

# Wait for new AMIs to become available
aws ec2 wait image-available --image-ids $AMI_IMAGE_PUB &
P1=$!
aws ec2 wait image-available --image-ids $AMI_IMAGE_PRIV &
P2=$!
wait $P1 $P2
echo "Public $BUILD_COUNTER AMI is now available : $AMI_IMAGE_PUB "
echo "Private AMI is now available : $AMI_IMAGE_PRIV"

# Terminate the instances - no longer needed.
aws ec2 terminate-instances --instance-ids $INSTANCE_ID_PUB $INSTANCE_ID_PRIV > /dev/null
echo "$BUILD_COUNTER Instances have now terminated..."



#------------
# Create Launch Template for AutoScaling Group
# Update Stack with Stage3 parameters
BUILD_COUNTER="Stage3"
echo "$BUILD_COUNTER"
aws cloudformation update-stack --stack-name $STACK_ID --parameters ParameterKey=ProjectName,ParameterValue=$PROJECT_NAME ParameterKey=BuildStage,ParameterValue=$BUILD_COUNTER  ParameterKey=CurrentAmi,ParameterValue=$AMI_IMAGE_PUB --tags Key=Name,Value=openvpn-stage3 --use-previous-template > /dev/null
echo "$BUILD_COUNTER Stack has now been Initiated..."
# Wait for Stage3 Update to complete
if (aws cloudformation wait stack-update-complete --stack-name $STACK_ID)
then echo "$BUILD_COUNTER Stack Update is now Complete : $STACK_ID"
else echo "Error: Stack Wait Update Failed : $STACK_ID"
fi

# Copy client configuration files locally & timestamp
cd openvpn
if (aws s3 sync s3://dh-scripts/openvpn/client/ . --exclude "*" --include "*.tar.gz")
then 
  echo "OpenVPN client files successfully copied locally"
  for file in $(ls *.tar.gz); do [ -f $file ] && mv $file "${file%%.*}_$(date +%F_%H%M).tar.gz" || echo "Failed to timestamp : $file"; done
else 
  echo "OpenVPN client files failed to copy locally"
fi
cd ..


