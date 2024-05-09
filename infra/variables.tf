variable "project_id" {
  type = string
}

variable "canary_enabled" {
  description = "Canary switch"
  type        = bool
}

variable "expert_api_live_version" {
  type = string
}

variable "expert_api_canary_version" {
  type = string

}
