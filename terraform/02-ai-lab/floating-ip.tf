resource "openstack_networking_floatingip_v2" "vm" {
  pool = data.openstack_networking_network_v2.public.name
}

resource "openstack_networking_floatingip_associate_v2" "vm" {
  floating_ip = openstack_networking_floatingip_v2.vm.address
  port_id     = data.openstack_networking_port_v2.vm.id
}

resource "openstack_networking_floatingip_v2" "vm2" {
  pool = data.openstack_networking_network_v2.public.name
}

resource "openstack_networking_floatingip_associate_v2" "vm2" {
  floating_ip = openstack_networking_floatingip_v2.vm2.address
  port_id     = data.openstack_networking_port_v2.vm2.id
}