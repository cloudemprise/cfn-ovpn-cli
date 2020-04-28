#!/bin/bash 
#-xe


#!! COMMENT BEGIN
: <<'END'
#!! COMMENT BEGIN

#!! COMMENT END
END
#!! COMMENT END

#-----------------------------
# Record Script Execution Time
TIME_START_PROJ=$(date +%s)
TIME_STAMP_PROJ=$(date "+%Y-%m-%d %Hh%Mm%Ss")
echo "The Time Stamp.................: $TIME_STAMP_PROJ"

#.............................

#-----------------------------
# Name Given to Entire Project
# must be compatible with s3bucket name restrictions
PROJECT_NAME="dh-openvpn-test8"
[[ ! $PROJECT_NAME =~ (^[a-z0-9]([a-z0-9-]*(\.[a-z0-9])?)*$) ]] \
    && { echo "Invalid Project Name!"; exit 1; } \
    || { echo "The Project Name...............: $PROJECT_NAME"; }
#.............................



#-----------------------------
# Get Route 53 Domain hosted zone ID
AWS_DOMAIN_NAME="cloudemprise.net"
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name $AWS_DOMAIN_NAME \
    --query "HostedZones[].Id" --output text | awk -F "/" '{print $3}')
[[ -z $HOSTED_ZONE_ID ]] \
    && { echo "Invalid Hosted Zone!"; exit 1; } \
    || { echo "The Hosted Zone ID.............: $HOSTED_ZONE_ID"; }
#.............................

#-----------------------------
# Variable Creation
#-----------------------------
# Name given to Cloudformation Stack
STACK_NAME="cfn-stack-$PROJECT_NAME"
echo "The Stack Name.................: $STACK_NAME"
# Region to deploy
AWS_REGION=$(aws configure get region)
echo "The Deploy Region..............: $AWS_REGION"
# Get Account(ROOT) ID
AWS_ACC_ID=$(aws sts get-caller-identity --query Account --output text)
echo "The Root Account ID............: $AWS_ACC_ID"
# CLI profile userid
AWS_CLI_ID=$(aws sts get-caller-identity --query UserId --output text)
echo "The Script Caller userid.......: $AWS_CLI_ID"
# EC2 Instance Profile Name
EC2_ROLE_NAME="dh-openvpn-server-system-administrator"
echo "The Instance Profile Name......: $EC2_ROLE_NAME"
# EC2 Instance Profile userid
EC2_ROLE_ID=$(aws iam get-role --role-name $EC2_ROLE_NAME \
    --query "Role.RoleId" --output text)
echo "The Instance Profile userid....: $EC2_ROLE_ID"
# Grab the latest Amazon_Linux_2 AMI
AMI_LATEST=$(aws ssm get-parameters --names /aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 --query 'Parameters[0].[Value]' --output text)
echo "The lastest Amazon Linux 2 AMI.: $AMI_LATEST"
#.............................


#-----------------------------
# Create Project S3 Bucket Policy from local template
if [ -f policies/s3-buckets/template-s3-bucket-policy.json ]
then 
  cp policies/s3-buckets/template-s3-bucket-policy.json policies/s3-buckets/${PROJECT_NAME}-s3-bucket-policy.json
  sed -i "s/ProjectName/$PROJECT_NAME/" policies/s3-buckets/${PROJECT_NAME}-s3-bucket-policy.json
  sed -i "s/RootAccount/$AWS_ACC_ID/" policies/s3-buckets/${PROJECT_NAME}-s3-bucket-policy.json
  sed -i "s/ScriptCallerUserId/$AWS_CLI_ID/" policies/s3-buckets/${PROJECT_NAME}-s3-bucket-policy.json
  sed -i "s/Ec2RoleUserId/$EC2_ROLE_ID/" policies/s3-buckets/${PROJECT_NAME}-s3-bucket-policy.json
else
  echo "Template Bucket Policy Not Found!"
  exit 1
fi
#.............................


#-----------------------------
# Create S3 Project Bucket with Encryption & Policy
set -x
PROJECT_BUCKET="s3://${PROJECT_NAME}"
if (aws s3 mb $PROJECT_BUCKET)
then 
  aws s3api put-bucket-encryption --bucket $PROJECT_NAME  \
      --server-side-encryption-configuration              \
      '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}'
  aws s3api put-bucket-policy --bucket $PROJECT_NAME      \
      --policy "file://policies/s3-buckets/${PROJECT_NAME}-s3-bucket-policy.json"
else
  echo "Failed to create s3 project bucket!"
  exit 1
fi
set +x
#.............................


#----------------------------------------------
# Upload Latest Stack Policy to S3
echo "Uploading Policy Documents to S3 Bucket :  ${PROJECT_BUCKET}/policies/"
for file in $(ls policies/*/*.json); do [ -f $file ] && \
    aws s3 cp $file ${PROJECT_BUCKET}/${file} || echo "Failed to upload : $file"; done
#.............................

#----------------------------------------------
# Upload Latest Nested Templates to S3
echo "Uploading Cloudformation Templates to S3 location: ${PROJECT_BUCKET}/cfn-templates/"
for file in $(ls cfn-templates/*.yaml); do [ -f $file ] && \
    aws s3 cp $file ${PROJECT_BUCKET}/${file} || echo "Failed to upload : $file"; done
#.............................


#-----------------------------
# Upload to S3: EC2 Instance configuration files & local scripts
set -x
#-----------------------------
#Upload easy-rsa pki keygen configs to S3
tar -zcf - easy-rsa/dh-openvpn-vars/vars* | aws s3 cp - ${PROJECT_BUCKET}/easy-rsa/dh-openvpn-vars/dh-openvpn-easyrsa-vars.tar.gz

#Compress & Upload separate iptables scripts to S3
tar -zcf - iptables/dh-openvpn-ec2-pub-iptables.sh | aws s3 cp - ${PROJECT_BUCKET}/iptables/dh-openvpn-ec2-pub-iptables.sh.tar.gz
tar -zcf - iptables/dh-openvpn-ec2-priv-iptables.sh | aws s3 cp - ${PROJECT_BUCKET}/iptables/dh-openvpn-ec2-priv-iptables.sh.tar.gz

#Compress & Upload openvpn server/client configs to S3
# Remove hierarchy from archives more flexible extraction options.
#tar -zcf - openvpn/server/conf/dh-openvpn-server*.conf | aws s3 cp - ${PROJECT_BUCKET}/openvpn/server/conf/dh-openvpn-server-1194.conf.tar.gz
tar -zcf - -C openvpn/server/conf/ . | aws s3 cp - ${PROJECT_BUCKET}/openvpn/server/conf/dh-openvpn-server-1194.conf.tar.gz
#tar -zcf - openvpn/client/ovpn/template-client*.ovpn | aws s3 cp - ${PROJECT_BUCKET}/openvpn/client/ovpn/dh-openvpn-client-1194.ovpn.tar.gz
tar -zcf - -C openvpn/client/ovpn/ . | aws s3 cp - ${PROJECT_BUCKET}/openvpn/client/ovpn/dh-openvpn-client-1194.ovpn.tar.gz

#Compress & Upload sshd hardening script to S3
tar -zcf - ssh/dh-openvpn-ec2-harden-ssh.sh | aws s3 cp - ${PROJECT_BUCKET}/ssh/dh-openvpn-ec2-harden-ssh.sh.tar.gz
set +x
#.............................



#-----------------------------
#-----------------------------
# Stage1 Stack Creation Code Block
BUILD_COUNTER="Stage1"
echo "Cloudformation Stack Creation: $BUILD_COUNTER"
TIME_START_STACK=$(date +%s)
#-----------------------------
STACK_ID=$(aws cloudformation create-stack --stack-name $STACK_NAME --parameters  \
                ParameterKey=BuildStep,ParameterValue=$BUILD_COUNTER             \
                ParameterKey=ProjectName,ParameterValue=$PROJECT_NAME             \
                ParameterKey=DomainName,ParameterValue=$AWS_DOMAIN_NAME           \
                ParameterKey=DomainHostedZoneId,ParameterValue=$HOSTED_ZONE_ID    \
                ParameterKey=CurrentAmi,ParameterValue=$AMI_LATEST                \
                --tags Key=Name,Value=openvpn-stage1                              \
                --stack-policy-url "https://$PROJECT_NAME.s3.eu-central-1.amazonaws.com/policies/cfn-stacks/template_cfn-stack-policy.json" \
                --template-url "https://$PROJECT_NAME.s3.eu-central-1.amazonaws.com/cfn-templates/dh-openvpn-cfn.yaml" \
                --on-failure DO_NOTHING --output text)
#-----------------------------
if [[ $? -eq 0 ]]; then
  # Wait for stack creation to complete
  echo "Waiting for $BUILD_COUNTER stack creation to complete:"
  CREATE_STACK_STATUS=$(aws cloudformation describe-stacks --stack-name ${STACK_ID} --query 'Stacks[0].StackStatus' --output text)
  while [[ $CREATE_STACK_STATUS == "REVIEW_IN_PROGRESS" ]] || [[ $CREATE_STACK_STATUS == "CREATE_IN_PROGRESS" ]]
  do
      # Wait 1 seconds and then check stack status again
      sleep 1
      printf '.'
      CREATE_STACK_STATUS=$(aws cloudformation describe-stacks --stack-name ${STACK_ID} --query 'Stacks[0].StackStatus' --output text)
  done
  printf "\n"
fi
#-----------------------------
# Validate stack creation has not failed
if (aws cloudformation wait stack-create-complete --stack-name ${STACK_ID})
then echo "Stack $BUILD_COUNTER is now Complete with Stack ID:"
else 
  echo "Error: Stack Creation Failed!"
  exit 1
fi
echo "$STACK_ID"
#-----------------------------
# Calculate Stack Creation Execution Time
TIME_END_STACK=$(date +%s)
TIME_DIFF_STACK=$(($TIME_END_STACK - $TIME_START_STACK))
echo "Execution Time $BUILD_COUNTER : $(( ${TIME_DIFF_STACK} / 3600 ))h $(( (${TIME_DIFF_STACK} / 60) % 60 ))m $(( ${TIME_DIFF_STACK} % 60 ))s"
#.............................
#.............................



#-----------------------------
#-----------------------------
# Stage2 Stack Creation Code Block
BUILD_COUNTER="Stage2"
echo "Cloudformation Stack Update: $BUILD_COUNTER"
TIME_START_STACK=$(date +%s)
#-----------------------------
aws cloudformation update-stack --stack-name $STACK_ID --parameters   \
      ParameterKey=BuildStep,ParameterValue=$BUILD_COUNTER            \
      ParameterKey=ProjectName,UsePreviousValue=true                  \
      ParameterKey=DomainName,UsePreviousValue=true                   \
      ParameterKey=DomainHostedZoneId,UsePreviousValue=true           \
      ParameterKey=CurrentAmi,UsePreviousValue=true                   \
      --tags Key=Name,Value=openvpn-stage2 --use-previous-template > /dev/null
#-----------------------------
if [[ $? -eq 0 ]]; then
  # Wait for stack creation to complete
  echo "Waiting for $BUILD_COUNTER stack update to complete:"
  CREATE_STACK_STATUS=$(aws cloudformation describe-stacks --stack-name ${STACK_ID} --query 'Stacks[0].StackStatus' --output text)
  while [[ $CREATE_STACK_STATUS == "UPDATE_IN_PROGRESS" ]] || [[ $CREATE_STACK_STATUS == "CREATE_IN_PROGRESS" ]]
  do
      # Wait 1 seconds and then check stack status again
      sleep 1
      printf '.'
      CREATE_STACK_STATUS=$(aws cloudformation describe-stacks --stack-name ${STACK_ID} --query 'Stacks[0].StackStatus' --output text)
  done
  printf "\n"
fi
#-----------------------------
# Validate stack creation has not failed
if (aws cloudformation wait stack-update-complete --stack-name ${STACK_ID})
then 
  echo "Stack $BUILD_COUNTER Update is now complete. Stack ID:"
  echo "$STACK_ID"
else 
  echo "Error: Stack Update Failed!"
  exit 1
fi
#-----------------------------
# Calculate Stack Creation Execution Time
TIME_END_STACK=$(date +%s)
TIME_DIFF_STACK=$(($TIME_END_STACK - $TIME_START_STACK))
echo "Execution Time $BUILD_COUNTER : $(( ${TIME_DIFF_STACK} / 3600 ))h $(( (${TIME_DIFF_STACK} / 60) % 60 ))m $(( ${TIME_DIFF_STACK} % 60 ))s"
#.............................
#.............................

#-----------------------------
# Grab the IDs of the ec2 instances for further processing
INSTANCE_ID_PUB=$(aws cloudformation describe-stacks --stack-name $STACK_ID --output text --query "Stacks[].Outputs[?OutputKey == 'InstanceIdPublic'].OutputValue")
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
#-----------------------------
# Stage3 Stack Creation Code Block
BUILD_COUNTER="Stage3"
echo "Cloudformation Stack Update: $BUILD_COUNTER"
TIME_START_STACK=$(date +%s)
#-----------------------------
aws cloudformation update-stack --stack-name $STACK_ID --parameters   \
      ParameterKey=BuildStep,ParameterValue=$BUILD_COUNTER            \
      ParameterKey=CurrentAmi,ParameterValue=$AMI_IMAGE_PUB           \
      ParameterKey=ProjectName,UsePreviousValue=true                  \
      ParameterKey=DomainName,UsePreviousValue=true                   \
      ParameterKey=DomainHostedZoneId,UsePreviousValue=true           \
      --tags Key=Name,Value=openvpn-stage3 --use-previous-template > /dev/null
#-----------------------------
if [[ $? -eq 0 ]]; then
  # Wait for stack creation to complete
  echo "Waiting for $BUILD_COUNTER stack update to complete:"
  CREATE_STACK_STATUS=$(aws cloudformation describe-stacks --stack-name ${STACK_ID} --query 'Stacks[0].StackStatus' --output text)
  while [[ $CREATE_STACK_STATUS == "UPDATE_IN_PROGRESS" ]] || [[ $CREATE_STACK_STATUS == "CREATE_IN_PROGRESS" ]]
  do
      # Wait 1 seconds and then check stack status again
      sleep 1
      printf '.'
      CREATE_STACK_STATUS=$(aws cloudformation describe-stacks --stack-name ${STACK_ID} --query 'Stacks[0].StackStatus' --output text)
  done
  printf "\n"
fi
#-----------------------------
# Validate stack creation has not failed
if (aws cloudformation wait stack-update-complete --stack-name ${STACK_ID})
then 
  echo "Stack $BUILD_COUNTER Update is now complete. Stack ID:"
  echo "$STACK_ID"
else 
  echo "Error: Stack Update Failed!"
  exit 1
fi
#-----------------------------
# Calculate Stack Creation Execution Time
TIME_END_STACK=$(date +%s)
TIME_DIFF_STACK=$(($TIME_END_STACK - $TIME_START_STACK))
echo "Execution Time $BUILD_COUNTER : $(( ${TIME_DIFF_STACK} / 3600 ))h $(( (${TIME_DIFF_STACK} / 60) % 60 ))m $(( ${TIME_DIFF_STACK} % 60 ))s"
#.............................




#-----------------------------
# DOWNLOAD & SORT CLIENT CONFIGURATION FILES
#-----------------------------

# Create Temporary scratch folder
TMP_DIR=/tmp/ovpn
rm -Rf $TMP_DIR
mkdir $TMP_DIR
echo "Temporary working directory....: $TMP_DIR"


# Download client archives locally
aws s3 sync $PROJECT_BUCKET/openvpn/client/ $TMP_DIR  --exclude "*" --include "*.tar.gz"

# Extract archive and then delete them
for FILE in $(find $TMP_DIR -type f -name '*.tar.gz'); do 
  tar -zxf $FILE -C $(dirname "${FILE}");
  rm $FILE
done

# Make directory for each client and distribute files
for FILE in $(find $TMP_DIR -type f -name "*-client*" ! -path "$TMP_DIR/ovpn/*"); do
  mkdir -p "${TMP_DIR}/client/$(basename ${FILE%%-client*})"
  cp ${TMP_DIR}/crt/ca.crt $_
  cp ${TMP_DIR}/hmac-sig.key $_
  cp ${TMP_DIR}/ovpn/*.ovpn $_
  cp $FILE $_
done

# Remove unwanted files
find $TMP_DIR -name "*" ! -path "$TMP_DIR/client/*" -delete


# Create client specific configurations files
for FILE in $(find $TMP_DIR -type f); do
  # Rename template files to reflect client specifics via parameter expansion
  [[ "$(basename $FILE)" == "template-client"* ]] && mv $FILE ${FILE//template-client/$(basename $(dirname $FILE))}
  # Insert certificates into respective sections configuration files
  [[ $(basename $FILE) = "ca.crt" ]] && { sed -i -e "/<ca>/ r ${FILE}" $(dirname $FILE)/*.ovpn; }
  [[ $(basename $FILE) = "hmac-sig.key" ]] && { sed -i -e "/<tls-crypt>/ r ${FILE}" $(dirname $FILE)/*.ovpn; }
  [[ "$(basename $FILE)" == *"-client.crt" ]] && { sed -i -e "/<cert>/ r ${FILE}" $(dirname $FILE)/*.ovpn; }
  [[ "$(basename $FILE)" == *"-client.key" ]] && { sed -i -e "/<key>/ r ${FILE}" $(dirname $FILE)/*.ovpn; }
done

# Archive individual client configuration directories
for DIR in $(find $TMP_DIR/client/* -type d); do
  tar -zcf "$(basename $DIR)_$(date +%F_%H%M).tar.gz" -C $DIR .
  echo "Configuration archive..........: ./openvpn/client/$(ls *.tar.gz)"
  mv $(basename $DIR)*.tar.gz ./openvpn/client/
#  echo "Configuration archive..........: $_"
done

# Delete temporary files
rm -Rf $TMP_DIR
#.............................


#-----------------------------
# Calculate Script Total Execution Time
TIME_END_PROJ=$(date +%s)
TIME_DIFF=$(($TIME_END_PROJ - $TIME_START_PROJ))
echo "Total Execution Time: $(( ${TIME_DIFF} / 3600 ))h $(( (${TIME_DIFF} / 60) % 60 ))m $(( ${TIME_DIFF} % 60 ))s"
#.............................

