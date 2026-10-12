data "openstack_networking_network_v2" "public" {
  name = "public"
}

data "openstack_images_image_v2" "ubuntu" {
  name        = "ubuntu-24.04"
  most_recent = true
}

data "openstack_compute_flavor_v2" "ubuntu_small" {
  name = "lab.ubuntu.small"
}

data "openstack_networking_network_v2" "ai_private" {
  name = "ai-private"
}

data "openstack_networking_subnet_v2" "ai_private" {
  name       = "ai-private-subnet"
  network_id = data.openstack_networking_network_v2.ai_private.id
}

data "openstack_compute_keypair_v2" "ai_key" {
  name = "ai-key"
}