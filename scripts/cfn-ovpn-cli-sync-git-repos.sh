#!/bin/bash -e
# debug options include -v -x
# cfn-ovpn-cli-sync-git-repos.sh
# sync to multiple git remotes, namely: github & codecommit
# A script to reconfigure the git remotes to push to multiple git repositories.

#-----------------------------
# Request Named Profile
AWS_PROFILE="default"
while true
do
  # -e : stdin from terminal
  # -r : backslash not an escape character
  # -p : prompt on stderr
  # -i : use default buffer val
  read -er -i "$AWS_PROFILE" -p "Enter Project AWS CLI Named Profile ...........: " USER_INPUT
  if aws configure list-profiles 2>/dev/null | grep -qw -- "$USER_INPUT"
  then
    echo "Project AWS CLI Named Profile is valid ........: $USER_INPUT"
    AWS_PROFILE=$USER_INPUT
    break
  else
    echo "Error! Project AWS CLI Named Profile invalid ..: $USER_INPUT"
  fi
done
#.............................

#-----------------------------
# Request Region
AWS_REGION=$(aws configure get region --profile "$AWS_PROFILE")
while true
do
  # -e : stdin from terminal
  # -r : backslash not an escape character
  # -p : prompt on stderr
  # -i : use default buffer val
  read -er -i "$AWS_REGION" -p "Enter Project AWS CLI Region ..................: " USER_INPUT
  if aws ec2 describe-regions --profile "$AWS_PROFILE" --query 'Regions[].RegionName' \
    --output text 2>/dev/null | grep -qw -- "$USER_INPUT"
  then
    echo "Project AWS CLI Region is valid ...............: $USER_INPUT"
    AWS_REGION=$USER_INPUT
    break
  else
    echo "Error! Project AWS CLI Region is invalid ......: $USER_INPUT"
  fi
done
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
  read -er -i "$PROJECT_NAME" -p "Enter the Name of this Project ................: " USER_INPUT
  if [[ "${USER_INPUT:=$PROJECT_NAME}" =~ (^[a-z0-9]([a-z0-9-]*(\.[a-z0-9])?)*$) ]]
  then
    echo "Project Name is valid .........................: $USER_INPUT"
    PROJECT_NAME=$USER_INPUT
    # Doc Store for this project
    PROJECT_BUCKET="proj-${PROJECT_NAME}"
    break
  else
    echo "Error! Project Name must be S3 Compatible .....: $USER_INPUT"
  fi
done
#.............................

#-----------------------------
# Request ECR description
REPO_DESCRIPTION=\
"A hardened, fault-tolerant and highly-available, multi-client, dual-protocol, \
Cloud-based VPN appliance, accompanied by an isolated Public Key Infrastructure \
framework, orchestrated in Cloudformation via the AWS Command Line Interface."
while true
do
  # -e : stdin from terminal
  # -r : backslash not an escape character
  # -p : prompt on stderr
  # -i : use default buffer val
  read -er -i "$REPO_DESCRIPTION" -p "Enter the description here ....................: " USER_INPUT
  if [[ "${USER_INPUT:=$REPO_DESCRIPTION}" =~ (^[a-zA-Z0-9(). -:\']*$) ]]
  then
    echo "Check Valid Comment ...........................: PASS"
    REPO_DESCRIPTION=$USER_INPUT
    break
  else
    echo "Check Valid Comment ...........................: FAIL"
  fi
done
#.............................


#-----------------------------
# Create a mirror repository in AWS CodeCommit and configure to push origin.
cd ..
REPO_GIT=$(git config --get remote.origin.url)

echo "REPO_GIT: $REPO_GIT"


REPO_NAME=$(echo "$REPO_GIT" | grep -o -P '(?<=git@github.com:cloudemprise/).*(?=.git)')

#echo "REPO_NAME: $REPO_NAME"

git remote rm origin

git remote add origin "$REPO_GIT"

git remote set-url --add --push origin "$REPO_GIT"

REPO_AWS=$(aws codecommit create-repository --repository-name "$REPO_NAME" \
  --output text --profile "$AWS_PROFILE" --region "$AWS_REGION" \
  --repository-description "$REPO_DESCRIPTION" \
  --query "repositoryMetadata.cloneUrlSsh"  \
  --tags Function="maintenance",Project="setup",Reference="script")

#echo "REPO_AWS: $REPO_AWS"

git remote set-url --add --push origin "$REPO_AWS"

git push --set-upstream origin main
#.............................

