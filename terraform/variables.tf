variable "virtual_environment_endpoint" {
  type        = string
  description = "Proxmox API endpoint"
}

variable "virtual_environment_username" {
  type        = string
  description = "User username for proxmox cluster"
  sensitive   = true
  ephemeral   = true
}

variable "virtual_environment_password" {
  type        = string
  description = "User password for proxmox cluster"
  sensitive   = true
  ephemeral   = true
}