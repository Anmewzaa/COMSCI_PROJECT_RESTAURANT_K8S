terraform {
  required_version = ">= 1.0.0"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.61.0" 
    }
  }
}

provider "google" {
  credentials = file(var.credentials_file)
  project     = var.project_id                         
  region      = var.region                                  
}

resource "google_compute_network" "vpc_network" {
  name = var.network_name
  auto_create_subnetworks  = false
}

resource "google_compute_subnetwork" "vpc_subnetwork" {
  name          = var.subnet_name
  ip_cidr_range = "192.168.1.0/24"
  region        = var.region
  network       = google_compute_network.vpc_network.id
}

resource "google_compute_firewall" "project_firewall" {
  name    = "project-firewall"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  allow {
    protocol = "tcp"
    ports    = ["80", "443"] 
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["allow-ssh"]
  direction     = "INGRESS"
}

resource "google_artifact_registry_repository" "artifact_repo_customer" {
  repository_id = "customer-registry"
  project    = var.project_id
  location   = var.region         

  description = "Artifact Registry for storing Customer Artifact"
  format      = "DOCKER"            
}

resource "google_artifact_registry_repository" "artifact_admin_customer" {
  repository_id = "admin-registry"
  project    = var.project_id
  location   = var.region         

  description = "Artifact Registry for storing Admin Artifact"
  format      = "DOCKER"            
}

resource "google_container_cluster" "kubernetes_cluster" {
  name               = "kubernetes-cluster"
  location           = "asia-southeast1-a"       
  network            = google_compute_network.vpc_network.id
  subnetwork         = google_compute_subnetwork.vpc_subnetwork.id
  initial_node_count = 1                             

  remove_default_node_pool = true               

  min_master_version = "1.30.5-gke.1014003"   

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }
}

resource "google_container_node_pool" "default_node_pool" {
  name       = "default"
  location   = google_container_cluster.kubernetes_cluster.location
  cluster    = google_container_cluster.kubernetes_cluster.name

  node_count = 1   

  autoscaling {
    min_node_count = 1 
    max_node_count = 2
  }     

  node_config {
    machine_type    = "e2-small"                      
    disk_size_gb    = 50                          
    image_type      = "COS_CONTAINERD"         

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    tags = ["gke-node"]
  }
}
