#!/bin/bash

# Define the URL of the 3CX SBC file
url="https://downloads-global.3cx.com/downloads/sbc/3cxsbc.zip"

# Download and execute the script
wget "$url" -O- | sudo bash

# Check if the wget command succeeded
if [ $? -ne 0 ]; then
    echo "Error: Download and execution failed."
    exit 1
fi

echo "3CX SBC installation started successfully."
