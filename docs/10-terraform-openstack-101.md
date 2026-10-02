# Terraform with OpenStack

This chapter introduces Terraform Infrastructure as Code against the
OpenStack homelab built in the previous chapters.

The initial goal is deliberately small:

```text
Terraform CLI
      ↓
OpenStack Terraform Provider
      ↓
clouds.yaml
      ↓
Keystone authentication
      ↓
OpenStack APIs
```

No OpenStack resources are created until Terraform installation,
provider initialization, and authentication have been verified.

---

# 1. Why Terraform?

The OpenStack workload in Chapter 08 was created manually using the
OpenStack CLI.

The manual workflow included:

```text
network
subnet
router
security group
keypair
VM
floating IP
```

Terraform will eventually describe the same infrastructure as code.

The target workflow is:

```text
Terraform configuration
        ↓
terraform plan
        ↓
terraform apply
        ↓
OpenStack APIs
        ↓
desired infrastructure
```

Terraform will first create a separate test workload so the manually
created Chapter 08 environment can remain untouched.

---

# 2. Where Terraform Runs

Terraform is installed on the Hermes management VM.

It is not installed on node1, node2, or node3.

The relationship is:

```text
Hermes
  |
  | Terraform
  ↓
OpenStack API VIP
192.168.0.100
  |
  ↓
Keystone / Neutron / Nova / Glance
  |
  ↓
OpenStack infrastructure
```

Terraform itself is independent of the Python virtual environment used
by Kolla-Ansible and the OpenStack CLI.

The existing Python environment remains:

```text
~/venvs/kolla
```

Terraform is installed as a normal system command.

---

# 3. Terraform and the OpenStack Provider

There are two separate components:

```text
Terraform CLI
    installed on Hermes
        |
        ↓
OpenStack Terraform Provider
    downloaded by terraform init
```

The OpenStack provider is not installed using:

```text
apt
pip
```

Terraform downloads the required provider automatically after it is
declared in the Terraform configuration.

---

# 4. Install Terraform Prerequisites

Update APT:

```bash
sudo apt update
```

Install the packages used to configure and verify the HashiCorp package
repository:

```bash
sudo apt install -y \
  ca-certificates \
  gnupg \
  software-properties-common \
  wget
```

---

# 5. Add the HashiCorp Signing Key

Download the official HashiCorp package signing key and store it as an
APT keyring:

```bash
wget -O- https://apt.releases.hashicorp.com/gpg | \
  gpg --dearmor | \
  sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
```

Verify the key:

```bash
gpg --no-default-keyring \
  --keyring /usr/share/keyrings/hashicorp-archive-keyring.gpg \
  --fingerprint
```

---

# 6. Add the HashiCorp APT Repository

Add the repository appropriate for the installed Ubuntu release:

```bash
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list
```

Refresh package information:

```bash
sudo apt update
```

---

# 7. Install Terraform

Install Terraform:

```bash
sudo apt install -y terraform
```

Verify the installed version:

```bash
terraform version
```

Verify the executable location:

```bash
which terraform
```

Expected executable location on this Ubuntu installation:

```text
/usr/bin/terraform
```

Observed in this lab:

```text
Terraform v1.16.4
Platform: linux_amd64
Executable: /usr/bin/terraform
```

---

# 8. What Comes Next

Installing Terraform does not yet give it access to OpenStack.

The next stages are:

```text
Terraform installed
        ↓
create Terraform working directory
        ↓
declare OpenStack provider
        ↓
terraform init
        ↓
provider downloaded
        ↓
authenticate using clouds.yaml
        ↓
read-only OpenStack test
        ↓
first Terraform-managed resource
```

The first Terraform interaction with OpenStack will be read-only.


---

# 9. Create the First Terraform Working Directory

Create a dedicated Terraform working directory:

```bash
mkdir -p terraform/01-first-workload
cd terraform/01-first-workload
```

The initial structure is:

```text
01-first-workload/
├── versions.tf
├── providers.tf
├── data.tf
└── outputs.tf
```

Terraform loads all `.tf` files in the directory as one configuration.

The filenames are organizational conventions for humans.

---

# 10. Terraform Configuration Files

## versions.tf

Defines the Terraform CLI and provider requirements:

```hcl
terraform {
  required_version = "~> 1.16.0"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "3.4.0"
    }
  }
}
```

## providers.tf

Configures the OpenStack provider:

```hcl
provider "openstack" {
  cloud = "kolla-admin"
}
```

Authentication continues to use:

```text
/etc/kolla/clouds.yaml
```

through:

```bash
export OS_CLIENT_CONFIG_FILE=/etc/kolla/clouds.yaml
export OS_CLOUD=kolla-admin
```

No OpenStack password is stored in the Terraform files.

## data.tf

Looks up infrastructure that already exists:

```hcl
data "openstack_networking_network_v2" "public" {
  name = "public"
}
```

A Terraform `data` block reads an existing object.

It does not create the object.

## outputs.tf

Returns a useful value:

```hcl
output "public_network_id" {
  value = data.openstack_networking_network_v2.public.id
}
```

A useful mental model is:

```text
variable = INPUT

data = LOOK UP existing infrastructure

resource = CREATE / MANAGE infrastructure

output = RETURN useful information
```

---

# 11. Initialize Terraform

Format the configuration:

```bash
terraform fmt
```

Initialize the working directory:

```bash
terraform init
```

Observed in this lab:

```text
OpenStack provider installed: 3.4.0
Terraform initialization: SUCCESS
```

Terraform created:

```text
.terraform/
.terraform.lock.hcl
```

`.terraform/` is a local working directory and should not be committed.

`.terraform.lock.hcl` should normally be committed because it records the
provider selection used by the configuration.

---

# 12. Validate the Configuration

Run:

```bash
terraform validate
```

Observed:

```text
Success! The configuration is valid.
```

This verifies Terraform can parse the configuration and provider schema.

---

# 13. First Read-Only Terraform Plan

Run:

```bash
terraform plan
```

Terraform successfully queried the existing OpenStack `public` network.

Observed:

```text
data.openstack_networking_network_v2.public: Read complete

public_network_id = "907bac8a-183b-4675-81f0-d4c2fe91876b"
```

This matched the existing Neutron public network.

No OpenStack infrastructure was created or modified.

This proves:

```text
Terraform CLI
      ↓
OpenStack provider
      ↓
clouds.yaml
      ↓
Keystone authentication
      ↓
Neutron API
      ↓
existing public network
```

---

# 14. Protect Terraform State from Git

Terraform state must not be casually committed to Git.

The repository `.gitignore` excludes:

```text
.terraform/
*.tfstate
*.tfstate.*
*.tfplan
*.tfvars
*.tfvars.json
```

The provider lock file remains tracked:

```text
.terraform.lock.hcl
```


---

# 15. Create the First Terraform-Managed Network

The first Terraform-managed OpenStack resource is a private Neutron network.

Configuration:

```hcl
resource "openstack_networking_network_v2" "private" {
  name           = "tf-private"
  admin_state_up = true
}
```

Before applying:

```bash
terraform plan
```

Terraform reported:

```text
Plan: 1 to add, 0 to change, 0 to destroy.
```

After:

```bash
terraform apply
```

the network was created successfully.

Observed:

```text
Name: tf-private
ID:   5fef4c1a-0756-4275-87fb-91afe685890d
```

This is the first OpenStack resource created and managed by Terraform in
this lab.

---

# 16. Create the Terraform Private Subnet

The Terraform workload uses a separate tenant CIDR from the manually created
Chapter 08 workload.

```text
Manual workload:     10.10.10.0/24
Terraform workload:  10.10.20.0/24
```

Configuration:

```hcl
resource "openstack_networking_subnet_v2" "private" {
  name       = "tf-private-subnet"
  network_id = openstack_networking_network_v2.private.id
  cidr       = "10.10.20.0/24"
  ip_version = 4
  gateway_ip = "10.10.20.1"

  dns_nameservers = [
    "1.1.1.1"
  ]
}
```

The important dependency is:

```hcl
network_id = openstack_networking_network_v2.private.id
```

Terraform can infer:

```text
tf-private
    ↓
tf-private-subnet
```

and therefore knows the network must exist before the subnet can be created.

Observed after apply:

```text
Network:
  tf-private
  5fef4c1a-0756-4275-87fb-91afe685890d

Subnet:
  tf-private-subnet
  8153fcd9-d068-4f0a-9687-1d1934aa6f7d

CIDR:
  10.10.20.0/24
```

Terraform state:

```bash
terraform state list
```

Observed:

```text
data.openstack_networking_network_v2.public
openstack_networking_network_v2.private
openstack_networking_subnet_v2.private
```

A `data` object may appear in Terraform state, but it remains a read-only
lookup.

A `resource` object is created and managed by Terraform.


---

# 17. Create the Terraform Router

The Terraform tenant network requires a Neutron router to reach the existing
external `public` network.

Configuration:

```hcl
resource "openstack_networking_router_v2" "router" {
  name                = "tf-router"
  admin_state_up      = true
  external_network_id = data.openstack_networking_network_v2.public.id
}

resource "openstack_networking_router_interface_v2" "private" {
  router_id = openstack_networking_router_v2.router.id
  subnet_id = openstack_networking_subnet_v2.private.id
}
```

Terraform automatically inferred the dependencies:

```text
existing public network
        |
        v
    tf-router
        |
        v
router interface
        ^
        |
tf-private-subnet
```

Before apply:

```text
Plan: 2 to add, 0 to change, 0 to destroy.
```

Observed after apply:

```text
Router:
  tf-router
  07c581b7-37ce-4449-9afa-edc419a7e448

Private router interface:
  10.10.20.1

External network:
  public

External router IP:
  192.168.0.166

SNAT:
  enabled
```

Neutron automatically allocated `192.168.0.166` from the allocation pool
configured on `public-subnet`.

The router itself does not define that allocation pool.

The relationship is:

```text
tf-private
10.10.20.0/24
      |
10.10.20.1
      |
  tf-router
      |
192.168.0.166
      |
    public
      |
192.168.0.150-169 allocation pool
```

Terraform state now contains:

```text
data.openstack_networking_network_v2.public
openstack_networking_network_v2.private
openstack_networking_subnet_v2.private
openstack_networking_router_v2.router
openstack_networking_router_interface_v2.private
```


---

# 18. Create the Terraform Security Group

Create a dedicated security group for the Terraform-managed VM.

Configuration:

```hcl
resource "openstack_networking_secgroup_v2" "vm" {
  name        = "tf-sg"
  description = "Security group for Terraform lab VMs"
}

resource "openstack_networking_secgroup_rule_v2" "icmp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.vm.id
}

resource "openstack_networking_secgroup_rule_v2" "ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.vm.id
}
```

Before apply:

```text
Plan: 3 to add, 0 to change, 0 to destroy.
```

Observed after apply:

```text
Security group:
  tf-sg

Ingress:
  ICMP IPv4 from 0.0.0.0/0
  TCP/22 IPv4 from 0.0.0.0/0

Egress:
  IPv4 to 0.0.0.0/0
  IPv6 to ::/0
```

The IPv4 and IPv6 egress rules were automatically created by OpenStack.

Terraform explicitly manages:

```text
openstack_networking_secgroup_v2.vm
openstack_networking_secgroup_rule_v2.icmp
openstack_networking_secgroup_rule_v2.ssh
```

The automatically generated egress rules do not appear as separate
Terraform-managed rule resources in this configuration.


---

# 19. Make the OpenStack Client Environment Persistent

Terraform and the OpenStack CLI both need to know where the Kolla-generated
OpenStack client configuration is located.

The required environment variables are:

```bash
export OS_CLIENT_CONFIG_FILE=/etc/kolla/clouds.yaml
export OS_CLOUD=kolla-admin
```

These variables exist only in the current shell unless they are made
persistent.

This became visible after reboot when Terraform returned:

```text
Error: unable to load clouds.yaml:
no clouds.yml file found: file does not exist
```

Temporarily exporting the variables fixed the problem:

```bash
export OS_CLIENT_CONFIG_FILE=/etc/kolla/clouds.yaml
export OS_CLOUD=kolla-admin
```

For the Hermes management VM, add them to:

```text
~/.bashrc
```

Then reload the shell configuration:

```bash
source ~/.bashrc
```

Verify:

```bash
echo "$OS_CLIENT_CONFIG_FILE"
echo "$OS_CLOUD"
```

Expected:

```text
/etc/kolla/clouds.yaml
kolla-admin
```

Important distinction:

```text
OS_CLIENT_CONFIG_FILE + OS_CLOUD
        |
        +--> Terraform/OpenStack API authentication

~/.ssh/openstack-lab-vm
        |
        +--> SSH authentication into guest VMs
```

These are two completely different authentication paths.

The OpenStack CLI itself is installed inside the Kolla Python virtual
environment:

```bash
source ~/venvs/kolla/bin/activate
```

After activation:

```bash
which openstack
```

The prompt also shows:

```text
(kolla)
```

Do not use:

```bash
sudo openstack ...
```

The `openstack` command belongs to the user's Python virtual environment,
not root's normal PATH.

---

# 20. Create the Terraform-Managed SSH Keypair

The private SSH key already exists on Hermes:

```text
~/.ssh/openstack-lab-vm
```

The corresponding public key is:

```text
~/.ssh/openstack-lab-vm.pub
```

Terraform registers only the public key in OpenStack.

Configuration in `compute.tf`:

```hcl
resource "openstack_compute_keypair_v2" "vm" {
  name       = "tf-key"
  public_key = file(pathexpand("~/.ssh/openstack-lab-vm.pub"))
}
```

This does not upload the private key.

The private key stays on Hermes.

Apply result:

```text
openstack_compute_keypair_v2.vm: Creation complete
[id=tf-key]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

Verify from OpenStack:

```bash
openstack keypair show tf-key
```

Observed:

```text
name        = tf-key
type        = ssh
fingerprint = 52:5a:cc:02:b3:89:58:47:62:23:50:5c:95:a1:e6:dd
private_key = None
```

Verify Terraform state:

```bash
terraform state list | grep keypair
```

Observed:

```text
openstack_compute_keypair_v2.vm
```

The same local SSH key can therefore be used to access the Terraform-created
guest VM later:

```bash
ssh -i ~/.ssh/openstack-lab-vm cirros@<FLOATING-IP>
```

---

# 21. Look Up the Existing Image and Flavor

The CirrOS image and flavor were created earlier in OpenStack.

For this first Terraform workload, Terraform does not create replacements.
Instead, it looks up the existing OpenStack objects using data sources.

Add to `data.tf`:

```hcl
data "openstack_images_image_v2" "cirros" {
  name        = "cirros-0.6.3"
  most_recent = true
}

data "openstack_compute_flavor_v2" "cirros" {
  name = "m1.cirros"
}
```

The distinction is important:

```text
data
  = look up an existing object

resource
  = create/manage an object with Terraform
```

The existing flavor was verified with:

```bash
openstack flavor list
```

Observed:

```text
Name:   m1.cirros
RAM:    512 MB
Disk:   1 GB
VCPUs:  1
Public: True
```

Terraform resolved the flavor to:

```text
3b8ed62d-dedb-4aaa-b765-b62cbe8669f5
```

Terraform resolved the CirrOS image to:

```text
57ce0724-c3fd-423d-b77d-b88a91ad8b6a
```

Therefore:

```text
Image
  |
  +--> decides what operating system/image the VM boots

Flavor
  |
  +--> decides vCPU, RAM, and root disk size
```

Terraform itself does not invent these values.

---

# 22. Create the First Terraform VM

Add the VM resource to `compute.tf`:

```hcl
resource "openstack_compute_instance_v2" "vm" {
  name      = "tf-cirros-01"
  image_id  = data.openstack_images_image_v2.cirros.id
  flavor_id = data.openstack_compute_flavor_v2.cirros.id

  key_pair = openstack_compute_keypair_v2.vm.name

  security_groups = [
    openstack_networking_secgroup_v2.vm.name
  ]

  network {
    uuid = openstack_networking_network_v2.private.id
  }
}
```

The VM connects the components built earlier:

```text
cirros-0.6.3
      |
m1.cirros
      |
tf-key
      |
tf-sg
      |
tf-private
      |
      v
tf-cirros-01
```

Validate and preview:

```bash
terraform fmt
terraform validate
terraform plan
```

Observed plan:

```text
Plan: 1 to add, 0 to change, 0 to destroy.
```

Apply:

```bash
terraform apply
```

Approve with lowercase:

```text
yes
```

Observed:

```text
openstack_compute_instance_v2.vm: Creation complete after 25s
[id=7a3b97c8-25f8-4c1f-abf9-be94448fb252]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

Verify:

```bash
openstack server show tf-cirros-01
```

Observed:

```text
Name:              tf-cirros-01
UUID:              7a3b97c8-25f8-4c1f-abf9-be94448fb252
Status:            ACTIVE
Compute host:      node3
Nova instance:     instance-00000003
Image:             cirros-0.6.3
Flavor:            m1.cirros
vCPU:              1
RAM:               512 MB
Disk:              1 GB
Keypair:           tf-key
Security group:    tf-sg
Fixed IP:          10.10.20.31
```

Nova Scheduler selected `node3`.

Terraform did not explicitly select the compute node.

The relationship is:

```text
Terraform
    |
    +--> asks Nova to create the server
             |
             +--> Nova Scheduler selects a compute host
```

---

# 23. Allocate and Associate a Floating IP

The VM initially had only its private address:

```text
10.10.20.31
```

To access it from the home LAN, allocate a floating IP from the existing
external network named:

```text
public
```

First look up the Neutron port belonging to the VM.

Add to `data.tf`:

```hcl
data "openstack_networking_port_v2" "vm" {
  device_id  = openstack_compute_instance_v2.vm.id
  network_id = openstack_networking_network_v2.private.id
}
```

Observed VM Neutron port:

```text
c144baf4-1ff7-4624-a5ec-c9044d83d2e9
```

Create `floating-ip.tf`:

```hcl
resource "openstack_networking_floatingip_v2" "vm" {
  pool = data.openstack_networking_network_v2.public.name
}

resource "openstack_networking_floatingip_associate_v2" "vm" {
  floating_ip = openstack_networking_floatingip_v2.vm.address
  port_id     = data.openstack_networking_port_v2.vm.id
}
```

Add useful outputs to `outputs.tf`:

```hcl
output "vm_fixed_ip" {
  value = openstack_compute_instance_v2.vm.network[0].fixed_ip_v4
}

output "vm_floating_ip" {
  value = openstack_networking_floatingip_v2.vm.address
}
```

Validate:

```bash
terraform fmt
terraform validate
terraform plan
```

Observed:

```text
Plan: 2 to add, 0 to change, 0 to destroy.
```

Apply:

```bash
terraform apply
```

Observed:

```text
Apply complete! Resources: 2 added, 0 changed, 0 destroyed.
```

Terraform outputs:

```text
public_network_id = "907bac8a-183b-4675-81f0-d4c2fe91876b"
vm_fixed_ip       = "10.10.20.31"
vm_floating_ip    = "192.168.0.163"
```

Verify:

```bash
openstack floating ip list
```

Observed mapping:

```text
192.168.0.163
      |
      +--> 10.10.20.31
      |
      +--> Neutron port
           c144baf4-1ff7-4624-a5ec-c9044d83d2e9
```

---

# 24. Validate the Terraform Workload End to End

SSH from Hermes:

```bash
ssh -i ~/.ssh/openstack-lab-vm cirros@192.168.0.163
```

The first SSH connection asked to trust the guest host key.

After connecting:

```bash
hostname
```

Observed:

```text
tf-cirros-01
```

CirrOS is intentionally minimal, so utilities such as:

```text
hostnamectl
```

are not installed.

Check the guest interface:

```bash
ip addr
```

Observed:

```text
eth0
IP:   10.10.20.31/24
MTU:  1450
MAC:  fa:16:3e:67:5d:89
```

Check routes:

```bash
ip route
```

Observed:

```text
default via 10.10.20.1 dev eth0
10.10.20.0/24 dev eth0
169.254.169.254 via 10.10.20.2 dev eth0
```

Test the Neutron router:

```bash
ping -c 3 10.10.20.1
```

Result:

```text
3 packets transmitted
3 packets received
0% packet loss
```

Test Internet connectivity:

```bash
ping -c 3 1.1.1.1
```

Result:

```text
3 packets transmitted
3 packets received
0% packet loss
```

The complete Terraform workload is therefore operational:

```text
Hermes
  |
  | SSH to 192.168.0.163
  v
Floating IP
192.168.0.163
  |
  v
Neutron port
  |
  v
tf-cirros-01
10.10.20.31
  |
  v
tf-router
10.10.20.1
  |
  | SNAT
  v
public network
  |
  v
Home LAN / Internet
```

At this point Terraform manages the complete first tenant workload:

```text
tf-private
tf-private-subnet
tf-router
tf-router interface
tf-sg
ICMP security-group rule
SSH security-group rule
tf-key
tf-cirros-01
floating IP
floating-IP association
```

The existing OpenStack objects being consumed as data sources remain outside
Terraform ownership:

```text
public network
cirros-0.6.3 image
m1.cirros flavor
```

This separation is intentional.

---

# 25. Destroy and Rebuild — Proving Reproducibility

The first Terraform workload was now fully operational.

Before testing reproducibility, Terraform confirmed that the deployed
infrastructure matched the configuration:

```bash
terraform plan
```

Observed:

```text
No changes. Your infrastructure matches the configuration.
```

This means there was no detected configuration drift at that point.

## Preview the Destroy

Before deleting anything, preview the operation:

```bash
terraform plan -destroy
```

Observed:

```text
Plan: 0 to add, 0 to change, 11 to destroy.
```

Terraform planned to destroy only the resources it managed:

```text
tf-cirros-01
tf-key
floating IP
floating-IP association
tf-private
tf-private-subnet
tf-router
tf-router interface
tf-sg
ICMP ingress rule
SSH ingress rule
```

The following existing OpenStack resources were not Terraform-managed
resources and therefore were not destroyed:

```text
public network
cirros-0.6.3 image
m1.cirros flavor
manual private network
manual cirros-01 VM
```

This demonstrates the difference between:

```text
data "..."
```

and:

```text
resource "..."
```

A Terraform data source reads an existing object.

A Terraform resource is part of Terraform's managed lifecycle.

---

## Destroy the Terraform Workload

Run:

```bash
terraform destroy
```

After reviewing the plan, approve with:

```text
yes
```

Observed:

```text
Destroy complete! Resources: 11 destroyed.
```

After destruction:

```bash
terraform state list
```

returned no resources.

The Terraform-created network:

```text
tf-private
```

was gone.

The original manually-created networks remained:

```text
private
public
```

The Terraform floating IP:

```text
192.168.0.163
```

was released.

The original manual VM floating IP remained:

```text
192.168.0.164
```

This proved that Terraform removed only the infrastructure represented by
its managed resources.

---

## Rebuild from the Same Terraform Configuration

No Terraform configuration files were changed.

Run:

```bash
terraform plan
```

Observed:

```text
Plan: 11 to add, 0 to change, 0 to destroy.
```

Terraform still used the existing shared OpenStack objects:

```text
public network
cirros-0.6.3 image
m1.cirros flavor
```

and planned to rebuild the complete Terraform-managed tenant workload.

Apply:

```bash
terraform apply
```

Approve with:

```text
yes
```

Observed:

```text
Apply complete! Resources: 11 added, 0 changed, 0 destroyed.
```

Terraform successfully reconstructed the workload from the same `.tf` files.

---

## Runtime Values Changed After Rebuild

The infrastructure architecture was the same, but several dynamically
allocated values changed.

First deployment:

```text
VM UUID:       7a3b97c8-25f8-4c1f-abf9-be94448fb252
Fixed IP:      10.10.20.31
Floating IP:   192.168.0.163
Compute host:  node3
Nova instance: instance-00000003
```

Rebuilt deployment:

```text
VM UUID:       f986eaf6-254c-44b9-a6dc-4ca512f3657f
Fixed IP:      10.10.20.245
Floating IP:   192.168.0.150
Compute host:  node3
Nova instance: instance-00000006
```

The rebuilt Neutron network also received a new UUID:

```text
45cf5658-3ca8-4361-901e-4109114c77f1
```

and the rebuilt VM Neutron port became:

```text
b5a8f9ff-6afc-49c4-8968-2c019d74e361
```

This is expected.

Terraform describes the desired infrastructure architecture.

OpenStack may dynamically assign new:

```text
UUIDs
fixed IP addresses
floating IP addresses
Neutron ports
VXLAN segmentation IDs
Nova instance numbers
compute hosts
```

when infrastructure is recreated.

The important point is not that every generated value remains identical.

The important point is that the intended infrastructure is reconstructed
correctly.

---

## Verify the Rebuilt VM

Terraform outputs:

```text
public_network_id = "907bac8a-183b-4675-81f0-d4c2fe91876b"
vm_fixed_ip       = "10.10.20.245"
vm_floating_ip    = "192.168.0.150"
```

Verify the server:

```bash
openstack server show tf-cirros-01 \
  -c id \
  -c status \
  -c addresses \
  -c OS-EXT-SRV-ATTR:host \
  -c OS-EXT-SRV-ATTR:instance_name
```

Observed:

```text
id                            f986eaf6-254c-44b9-a6dc-4ca512f3657f
status                        ACTIVE
OS-EXT-SRV-ATTR:host          node3
OS-EXT-SRV-ATTR:instance_name instance-00000006
addresses                     tf-private=10.10.20.245, 192.168.0.150
```

SSH into the rebuilt VM:

```bash
ssh -i ~/.ssh/openstack-lab-vm cirros@192.168.0.150
```

Verify:

```bash
hostname
```

Observed:

```text
tf-cirros-01
```

Guest interface:

```text
eth0
IP:  10.10.20.245/24
MAC: fa:16:3e:48:95:ee
MTU: 1450
```

Guest routing:

```text
default via 10.10.20.1 dev eth0
10.10.20.0/24 dev eth0
169.254.169.254 via 10.10.20.2 dev eth0
```

Test the Neutron router:

```bash
ping -c 3 10.10.20.1
```

Observed:

```text
3 packets transmitted
3 packets received
0% packet loss
```

Test Internet connectivity:

```bash
ping -c 3 1.1.1.1
```

Observed:

```text
3 packets transmitted
3 packets received
0% packet loss
```

The rebuilt workload therefore passed the same functional tests as the
original deployment.

---

## The Important Terraform Lesson

Before Terraform:

```text
Infrastructure itself is the thing that must be carefully preserved.
```

With Infrastructure as Code:

```text
Terraform configuration
        |
        v
Desired infrastructure
        |
        v
terraform apply
        |
        v
OpenStack resources
```

The individual VM, network UUID, floating IP, or Neutron port is not the
source of truth.

The Terraform configuration describes the desired infrastructure.

Terraform state records the relationship between that configuration and
the currently deployed OpenStack resources.

This lab demonstrated the full lifecycle:

```text
WRITE
  |
  v
PLAN
  |
  v
APPLY
  |
  v
VERIFY
  |
  v
DESTROY
  |
  v
REBUILD
  |
  v
VERIFY AGAIN
```

The first Terraform OpenStack workload is now proven reproducible.
