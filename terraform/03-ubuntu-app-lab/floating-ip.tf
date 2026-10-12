data "openstack_networking_port_v2" "web" {
  device_id  = openstack_compute_instance_v2.web.id
  network_id = data.openstack_networking_network_v2.ai_private.id
}

resource "openstack_networking_floatingip_v2" "web" {
  pool = data.openstack_networking_network_v2.public.name
}

resource "openstack_networking_floatingip_associate_v2" "web" {
  floating_ip = openstack_networking_floatingip_v2.web.address
  port_id     = data.openstack_networking_port_v2.web.id
}