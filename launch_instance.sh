#!/usr/bin/env bash

set -euo pipefail

if ! [ -x "$(command -v aws)" ]; then
    echo 'AWS CLI is not installed and must be installed' >&2
    exit 1
fi

if ! [ -x "$(command -v jq)" ]; then
    echo 'jq command is not installed and must be installed' >&2
    exit 1
fi

# Verify that we have AWS credentials to use...
aws sts get-caller-identity

read -p "Are you sure you want to create the instance using above AWS credentials? " -n 1 -r
echo    # (optional) move to a new line
if ! [[ $REPLY =~ ^[Yy]$ ]]
then
  echo "OK, nevermind then."
  exit 0
fi

PYTHON_CMD="python"
if ! [ -x "$(command -v python)" ]; then
  if ! [ -x "$(command -v python3)" ]; then
    echo '"python" or "python3" command is not installed and must be installed' >&2
    exit 1
  fi
  PYTHON_CMD="python3"
fi

TEMPDIR="$(mktemp -d)"

USER_DATA_FILES="$TEMPDIR/user_data"
cp -r ./user_data "$USER_DATA_FILES"
echo -n "Uber Entertainment Password: "
read -s uber_password
sed -i'' "s/UBER_ENTERTAINMENT_PASSWORD/$uber_password/" "$USER_DATA_FILES/install-pa-server.sh"

USER_DATA="$TEMPDIR/user-data.txt"
USER_DATA_GZ="$USER_DATA.gz"

"$PYTHON_CMD" ./lib/generate_mime.py \
  "$USER_DATA_FILES/cloud-config.yml:text/cloud-config" \
  "$USER_DATA_FILES/install-pa-server.sh:text/x-shellscript" \
  > "$USER_DATA"

gzip -c "$USER_DATA" > "$USER_DATA_GZ"

# Ubuntu Server 18.04 LTS (HVM), SSD Volume Type - ami-04b9e92b5572fa0d1 (64-bit x86)
AMAZON_IMAGE_ID=ami-04b9e92b5572fa0d1
# c5.2xlarge is 16 vCPU / 32 Gi RAM. r5.xlarge is 4 vCPU / 32 Gi RAM
# t2.micro is extremely small and cheap and I used it to test the setup script, but the server crashes instantly on connect :-)
INSTANCE_TYPE="c5.4xlarge"
# Created using instructions at https://docs.aws.amazon.com/systems-manager/latest/userguide/setup-instance-profile.html#instance-profile-add-permissions
IAM_INSTANCE_PROFILE="Arn=arn:aws:iam::211002410956:instance-profile/AmazonSSMRoleForInstancesQuickSetup"

BLOCK_DEVICE_MAPPINGS_INITIAL_JSON="$TEMPDIR/block_device_mappings.json"
aws ec2 describe-images --image-ids ami-04b9e92b5572fa0d1 > "$BLOCK_DEVICE_MAPPINGS_INITIAL_JSON"
EBS_DEVICE_JSON="$(cat "$BLOCK_DEVICE_MAPPINGS_INITIAL_JSON" | jq '.Images[0].BlockDeviceMappings[0]')"
# Change the default 8 GiB storage to 50, so we don't fill up with logs...
BLOCK_DEVICE_MAPPINGS_FINAL_JSON="$(echo "$EBS_DEVICE_JSON" | jq '.Ebs.VolumeSize = 50' | jq ' [ . ]')"

RUN_INSTANCES_JSON="$TEMPDIR/run_instances.out.json"

aws ec2 run-instances \
  --image-id "$AMAZON_IMAGE_ID" \
  --subnet-id subnet-07ebd397f89e5a8ce \
  --block-device-mappings "$BLOCK_DEVICE_MAPPINGS_FINAL_JSON" \
  --iam-instance-profile "$IAM_INSTANCE_PROFILE" \
  --associate-public-ip-address \
  --instance-type "$INSTANCE_TYPE" \
  --user-data "fileb://$USER_DATA_GZ" > "$RUN_INSTANCES_JSON"

echo "$RUN_INSTANCES_JSON"
INSTANCE_ID="$(cat "$RUN_INSTANCES_JSON" | jq -r '.Instances[].InstanceId')"
echo "Started instance with ID: $INSTANCE_ID"
sleep 10

PUBLIC_IP_ADDRESS="$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" | jq -r '.Reservations[].Instances[].NetworkInterfaces[].Association.PublicIp')"

echo "Public IP address: $PUBLIC_IP_ADDRESS"
