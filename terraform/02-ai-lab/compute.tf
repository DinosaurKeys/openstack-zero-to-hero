resource "openstack_compute_keypair_v2" "vm" {
  name       = "ai-key"
  public_key = file(pathexpand("~/.ssh/openstack-lab-vm.pub"))
}

resource "openstack_compute_instance_v2" "vm" {
  name      = "ai-cirros-01"
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

resource "openstack_compute_instance_v2" "vm2" {
  name      = "ai-cirros-02"
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