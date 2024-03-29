#!/bin/bash
# Script for terminating EC2 instances part of K8s cluster provided in a input file. Assumed here that the K8s cluster has a ASG association that will spin up new nodes.

# Check if input file, profile, kubeconfig path & node count difference values are provided
if [ $# -ne 4 ]; then
  echo "Usage: $0 <file> <profile> <kubeconfig_path> <node_count_diff>"
  exit 1
fi

file=$1              # List of instances provided in a input file
profile=$2           # Profile associated with the instance's AWS account and region
kubeconfig_path=$3   # Kubeconfig path for the cluster whose worker instances are in input file
node_count_diff=$4   # Node count difference

export AWS_SHARED_CREDENTIALS_FILE="aws_creds.ini"
export KUBECONFIG=$kubeconfig_path

# Check if any non-cluster nodes or master nodes are present in the input file
cluster_nodes=$(/usr/bin/kubectl --kubeconfig=$KUBECONFIG get nodes -o=json | jq -r '.items[] | .metadata.name')
master_nodes=$(/usr/bin/kubectl --kubeconfig=$KUBECONFIG get nodes -o=json | jq -r '.items[] | select(.metadata.labels["node-role.kubernetes.io/master"] != null) | .metadata.name')
while IFS= read -r node; do
  if ! echo "$cluster_nodes" | grep -q "$node"; then
    echo "Node $node is NOT part of the cluster. Exiting script."
    exit 1
  fi

  if echo "$master_nodes" | grep -q "$node"; then
    echo "Input file contains a master node: $node. Please remove master node entry. Exiting script."
    exit 1
  fi
done < "$file"

# Setting the expected minimum node count for the cluster
num_lines=$(wc -l < "$file")
expected_min_nodes=$((num_lines - $node_count_diff))
echo "Expected mininum nodes in cluster is $expected_min_nodes."
echo

# Loop over each node in the cluster
while IFS= read -r node; do
  echo "---"
  echo "Starting termination for Node: $node."
  # Cordon and Drain the node
  /usr/bin/kubectl --kubeconfig=$KUBECONFIG cordon $node
  /usr/bin/kubectl --kubeconfig=$KUBECONFIG drain $node --delete-emptydir-data --ignore-daemonsets

  # Get Instance ID based on node name
  instance_id=$(aws --profile $profile ec2 describe-instances --filters "Name=private-dns-name,Values=$node" --query 'Reservations[*].Instances[*].InstanceId' --output text)

  if [ -z "$instance_id" ]; then
    echo "Instance ID not found for node: $node." >> instance-not-found
    echo
    continue
  fi

  # Terminating the node instance
  echo
  echo "Terminating EC2 instance: $instance_id for $node"
  aws --profile $profile ec2 terminate-instances --instance-ids $instance_id
  # Check the return code of the terminate command
  if [ $? -eq 0 ]; then
    echo "Termination for $instance_id successful."
    echo
    sleep 360
  else
    echo "Termination failed for $instance_id." >> reboot-fail
    echo
    # Check if the current worker node count is not less than the expected minimum
    current_node_count=$(/usr/bin/kubectl --kubeconfig=$KUBECONFIG get nodes -o=json | jq '.items[] | select(.metadata.labels["node-role.kubernetes.io/worker"] != null) | .metadata.name' | jq -s 'length')
    if [ $current_nodes -lt $expected_min_nodes ]; then
      echo "Node count is less than expected minimum $expected_min_nodes. Stopping script."
      exit 1
    else
      echo "Node count is not less than $expected_min_nodes from the provided input file. Moving to the next node."
      echo
    fi
  fi
done < "$file"
