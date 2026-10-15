terraform {
  required_version = ">= 1.5.0"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

# Plateforme "cloud simulé" : le démon Docker local joue le rôle de l'API
# du fournisseur. L'adresse du démon passe par une variable (TF_VAR_docker_host)
# pour s'adapter à Linux, macOS (Docker Desktop / Colima) ou WSL2.
provider "docker" {
  host = var.docker_host
}
