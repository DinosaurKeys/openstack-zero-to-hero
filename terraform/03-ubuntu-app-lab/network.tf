resource "openstack_networking_secgroup_v2" "web" {
  name        = "web-sg"
  description = "Security group for web VM"
}

resource "openstack_networking_secgroup_rule_v2" "ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "192.168.0.0/24"
  security_group_id = openstack_networking_secgroup_v2.web.id
}

resource "openstack_networking_secgroup_rule_v2" "http" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "192.168.0.0/24"
  security_group_id = openstack_networking_secgroup_v2.web.id
}

resource "openstack_networking_secgroup_v2" "db" {
  name        = "db-sg"
  description = "Security group for database VM"
}

resource "openstack_networking_secgroup_rule_v2" "db_ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_group_id   = openstack_networking_secgroup_v2.web.id
  security_group_id = openstack_networking_secgroup_v2.db.id
}

resource "openstack_networking_secgroup_rule_v2" "db_postgresql" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 5432
  port_range_max    = 5432
  remote_group_id   = openstack_networking_secgroup_v2.web.id
  security_group_id = openstack_networking_secgroup_v2.db.id
}