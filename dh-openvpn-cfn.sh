#!/bin/bash -e
# dh-openvpn-cfn.sh 
# A hardened, hightly available, multi-protocol, multi-client openvpn 
# server cloudformation template composition.


#!! COMMENT Construct Begins Here:
: <<'END'
#!! COMMENT BEGIN

#!! COMMENT END
END
#!! COMMENT Construct Ends Here:


#-----------------------------
# Record Script Start Execution Time
TIME_START_PROJ=$(date +%s)
TIME_STAMP_PROJ=$(date "+%Y-%m-%d %Hh%Mm%Ss")
echo "The Time Stamp ................................: $TIME_STAMP_PROJ"
#.............................


#-----------------------------
# Name Given to Cloudformation Entire Project
# Must be compatible with s3bucket name restrictions
PROJECT_NAME="dh-openvpn-test8"
[[ ! "$PROJECT_NAME" =~ (^[a-z0-9]([a-z0-9-]*(\.[a-z0-9])?)*$) ]] \
    && { echo "Invalid Project Name!"; exit 1; } \
    || { echo "The Project Name ..............................: $PROJECT_NAME"; }
#.............................


#-----------------------------
# Get Route 53 Domain hosted zone ID
AWS_DOMAIN_NAME="cloudemprise.net"
echo "The IP Domain Name ............................: $AWS_DOMAIN_NAME"
echo "The Openvpn Server FQDN .......................: ${PROJECT_NAME}.${AWS_DOMAIN_NAME}"
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name "$AWS_DOMAIN_NAME" \
    --query "HostedZones[].Id" --output text | awk -F "/" '{print $3}')
[[ -z "$HOSTED_ZONE_ID" ]] \
    && { echo "Invalid Hosted Zone!"; exit 1; } \
    || { echo "Route53 Hosted Zone ID ........................: $HOSTED_ZONE_ID"; }
#.............................


#-----------------------------
# Variable Creation
#-----------------------------
# Script caller IP CIDR for SSH Bastion Host
SSH_ACCESS_CIDR="$(curl -s https://checkip.amazonaws.com/)/32"
echo "The Script Caller IP CIDR  ....................: $SSH_ACCESS_CIDR"
# Name given to Cloudformation Stack
STACK_NAME="cfn-stack-$PROJECT_NAME"
echo "The Stack Name ................................: $STACK_NAME"
# Region to deploy
AWS_REGION=$(aws configure get region)
echo "The Deploy Region .............................: $AWS_REGION"
# Get Account(ROOT) ID
AWS_ACC_ID=$(aws sts get-caller-identity --query Account --output text)
echo "The Root Account ID ...........................: $AWS_ACC_ID"
# CLI profile userid
AWS_CLI_ID=$(aws sts get-caller-identity --query UserId --output text)
echo "The Script Caller userid ......................: $AWS_CLI_ID"
# Grab the latest Amazon_Linux_2 AMI
AMI_LATEST=$(aws ssm get-parameters --output text                         \
    --names /aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 \
    --query 'Parameters[0].[Value]')
echo "The lastest Amazon Linux 2 AMI ................: $AMI_LATEST"
#.............................


#-----------------------------
# Request Cert Auth Private Key Passphrase
USER_INPUT1="false"
USER_INPUT2="true"
# While user input is different or empty...
while [[ "$USER_INPUT1" != "$USER_INPUT2" ]] || [[ "$USER_INPUT1" == '' ]] 
do
  read -srep $'Enter PKI Cert Auth Private Key Passphrase ....:\n' USER_INPUT1
  if [[ -z "$USER_INPUT1" ]]; then
    printf '%s\n' "Error. No Input Entered !"
    continue
  else
    read -srep $'Repeat PKI Cert Auth Private Key Passphrase ...:\n' USER_INPUT2
    if [[ "$USER_INPUT1" != "$USER_INPUT2" ]]; then
      printf '%s\n' "Error. Passphrase Mismatch !"
    else
      printf '%s\n' "Passphrase Match....... Continue ..............:"
      CERT_AUTH_PASS="$USER_INPUT2"
    fi
  fi
done

CERT_AUTH_PASS_NAME="/${PROJECT_NAME}/pki-cert-auth"
echo "Adding Passphrase to AWS Parameter Store ......: $CERT_AUTH_PASS_NAME"
aws ssm put-parameter --name "$CERT_AUTH_PASS_NAME" --value "$CERT_AUTH_PASS" \
        --type SecureString --overwrite \
        --description "Openvpn PKI Certificate Authority Private Key Passphrase" > /dev/null
#.............................


#-----------------------------
# Create IAM Role
EC2_ROLE_NAME="${PROJECT_NAME}-iam-role-${AWS_REGION}"
echo "The IAM Role Name .............................: $EC2_ROLE_NAME"
ASSUME_ROLE_POLICY=$(tr -d " \t\n\r" < ./policies/ec2-role/assume-role-policy.json)
EC2_ROLE_ID=$(aws iam create-role --role-name "$EC2_ROLE_NAME"  \
    --assume-role-policy-document "$ASSUME_ROLE_POLICY"         \
    --output text --query 'Role.RoleId')
echo "The IAM Role userid ...........................: $EC2_ROLE_ID"
#.............................

#-----------------------------
# Create EC2 Instance Profile
EC2_PROFILE_NAME="${PROJECT_NAME}-instance-profile-${AWS_REGION}"
echo "The EC2 Instance Profile Name .................: $EC2_PROFILE_NAME"
EC2_PROFILE_ID=$(aws iam create-instance-profile --output text  \
    --instance-profile-name "$EC2_PROFILE_NAME"                   \
    --query 'InstanceProfile.InstanceProfileId')
echo "The EC2 Instance Profile userid ...............: $EC2_PROFILE_ID"
#.............................

#-----------------------------
# Add the IAM role to the instance profile
aws iam add-role-to-instance-profile --instance-profile-name "$EC2_PROFILE_NAME" \
    --role-name "$EC2_ROLE_NAME"
echo "IAM Role Added to Instance Profile ............: "
#.............................


#-----------------------------
# Create Inline Role Policy for S3 Access from local template
if [ -f policies/ec2-role/template-s3-access-policy.json ]
then
  cp policies/ec2-role/template-s3-access-policy.json policies/ec2-role/${PROJECT_NAME}-s3-access-policy.json
  sed -i "s/ProjectName/$PROJECT_NAME/g" policies/ec2-role/${PROJECT_NAME}-s3-access-policy.json
else
  echo "Template EC2 S3 Role Policy Not Found!"
  exit 1
fi
#.............................

#-----------------------------
# Create Inline Role Policy for SSM Access from local template
if [ -f policies/ec2-role/template-ssm-access-policy.json ]
then
  cp policies/ec2-role/template-ssm-access-policy.json policies/ec2-role/${PROJECT_NAME}-ssm-access-policy.json
  sed -i "s/ProjectName/$PROJECT_NAME/g" policies/ec2-role/${PROJECT_NAME}-ssm-access-policy.json
else
  echo "Template EC2 SSM Role Policy Not Found!"
  exit 1
fi
#.............................


#-----------------------------
# Embedd S3 inline policy document in IAM role
EC2_ROLE_S3_POLICY=$(tr -d " \t\n\r" < ./policies/ec2-role/${PROJECT_NAME}-s3-access-policy.json)
EC2_ROLE_S3_NAME="${PROJECT_NAME}-ec2-s3-${AWS_REGION}"
aws iam put-role-policy --role-name "$EC2_ROLE_NAME"  \
    --policy-name "$EC2_ROLE_S3_NAME"                 \
    --policy-document "$EC2_ROLE_S3_POLICY"
echo "S3 Access Policy Attached to IAM Role .........: ${EC2_ROLE_S3_NAME}"

#-----------------------------
# Embedd SSM inline policy document in IAM role
EC2_ROLE_SSM_POLICY=$(tr -d " \t\n\r" < ./policies/ec2-role/${PROJECT_NAME}-ssm-access-policy.json)
EC2_ROLE_SSM_NAME="${PROJECT_NAME}-ec2-ssm-${AWS_REGION}"
aws iam put-role-policy --role-name "$EC2_ROLE_NAME"  \
    --policy-name "$EC2_ROLE_SSM_NAME"                 \
    --policy-document "$EC2_ROLE_SSM_POLICY"
echo "SSM Access Policy Attached to IAM Role ........: ${EC2_ROLE_SSM_NAME}"


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


#----------------------------------------------
# Create cfn Stack policies from local templates
echo "Creating Stack Policies .......................: "
for FILE in policies/cfn-stacks/template-stage?-cfn-stack-policy.json
do
  [[ ! -e "$FILE" ]] \
  && { echo "Template Stack Policy Not Found ...............: $FILE"; exit 1; } \
  || { cp "$FILE" "$(dirname "$FILE")/$PROJECT_NAME${FILE#*template}"; }
done
#.............................


#-----------------------------
# Create S3 Project Bucket with Encryption & Policy
PROJECT_BUCKET="s3://${PROJECT_NAME}"
if (aws s3 mb "$PROJECT_BUCKET" > /dev/null)
then 
  aws s3api put-bucket-encryption --bucket "$PROJECT_NAME"  \
      --server-side-encryption-configuration              \
      '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}'
  aws s3api put-bucket-policy --bucket "$PROJECT_NAME"      \
      --policy "file://policies/s3-buckets/${PROJECT_NAME}-s3-bucket-policy.json"
  echo "S3 Project Bucket Created .....................: $PROJECT_BUCKET"
else
  echo "Failed to Create S3 Project Bucket !!!!!!!!!!!!: $PROJECT_BUCKET"
  exit 1
fi
#.............................


#----------------------------------------------
# Upload Latest Stack/IAM/Bucket Policies to S3
echo "Uploading Policy Documents to S3 Location .....: $PROJECT_BUCKET/policies/"
for FILE in policies/*/"$PROJECT_NAME"*.json
do
  [[ -e "$FILE" ]] \
  && aws s3 mv "$FILE" "$PROJECT_BUCKET/$FILE" > /dev/null \
  || echo "Failed to Upload Policy Docs to S3 ............: $FILE"
done
#.............................


#----------------------------------------------
# Upload Latest Nested Templates to S3
echo "Uploading cfn Templates to S3 Location ........: $PROJECT_BUCKET/cfn-templates/"
for FILE in cfn-templates/*.yaml
do
  [[ -e "$FILE" ]] \
  && aws s3 cp "$FILE" "$PROJECT_BUCKET/$FILE" > /dev/null \
  || echo "Failed to Upload cfn Templates to S3 ..........: $FILE"
done
#.............................


#-----------------------------
# Upload easy-rsa pki keygen configs to S3
S3_LOCATION="$PROJECT_BUCKET/easy-rsa/dh-openvpn-vars"
if [[ $(tar -zcf - easy-rsa/dh-openvpn-vars/vars* | aws s3 cp - ${S3_LOCATION}/dh-openvpn-easyrsa-vars.tar.gz) -ne 0 ]]
then
  echo "easy-rsa Configs Failed to Uploaded to S3 .....: $S3_LOCATION"
  exit 1
else
  echo "easy-rsa Configs Uploaded to S3 Location ......: $S3_LOCATION"
fi
#.............................


#-----------------------------
#Compress & Upload public iptables scripts to S3
S3_LOCATION="$PROJECT_BUCKET/iptables"
if [[ $(tar -zcf - iptables/dh-openvpn-ec2-pub-iptables.sh  | aws s3 cp - ${S3_LOCATION}/dh-openvpn-ec2-pub-iptables.sh.tar.gz) -ne 0 ]] || \
   [[ $(tar -zcf - iptables/dh-openvpn-ec2-priv-iptables.sh | aws s3 cp - ${S3_LOCATION}/dh-openvpn-ec2-priv-iptables.sh.tar.gz) -ne 0 ]]
then
  echo "iptables Configs Failed to Uploaded to S3 .....: ${S3_LOCATION}"
  exit 1
else
  echo "iptables Configs Uploaded to S3 Location ......: ${S3_LOCATION}"
fi
#.............................


#-----------------------------
#Compress & Upload openvpn server/client configs to S3
# Remove hierarchy from archives for more flexible extraction options.
S3_LOCATION="$PROJECT_BUCKET/openvpn"
if [[ $(tar -zcf - -C openvpn/server/conf/ . | aws s3 cp - ${S3_LOCATION}/server/conf/dh-openvpn-server-1194.conf.tar.gz) -ne 0 ]] || \
   [[ $(tar -zcf - -C openvpn/client/ovpn/ . | aws s3 cp - ${S3_LOCATION}/client/ovpn/dh-openvpn-client-1194.ovpn.tar.gz) -ne 0 ]]
then
  echo "Openvpn Configs Failed to Uploaded to S3 ......: ${S3_LOCATION}"
  exit 1
else
  echo "Openvpn Configs Uploaded to S3 Location .......: ${S3_LOCATION}"
fi
#.............................


#-----------------------------
#Compress & Upload sshd hardening script to S3
S3_LOCATION="$PROJECT_BUCKET/ssh"
if [[ $(tar -zcf - ssh/dh-openvpn-ec2-harden-ssh.sh | aws s3 cp - ${S3_LOCATION}/dh-openvpn-ec2-harden-ssh.sh.tar.gz) -ne 0 ]]
then
  echo "Harden SSH Configs Failed to Uploaded to S3 ...: ${S3_LOCATION}"
  exit 1
else
  echo "Harden SSH Configs Uploaded to S3 Location ....: ${S3_LOCATION}"
fi
#.............................



#-----------------------------
#-----------------------------
# Stage1 Stack Creation Code Block
BUILD_COUNTER="stage1"
echo "cfn Stack Creation Initiated ..................: $BUILD_COUNTER"
STACK_POLICY_URL="https://${PROJECT_NAME}.s3.eu-central-1.amazonaws.com/policies/cfn-stacks/${PROJECT_NAME}-${BUILD_COUNTER}-cfn-stack-policy.json"
TEMPLATE_URL="https://${PROJECT_NAME}.s3.eu-central-1.amazonaws.com/cfn-templates/dh-openvpn-cfn.yaml"
TIME_START_STACK=$(date +%s)
#-----------------------------
STACK_ID=$(aws cloudformation create-stack --stack-name "$STACK_NAME" --parameters  \
                ParameterKey=ProjectName,ParameterValue="$PROJECT_NAME"             \
                ParameterKey=BuildStep,ParameterValue="$BUILD_COUNTER"              \
                ParameterKey=DomainName,ParameterValue="$AWS_DOMAIN_NAME"           \
                ParameterKey=DomainHostedZoneId,ParameterValue="$HOSTED_ZONE_ID"    \
                ParameterKey=SshAccessCIDR,ParameterValue="$SSH_ACCESS_CIDR"        \
                ParameterKey=CurrentAmi,ParameterValue="$AMI_LATEST"                \
                --tags Key=Name,Value=openvpn-stage1                                \
                --stack-policy-url $STACK_POLICY_URL --template-url $TEMPLATE_URL   \
                --on-failure DO_NOTHING --capabilities CAPABILITY_NAMED_IAM --output text)
#-----------------------------
if [[ $? -eq 0 ]]; then
  # Wait for stack creation to complete
  echo "Stack Creation Process Wait....................: $BUILD_COUNTER"
  CREATE_STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK_ID" --query 'Stacks[0].StackStatus' --output text)
  while [[ $CREATE_STACK_STATUS == "REVIEW_IN_PROGRESS" ]] || [[ $CREATE_STACK_STATUS == "CREATE_IN_PROGRESS" ]]
  do
      # Wait 1 seconds and then check stack status again
      sleep 1
      printf '.'
      CREATE_STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK_ID" --query 'Stacks[0].StackStatus' --output text)
  done
  printf '\n'
fi
#-----------------------------
# Validate stack creation has not failed
if (aws cloudformation wait stack-create-complete --stack-name "$STACK_ID")
then 
  echo "Stack Create Process Done .....................: $BUILD_COUNTER"
else 
  echo "Error: Stack Create Failed!"
  printf 'Stack ID: \n%s\n' "$STACK_ID"
  exit 1
fi
#-----------------------------
# Calculate Stack Creation Execution Time
TIME_END_STACK=$(date +%s)
TIME_DIFF_STACK=$((TIME_END_STACK - TIME_START_STACK))
echo "$BUILD_COUNTER Finished Execution Time ................: \
$(( TIME_DIFF_STACK / 3600 ))h $(( (TIME_DIFF_STACK / 60) % 60 ))m $(( TIME_DIFF_STACK % 60 ))s"
#.............................
#.............................


#-----------------------------
#-----------------------------
# Stage2 Stack Creation Code Block
BUILD_COUNTER="stage2"
echo "cfn Stack Update Initiated ....................: $BUILD_COUNTER"
TIME_START_STACK=$(date +%s)
#-----------------------------
aws cloudformation update-stack --stack-name "$STACK_ID" --parameters          \
      ParameterKey=BuildStep,ParameterValue="$BUILD_COUNTER"                   \
      ParameterKey=ProjectName,UsePreviousValue=true                           \
      ParameterKey=DomainName,UsePreviousValue=true                            \
      ParameterKey=DomainHostedZoneId,UsePreviousValue=true                    \
      ParameterKey=SshAccessCIDR,UsePreviousValue=true                         \
      ParameterKey=CurrentAmi,UsePreviousValue=true                            \
      --stack-policy-url $STACK_POLICY_URL --capabilities CAPABILITY_NAMED_IAM \
      --tags Key=Name,Value=openvpn-stage2 --use-previous-template > /dev/null
#-----------------------------
if [[ $? -eq 0 ]]; then
  # Wait for stack creation to complete
  echo "Stack Update Process Wait......................: $BUILD_COUNTER"
  CREATE_STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK_ID" --query 'Stacks[0].StackStatus' --output text)
  while [[ $CREATE_STACK_STATUS == "UPDATE_IN_PROGRESS" ]] || [[ $CREATE_STACK_STATUS == "CREATE_IN_PROGRESS" ]]
  do
      # Wait 1 seconds and then check stack status again
      sleep 1
      printf '.'
      CREATE_STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK_ID" --query 'Stacks[0].StackStatus' --output text)
  done
  printf '\n'
fi

#-----------------------------
# Validate stack creation has not failed
if (aws cloudformation wait stack-update-complete --stack-name "$STACK_ID")
then 
  echo "Stack Update Process Done .....................: $BUILD_COUNTER"
  printf 'Stack ID: \n%s\n' "$STACK_ID"
else 
  echo "Error: Stack Update Failed!"
  printf 'Stack ID: \n%s\n' "$STACK_ID"
  exit 1
fi

#-----------------------------
# Calculate Stack Creation Execution Time
TIME_END_STACK=$(date +%s)
TIME_DIFF_STACK=$(( TIME_END_STACK -  TIME_START_STACK))
echo "$BUILD_COUNTER Finished Execution Time ................: \
$(( TIME_DIFF_STACK / 3600 ))h $(( (TIME_DIFF_STACK / 60) % 60 ))m $(( TIME_DIFF_STACK % 60 ))s"
#.............................
#.............................



#-----------------------------
# Grab the IDs of the ec2 instances for further processing
INSTANCE_ID_PUB=$(aws cloudformation describe-stacks --stack-name "$STACK_ID" --output text --query "Stacks[].Outputs[?OutputKey == 'InstanceIdPublic'].OutputValue")
echo "Public Instance ID ............................: $INSTANCE_ID_PUB"
INSTANCE_ID_PRIV=$(aws cloudformation describe-stacks --stack-name "$STACK_ID" --output text --query "Stacks[].Outputs[?OutputKey == 'InstanceIdPrivate'].OutputValue")
echo "Private Instance ID ...........................: $INSTANCE_ID_PRIV"

#-----------------------------
# Validity Check. Wait for instance status ok before moving on.
aws ec2 wait instance-status-ok --instance-ids "$INSTANCE_ID_PUB" &
P1=$!
aws ec2 wait instance-status-ok --instance-ids "$INSTANCE_ID_PRIV" &
P2=$!
wait $P1 $P2
echo "Public Instance State .........................: Ok"
echo "Private Instance State ........................: Ok"


#-----------------------------
# Create IMAGE AMIs
#AMI_IMAGE_PUB=$(aws ec2 create-image --instance-id "$INSTANCE_ID_PUB" --name $(echo "openvpn-pub-$INSTANCE_ID_PUB") --description "openvpn-pub-ami" --output text)
AMI_IMAGE_PUB=$(aws ec2 create-image --instance-id "$INSTANCE_ID_PUB" --name "openvpn-pub-${INSTANCE_ID_PUB}" --description "openvpn-pub-ami" --output text)
echo "Public AMI Creation Initiated .................: "
#AMI_IMAGE_PRIV=$(aws ec2 create-image --instance-id "$INSTANCE_ID_PRIV" --name $(echo "openvpn-priv-$INSTANCE_ID_PRIV") --description "openvpn-priv-ami" --output text)
AMI_IMAGE_PRIV=$(aws ec2 create-image --instance-id "$INSTANCE_ID_PRIV" --name "openvpn-priv-${INSTANCE_ID_PRIV}" --description "openvpn-priv-ami" --output text)
echo "Private AMI Creation Initiated ................: "

# Wait for new AMIs to become available
aws ec2 wait image-available --image-ids "$AMI_IMAGE_PUB" &
P1=$!
aws ec2 wait image-available --image-ids "$AMI_IMAGE_PRIV" &
P2=$!
wait $P1 $P2
echo "Public AMI is now available ...................: $AMI_IMAGE_PUB "
echo "Private AMI Now Available .....................: $AMI_IMAGE_PRIV"


# Terminate the instances - no longer needed.
aws ec2 terminate-instances --instance-ids "$INSTANCE_ID_PUB" "$INSTANCE_ID_PRIV" > /dev/null
echo "$BUILD_COUNTER Instances Terminated ...................:"
#.............................



#-----------------------------
#-----------------------------
# Stage3 Stack Creation Code Block
BUILD_COUNTER="stage3"
echo "cfn Stack Update Initiated ....................: $BUILD_COUNTER"
TIME_START_STACK=$(date +%s)
#-----------------------------
aws cloudformation update-stack --stack-name "$STACK_ID" --parameters \
      ParameterKey=BuildStep,ParameterValue="$BUILD_COUNTER"          \
      ParameterKey=CurrentAmi,ParameterValue="$AMI_IMAGE_PUB"         \
      ParameterKey=ProjectName,UsePreviousValue=true                  \
      ParameterKey=DomainName,UsePreviousValue=true                   \
      ParameterKey=DomainHostedZoneId,UsePreviousValue=true           \
      ParameterKey=SshAccessCIDR,UsePreviousValue=true                \
      --stack-policy-url $STACK_POLICY_URL --use-previous-template    \
      --tags Key=Name,Value=openvpn-stage3 > /dev/null    
#-----------------------------
if [[ $? -eq 0 ]]; then
  # Wait for stack creation to complete
  echo "Stack Update Process Wait......................: $BUILD_COUNTER"
  CREATE_STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK_ID" --query 'Stacks[0].StackStatus' --output text)
  while [[ $CREATE_STACK_STATUS == "UPDATE_IN_PROGRESS" ]] || [[ $CREATE_STACK_STATUS == "CREATE_IN_PROGRESS" ]]
  do
      # Wait 1 seconds and then check stack status again
      sleep 1
      printf '.'
      CREATE_STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK_ID" --query 'Stacks[0].StackStatus' --output text)
  done
  printf '\n'
fi

#-----------------------------
# Validate stack creation has not failed
if (aws cloudformation wait stack-update-complete --stack-name "$STACK_ID")
then 
  echo "Stack Update Process Done .....................: $BUILD_COUNTER"
  printf 'Stack ID: \n%s\n' "$STACK_ID"
else 
  echo "Error: Stack Update Failed!"
  printf 'Stack ID: \n%s\n' "$STACK_ID"
  exit 1
fi

#-----------------------------
# Calculate Stack Creation Execution Time
TIME_END_STACK=$(date +%s)
TIME_DIFF_STACK=$(( TIME_END_STACK - TIME_START_STACK))
echo "$BUILD_COUNTER Finished Execution Time ................: \
$(( TIME_DIFF_STACK / 3600 ))h $(( (TIME_DIFF_STACK / 60) % 60 ))m $(( TIME_DIFF_STACK % 60 ))s"
#.............................
#.............................


#-----------------------------
# Grab the IDs of the ec2 instances for further processing
INSTANCE_ID_PUB=$(aws cloudformation describe-stacks --stack-name "$STACK_ID" --output text \
    --query "Stacks[].Outputs[?OutputKey == 'InstanceIdPublic'].OutputValue")
echo "Server Instance ID ............................: $INSTANCE_ID_PRIV"
#.............................



#-----------------------------
# DOWNLOAD & MANGLE CLIENT CONFIGURATION FILES
#-----------------------------

# Create Temporary scratch directory
TMP_DIR=/tmp/aws
[[ -d $TMP_DIR ]] && rm -rf $TMP_DIR
mkdir $TMP_DIR
echo "Temporary working directory....................: $TMP_DIR"
# --
# Download client archives to temp dir
echo "Processing Client Configuration Files .........: "
aws s3 sync ${PROJECT_BUCKET}/openvpn/client/ $TMP_DIR  --exclude "*" --include "*.tar.gz" > /dev/null
# --
# Extract then remove archives
find $TMP_DIR -type f -name '*.tar.gz' -print0 |
  while IFS= read -r -d '' FILE
  do
    tar -zxf "$FILE" -C "$(dirname "$FILE")"
    rm "$FILE"
  done
# --
# Distribute key/crt/ovpn for each client
find "${TMP_DIR}/key" -type f -name '*-client*' -print0 |
  while IFS= read -r -d '' FILE
  do
    # make dir for each client key
    mkdir -p "${TMP_DIR}/client/$(basename "${FILE%%-client*}")"
    # copy crt/key/ovpn into dir
    cp ${TMP_DIR}/crt/ca.crt "$_"
    cp ${TMP_DIR}/hmac-sig.key "$_"
    cp ${TMP_DIR}/ovpn/*.ovpn "$_"
    cp "$FILE" "$_"
  done
# --
# Remove unwanted files
find $TMP_DIR ! -path "*/client*" -type f -delete
# Remove unwanted directories
find $TMP_DIR -mindepth 1 ! -path "*/client*" -type d -delete
# --
# Modifiy templates for client specifics
find $TMP_DIR -type f -print0 |
  while IFS= read -r -d '' RECORD
  do
    FILE="$(basename "$RECORD")"
    DIR="$(dirname "$RECORD")"
    # Rename template files to reflect client specifics via parameter expansion
    [[ "$FILE" == "template-client"* ]] && mv "$RECORD" "${RECORD//template-client/$(basename "$DIR")}"
    # Insert certificates into respective sections of config files
    [[ "$FILE" == "ca.crt" ]] && { sed -i -e "/<ca>/r ${RECORD}" "$DIR"/*.ovpn; }
    [[ "$FILE" == "hmac-sig.key" ]] && { sed -i -e "/<tls-crypt>/r ${RECORD}" "$DIR"/*.ovpn; }
    [[ "$FILE" == *"-client.crt" ]] && { sed -i -e "/<cert>/r ${RECORD}" "$DIR"/*.ovpn; }
    [[ "$FILE" == *"-client.key" ]] && { sed -i -e "/<key>/r ${RECORD}" "$DIR"/*.ovpn; }
  done
# --
# Archive each client configuration directory
find $TMP_DIR/client/* -type d -print0 |
  while IFS= read -r -d '' DIR
  do
    # Create date-stamped archive of client configs
    ARCHIVE="$(basename "$DIR")_$(date +%F_%H%M).tar.gz"
    tar -zcf "$ARCHIVE" -C "$DIR" .
    # move archive to local project dir
    mv "$ARCHIVE" ./openvpn/client/
    printf 'Configuration archive..........................: %s\n' ./openvpn/client/"$ARCHIVE"
  done
# --
# Delete temporary files
[[ -d $TMP_DIR ]] && rm -rf $TMP_DIR
#.............................


#-----------------------------
# Calculate Script Total Execution Time
TIME_END_PROJ=$(date +%s)
TIME_DIFF=$((TIME_END_PROJ - TIME_START_PROJ))
echo "Total Finished Execution Time .................: \
$(( TIME_DIFF / 3600 ))h $(( (TIME_DIFF / 60) % 60 ))m $(( TIME_DIFF % 60 ))s"
#.............................

