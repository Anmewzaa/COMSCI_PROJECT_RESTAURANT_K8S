output "jenkins_vm_name" {
  description = "The name of the Jenkins VM"
  value       = google_compute_instance.jenkins-vm.name
}

output "jenkins_vm_internal_ip" {
  description = "The internal IP address of the Jenkins VM"
  value       = google_compute_instance.jenkins-vm.network_interface[0].network_ip
}

output "jenkins_vm_external_ip" {
  description = "The external IP address of the Jenkins VM"
  value       = google_compute_instance.jenkins-vm.network_interface[0].access_config[0].nat_ip
}
