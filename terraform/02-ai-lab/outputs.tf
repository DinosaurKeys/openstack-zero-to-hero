output "public_network_id" {
  value = data.openstack_networking_network_v2.public.id
}

output "vm_fixed_ip" {
  value = openstack_compute_instance_v2.vm.network[0].fixed_ip_v4
}

output "vm_floating_ip" {
  value = openstack_networking_floatingip_v2.vm.address
}