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

variable "name" {
  type        = string
  description = "Prefix name for the destination"
}

variable "region" {
  type        = string
  default     = "ap-southeast-1"
  description = "AWS region"
}

variable "associate_secrets" {
  type = map(
    object({
      mount       = string
      secret_name = list(string)
    })
  )
  default     = {}
  description = "Map of vault kv to create secret sync association"
}

variable "unassociate_secrets" {
  type = map(
    object({
      mount       = string
      secret_name = list(string)
    })
  )
  default     = {}
  description = "Map of vault kv to remove secret sync association"
}
