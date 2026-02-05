#!/bin/bash

echo "     #############################################"
echo "     #                                           #"
echo "     #      Script powered by Chiappina.com      #"
echo "     #                                           #"
echo "     #############################################"
echo
echo "     Disclaimer: Use this script at your own risk!     "
echo "Always ensure you have proper backups before proceeding."
echo
sleep 2

#Prompt user for VMID and new size
echo "Fetching container list..."
pct list
echo
read -p "Enter the VMID of the container you want to resize: " VMID
read -p "Enter the new size (e.g., 5G): " NEW_SIZE

#Confirm with the user
echo "You have selected VMID: $VMID and new size: $NEW_SIZE"
read -p "Are you sure you want to continue? (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" ]]; then
    echo "Operation aborted."
    exit 1
fi

#Stop the container, if running
echo "Stopping container $VMID..."
pct stop "$VMID" 2>/dev/null
if [[ $? -eq 0 ]]; then
    echo "Container $VMID stopped successfully."
else
    echo "Container $VMID was not running."
fi

#Find and display the LV path
echo "Finding logical volume path for VMID $VMID..."
LV_PATH=$(lvdisplay | grep -A1 "vm-$VMID-disk-0" | grep "LV Path" | grep -v snap | awk '{print $3}')
if [[ -z "$LV_PATH" ]]; then
    echo "Failed to find LV path. Exiting."
    exit 1
fi
echo "LV Path: $LV_PATH"

#Activate the logical volume
echo "Activating logical volume $LV_PATH..."
lvchange -a y "$LV_PATH"
if [[ $? -ne 0 ]]; then
    echo "Failed to activate logical volume. Exiting."
    exit 1
fi

#Reduce the logical volume and filesystem
echo "Reducing logical volume and filesystem to $NEW_SIZE..."
lvreduce -r -L "$NEW_SIZE" "$LV_PATH"
if [[ $? -ne 0 ]]; then
    echo "Logical volume reduction failed. Exiting."
    exit 1
fi

#Deactivate the logical volume
echo "Deactivating logical volume $LV_PATH..."
lvchange -a n "$LV_PATH"
if [[ $? -ne 0 ]]; then
    echo "Failed to deactivate logical volume. Exiting."
    exit 1
fi

#Edit the container configuration
CONF_FILE="/etc/pve/lxc/$VMID.conf"
if [[ ! -f "$CONF_FILE" ]]; then
    echo "Container configuration file not found. Exiting."
    exit 1
fi

echo "Updating container configuration file $CONF_FILE..."
sed -i "s|rootfs:.*|rootfs: local-lvm:vm-$VMID-disk-0,size=$NEW_SIZE|" "$CONF_FILE"
if [[ $? -ne 0 ]]; then
    echo "Failed to update container configuration. Exiting."
    exit 1
fi

echo "Container $VMID resized successfully!"

#Confirm with the user
read -p "Do you want to start the container? (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" ]]; then
    echo "Container will not be started but the resizing process was completed successfully!"
    exit 1
fi

#Start the container
echo "Starting container $VMID..."
pct start "$VMID"
if [[ $? -ne 0 ]]; then
    echo "Failed to start container. Please check manually."
    exit 1
fi

echo "Container $VMID resized and started successfully!"
exit 0
