locals {
  instance_name = "urbanhub-${var.env}-web"
  size          = var.instance_types[var.instance_type]
  repo_root     = "${path.module}/.."
}

# Image de l'instance (équivalent : choix de l'AMI)
resource "docker_image" "base" {
  name         = var.instance_image
  keep_locally = true
}

# Réseau isolé par environnement (équivalent : VPC / subnet)
resource "docker_network" "env" {
  name = "urbanhub-${var.env}-net"
}

# Instance serveur de l'application UrbanHub
resource "docker_container" "web" {
  name     = local.instance_name
  hostname = local.instance_name
  image    = docker_image.base.image_id
  restart  = "unless-stopped"

  # "Démarrage de l'instance" : si Ansible a installé le script de boot,
  # il relance les services (nginx, node_exporter) à chaque redémarrage.
  command = [
    "/bin/bash", "-c",
    "if [ -x /usr/local/bin/urbanhub-boot.sh ]; then /usr/local/bin/urbanhub-boot.sh; fi; trap 'exit 0' TERM; sleep infinity & wait"
  ]

  memory     = local.size.memory
  cpu_shares = local.size.cpu_shares

  ports {
    internal = 80
    external = var.http_port
  }

  ports {
    internal = 9100
    external = var.metrics_port
  }

  networks_advanced {
    name = docker_network.env.name
  }

  labels {
    label = "project"
    value = "urbanhub"
  }

  labels {
    label = "env"
    value = var.env
  }
}

# Inventaire Ansible généré par le code d'infrastructure :
# l'adresse de l'instance y est injectée automatiquement.
resource "local_file" "inventory" {
  filename        = "${local.repo_root}/ansible/inventory/${var.env}.ini"
  file_permission = "0644"

  content = templatefile("${path.module}/templates/inventory.ini.tftpl", {
    env           = var.env
    instance_name = docker_container.web.name
    instance_ip   = docker_container.web.network_data[0].ip_address
    http_port     = var.http_port
    instance_type = var.instance_type
  })
}

# Cibles de supervision générées elles aussi par le code (Prometheus file_sd)
resource "local_file" "prom_node_targets" {
  filename        = "${local.repo_root}/monitoring/prometheus/targets/${var.env}-node.json"
  file_permission = "0644"

  content = jsonencode([{
    targets = ["host.docker.internal:${var.metrics_port}"]
    labels  = { env = var.env, instance_name = local.instance_name }
  }])
}

resource "local_file" "prom_http_targets" {
  filename        = "${local.repo_root}/monitoring/prometheus/targets/${var.env}-http.json"
  file_permission = "0644"

  content = jsonencode([{
    targets = ["http://host.docker.internal:${var.http_port}/"]
    labels  = { env = var.env, instance_name = local.instance_name }
  }])
}
