#!/bin/bash

#This is a VERY basic script designed to speed up encryption and adding of drives to ScaleIO
#IMPORTANT the device MUST be removed from ScaleIO first using the ScaleIO UI, currently the script will exit if it finds the device already in ScaleIO before it tries to encrypt it

# Expected Parameters
# i = IP Address of the node to encrypt
# p = Storage pool to add the encrypted disks to
# d = List of drives to encrypt

#Example Usage:
#./cloudlinkenc.sh -i 192.168.1.32 -p SP1 -d sdb sdc sdd 

#Edit the variables below to set the CloudLink Center IP and/or modify any other settings

#Variables

#CloudLink Center IP (You only need 1 even for a cluster)
CLOUDLINKC="10.180.1.50"

#ScaleIO scli login details
SCLI_USERNAME="admin"
SCLI_PASSWORD="VMwar3123"


#SDS Login for root access to the SDS node for agent installation and disk encryption
SDS_USERNAME="root"

#--------------------------------------------------------------------------------------------------



#Check arguments contain all  items
if [[ $# < 6 ]] ; then
    echo 'Missing arguments, please re-run setting the IP, Storage Pool and Devices to encrypt'
    echo 'Example: cloudlink_singlenode.sh -i 192.168.10.32 -p SSDPoo1 -d sdb sdc sdd sde sdf sdg'
    exit 1
fi

#Set expected path (This should always be /dev/ )
PREFIX="/dev/"


#Setting arguments and display the results
IP_ADDRESS=$2
POOL=$4
echo ""
echo "Node IP is set to $IP_ADDRESS"
echo ""
echo "Using Storage Pool $POOL"
echo ""
echo "List of devices to encrypt and add to ScaleIO:"

#Get array of devices with the full path to encrypt using PREFIX variable above
DISKS=()
for DISK_LIST in "${@:6}"
do
    DISKS=(${DISKS[@]} $PREFIX$DISK_LIST)
    echo $DISK_LIST
done 



#Quick check to see if the device is there by confirming we can't clear any errors (Need to improve this)
echo "Logging into ScaleIO MDM"
echo ""
scli --login --username $SCLI_USERNAME --password $SCLI_PASSWORD
for x in "${DISKS[@]}"
do
    echo "Checking to see if $x is part of ScaleIO"
    scli --clear_sds_device_error --sds_ip $IP_ADDRESS --device_path $x --storage_pool_name $POOL 2> /dev/null
    if [ $? -eq 0 ]; then
        echo "Found a device that may be part of ScaleIO already, exiting"
        exit 1
    fi
done

echo "Devices not found in ScaleIO, continuing..."
echo ""
echo "Remoting into $IP_ADDRESS please enter the password if prompted..."
echo ""

#Remoting into node, installing agent and triggering encryption of disks

DISKS_definition=$(typeset -p DISKS)
ssh $SDS_USERNAME@$IP_ADDRESS << EOF
$DISKS_definition
if hash svm 2>/dev/null; then
        echo "CloudLink agent already installed, skipping installation"
    else
        echo "Downloading and installing the CloudLink agent"
        curl -O http://$CLOUDLINKC/cloudlink/securevm
        sleep 1
        sh securevm -S $CLOUDLINKC 
        sleep 2
fi
for x in "\${DISKS[@]}"
do
    svm encrypt "\$x"
    sleep 2
done
svm status 
EOF

echo ""
#Add the devices back to the ScaleIO pool using the new path
echo "Logging into ScaleIO MDM to add the encrypted devices"
echo ""
scli --login --username $SCLI_USERNAME --password $SCLI_PASSWORD
echo ""
for DISK_LIST in "${@:6}"
do
    ENC_PATH="/dev/mapper/svm_"$DISK_LIST
    echo "Adding new encrypted disk $ENC_PATH"
    echo "Waiting for disk to be ready and adding to ScaleIO..."
    echo ""
    #For each disk, following encrpytion the script will wait for 10 seconds for the system to detect the new drive path before disks are added to ScaleIO. 
    sleep 10
    scli --add_sds_device --sds_ip $IP_ADDRESS --device_path $ENC_PATH --device_name $ENC_PATH --storage_pool_name $POOL
done
