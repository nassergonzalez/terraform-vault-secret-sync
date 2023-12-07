variable "delete_sync_destination" {
  type        = bool
  default     = false
  description = "Delete the sync destination. Secret associations must be removed beforehand."
}

variable "delete_all_secret_associations" {
  type        = bool
  default     = false
  description = "Delete the secret associations"
}

variable "mount" {
  type        = string
  description = "Vault mount path for the secret to sync to AWS SM."
}

variable "mount_accessor" {
  type        = string
  description = "Vault mount accessor for the secret to sync to AWS SM."
  default     = ""
}

variable "name" {
  type        = string
  description = "Name of the publication."
}

variable "region" {
  type        = string
  default     = "ap-southeast-1"
  description = "AWS region"
}

variable "associate_secrets" {
  type        = list(string)
  description = "List of secrets to sync to AWS SM"
}

variable "unassociate_secrets" {
  type        = list(string)
  default     = []
  description = "List of secrets to unassociate from AWS SM"
}
