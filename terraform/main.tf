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

resource "google_compute_firewall" "jenkins_firewall" {
  name    = "allow-jenkins"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["8080"]  
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["allow-jenkins"]
}

resource "google_compute_firewall" "sonarqube_firewall" {
  name    = "allow-sonarqube"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["9000"] 
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["allow-sonarqube"]
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
    max_node_count = 3
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

resource "google_compute_instance" "jenkins_vm" {
  name         = "jenkins-vm"
  machine_type = "e2-medium"
  zone         = "asia-southeast1-a"

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2004-lts"
      size  = 50                  
      type  = "pd-balanced"        
    }
  }

  network_interface {
    subnetwork   = google_compute_subnetwork.vpc_subnetwork.name
    access_config {}
  }

  tags = ["allow-ssh", "allow-jenkins"]

  metadata = {
    startup-script = <<-EOT
      #!/bin/bash
      sudo apt update
      sudo apt install -y fontconfig openjdk-17-jre
      sudo wget -O /usr/share/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
      echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc]" https://pkg.jenkins.io/debian-stable binary/ | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
      sudo apt-get update
      sudo apt-get install -y jenkins
      sudo systemctl enable jenkins
      sudo systemctl start jenkins
    EOT
  }
}

resource "google_compute_instance" "sonarqube_vm" {
  name         = "sonarqube-vm"
  machine_type = "e2-medium"
  zone         = "asia-southeast1-a"

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2004-lts"
      size  = 50                   
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork   = google_compute_subnetwork.vpc_subnetwork.name
    access_config {}
  }

  tags = ["allow-ssh", "allow-sonarqube"]

  metadata = {
    startup-script = <<-EOT
      #!/bin/bash
      # Increase the vm.max_map_count for kernel and ulimit for the current session at runtime.
      sudo bash -c 'cat <<EOT> /etc/sysctl.conf
      vm.max_map_count=524288
      fs.file-max=131072
      ulimit -n 65536
      ulimit -u 4096
      EOT'
      sudo sysctl -w vm.max_map_count=524288
      sysctl -w fs.file-max=131072
      #Increase these permanently
      sudo bash -c 'cat <<EOT> /etc/security/limits.conf
      sonarqube   -   nofile   65536
      sonarqube   -   nproc    4096
      EOT'
      # Need JDK 17 or higher to run SonarQube 9.9
      sudo apt-get update -y
      sudo apt-get install openjdk-17-jdk -y
      sudo update-alternatives --config java
      java -version
      # Install and configure PostgreSQL & Create a user and database for sonar
      wget -q https://www.postgresql.org/media/keys/ACCC4CF8.asc -O - | sudo apt-key add -
      sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt/ `lsb_release -cs`-pgdg main" >> /etc/apt/sources.list.d/pgdg.list'
      sudo apt install postgresql postgresql-contrib -y
      sudo systemctl enable postgresql.service
      sudo systemctl start  postgresql.service
      sudo echo "postgres:admin123" | chpasswd
      runuser -l postgres -c "createuser sonar"
      sudo -i -u postgres psql -c "ALTER USER sonar WITH ENCRYPTED PASSWORD 'admin123';"
      sudo -i -u postgres psql -c "CREATE DATABASE sonarqube OWNER sonar;"
      sudo -i -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE sonarqube to sonar;"
      sudo systemctl restart  postgresql
      #Download the binaries for SonarQube 
      sudo mkdir -p /sonarqube/
      cd /sonarqube/
      sudo curl -O https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-9.9.0.65466.zip
      sudo apt-get install zip -y
      sudo unzip -o sonarqube-9.9.0.65466.zip -d /opt/
      sudo mv /opt/sonarqube-9.9.0.65466/ /opt/sonarqube
      sudo rm -rf /opt/sonarqube/conf/sonar.properties
      sudo touch /opt/sonarqube/conf/sonar.properties
      # PostgreSQL database username and password
      sudo bash -c 'cat <<EOT> /opt/sonarqube/conf/sonar.properties
      sonar.jdbc.username=sonar
      sonar.jdbc.password=admin123
      sonar.jdbc.url=jdbc:postgresql://localhost/sonarqube
      sonar.web.host=0.0.0.0
      sonar.web.port=9000
      sonar.web.javaAdditionalOpts=-server
      sonar.search.javaOpts=-Xmx512m -Xms512m -XX:+HeapDumpOnOutOfMemoryError
      sonar.log.level=INFO
      sonar.path.logs=logs
      EOT'
      # Create the group
      sudo groupadd sonar
      sudo useradd -c "SonarQube - User" -d /opt/sonarqube/ -g sonar sonar
      sudo chown sonar:sonar /opt/sonarqube/ -R
      # Create a systemd service file for SonarQube to run at system startup
      sudo touch /etc/systemd/system/sonarqube.service
      sudo bash -c 'cat <<EOT> /etc/systemd/system/sonarqube.service
      [Unit]
      Description=SonarQube service
      After=syslog.target network.target
      [Service]
      Type=forking
      ExecStart=/opt/sonarqube/bin/linux-x86-64/sonar.sh start
      ExecStop=/opt/sonarqube/bin/linux-x86-64/sonar.sh stop
      User=sonar
      Group=sonar
      Restart=always
      LimitNOFILE=65536
      LimitNPROC=4096
      [Install]
      WantedBy=multi-user.target
      EOT'
      # automatically system startup enable
      sudo systemctl daemon-reload
      sudo systemctl enable sonarqube.service
      # Install and configure Nginx as a reverse proxy for SonarQube.
      apt-get install nginx -y
      sudo rm -rf /etc/nginx/sites-enabled/default
      sudo rm -rf /etc/nginx/sites-available/default
      sudo touch /etc/nginx/sites-available/sonarqube
      sudo bash -c 'sudo cat <<EOT> /etc/nginx/sites-available/sonarqube
      server{
          listen      80;
          server_name sonar.robofarming.link;
          access_log  /var/log/nginx/sonar.access.log;
          error_log   /var/log/nginx/sonar.error.log;
          proxy_buffers 16 64k;
          proxy_buffer_size 128k;
          location / {
              proxy_pass  http://127.0.0.1:9000;
              proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
              proxy_redirect off;
                    
              proxy_set_header    Host            \$host;
              proxy_set_header    X-Real-IP       \$remote_addr;
              proxy_set_header    X-Forwarded-For \$proxy_add_x_forwarded_for;
              proxy_set_header    X-Forwarded-Proto http;
          }
      }
      EOT'
      ln -s /etc/nginx/sites-available/sonarqube /etc/nginx/sites-enabled/sonarqube
      # Automatically system startup enable
      sudo systemctl enable nginx.service
      sudo systemctl restart nginx.service
      sudo systemctl restart sonarqube.service
    EOT
  }
}