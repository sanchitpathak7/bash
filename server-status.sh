#!/bin/bash

# This script checks the availability of servers provided in input file

# Check if server file is provided
if [ $# -ne 1 ]; then
  echo "Usage: $0 <server_list_file>"
  exit 1
fi

server_list_file=$1              # List of servers provided in a input file

# Check if the server list file exists
if [[ ! -ne "${server_list_file}" ]]; then
    echo "Error: Unable to open the server list file." >&2
    exit 1
fi

# Loop through each server in the file
while IFS= read -r server_address; do
    # Ping the server to check its availability
    echo "Pinging ${server_address}"
    if ping -c 2 "${server_address}" &> /dev/null; then
        echo "${server_address} is responding"
    else
        echo "${server_address} is unreachable"
    fi
done < "${server_list_file}"
