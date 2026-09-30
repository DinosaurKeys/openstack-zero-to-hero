# OpenStack First Tenant Network and VM

This chapter builds the first usable OpenStack workload manually.

The goal is to understand each object instead of using `init-runonce`.

---

# 1. Lab IP Plan

Physical/home network:

```text
192.168.0.0/24

192.168.0.1        Home router / gateway
192.168.0.2-99     Home DHCP range
192.168.0.100      OpenStack internal VIP

192.168.0.150-169  OpenStack external / floating IP pool

192.168.0.200      node1
192.168.0.201      node2
192.168.0.202      node3
```

Tenant network:

```text
10.10.10.0/24
Gateway: 10.10.10.1
```

---

# 2. Prepare OpenStack CLI

Kolla virtual environment:

```bash
source ~/venvs/kolla/bin/activate
```

Set OpenStack credentials:

```bash
export OS_CLIENT_CONFIG_FILE=/etc/kolla/clouds.yaml
export OS_CLOUD=kolla-admin
```

Verify authentication without printing the token:

```bash
openstack token issue \
  -f value \
  -c expires
```

---

# 3. Check Existing Resources

```bash
openstack image list
openstack flavor list
openstack network list
openstack subnet list
openstack router list
openstack keypair list
openstack server list
```

At the beginning of this lab all of these were empty.

---

# 4. Upload CirrOS to Glance

Create a local image directory:

```bash
mkdir -p ~/images
cd ~/images
```

Download CirrOS:

```bash
curl -fLO \
  https://download.cirros-cloud.net/0.6.3/cirros-0.6.3-x86_64-disk.img
```

Verify the downloaded file:

```bash
ls -lh cirros-0.6.3-x86_64-disk.img
```

Upload the image to Glance:

```bash
openstack image create cirros-0.6.3 \
  --file cirros-0.6.3-x86_64-disk.img \
  --disk-format qcow2 \
  --container-format bare \
  --public
```

Verify:

```bash
openstack image list
openstack image show cirros-0.6.3
```

Expected important values:

```text
status       active
disk_format  qcow2
visibility   public
```

VMware comparison:

```text
Glance image ~= VM template / golden image
```

---

# 5. Create a Flavor

Create a small flavor for CirrOS:

```bash
openstack flavor create m1.cirros \
  --vcpus 1 \
  --ram 512 \
  --disk 1
```

Verify:

```bash
openstack flavor list
openstack flavor show m1.cirros
```

Resources:

```text
vCPU: 1
RAM:  512 MB
Disk: 1 GB
```

VMware comparison:

```text
Flavor ~= VM CPU/RAM/Disk hardware configuration
```

---

# 6. Verify Neutron External Bridge Mapping

Kolla configured the Neutron Open vSwitch agent with a provider bridge.

Check node1:

```bash
ssh openstack@192.168.0.200 \
  "sudo docker exec neutron_openvswitch_agent \
  grep -E '^[[:space:]]*bridge_mappings' \
  /etc/neutron/plugins/ml2/openvswitch_agent.ini"
```

Observed:

```text
bridge_mappings = physnet1:br-ex
```

Meaning:

```text
physnet1
   |
 br-ex
   |
veth-ovs
   ||
veth-host
   |
br-mgmt
   |
enp0s31f6
   |
Home LAN
```

Therefore the OpenStack external network must use:

```text
provider physical network = physnet1
```

---

# 7. Create the External Network

Create the provider network:

```bash
openstack network create public \
  --external \
  --provider-network-type flat \
  --provider-physical-network physnet1
```

Verify:

```bash
openstack network show public
```

Important values:

```text
provider:network_type      flat
provider:physical_network  physnet1
router:external            External
status                     ACTIVE
```

---

# 8. Create the External Subnet

The physical LAN is:

```text
192.168.0.0/24
```

Home router:

```text
192.168.0.1
```

Home DHCP pool:

```text
192.168.0.2-192.168.0.99
```

OpenStack external allocation pool:

```text
192.168.0.150-192.168.0.169
```

Create the subnet:

```bash
openstack subnet create public-subnet \
  --network public \
  --subnet-range 192.168.0.0/24 \
  --gateway 192.168.0.1 \
  --no-dhcp \
  --allocation-pool start=192.168.0.150,end=192.168.0.169
```

Verify:

```bash
openstack subnet show public-subnet
```

Important:

```text
enable_dhcp = False
```

Neutron DHCP is disabled on the external network because the physical home router already provides DHCP.

---

# 9. Create the Private Tenant Network

Create the network:

```bash
openstack network create private
```

Create its subnet:

```bash
openstack subnet create private-subnet \
  --network private \
  --subnet-range 10.10.10.0/24 \
  --gateway 10.10.10.1 \
  --dns-nameserver 1.1.1.1
```

DHCP remains enabled on this subnet.

Verify:

```bash
openstack network list
openstack subnet list
openstack network show private
```

Observed network:

```text
Network type:    VXLAN
VNI:             137
MTU:             1450
Physical network: None
```

The VNI is dynamically allocated and may be different if the network is recreated.

Concept:

```text
VM on node1
     |
     +------ VXLAN ------+
                         |
                    VM on node2
                         |
                    VM on node3
```

---

# 10. Create the Neutron Router

Create the router:

```bash
openstack router create lab-router
```

Attach its external gateway:

```bash
openstack router set lab-router \
  --external-gateway public
```

Attach the private subnet:

```bash
openstack router add subnet \
  lab-router private-subnet
```

Verify:

```bash
openstack router show lab-router
```

List router ports:

```bash
openstack port list \
  --router lab-router
```

Observed router addresses:

```text
Internal:
10.10.10.1

External:
192.168.0.152
```

The exact external address can change because Neutron allocates it from:

```text
192.168.0.150-192.168.0.169
```

The router external IP is NOT the VM floating IP.

It is used for the router's external connectivity and SNAT.

---

# 11. Neutron Packet Path

Current architecture:

```text
                     Internet
                        |
                 Home Router
                 192.168.0.1
                        |
                192.168.0.0/24
                        |
                     public
                        |
                     br-ex
                        |
                 Neutron Router
                 external address
                 192.168.0.152
                        |
                       SNAT
                        |
                    10.10.10.1
                        |
                  private VXLAN
                  10.10.10.0/24
                        |
                     future VM
```

Future VM outbound packet path:

```text
VM
10.10.10.x
    |
tap interface
    |
br-int
    |
qrouter
    |
SNAT
    |
br-ex
    |
veth-ovs
    ||
veth-host
    |
br-mgmt
    |
enp0s31f6
    |
192.168.0.1
    |
Internet
```

---

# 12. Inspect Neutron Namespaces

Before tenant resources existed:

```bash
ip netns list
```

returned nothing.

After creating the private network and router:

```bash
ansible network \
  -i ~/git/openstack-zero-to-hero/kolla/inventory/multinode \
  -b \
  -m shell \
  -a 'echo "===== $(hostname) ====="; ip netns list'
```

Observed on node1:

```text
qrouter-<router UUID>
qdhcp-<private network UUID>
```

Meanings:

```text
qrouter-* = Neutron router namespace

qdhcp-*   = Neutron DHCP namespace
```

The UUIDs match the corresponding OpenStack router/network objects.

Current configuration uses:

```text
DVR = disabled
L3 HA = disabled
```

Therefore the router namespace is not expected to exist simultaneously on all three nodes.

---

# 13. Important IP Roles

Do not confuse these addresses.

```text
192.168.0.200
    Physical management address of node1

192.168.0.100
    Kolla/OpenStack internal API VIP

10.10.10.x
    Future VM fixed/private IP

192.168.0.152
    Current Neutron router external/SNAT address

192.168.0.15x
    Future VM Floating IP
```

A future VM may look like:

```text
Fixed IP:
10.10.10.5

Floating IP:
192.168.0.153
```

Neutron performs NAT between them.

---

# 14. Current Build Status

Completed:

```text
Glance image ............ DONE
Flavor .................. DONE

Public network .......... DONE
Public subnet ........... DONE

Private VXLAN ........... DONE
Private subnet/DHCP ..... DONE

Neutron router .......... DONE
SNAT .................... DONE
```

Not yet completed:

```text
Security group .......... TODO
SSH keypair ............. TODO
VM ...................... TODO
Floating IP ............. TODO
Ping test ............... TODO
SSH test ................ TODO
```

---

# 15. Quick Verification Commands

Images:

```bash
openstack image list
```

Flavors:

```bash
openstack flavor list
```

Networks:

```bash
openstack network list
```

Subnets:

```bash
openstack subnet list
```

Routers:

```bash
openstack router list
openstack router show lab-router
```

Ports:

```bash
openstack port list
```

Neutron agents:

```bash
openstack network agent list
```

Compute services:

```bash
openstack compute service list
```

Hypervisors:

```bash
openstack hypervisor list
```

VMs:

```bash
openstack server list
```

Overall lab health:

```bash
cd ~/git/openstack-zero-to-hero
./scripts/lab-status.sh
```

---

# 16. Next Step

Next objects to create:

```text
Security Group
      |
SSH Keypair
      |
cirros-01 VM
      |
Floating IP
      |
Ping
      |
SSH
```

Do not use `init-runonce`.

The goal is to understand and manually create each OpenStack resource.

---

# 17. Create a Security Group

A security group controls what traffic is allowed to reach an OpenStack VM.

VMware mental model:

```text
OpenStack Security Group
        ~=
firewall policy applied to the VM network interface
```

Create the security group:

```bash
openstack security group create lab-sg
```

Allow ICMP/ping:

```bash
openstack security group rule create \
  --protocol icmp \
  lab-sg
```

Allow SSH on TCP port 22:

```bash
openstack security group rule create \
  --protocol tcp \
  --dst-port 22 \
  lab-sg
```

Verify:

```bash
openstack security group rule list lab-sg
```

In this lab the verified rules are:

```text
ICMP     IPv4   0.0.0.0/0   ingress
TCP      IPv4   0.0.0.0/0   22:22   ingress
Any      IPv4   0.0.0.0/0   egress
Any      IPv6   ::/0        egress
```

Meaning:

```text
Ping into VM ........ allowed
SSH into VM ......... allowed
IPv4 traffic out .... allowed
IPv6 traffic out .... allowed
```

Security groups are stateful. Return traffic for connections initiated
by the VM is automatically allowed.


---

# 18. Create an SSH Keypair

This lab uses a dedicated SSH keypair for OpenStack virtual machines.

Local files on Hermes:

```text
~/.ssh/openstack-lab-vm
    PRIVATE KEY

~/.ssh/openstack-lab-vm.pub
    PUBLIC KEY
```

The private key stays on Hermes.

The public key is registered in OpenStack as:

```text
lab-key
```

Verify the OpenStack keypair:

```bash
openstack keypair list
```

Verify the local public-key fingerprint:

```bash
ssh-keygen -E md5 -lf ~/.ssh/openstack-lab-vm.pub
```

Expected fingerprint in this lab:

```text
52:5a:cc:02:b3:89:58:47:62:23:50:5c:95:a1:e6:dd
```

The fingerprint should match the `lab-key` fingerprint shown by:

```bash
openstack keypair list
```

Do not recreate the keypair if it already exists and the fingerprint matches.

When a VM is created with:

```text
--key-name lab-key
```

OpenStack injects the public key into the guest so that the matching
private key on Hermes can be used for SSH access.


---

# 19. Boot the First VM

Create the first CirrOS instance:

```bash
openstack server create cirros-01 \
  --image cirros-0.6.3 \
  --flavor m1.cirros \
  --network private \
  --security-group lab-sg \
  --key-name lab-key \
  --wait
```

Verify:

```bash
openstack server list
```

Inspect the important fields:

```bash
openstack server show cirros-01 \
  -c status \
  -c addresses \
  -c OS-EXT-SRV-ATTR:host \
  -c flavor \
  -c image
```

Observed during this lab:

```text
VM name:       cirros-01
Status:        ACTIVE
Fixed IP:      10.10.10.205
Compute host:  node1
Image:         cirros-0.6.3
Flavor:        m1.cirros
```

Nova Scheduler selected `node1` as the physical compute host.

The address:

```text
10.10.10.205
```

is the VM fixed/private IP on the OpenStack tenant network.

It is not yet the address used to access the VM from the external
192.168.0.0/24 network.


---

# 20. Inspect the VM Neutron Port

List the Neutron port created for the VM:

```bash
openstack port list --server cirros-01
```

Observed during this lab:

```text
VM:        cirros-01
Fixed IP:  10.10.10.205
MAC:       fa:16:3e:65:33:f4
Status:    ACTIVE
```

Nova automatically creates the port when the VM is created.

The port name may initially be blank. This is not a networking problem.

The UUID is the real identity of the Neutron port.

Optionally give the port a friendly name:

```bash
openstack port set \
  --name cirros-01-port \
  <PORT-UUID>
```

Verify:

```bash
openstack port list --server cirros-01
```

The name is cosmetic and does not affect connectivity.

---

# 21. Allocate a Floating IP

The VM currently has only its fixed tenant IP:

```text
10.10.10.205
```

Allocate an external address from the `public` network:

```bash
openstack floating ip create public
```

Verify:

```bash
openstack floating ip list
```

Observed during this lab:

```text
Floating IP: 192.168.0.164
Fixed IP:    None
Port:        None
Status:      DOWN
```

At this stage the Floating IP exists but is not associated with a VM.

The exact address can be different on a rebuild because Neutron dynamically
allocates an address from:

```text
192.168.0.150-192.168.0.169
```

Do not hard-code `192.168.0.164` when rebuilding.

---

# 22. Associate the Floating IP with the VM

Associate the allocated address with `cirros-01`.

Example from this lab:

```bash
openstack server add floating ip \
  cirros-01 192.168.0.164
```

Use the actual address returned by:

```bash
openstack floating ip list
```

Verify:

```bash
openstack server list
```

Observed:

```text
cirros-01
private=10.10.10.205, 192.168.0.164
```

The relationship is:

```text
192.168.0.164
    Floating IP
        |
        | DNAT / SNAT
        |
10.10.10.205
    Fixed IP
        |
    cirros-01
```

The Floating IP is not configured directly inside the guest OS.

The guest still sees:

```text
10.10.10.205
```

on its network interface.

Neutron performs the Floating IP translation outside the guest.

---

# 23. Test Ping from Hermes

The security group `lab-sg` allows ICMP ingress.

Test:

```bash
ping -c 4 192.168.0.164
```

Observed result:

```text
4 packets transmitted
4 received
0% packet loss
```

Successful ping proves the following path works:

```text
Hermes
   |
192.168.0.164
   |
Neutron Floating IP
   |
Security Group
   |
10.10.10.205
   |
cirros-01
```

Use the actual Floating IP assigned during a rebuild.

---

# 24. SSH to the VM

CirrOS username:

```text
cirros
```

The private SSH key remains on Hermes:

```text
~/.ssh/openstack-lab-vm
```

Connect:

```bash
ssh \
  -i ~/.ssh/openstack-lab-vm \
  cirros@192.168.0.164
```

Use the actual Floating IP assigned to the VM.

On first connection SSH may ask:

```text
Are you sure you want to continue connecting?
```

After accepting the host key, a successful login gives a shell prompt:

```text
$
```

This proves:

```text
Floating IP ........ working
TCP/22 ............. allowed
Security Group ..... working
SSH key injection .. working
VM .................. reachable
```

---

# 25. Verify Networking Inside CirrOS

Inside the VM:

```bash
hostname
```

Observed:

```text
cirros-01
```

Inspect the interface:

```bash
ip addr
```

Observed:

```text
eth0
MTU 1450
MAC fa:16:3e:65:33:f4
IP 10.10.10.205/24
```

The `1450` MTU is consistent with the VXLAN tenant network.

Inspect routing:

```bash
ip route
```

Observed:

```text
default via 10.10.10.1 dev eth0
10.10.10.0/24 dev eth0
169.254.169.254 via 10.10.10.2 dev eth0
```

Important addresses:

```text
10.10.10.205
    VM fixed IP

10.10.10.1
    Neutron router / tenant gateway

169.254.169.254
    OpenStack metadata service address
```

Test the tenant gateway:

```bash
ping -c 3 10.10.10.1
```

Test Internet access:

```bash
ping -c 3 1.1.1.1
```

Both tests succeeded during this lab.

Outbound path:

```text
cirros-01
10.10.10.205
      |
10.10.10.1
Neutron Router
      |
SNAT
      |
Router external IP
      |
br-ex
      |
Home router
192.168.0.1
      |
Internet
```

Exit the VM:

```bash
exit
```

---

# 26. Final Working OpenStack VM

The first workload was successfully created and tested.

```text
Image ................. cirros-0.6.3
Flavor ................ m1.cirros

External network ...... public
External subnet ....... public-subnet

Private network ....... private
Private subnet ........ private-subnet
Tenant CIDR ........... 10.10.10.0/24

Router ................. lab-router
Tenant gateway ......... 10.10.10.1

Security Group ......... lab-sg
SSH keypair ............ lab-key

VM ..................... cirros-01
Compute host ........... node1
Fixed IP ............... 10.10.10.205
Floating IP ............ 192.168.0.164

Ping ................... PASS
SSH .................... PASS
Internet from VM ....... PASS
```

The dynamically allocated addresses and compute host may change when the
lab is rebuilt.

---

# 27. Quick Rebuild Order

Use this section as the quick command reference when rebuilding the workload
from a clean OpenStack project.

## Prepare the CLI

```bash
source ~/venvs/kolla/bin/activate

export OS_CLIENT_CONFIG_FILE=/etc/kolla/clouds.yaml
export OS_CLOUD=kolla-admin
```

## Upload CirrOS

```bash
mkdir -p ~/images
cd ~/images

curl -fLO \
  https://download.cirros-cloud.net/0.6.3/cirros-0.6.3-x86_64-disk.img

openstack image create cirros-0.6.3 \
  --file cirros-0.6.3-x86_64-disk.img \
  --disk-format qcow2 \
  --container-format bare \
  --public
```

## Create flavor

```bash
openstack flavor create m1.cirros \
  --vcpus 1 \
  --ram 512 \
  --disk 1
```

## Create external network

```bash
openstack network create public \
  --external \
  --provider-network-type flat \
  --provider-physical-network physnet1
```

```bash
openstack subnet create public-subnet \
  --network public \
  --subnet-range 192.168.0.0/24 \
  --gateway 192.168.0.1 \
  --no-dhcp \
  --allocation-pool start=192.168.0.150,end=192.168.0.169
```

## Create private tenant network

```bash
openstack network create private
```

```bash
openstack subnet create private-subnet \
  --network private \
  --subnet-range 10.10.10.0/24 \
  --gateway 10.10.10.1 \
  --dns-nameserver 1.1.1.1
```

## Create router

```bash
openstack router create lab-router
```

```bash
openstack router set lab-router \
  --external-gateway public
```

```bash
openstack router add subnet \
  lab-router private-subnet
```

## Create security group

```bash
openstack security group create lab-sg
```

```bash
openstack security group rule create \
  --protocol icmp \
  lab-sg
```

```bash
openstack security group rule create \
  --protocol tcp \
  --dst-port 22 \
  lab-sg
```

## Create VM SSH key

Only create a new key if it does not already exist.

```bash
ssh-keygen \
  -t ed25519 \
  -f ~/.ssh/openstack-lab-vm \
  -N '' \
  -C 'openstack-lab-vm'
```

Register its public key:

```bash
openstack keypair create \
  --public-key ~/.ssh/openstack-lab-vm.pub \
  lab-key
```

## Boot VM

```bash
openstack server create cirros-01 \
  --image cirros-0.6.3 \
  --flavor m1.cirros \
  --network private \
  --security-group lab-sg \
  --key-name lab-key \
  --wait
```

Verify:

```bash
openstack server list
```

## Allocate Floating IP

```bash
openstack floating ip create public
```

Find the allocated address:

```bash
openstack floating ip list
```

Associate the actual allocated address:

```bash
openstack server add floating ip \
  cirros-01 <FLOATING-IP>
```

## Test

```bash
ping -c 4 <FLOATING-IP>
```

```bash
ssh \
  -i ~/.ssh/openstack-lab-vm \
  cirros@<FLOATING-IP>
```

Inside the VM:

```bash
hostname
ip addr
ip route
ping -c 3 10.10.10.1
ping -c 3 1.1.1.1
```

If all tests pass:

```text
FIRST OPENSTACK WORKLOAD: SUCCESS
```

