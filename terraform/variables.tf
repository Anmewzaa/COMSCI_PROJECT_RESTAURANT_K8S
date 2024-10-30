variable "credentials_file" {
  description = "Path to the GCP credentials JSON file"
  type        = string
}

variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region"
  type        = string
  default     = "asia-southeast1"
}

variable "network_name" {
  description = "The name of the VPC network"
  type        = string
  default     = "project-vpc-network"
}

variable "subnet_name" {
  description = "The name of the subnetwork"
  type        = string
  default     = "project-subnet"
}

variable "repo_name" {
  description = "The name of the Artifact Registry Repo"
  type        = string
  default     = "project-subnet"
}