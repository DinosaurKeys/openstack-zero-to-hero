data "openstack_networking_network_v2" "public" {
  name = "public"
}

data "openstack_images_image_v2" "cirros" {
  name        = "cirros-0.6.3"
  most_recent = true
}

data "openstack_compute_flavor_v2" "cirros" {
  name = "m1.cirros"
}

data "openstack_networking_port_v2" "vm" {
  device_id  = openstack_compute_instance_v2.vm.id
  network_id = openstack_networking_network_v2.private.id
}

data "openstack_networking_port_v2" "vm2" {
  device_id  = openstack_compute_instance_v2.vm2.id
  network_id = openstack_networking_network_v2.private.id
}