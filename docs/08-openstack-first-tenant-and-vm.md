# OpenStack First Tenant Network and VM

This chapter builds and validates the first usable OpenStack workload manually with the OpenStack CLI.

The goal is to understand each OpenStack object before automating the same concepts with Terraform.

Do not use `init-runonce` for this learning exercise.

This chapter records the original manual workload:

```text
cirros-01
```

The current physical OpenStack network uses the dual-NIC design documented in:

```text
docs/17-openstack-dual-nic-networking.md
```

---

# 1. Lab IP Plan

Physical/home network:

```text
192.168.0.0/24

192.168.0.1        Home router / gateway
192.168.0.2-99     Home DHCP range
192.168.0.100      OpenStack internal API VIP

192.168.0.150-169  OpenStack external / Floating IP pool

192.168.0.200      node1
192.168.0.201      node2
192.168.0.202      node3
```

Manual tenant network used in this chapter:

```text
10.10.10.0/24
Gateway: 10.10.10.1
```

---

# 2. Prepare the OpenStack CLI

Activate the Kolla virtual environment on Hermes:

```bash
source ~/venvs/kolla/bin/activate
```

For administrative setup tasks in this chapter, select the Kolla admin cloud for the current shell session:

```bash
export OS_CLIENT_CONFIG_FILE=/etc/kolla/clouds.yaml
export OS_CLOUD=kolla-admin
```

Verify authentication without printing the token value:

```bash
openstack token issue \
  -f value \
  -c expires
```

Confirm which cloud profile is active:

```bash
echo "$OS_CLIENT_CONFIG_FILE"
echo "$OS_CLOUD"
```

Expected for this administrative exercise:

```text
/etc/kolla/clouds.yaml
kolla-admin
```

Important:

```text
kolla-admin
```

is an administrator identity.

Do not embed it inside Terraform files intended for Hermes or AI-assisted workloads.

Do not treat an administrator cloud profile as the default identity for every future automation task.

For the later Hermes workflow, the repository uses a restricted OpenStack identity and selects credentials at execution time.

---

# 3. Check Existing Resources

Useful inventory commands:

```bash
openstack image list
openstack flavor list
openstack network list
openstack subnet list
openstack router list
openstack keypair list
openstack server list
```

During the original first-workload exercise, the required resources were created manually so that each object could be understood.

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

Upload it to Glance:

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

Important values:

```text
status       active
disk_format  qcow2
visibility   public
```

VMware mental model:

```text
Glance image
    ~
VM template / golden image
```

---

# 5. Create a Flavor

Create a small CirrOS flavor:

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

VMware mental model:

```text
Flavor
    ~
VM CPU / RAM / disk hardware profile
```

---

# 6. Verify the Neutron Provider Bridge Mapping

Kolla configured the Neutron Open vSwitch agent with a provider bridge mapping.

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
 ext0
   |
physical LAN
```

Therefore the OpenStack external network uses:

```text
provider physical network = physnet1
```

The original single-NIC path using `veth-ovs` is preserved in Chapter 03 but is no longer the current external uplink.

---

# 7. Verify br-ex Uses ext0

On a node:

```bash
ssh openstack@192.168.0.200 \
  "sudo docker exec openvswitch_vswitchd \
  ovs-vsctl list-ports br-ex"
```

Current expected ports include:

```text
ext0
phy-br-ex
```

The important physical uplink is:

```text
ext0
```

Current external path:

```text
Neutron
   |
br-ex
   |
ext0
   |
physical LAN
```

---

# 8. Create the External Network

Create the flat provider network:

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

# 9. Create the External Subnet

Physical LAN:

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

Reserved OpenStack external allocation pool:

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

Neutron DHCP is disabled on the external network because the physical home router already provides DHCP for the normal LAN.

The OpenStack allocation pool is deliberately outside the normal home DHCP range.

---

# 10. Create the Private Tenant Network

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

DHCP remains enabled on this tenant subnet.

Verify:

```bash
openstack network list
openstack subnet list
openstack network show private
```

During the original exercise the network was observed as:

```text
Network type:     VXLAN
VNI:              137
MTU:              1450
Physical network: None
```

The VNI is dynamically allocated and can change when the network is recreated.

Conceptually:

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

# 11. Create the Neutron Router

Create the router:

```bash
openstack router create lab-router
```

Set its external gateway:

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

List its ports:

```bash
openstack port list \
  --router lab-router
```

During the original exercise the router used:

```text
Internal:
10.10.10.1

External:
192.168.0.152
```

The exact external address is dynamic and can change because it is allocated from:

```text
192.168.0.150-192.168.0.169
```

The router external/SNAT address is not the same thing as a VM Floating IP.

---

# 12. Current Neutron Packet Path

Simplified topology:

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
                      ext0
                        |
                 physical LAN
```

For an outbound VM packet:

```text
VM
10.10.10.x
    |
Neutron port
    |
br-int
    |
qrouter
    |
SNAT
    |
br-ex
    |
ext0
    |
physical LAN
    |
192.168.0.1
    |
Internet
```

The detailed path is covered in:

```text
docs/05-neutron-packet-walk.md
```

---

# 13. Inspect Neutron Namespaces

On a node:

```bash
sudo ip netns
```

A router host may contain namespaces resembling:

```text
qrouter-<router UUID>
qdhcp-<network UUID>
```

Meanings:

```text
qrouter-*
    Neutron router namespace

qdhcp-*
    Neutron DHCP namespace
```

To find which L3 agent hosts a router, use Hermes:

```bash
openstack network agent list \
  --router lab-router
```

Then inspect that physical node.

Do not assume every router namespace must exist on every node.

Router placement depends on the actual Neutron configuration.

---

# 14. Important IP Roles

Do not confuse these addresses:

```text
192.168.0.200
    physical management address of node1

192.168.0.100
    Kolla/OpenStack internal API VIP

10.10.10.x
    VM fixed/private IP

192.168.0.152
    historical router external/SNAT address from this exercise

192.168.0.150-169
    external/Floating IP allocation pool
```

The original manual VM eventually used:

```text
Fixed IP:
10.10.10.205

Floating IP:
192.168.0.164
```

Those dynamically allocated addresses are historical observations, not rebuild requirements.

---

# 15. Create a Security Group

Create:

```bash
openstack security group create lab-sg
```

Allow ICMP:

```bash
openstack security group rule create \
  --protocol icmp \
  lab-sg
```

Allow SSH:

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

The intended behavior is:

```text
Ping into VM ........ allowed
SSH into VM ......... allowed
IPv4 traffic out .... allowed
IPv6 traffic out .... allowed
```

Security groups are stateful.

Return traffic for an allowed or VM-initiated connection is handled automatically.

---

# 16. Create a Dedicated VM SSH Key

Do not reuse the physical-node administration key for guest VMs.

This lab uses:

```text
~/.ssh/openstack-lab-vm
    private key

~/.ssh/openstack-lab-vm.pub
    public key
```

The two purposes are separate:

```text
Hermes
   |
   | physical-host administration key
   v
node1 / node2 / node3
```

and:

```text
Hermes
   |
   | openstack-lab-vm private key
   v
OpenStack guest VM
```

Check whether the files already exist:

```bash
ls -l \
  ~/.ssh/openstack-lab-vm \
  ~/.ssh/openstack-lab-vm.pub
```

If they do not exist:

```bash
ssh-keygen \
  -t ed25519 \
  -f ~/.ssh/openstack-lab-vm \
  -N '' \
  -C 'openstack-lab-vm'
```

The public key can be inspected:

```bash
cat ~/.ssh/openstack-lab-vm.pub
```

Do not print, copy, or commit the private key.

---

# 17. Register the Public Key in OpenStack

Check existing keypairs:

```bash
openstack keypair list
```

The manual workload uses:

```text
lab-key
```

If it does not exist:

```bash
openstack keypair create \
  --public-key ~/.ssh/openstack-lab-vm.pub \
  lab-key
```

Verify:

```bash
openstack keypair show lab-key
```

The private key never goes into OpenStack.

Only the public key is registered.

Conceptually:

```text
Hermes private key
      |
      | proves identity
      v
guest VM
      |
      | contains matching public key
      v
SSH login
```

---

# 18. Boot the First VM

Create the instance:

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

Inspect important fields:

```bash
openstack server show cirros-01 \
  -c status \
  -c addresses \
  -c OS-EXT-SRV-ATTR:host \
  -c flavor \
  -c image
```

Historical observation from the original exercise:

```text
VM name:       cirros-01
Status:        ACTIVE
Fixed IP:      10.10.10.205
Compute host:  node1
Image:         cirros-0.6.3
Flavor:        m1.cirros
```

Nova Scheduler selected node1 at that time.

The selected host and dynamically assigned IP may differ after a rebuild.

---

# 19. Inspect the VM Neutron Port

List the port:

```bash
openstack port list --server cirros-01
```

Historical observation:

```text
Fixed IP:
10.10.10.205

MAC:
fa:16:3e:65:33:f4

Status:
ACTIVE
```

Nova automatically creates the Neutron port when the VM is created with a network.

The port UUID is the important identity.

A friendly port name is optional.

---

# 20. Allocate a Floating IP

Allocate an address:

```bash
openstack floating ip create public
```

Verify:

```bash
openstack floating ip list
```

Before association, the new address may show:

```text
Fixed IP: None
Port:     None
Status:   DOWN
```

The exact Floating IP is dynamically allocated from:

```text
192.168.0.150-192.168.0.169
```

Do not hard-code the historical value when rebuilding.

---

# 21. Associate the Floating IP

Use the actual allocated address:

```bash
openstack server add floating ip \
  cirros-01 <FLOATING-IP>
```

Verify:

```bash
openstack server list
```

The original manual workload used:

```text
Fixed IP:
10.10.10.205

Floating IP:
192.168.0.164
```

Conceptually:

```text
192.168.0.164
    Floating IP
        |
        | Neutron NAT
        v
10.10.10.205
    Fixed IP
        |
        v
cirros-01
```

The Floating IP is not configured directly inside the guest OS.

The guest still sees its fixed tenant address.

---

# 22. Test Ping From Hermes

Use the actual Floating IP:

```bash
ping -c 4 <FLOATING-IP>
```

The original `cirros-01` exercise succeeded with:

```text
4 packets transmitted
4 received
0% packet loss
```

A successful ping validates a path resembling:

```text
Hermes
   |
Floating IP
   |
ext0
   |
br-ex
   |
Neutron router / NAT
   |
security group
   |
fixed IP
   |
VM
```

---

# 23. SSH to the VM

CirrOS user:

```text
cirros
```

Connect:

```bash
ssh \
  -i ~/.ssh/openstack-lab-vm \
  cirros@<FLOATING-IP>
```

Successful SSH proves:

```text
Floating IP ........ working
TCP/22 ............. allowed
Security Group ..... working
SSH key injection .. working
VM .................. reachable
```

The guest private key remains only on Hermes.

---

# 24. Verify Networking Inside CirrOS

Inside the VM:

```bash
hostname
```

Inspect addressing:

```bash
ip addr
```

Inspect routing:

```bash
ip route
```

During the original exercise, the VM had:

```text
eth0
MTU 1450
IP 10.10.10.205/24
```

and routes similar to:

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
    tenant gateway / Neutron router

169.254.169.254
    metadata service address
```

Test the gateway:

```bash
ping -c 3 10.10.10.1
```

Test external connectivity:

```bash
ping -c 3 1.1.1.1
```

Both succeeded during the original exercise.

---

# 25. Current Physical External Path

The current external packet path is:

```text
VM
 |
Neutron port
 |
br-int
 |
Neutron router
 |
br-ex
 |
ext0
 |
physical LAN
 |
192.168.0.1
 |
Internet
```

This differs from the original single-NIC learning stage.

The old path:

```text
br-ex
 |
veth-ovs
 |
veth-host
 |
br-mgmt
```

is historical and documented in Chapter 03.

---

# 26. First Manual Workload Result

The original manual workload completed successfully.

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

The dynamically allocated addresses and compute host are observations from that run.

They may change when the workload is recreated.

---

# 27. Quick Rebuild Order

This is the compact manual rebuild reference.

## Prepare CLI

```bash
source ~/venvs/kolla/bin/activate

export OS_CLIENT_CONFIG_FILE=/etc/kolla/clouds.yaml
export OS_CLOUD=kolla-admin
```

Use the admin identity only for this deliberate administrative exercise.

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

## Create private network

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

## Create or reuse guest SSH key

Check local files:

```bash
ls -l \
  ~/.ssh/openstack-lab-vm \
  ~/.ssh/openstack-lab-vm.pub
```

If missing:

```bash
ssh-keygen \
  -t ed25519 \
  -f ~/.ssh/openstack-lab-vm \
  -N '' \
  -C 'openstack-lab-vm'
```

Check OpenStack:

```bash
openstack keypair list
```

If `lab-key` is missing:

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

## Allocate Floating IP

```bash
openstack floating ip create public
```

Find it:

```bash
openstack floating ip list
```

Associate it:

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

---

# 28. Manual CLI vs Terraform

This chapter intentionally uses the OpenStack CLI.

Chapter 10 automates the same kinds of resources using Terraform.

The learning relationship is:

```text
Chapter 08
manual OpenStack CLI
        |
        v
understand each object
        |
        v
Chapter 10
Terraform Infrastructure as Code
```

A simplified comparison:

| OpenStack Concept | Manual CLI | Terraform |
| --- | --- | --- |
| Existing public network | `openstack network show public` | `data.openstack_networking_network_v2.public` |
| Private network | `openstack network create private` | `openstack_networking_network_v2.private` |
| Private subnet | `openstack subnet create ...` | `openstack_networking_subnet_v2.private` |
| Router | `openstack router create ...` | `openstack_networking_router_v2.router` |
| Router interface | `openstack router add subnet ...` | `openstack_networking_router_interface_v2.private` |
| Security group | `openstack security group create ...` | `openstack_networking_secgroup_v2.vm` |
| Security rules | CLI rule commands | `openstack_networking_secgroup_rule_v2` |
| SSH keypair | `openstack keypair create ...` | `openstack_compute_keypair_v2.vm` |
| VM | `openstack server create ...` | `openstack_compute_instance_v2.vm` |
| Floating IP | CLI allocation/association | Terraform Floating-IP resources |

---

# 29. Shared Infrastructure vs Workload Infrastructure

A very important Terraform lesson comes directly from this chapter.

The shared external network:

```text
public
```

belongs to the OpenStack foundation.

A workload should generally **use** it rather than recreate or destroy it.

Terraform can therefore look up existing infrastructure:

```hcl
data "openstack_networking_network_v2" "public" {
  name = "public"
}
```

Then Terraform owns only workload-specific resources.

Memory:

```text
data
    LOOK UP existing infrastructure

resource
    CREATE / MANAGE infrastructure
```

This ownership boundary is extremely important when AI-assisted IaC is introduced later.

---

# 30. Administrative Infrastructure vs Tenant Workloads

This chapter mixes two learning responsibilities because it starts from a nearly empty cloud:

```text
administrator setup
    image
    flavor
    provider network

workload setup
    private network
    router
    security group
    keypair
    VM
    Floating IP
```

In a more mature environment these responsibilities should be separated.

A safer long-term model is:

```text
OpenStack foundation/admin
    manages shared provider infrastructure

Terraform workload
    consumes shared infrastructure

Hermes
    modifies workload IaC under restricted credentials
```

This separation prevents an AI workload assistant from casually owning shared cloud infrastructure.

---

# 31. Useful Verification Commands

```bash
openstack image list
```

```bash
openstack flavor list
```

```bash
openstack network list
```

```bash
openstack subnet list
```

```bash
openstack router list
```

```bash
openstack port list
```

```bash
openstack network agent list
```

```bash
openstack compute service list
```

```bash
openstack hypervisor list
```

```bash
openstack server list --all-projects
```

Overall lab health:

```bash
cd ~/git/openstack-zero-to-hero
./scripts/lab-status.sh
```

The normal healthy target is:

```text
RESULT: HEALTHY
PASS checks: 14
```

---

# 32. Current Lab Context

The original manual workload:

```text
cirros-01
```

is only one of several workloads that have existed in the lab.

The repository later added Terraform-managed workloads and the restricted AI lab.

The important purpose of this chapter is not the specific VM name.

It is the manual sequence:

```text
image
  ↓
flavor
  ↓
external network
  ↓
private network
  ↓
router
  ↓
security group
  ↓
keypair
  ↓
VM
  ↓
Floating IP
  ↓
connectivity validation
```

That sequence makes the Terraform resources in later chapters much easier to understand.

---

# 33. Final Memory Hook

```text
Glance
    IMAGE

Flavor
    VM SIZE

Neutron network
    L2 NETWORK

Subnet
    IP RANGE

Router
    L3 CONNECTIVITY

Security Group
    FIREWALL POLICY

Keypair
    SSH PUBLIC KEY

Nova instance
    VM

Floating IP
    EXTERNAL NAT ADDRESS
```

And the current external path is:

```text
VM
 |
Neutron
 |
br-ex
 |
ext0
 |
physical LAN
```

That is the foundation Chapter 10 later converts into Terraform.

