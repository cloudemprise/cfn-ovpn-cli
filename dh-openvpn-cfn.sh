#!/bin/bash -e


#!! COMMENT BEGIN
: <<'END'
#!! COMMENT BEGIN

#!! COMMENT END
END
#!! COMMENT END

#-----------------------------
# Record Script Execution Time
TIME_START=$(date +%s)
TIME_STAMP=$(date "+%Y-%m-%d %Hh%Mm%Ss")
echo "Time Stamp: $TIME_STAMP"


#-----------------------------
# Name Given to Entire Project
# must be compatible with s3bucket name restrictions
PROJECT_NAME="dh-openvpn-test7"
[[ ! $PROJECT_NAME =~ (^[a-z0-9]([a-z0-9-]*(\.[a-z0-9])?)*$) ]] \
    && { echo "Invalid Project Name "; exit 1; } \
    || { echo "Project Name: $PROJECT_NAME"; }
#.............................


#-----------------------------
# Get Route 53 Domain hosted zone ID
AWS_DOMAIN_NAME="cloudemprise.net"
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name $AWS_DOMAIN_NAME \
    --query "HostedZones[].Id" --output text | awk -F "/" '{print $3}')
[[ -z $HOSTED_ZONE_ID ]] \
    && { echo "Invalid Hosted Zone "; exit 1; } \
    || { echo "Hosted Zone ID: $HOSTED_ZONE_ID"; }
#.............................


#-----------------------------
# Get Region
AWS_REGION=$(aws configure get region)
echo "Region : $AWS_REGION"

#-----------------------------
# Get Account(ROOT) ID
AWS_ACC_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account ID : $AWS_ACC_ID"

#-----------------------------
# CLI profile userid
AWS_CLI_ID=$(aws sts get-caller-identity --query UserId --output text)
echo "Script Caller userid : $AWS_CLI_ID"

#-----------------------------
# EC2 Instance Profile Name
EC2_ROLE_NAME="dh.instprofile.managed.sysadmin"
echo "Instance Profile Name : $EC2_ROLE_NAME"

#-----------------------------
# EC2 Instance Profile userid
EC2_ROLE_ID=$(aws iam get-role --role-name $EC2_ROLE_NAME \
    --query "Role.RoleId" --output text)
echo "Instance Profile userid : $EC2_ROLE_ID"



#-----------------------------
# Create Project S3 Bucket Policy from Template
if [ -f policies/s3-buckets/template_s3-bucket-policy.json ]
then 
  cp policies/s3-buckets/template_s3-bucket-policy.json policies/s3-buckets/${PROJECT_NAME}_s3-bucket-policy.json
  sed -i "s/ProjectName/$PROJECT_NAME/" policies/s3-buckets/${PROJECT_NAME}_s3-bucket-policy.json
  sed -i "s/RootAccount/$AWS_ACC_ID/" policies/s3-buckets/${PROJECT_NAME}_s3-bucket-policy.json
  sed -i "s/ScriptCallerUserId/$AWS_CLI_ID/" policies/s3-buckets/${PROJECT_NAME}_s3-bucket-policy.json
  sed -i "s/Ec2RoleUserId/$EC2_ROLE_ID/" policies/s3-buckets/${PROJECT_NAME}_s3-bucket-policy.json
else
  echo "Template Bucket Policy Not Found"
  exit 1
fi


#-----------------------------
set -x
# Create Project S3 Bucket with Encryption & Policy
if (aws s3 mb s3://$PROJECT_NAME)
then 
  aws s3api put-bucket-encryption \
      --bucket $PROJECT_NAME \
      --server-side-encryption-configuration \
      '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}'
  aws s3api put-bucket-policy --bucket $PROJECT_NAME \
      --policy "file://policies/s3-buckets/${PROJECT_NAME}_s3-bucket-policy.json"
else
  echo "Failed to create s3 project bucket"
  exit 1
fi
set +x
#.............................


# S3 Project Directory Structure
#S3_LOCATION_TEMPLATES="s3://$PROJECT_NAME/cfn-templates/"
#S3_LOCATION_POLICIES="s3://$PROJECT_NAME/policies/"
S3_LOCATION_EASYRSA="s3://$PROJECT_NAME/easy-rsa/"
S3_LOCATION_IPTABLES="s3://$PROJECT_NAME/iptables/"
S3_LOCATION_OPENVPN="s3://$PROJECT_NAME/openvpn/"
S3_LOCATION_SSH="s3://$PROJECT_NAME/ssh/"


# Cloudformation Stack Conditional Build Counter
BUILD_COUNTER="Stage0"

# Name given to Cloudformation Stack
STACK_NAME="$PROJECT_NAME-cfn-stack"
STACK_ID=""

INSTANCE_ID_PUB=""
INSTANCE_ID_PRIV=""

AMI_CURRENT=""
AMI_IMAGE_PUB=""
AMI_IMAGE_PRIV=""



#----------------------------------------------
# Upload Latest Stack Policy to S3
echo "Uploading Policy Documents to S3 Bucket :  s3://$PROJECT_NAME"
for file in $(ls policies/*/*.json); do [ -f $file ] && aws s3 cp $file s3://$PROJECT_NAME/$file || echo "Failed to upload : $file"; done


#----------------------------------------------
# Upload Latest (Nested) Templates to S3
echo "Uploading Cloudformation Templates to S3 location: s3://$PROJECT_NAME/cfn-templates"
for file in $(ls cfn-templates/*.yaml); do [ -f $file ] && aws s3 cp $file s3://$PROJECT_NAME/$file || echo "Failed to upload : $file"; done






#-----------------------------
# Get some debug messages here to validate
set -x
#-----------------------------
#Compress & Upload iptables script to S3
tar -zcf - iptables/dh-openvpn-ec2-pub-iptables.sh | aws s3 cp - ${S3_LOCATION_IPTABLES}dh-openvpn-ec2-pub-iptables.sh.tar.gz
tar -zcf - iptables/dh-openvpn-ec2-priv-iptables.sh | aws s3 cp - ${S3_LOCATION_IPTABLES}dh-openvpn-ec2-priv-iptables.sh.tar.gz
#Compress & Upload sshd hardening script to S3
tar -zcf - ssh/dh-openvpn-ec2-harden-ssh.sh | aws s3 cp - ${S3_LOCATION_SSH}dh-openvpn-ec2-harden-ssh.sh.tar.gz
#Compress & Upload openvpn server configs to S3
tar -zcf - openvpn/server/dh-openvpn-server*.conf | aws s3 cp - ${S3_LOCATION_OPENVPN}server/dh-openvpn-server-1194.conf.tar.gz
#Upload easy-rsa pki keygen configs to S3
tar -zcf - easy-rsa/vars* | aws s3 cp - ${S3_LOCATION_EASYRSA}gen-reqs/dh-openvpn-easyrsa-vars.tar.gz
set +x
#.............................


#-----------------------------
# Grab the latest Amazon_Linux_2 AMI
AMI_CURRENT=$(aws ssm get-parameters --names /aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 --query 'Parameters[0].[Value]' --output text)
echo "The lastest Amazon Linux 2 AMI : $AMI_CURRENT"




#-----------------------------
# Create Stage0 Stack
echo "$BUILD_COUNTER"
#STACK_ID=$(aws cloudformation create-stack --stack-name $STACK_NAME --parameters ParameterKey=ProjectName,ParameterValue=$PROJECT_NAME ParameterKey=BuildStage,ParameterValue=$BUILD_COUNTER  ParameterKey=CurrentAmi,ParameterValue=$AMI_CURRENT --tags Key=Name,Value=openvpn-stage0 --template-url "https://$PROJECT_NAME.s3.eu-central-1.amazonaws.com/cfn-templates/dh-openvpn-cfn.yaml" --on-failure DO_NOTHING --output text)
STACK_ID=$(aws cloudformation create-stack --stack-name $STACK_NAME --parameters \
    ParameterKey=ProjectName,ParameterValue=$PROJECT_NAME \
    ParameterKey=DomainName,ParameterValue=$AWS_DOMAIN_NAME \
    ParameterKey=DomainHostedZoneId,ParameterValue=$HOSTED_ZONE_ID \
    ParameterKey=BuildStage,ParameterValue=$BUILD_COUNTER \
    ParameterKey=CurrentAmi,ParameterValue=$AMI_CURRENT \
    --tags Key=Name,Value=openvpn-stage0 \
    --stack-policy-url "https://$PROJECT_NAME.s3.eu-central-1.amazonaws.com/policies/cfn-stacks/template_cfn-stack-policy.json" \
    --template-url "https://$PROJECT_NAME.s3.eu-central-1.amazonaws.com/cfn-templates/dh-openvpn-cfn.yaml" \
    --on-failure DO_NOTHING --output text)
echo "$BUILD_COUNTER Stack has now been Initiated..."
echo "Cloudformation Stack ID : $STACK_ID"
# Wait for Stage0 to complete
if (aws cloudformation wait stack-create-complete --stack-name $STACK_ID)
then echo "$BUILD_COUNTER Stack Update is now Complete : $STACK_ID"
else echo "Error: Stack Wait Update Failed : $STACK_ID"
fi



#-----------------------------
# Update Stack with Stage1 parameters
BUILD_COUNTER="Stage1"
echo "$BUILD_COUNTER"
#aws cloudformation update-stack --stack-name $STACK_ID --parameters ParameterKey=ProjectName,ParameterValue=$PROJECT_NAME ParameterKey=BuildStage,ParameterValue=$BUILD_COUNTER  ParameterKey=CurrentAmi,ParameterValue=$AMI_CURRENT --tags Key=Name,Value=openvpn-stage1 --use-previous-template > /dev/null
aws cloudformation update-stack --stack-name $STACK_ID --parameters \
    ParameterKey=ProjectName,ParameterValue=$PROJECT_NAME \
    ParameterKey=DomainName,ParameterValue=$AWS_DOMAIN_NAME \
    ParameterKey=DomainHostedZoneId,ParameterValue=$HOSTED_ZONE_ID \
    ParameterKey=BuildStage,ParameterValue=$BUILD_COUNTER  \
    ParameterKey=CurrentAmi,ParameterValue=$AMI_CURRENT \
    --tags Key=Name,Value=openvpn-stage1 --use-previous-template > /dev/null

echo "$BUILD_COUNTER Stack has now been Initiated..."
# Wait for Stage1 Update to complete
if (aws cloudformation wait stack-update-complete --stack-name $STACK_ID)
then echo "$BUILD_COUNTER Stack Update is now Complete : $STACK_ID"
else echo "Error: Stack Wait Update Failed : $STACK_ID"
fi

#-----------------------------
# Grab the IDs of the ec2 instances for further processing
INSTANCE_ID_PUB=$(aws cloudformation describe-stacks --stack-name $STACK_ID --output text --query "Stacks[].Outputs[?OutputKey == 'InstanceIdPublic1'].OutputValue")
echo "Public $BUILD_COUNTER Instance ID is : $INSTANCE_ID_PUB"
INSTANCE_ID_PRIV=$(aws cloudformation describe-stacks --stack-name $STACK_ID --output text --query "Stacks[].Outputs[?OutputKey == 'InstanceIdPrivate'].OutputValue")
echo "Private Instance ID is : $INSTANCE_ID_PRIV"

#-----------------------------
# Validity Check Here.
# Wait for instance status ok
aws ec2 wait instance-status-ok --instance-ids $INSTANCE_ID_PUB &
P1=$!
aws ec2 wait instance-status-ok --instance-ids $INSTANCE_ID_PRIV &
P2=$!
wait $P1 $P2
echo "Public $BUILD_COUNTER Instance State: Ok..."
echo "Private Instance State: Ok..."











#-----------------------------
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



#-----------------------------
# Create Launch Template for AutoScaling Group
# Update Stack with Stage3 parameters
BUILD_COUNTER="Stage3"
echo "$BUILD_COUNTER"
#aws cloudformation update-stack --stack-name $STACK_ID --parameters ParameterKey=ProjectName,ParameterValue=$PROJECT_NAME ParameterKey=BuildStage,ParameterValue=$BUILD_COUNTER  ParameterKey=CurrentAmi,ParameterValue=$AMI_IMAGE_PUB --tags Key=Name,Value=openvpn-stage3 --use-previous-template > /dev/null
aws cloudformation update-stack --stack-name $STACK_ID --parameters \
    ParameterKey=ProjectName,ParameterValue=$PROJECT_NAME \
    ParameterKey=DomainName,ParameterValue=$AWS_DOMAIN_NAME \
    ParameterKey=DomainHostedZoneId,ParameterValue=$HOSTED_ZONE_ID \
    ParameterKey=BuildStage,ParameterValue=$BUILD_COUNTER \
    ParameterKey=CurrentAmi,ParameterValue=$AMI_IMAGE_PUB \
    --tags Key=Name,Value=openvpn-stage3 --use-previous-template > /dev/null


echo "$BUILD_COUNTER Stack has now been Initiated..."
# Wait for Stage3 Update to complete
if (aws cloudformation wait stack-update-complete --stack-name $STACK_ID)
then echo "$BUILD_COUNTER Stack Update is now Complete : $STACK_ID"
else echo "Error: Stack Wait Update Failed : $STACK_ID"
fi

# Copy client configuration files locally & timestamp
cd openvpn/client
if (aws s3 sync s3://$PROJECT_NAME/openvpn/client/ . --exclude "*" --include "*.tar.gz")
then 
  echo "OpenVPN client files successfully copied locally"
  for file in $(ls *.tar.gz); do [ -f $file ] && mv $file "${file%%.*}_$(date +%F_%H%M).tar.gz" || echo "Failed to timestamp : $file"; done
else 
  echo "OpenVPN client files failed to copy locally"
fi
cd ..



#-----------------------------
# Calculate Script Total Execution Time
TIME_END=$(date +%s)
TIME_DIFF=$(($TIME_END - $TIME_START))
echo "Execution Time: $(( ${TIME_DIFF} / 3600 ))h $(( (${TIME_DIFF} / 60) % 60 ))m $(( ${TIME_DIFF} % 60 ))s"



