resource "openstack_networking_network_v2" "private" {
  name           = "tf-private"
  admin_state_up = true
}

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
