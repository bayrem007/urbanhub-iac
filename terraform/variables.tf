variable "env" {
  description = "Nom de l'environnement (dev, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env doit valoir 'dev' ou 'prod'."
  }
}

variable "docker_host" {
  description = "Adresse de l'API Docker (équivalent de l'endpoint du fournisseur cloud)"
  type        = string
  default     = "unix:///var/run/docker.sock"
}

variable "instance_image" {
  description = "Image système de l'instance (équivalent d'une AMI)"
  type        = string
  default     = "ubuntu:22.04"
}

variable "instance_type" {
  description = "Gabarit de l'instance (équivalent t3.micro / t3.small)"
  type        = string
  default     = "small"

  validation {
    condition     = contains(["small", "medium"], var.instance_type)
    error_message = "instance_type doit valoir 'small' ou 'medium'."
  }
}

variable "instance_types" {
  description = "Catalogue des gabarits : mémoire max (Mo) et poids CPU relatif"

  type = map(object({
    memory     = number
    cpu_shares = number
  }))

  default = {
    small  = { memory = 512, cpu_shares = 512 }
    medium = { memory = 1024, cpu_shares = 1024 }
  }
}

variable "http_port" {
  description = "Port publié sur l'hôte pour le serveur web UrbanHub"
  type        = number
}

variable "metrics_port" {
  description = "Port publié sur l'hôte pour l'agent de métriques (node_exporter)"
  type        = number
}
