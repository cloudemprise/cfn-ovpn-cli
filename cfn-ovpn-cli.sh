#!/bin/bash -e
# debug options include -v -x
# cfn-ovpn-cli.sh 
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
# Request Project Name
PROJECT_NAME="cfn-ovpn-cli"
while true
do
  # -e : stdin from terminal
  # -r : backslash not an escape character
  # -p : prompt on stderr
  # -i : use default buffer val
  read -er -i "$PROJECT_NAME" -p "Enter Openvpn Infrastructure Project Name .....: " USER_INPUT
  if [[ "${USER_INPUT:=$PROJECT_NAME}" =~ (^[a-z0-9]([a-z0-9-]*(\.[a-z0-9])?)*$) ]]
  then
    echo "Project Name is valid .........................: $USER_INPUT"
    PROJECT_NAME=$USER_INPUT
    # S3 Bucket Document Store for this project
    PROJECT_BUCKET="s3://${PROJECT_NAME}"
    break
  else
    echo "Error! Project Name must be S3 Compatible .....: $USER_INPUT"
  fi
done
#.............................

#-----------------------------
# Get Route 53 Domain hosted zone ID
AWS_DOMAIN_NAME="cloudemprise.net"
echo "The IP Domain Name ............................: $AWS_DOMAIN_NAME"
echo "The Openvpn Server FQDN .......................: ${PROJECT_NAME}.${AWS_DOMAIN_NAME}:1194"
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
# Request Email Address
USER_EMAIL="dh.info@posteo.net"
while true
do
  # -e : stdin from terminal
  # -r : backslash not an escape character
  # -p : prompt on stderr
  # -i : use default buffer val
  read -er -i "$USER_EMAIL" -p "Enter Email Address for SNS Notification ......: " USER_INPUT
  if [[ "${USER_INPUT:=$USER_EMAIL}" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}$ ]]
  then
    echo "Email address is valid ........................: $USER_INPUT"
    USER_EMAIL=$USER_INPUT
    break
  else
    echo "Error! Entered Email address is invalid .......: $USER_INPUT"
  fi
done
#.............................

#-----------------------------
# Request Cert Auth Private Key Passphrase
USER_INPUT1="false"
USER_INPUT2="true"
# Validate! While user input is different or empty...
while [[ "$USER_INPUT1" != "$USER_INPUT2" ]] || [[ "$USER_INPUT1" == '' ]] 
do
  # -s : silent mode
  # -r : backslash not an escape character
  # -e : stdin from terminal
  # -p : prompt on stderr
  read -srep "Enter PKI Cert Auth Private Key Passphrase ....: " USER_INPUT1
  if [[ -z "$USER_INPUT1" ]]; then
    printf '\n%s\n' "Error. No Input Entered !"
    continue
  else
    read -srep $'\nRepeat PKI Cert Auth Private Key Passphrase ...: ' USER_INPUT2
    if [[ "$USER_INPUT1" != "$USER_INPUT2" ]]; then
      printf '\n%s\n' "Error. Passphrase Mismatch !"
    else
      printf '\n%s\n' "Passphrase Match....... Continue ..............:"
      CERT_AUTH_PASS="$USER_INPUT2"
    fi
  fi
done
# Store Passphrase in SSM Parameter Store
CERT_AUTH_PASS_NAME="/${PROJECT_NAME}/pki-cert-auth"
echo "Adding Passphrase to AWS Parameter Store ......: $CERT_AUTH_PASS_NAME"
aws ssm put-parameter --name "$CERT_AUTH_PASS_NAME" --value "$CERT_AUTH_PASS" \
        --type SecureString --overwrite \
        --description "Openvpn PKI Certificate Authority Private Key Passphrase" > /dev/null
#.............................

#----------------------------------------------
# Create S3 Bucket Policies from local templates
find ./policies/s3-buckets/template* -type f -print0 |
  while IFS= read -r -d '' TEMPLATE
  do
    if [[ ! -s "$TEMPLATE" ]]; then
      echo "Invalid Template Stack Policy .................: $TEMPLATE"
      exit 1
    else
      # Copy/Rename template via parameter expansion
      cp "$TEMPLATE" "${TEMPLATE//template/$PROJECT_NAME}"
      # Replace appropriate variables
      sed -i "s/ProjectName/$PROJECT_NAME/" "$_"
      sed -i "s/RootAccount/$AWS_ACC_ID/" "$_"
      sed -i "s/ScriptCallerUserId/$AWS_CLI_ID/" "$_"
      echo "Creating S3 Bucket Policy .....................: $_"
    fi
  done
#.............................

#----------------------------------------------
# Create Cloudformation Stack Policies from local templates
find ./policies/cfn-stacks/template* -type f -print0 |
  while IFS= read -r -d '' TEMPLATE
  do
    if [[ ! -s "$TEMPLATE" ]]; then
      echo "Invalid Template Stack Policy .................: $TEMPLATE"
      exit 1
    else
      # Copy/Rename template via parameter expansion
      cp "$TEMPLATE" "${TEMPLATE//template/$PROJECT_NAME}"
      echo "Creating Cloudformation Stack Policy ..........: $_"
    fi
  done
#.............................

#----------------------------------------------
# Create IAM inline Resource Policies from local templates
find ./policies/ec2-role/template* -type f -print0 |
  while IFS= read -r -d '' TEMPLATE
  do
    if [[ ! -s "$TEMPLATE" ]]; then
      echo "Invalid Template Stack Policy .................: $TEMPLATE"
      exit 1
    else
      # Copy/Rename template via parameter expansion
      cp "$TEMPLATE" "${TEMPLATE//template/$PROJECT_NAME}"
      # Replace appropriate variables
      sed -i "s/ProjectName/$PROJECT_NAME/" "$_"
      echo "Creating IAM inline Resource Policy ...........: $_"
    fi
  done
#.............................

#-----------------------------
# Stringify json Resource Inline Policies for awscli command input
ASSUME_ROLE_POLICY=$(tr -d " \t\n\r" < ./policies/ec2-role/assume-role-policy.json)
PRIV_SSM_EC2_POLICY=$(tr -d " \t\n\r" < ./policies/ec2-role/${PROJECT_NAME}-priv-ssm-access-policy.json)
PRIV_S3_EC2_POLICY=$(tr -d " \t\n\r" < ./policies/ec2-role/${PROJECT_NAME}-priv-s3-access-policy.json)
PUB_S3_EC2_POLICY=$(tr -d " \t\n\r" < ./policies/ec2-role/${PROJECT_NAME}-pub-s3-access-policy.json)
LT_S3_EC2_POLICY=$(tr -d " \t\n\r" < ./policies/ec2-role/${PROJECT_NAME}-lt-s3-access-policy.json)
# similar method using jq (preservers whitespace)
# jq '.' policy.json | jq -sR '.'

#-----------------------------
# Create EC2 Instance Profiles & IAM Role Polices for 
# Public, Private & Launch Templates
for PREFIX in PRIV PUB LT; do
  # --- Create (variable) IAM Role Name = Instance Profile Name
  declare "$PREFIX"_EC2_IAM_NAME="${PROJECT_NAME}"-"${PREFIX,,}"-iam-ec2-"${AWS_REGION}"
  VAR_NAME="$PREFIX"_EC2_IAM_NAME
  echo "Creating EC2 IAM Instance Profile .............: ${!VAR_NAME}"

  #--- Create EC2 Instance Profile
  declare "$PREFIX"_EC2_PROFILE_ID="$(aws iam create-instance-profile --output text \
      --instance-profile-name "${!VAR_NAME}"                                        \
      --query 'InstanceProfile.InstanceProfileId')"
  VAR_PROFILE_ID="$PREFIX"_EC2_PROFILE_ID
  echo "The EC2 Instance Profile userid ...............: ${!VAR_PROFILE_ID}"
  # --- Create IAM Role
  echo "Creating Complementary EC2 IAM Role ...........: ${!VAR_NAME}"
  declare "$PREFIX"_EC2_ROLE_ID="$(aws iam create-role --role-name "${!VAR_NAME}" \
      --assume-role-policy-document "$ASSUME_ROLE_POLICY"                         \
      --output text --query 'Role.RoleId')"
  VAR_ROLE_ID="$PREFIX"_EC2_ROLE_ID
  echo "The IAM Role userid ...........................: ${!VAR_ROLE_ID}"
  # --- Attaching IAM Role to Instance Profile
  aws iam add-role-to-instance-profile --instance-profile-name "${!VAR_NAME}" \
      --role-name "${!VAR_NAME}"
  echo "Attaching IAM Role to Instance Profile ........: ${!VAR_NAME}"
  # Add new json element to Project S3 Bucket Policy for EC2 RoleId
  POLICY_DOC=$(find ./policies/s3-buckets/${PROJECT_NAME}* -type f)
  jq --arg var_role_id "${!VAR_ROLE_ID}:*" '.Statement[].Condition.StringNotLike[] += [ $var_role_id ]' < "$POLICY_DOC" > "${POLICY_DOC}".tmp 
  mv "${POLICY_DOC}".tmp "$POLICY_DOC"
  # Embedd resource inline policy documents in IAM roles
  EC2_ROLE_SSM_NAME="${PROJECT_NAME}"-"${PREFIX,,}"-ec2-ssm-"${AWS_REGION}"
  EC2_ROLE_S3_NAME="${PROJECT_NAME}"-"${PREFIX,,}"-ec2-s3-"${AWS_REGION}"
  if [[ $PREFIX == "PRIV" ]]; then
      aws iam put-role-policy --role-name "${!VAR_NAME}"  \
          --policy-name "$EC2_ROLE_SSM_NAME"                 \
          --policy-document "$PRIV_SSM_EC2_POLICY"
      echo "The IAM Role is affixed with SSM Access Policy : ${EC2_ROLE_SSM_NAME}"
      # ...
      aws iam put-role-policy --role-name "${!VAR_NAME}"  \
          --policy-name "$EC2_ROLE_S3_NAME"                 \
          --policy-document "$PRIV_S3_EC2_POLICY"
      echo "The IAM Role is affixed with S3 Access Policy .: ${EC2_ROLE_S3_NAME}"
  elif [[ $PREFIX == "PUB" ]]; then
      aws iam put-role-policy --role-name "${!VAR_NAME}"  \
          --policy-name "$EC2_ROLE_S3_NAME"                 \
          --policy-document "$PUB_S3_EC2_POLICY"
      echo "The IAM Role is affixed with S3 Access Policy .: ${EC2_ROLE_S3_NAME}"
  else 
      aws iam put-role-policy --role-name "${!VAR_NAME}"  \
          --policy-name "$EC2_ROLE_S3_NAME"                 \
          --policy-document "$LT_S3_EC2_POLICY"
      echo "The IAM Role is affixed with S3 Access Policy .: ${EC2_ROLE_S3_NAME}"
  fi
done
#.............................

#-----------------------------
# Create S3 Project Bucket with Encryption & Policy
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
# Upload all created policy docs to S3
find ./policies -type f -name "${PROJECT_NAME}*.json" ! -path "*/scratch/*" -print0 |
  while IFS= read -r -d '' FILE
  do
    if [[ ! -s "$FILE" ]]; then
      echo "Invalid Template Policy Document ..............: $FILE"
      exit 1
    elif (aws s3 mv "$FILE" "$PROJECT_BUCKET${FILE#.}" > /dev/null); then
      echo "Uploading Policy Document to S3 Location ......: $PROJECT_BUCKET${FILE#.}"
    else continue
    fi
  done
#.............................

#----------------------------------------------
# Upload Cloudformation Templates to S3
find ./cfn-templates -type f -name "*.yaml" ! -path "*/scratch/*" -print0 |
  while IFS= read -r -d '' FILE
  do
    if [[ ! -s "$FILE" ]]; then
      echo "Invalid Cloudformation Template Document ......: $FILE"
      exit 1
    elif (aws s3 cp "$FILE" "$PROJECT_BUCKET${FILE#.}" > /dev/null); then
      echo "Uploading Cloudformation Template to S3 .......: $PROJECT_BUCKET${FILE#.}"
    else continue
    fi
  done
#.............................

#-----------------------------
# Upload easy-rsa pki keygen configs to S3
S3_LOCATION="$PROJECT_BUCKET/easy-rsa/cfn-ovpn-cli-vars"
if [[ $(tar -zcf - easy-rsa/cfn-ovpn-cli-vars/vars* | aws s3 cp - ${S3_LOCATION}/cfn-ovpn-cli-easyrsa-vars.tar.gz) -ne 0 ]]
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
if [[ $(tar -zcf - iptables/cfn-ovpn-cli-ec2-pub-iptables.sh  | aws s3 cp - ${S3_LOCATION}/cfn-ovpn-cli-ec2-pub-iptables.sh.tar.gz) -ne 0 ]] || \
   [[ $(tar -zcf - iptables/cfn-ovpn-cli-ec2-priv-iptables.sh | aws s3 cp - ${S3_LOCATION}/cfn-ovpn-cli-ec2-priv-iptables.sh.tar.gz) -ne 0 ]]
then
  echo "iptables Configs Failed to Uploaded to S3 .....: ${S3_LOCATION}"
  exit 1
else
  echo "iptables Configs Uploaded to S3 Location ......: ${S3_LOCATION}"
fi
#.............................

#-----------------------------
# Create client ovpn configs from template
find ./openvpn/client/ovpn/template*.ovpn -type f -print0 |
  while IFS= read -r -d '' TEMPLATE
  do
    # Copy/Rename template via parameter expansion
    cp "$TEMPLATE" "${TEMPLATE//template/$PROJECT_NAME}"
    # Update FQDN of vpn record set
    sed -i "s/ProjectName/$PROJECT_NAME/g" "$_"
    # Create archive of client configs
    tar -rf "$(dirname "$_")/${PROJECT_NAME}-client-1194.ovpn.tar" --remove-files -C "$(dirname "$_")" "$(basename "$_")"
    echo "Creating .ovpn Client Configuration File ......: $_"
  done
#.............................

#-----------------------------
#Compress & Upload openvpn server configs to S3
# Remove hierarchy from archives for more flexible extraction options.
S3_LOCATION="$PROJECT_BUCKET/openvpn"
if [[ $(tar -zcf - -C ./openvpn/server/conf/ . | aws s3 cp - ${S3_LOCATION}/server/conf/cfn-ovpn-cli-server-1194.conf.tar.gz) -ne 0 ]] || \
   [[ $(gzip -c ./openvpn/client/ovpn/*.tar | aws s3 cp - ${S3_LOCATION}/client/ovpn/cfn-ovpn-cli-client-1194.ovpn.tar.gz) -ne 0 ]]
then
  echo "Openvpn Configs Failed to Uploaded to S3 ......: ${S3_LOCATION}"
  exit 1
else
  echo "Openvpn Configs Uploaded to S3 Location .......: ${S3_LOCATION}"
  # archive no longer needed
  rm ./openvpn/client/ovpn/${PROJECT_NAME}*.tar
fi
#.............................

#-----------------------------
#Compress & Upload sshd hardening script to S3
S3_LOCATION="$PROJECT_BUCKET/ssh"
if [[ $(tar -zcf - ssh/cfn-ovpn-cli-ec2-harden-ssh.sh | aws s3 cp - ${S3_LOCATION}/cfn-ovpn-cli-ec2-harden-ssh.sh.tar.gz) -ne 0 ]]
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
echo "Cloudformation Stack Creation Initiated .......: $BUILD_COUNTER"



STACK_POLICY_URL="https://${PROJECT_NAME}.s3.eu-central-1.amazonaws.com/policies/cfn-stacks/${PROJECT_NAME}-${BUILD_COUNTER}-cfn-stack-policy.json"
TEMPLATE_URL="https://${PROJECT_NAME}.s3.eu-central-1.amazonaws.com/cfn-templates/cfn-ovpn-cli.yaml"
TIME_START_STACK=$(date +%s)
#-----------------------------
STACK_ID=$(aws cloudformation create-stack --stack-name "$STACK_NAME" --parameters  \
                ParameterKey=ProjectName,ParameterValue="$PROJECT_NAME"             \
                ParameterKey=BuildStep,ParameterValue="$BUILD_COUNTER"              \
                ParameterKey=DomainName,ParameterValue="$AWS_DOMAIN_NAME"           \
                ParameterKey=DomainHostedZoneId,ParameterValue="$HOSTED_ZONE_ID"    \
                ParameterKey=SshAccessCIDR,ParameterValue="$SSH_ACCESS_CIDR"        \
                ParameterKey=CurrentAmi,ParameterValue="$AMI_LATEST"                \
                ParameterKey=EmailAddrSNS,ParameterValue="$USER_EMAIL"              \
                --tags Key=Name,Value=openvpn-stage1                                \
                --stack-policy-url $STACK_POLICY_URL --template-url $TEMPLATE_URL   \
                --on-failure DO_NOTHING --capabilities CAPABILITY_NAMED_IAM --output text)
#-----------------------------
if [[ $? -eq 0 ]]; then
  # Wait for stack creation to complete
  echo "Cloudformation Stack Creation Process Wait.....: $BUILD_COUNTER"
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
  echo "Cloudformation Stack Create Process Complete ..: $BUILD_COUNTER"
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
echo "Cloudformation Stack Update Initiated .........: $BUILD_COUNTER"
TIME_START_STACK=$(date +%s)
#-----------------------------
aws cloudformation update-stack --stack-name "$STACK_ID" --parameters          \
      ParameterKey=BuildStep,ParameterValue="$BUILD_COUNTER"                   \
      ParameterKey=ProjectName,UsePreviousValue=true                           \
      ParameterKey=DomainName,UsePreviousValue=true                            \
      ParameterKey=DomainHostedZoneId,UsePreviousValue=true                    \
      ParameterKey=SshAccessCIDR,UsePreviousValue=true                         \
      ParameterKey=CurrentAmi,UsePreviousValue=true                            \
      ParameterKey=EmailAddrSNS,UsePreviousValue=true                          \
      --stack-policy-url $STACK_POLICY_URL --capabilities CAPABILITY_NAMED_IAM \
      --tags Key=Name,Value=openvpn-stage2 --use-previous-template > /dev/null
#-----------------------------
if [[ $? -eq 0 ]]; then
  # Wait for stack creation to complete
  echo "Cloudformation Stack Update Process Wait.......: $BUILD_COUNTER"
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
  echo "Cloudformation Stack Update Process Complete ..: $BUILD_COUNTER"
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
echo "Public Subnet EC2 Instance ID .................: $INSTANCE_ID_PUB"
INSTANCE_ID_PRIV=$(aws cloudformation describe-stacks --stack-name "$STACK_ID" --output text --query "Stacks[].Outputs[?OutputKey == 'InstanceIdPrivate'].OutputValue")
echo "Private Subnet EC2 Instance ID ................: $INSTANCE_ID_PRIV"

#-----------------------------
# Validity Check. Wait for instance status ok before moving on.
aws ec2 wait instance-status-ok --instance-ids "$INSTANCE_ID_PUB" &
P1=$!
aws ec2 wait instance-status-ok --instance-ids "$INSTANCE_ID_PRIV" &
P2=$!
wait $P1 $P2
echo "Public Subnet EC2 Instance State ..............: Ok"
echo "Private Subnet EC2 Instance State .............: Ok"
#.............................

#-----------------------------
# Create IMAGE AMIs
#AMI_IMAGE_PUB=$(aws ec2 create-image --instance-id "$INSTANCE_ID_PUB" --name $(echo "openvpn-pub-$INSTANCE_ID_PUB") --description "openvpn-pub-ami" --output text)
AMI_IMAGE_PUB=$(aws ec2 create-image --instance-id "$INSTANCE_ID_PUB" --name "${PROJECT_NAME}-openvpn-pub" --description "${PROJECT_NAME}-openvpn-pub-ami" --output text)
echo "Public Subnet EC2 AMI Creation Initiated ......: "
#AMI_IMAGE_PRIV=$(aws ec2 create-image --instance-id "$INSTANCE_ID_PRIV" --name $(echo "openvpn-priv-$INSTANCE_ID_PRIV") --description "openvpn-priv-ami" --output text)
AMI_IMAGE_PRIV=$(aws ec2 create-image --instance-id "$INSTANCE_ID_PRIV" --name "${PROJECT_NAME}-openvpn-priv" --description "${PROJECT_NAME}-openvpn-priv-ami" --output text)
echo "Private Subnet EC2 AMI Creation Initiated .....: "
#.............................

#-----------------------------
# Wait for new AMIs to become available
aws ec2 wait image-available --image-ids "$AMI_IMAGE_PUB" &
P1=$!
aws ec2 wait image-available --image-ids "$AMI_IMAGE_PRIV" &
P2=$!
wait $P1 $P2
echo "Public Subnet EC2 AMI Image is Now Available ..: $AMI_IMAGE_PUB "
echo "Private Subnet EC2 AMI Image is Now Available .: $AMI_IMAGE_PRIV"
#.............................

#-----------------------------
# Give AMIs a Name Tag
aws ec2 create-tags --resources "$AMI_IMAGE_PUB" --tags Key=Name,Value="${PROJECT_NAME}-openvpn-pub"
aws ec2 create-tags --resources "$AMI_IMAGE_PRIV" --tags Key=Name,Value="${PROJECT_NAME}-openvpn-priv"
#.............................

#-----------------------------
# Terminate the instances - no longer needed.
aws ec2 terminate-instances --instance-ids "$INSTANCE_ID_PUB" "$INSTANCE_ID_PRIV" > /dev/null
echo "$BUILD_COUNTER Instances Terminated ...................:"
#.............................



#-----------------------------
#-----------------------------
# Stage3 Stack Creation Code Block
BUILD_COUNTER="stage3"
echo "Cloudformation Stack Update Initiated .........: $BUILD_COUNTER"
TIME_START_STACK=$(date +%s)
#-----------------------------
aws cloudformation update-stack --stack-name "$STACK_ID" --parameters \
      ParameterKey=BuildStep,ParameterValue="$BUILD_COUNTER"          \
      ParameterKey=CurrentAmi,ParameterValue="$AMI_IMAGE_PUB"         \
      ParameterKey=ProjectName,UsePreviousValue=true                  \
      ParameterKey=DomainName,UsePreviousValue=true                   \
      ParameterKey=DomainHostedZoneId,UsePreviousValue=true           \
      ParameterKey=SshAccessCIDR,UsePreviousValue=true                \
      ParameterKey=EmailAddrSNS,UsePreviousValue=true                 \
      --stack-policy-url $STACK_POLICY_URL --use-previous-template    \
      --tags Key=Name,Value=openvpn-stage3 > /dev/null    
#-----------------------------
if [[ $? -eq 0 ]]; then
  # Wait for stack creation to complete
  echo "Cloudformation Stack Update Process Wait.......: $BUILD_COUNTER"
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
#.............................

#-----------------------------
# Validate stack creation has not failed
if (aws cloudformation wait stack-update-complete --stack-name "$STACK_ID")
then 
  echo "Cloudformation Stack Update Process Complete ..: $BUILD_COUNTER"
  printf 'Stack ID: \n%s\n' "$STACK_ID"
else 
  echo "Error: Stack Update Failed!"
  printf 'Stack ID: \n%s\n' "$STACK_ID"
  exit 1
fi
#.............................

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
echo "Openvpn Server EC2 Instance ID ................: $INSTANCE_ID_PRIV"
#.............................


#-----------------------------
# DOWNLOAD & PROCESS CLIENT CONFIGURATION FILES
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
    CLIENT_PREFIX=$(basename "${FILE%%-client*}")
    mkdir -p "${TMP_DIR}/client/$CLIENT_PREFIX"
    # copy crt/key/ovpn into dir
    cp ${TMP_DIR}/crt/ca.crt "$_"
    cp ${TMP_DIR}/hmac-sig.key "$_"
    cp ${TMP_DIR}/ovpn/*.ovpn "$_"
    cp ${TMP_DIR}/crt/"$CLIENT_PREFIX"*crt "$_"
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
    if [[ "$FILE" == "template-client"* ]]; then mv "$RECORD" "${RECORD//template-client/$(basename "$DIR")}"; fi
    # Insert certificates into respective sections of config files
    if [[ "$FILE" == "ca.crt" ]]; then sed -i "/<ca>/r ${RECORD}" "$DIR"/*.ovpn; fi
    if [[ "$FILE" == "hmac-sig.key" ]]; then sed -i "/<tls-crypt>/r ${RECORD}" "$DIR"/*.ovpn; fi
    if [[ "$FILE" == *"-client.crt" ]]; then sed -i "/<cert>/r ${RECORD}" "$DIR"/*.ovpn; fi
    if [[ "$FILE" == *"-client.key" ]]; then sed -i "/<key>/r ${RECORD}" "$DIR"/*.ovpn; fi
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
