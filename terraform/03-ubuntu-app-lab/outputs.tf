output "vm_name" {
  value = openstack_compute_instance_v2.web.name
}

output "vm_fixed_ip" {
  value = openstack_compute_instance_v2.web.network[0].fixed_ip_v4
}

output "vm_floating_ip" {
  value = openstack_networking_floatingip_v2.web.address
}

output "security_group_name" {
  value = openstack_networking_secgroup_v2.web.name
}

output "db_name" {
  value = openstack_compute_instance_v2.db.name
}

output "db_fixed_ip" {
  value = openstack_compute_instance_v2.db.network[0].fixed_ip_v4
}

output "db_security_group_name" {
  value = openstack_networking_secgroup_v2.db.name
}