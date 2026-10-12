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