output "instance_name" {
  description = "Nom de l'instance"
  value       = docker_container.web.name
}

output "instance_ip" {
  description = "Adresse IP privée de l'instance"
  value       = docker_container.web.network_data[0].ip_address
}

output "app_url" {
  description = "URL publique du service UrbanHub"
  value       = "http://localhost:${var.http_port}"
}

output "inventory_file" {
  description = "Inventaire Ansible généré"
  value       = "ansible/inventory/${var.env}.ini"
}
