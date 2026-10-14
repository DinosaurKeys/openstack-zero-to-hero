resource "openstack_compute_instance_v2" "web" {
  name      = "web-01"
  image_id  = data.openstack_images_image_v2.ubuntu.id
  flavor_id = data.openstack_compute_flavor_v2.ubuntu_small.id

  key_pair = data.openstack_compute_keypair_v2.ai_key.name

  security_groups = [
    openstack_networking_secgroup_v2.web.name
  ]

  network {
    uuid = data.openstack_networking_network_v2.ai_private.id
  }

  depends_on = [
    data.openstack_networking_subnet_v2.ai_private
  ]
}

resource "openstack_compute_instance_v2" "db" {
  name      = "db-01"
  image_id  = data.openstack_images_image_v2.ubuntu.id
  flavor_id = data.openstack_compute_flavor_v2.ubuntu_small.id

  key_pair = data.openstack_compute_keypair_v2.ai_key.name

  security_groups = [
    openstack_networking_secgroup_v2.db.name
  ]

  network {
    uuid = data.openstack_networking_network_v2.ai_private.id
  }

  depends_on = [
    data.openstack_networking_subnet_v2.ai_private
  ]
}