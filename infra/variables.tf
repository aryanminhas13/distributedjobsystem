variable "project" {
  type    = string
  default = "djobs"
}
variable "environment" {
  type    = string
  default = "prod"
}
variable "location" {
  type    = string
  default = "canadacentral"
}
variable "postgres_admin" {
  type    = string
  default = "jobadmin"
}
variable "worker_min_replicas" {
  type    = number
  default = 2
}
variable "worker_max_replicas" {
  type    = number
  default = 20
}
variable "alert_email" {
  type    = string
  default = ""
}
variable "monthly_budget_cad" {
  type    = number
  default = 150
}
variable "tags" {
  type = map(string)
  default = {
    workload = "distributed-job-platform", managed_by = "terraform"
  }
}
