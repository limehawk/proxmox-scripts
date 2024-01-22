# ...

# Import the qcow2 file to the specified storage
DISK_IMPORT_OUTPUT=$(qm importdisk "$ID" "$IMAGE_NAME" "$STORAGE_LOCATION" 2>&1)
DISK_IMPORT_SUCCESS=$?
if [[ $DISK_IMPORT_SUCCESS -ne 0 ]]; then
    echo "Error importing disk"
    echo "$DISK_IMPORT_OUTPUT"
    exit 1
fi

# Extract the disk identifier from the import output
DISK_IDENTIFIER=$(echo "$DISK_IMPORT_OUTPUT" | grep -oP 'Successfully imported disk as \'\K[^']+')

# Set VM settings
qm set "$ID" --cores "$CORES" || { echo "Error setting cores"; exit 1; }
qm set "$ID" --memory "$RAM" || { echo "Error setting memory"; exit 1; }
qm set "$ID" --net0 'virtio,bridge=vmbr0' || { echo "Error setting net0"; exit 1; }

# Attach the disk as SCSI device
qm set "$ID" --scsi0 "$DISK_IDENTIFIER" || { echo "Error attaching SCSI disk"; exit 1; }
qm set "$ID" --boot order=scsi0 || { echo "Error setting boot order"; exit 1; }
qm set "$ID" --scsihw virtio-scsi-pci || { echo "Error setting SCSI hardware"; exit 1; }
qm set "$ID" --name 'dietpi' >/dev/null

# ...

# Inform user that the virtual machine is created
echo "VM $ID Created."

# Start the virtual machine
qm start "$ID"
