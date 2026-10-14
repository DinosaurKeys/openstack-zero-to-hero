#!/usr/bin/env bash
set -euo pipefail

echo "======================================"
echo " OpenStack Lab Safe Shutdown"
echo "======================================"
echo

echo "Current OpenStack servers:"
openstack server list
echo

echo "Stopping ACTIVE virtual machines..."
for id in $(openstack server list --status ACTIVE -f value -c ID); do
    echo "Stopping VM: $id"
    openstack server stop "$id"
done

echo
echo "Waiting for VMs to stop..."
sleep 10

openstack server list
echo

echo "Shutting down node3..."
ssh openstack@192.168.0.202 'sudo shutdown -h now' || true
sleep 5

echo "Shutting down node2..."
ssh openstack@192.168.0.201 'sudo shutdown -h now' || true
sleep 5

echo "Shutting down node1..."
ssh openstack@192.168.0.200 'sudo shutdown -h now' || true

echo
echo "Shutdown commands sent to all nodes."
echo "Hermes remains running."
