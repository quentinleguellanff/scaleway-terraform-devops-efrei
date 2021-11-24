terraform {
  required_providers {
    scaleway = {
      source = "scaleway/scaleway"
    }
  }
  required_version = ">= 0.13"
}
provider "scaleway" {
  zone            = "fr-par-1"
  region          = "fr-par"
  access_key      = "SCW3CHTFTBJT6GSK27KN"
  secret_key      = "23320d79-5279-44be-9e11-f55ee6e32242"
  project_id = "6c2a04fc-b52a-42f8-a993-cbd5aa0713a2"
}
resource "scaleway_rdb_instance" "main" {
  name           = "test-rdb"
  node_type      = "db-dev-s"
  engine         = "PostgreSQL-12"
  is_ha_cluster  = false
  disable_backup = true
  user_name      = "root"
  password       = "Efrei2021*db"
}
resource "scaleway_instance_ip" "public_ip" {
    count = 2
}

resource "scaleway_instance_server" "web" {
  count = 2
  type = "DEV1-S"
  image = "ubuntu_focal"
  ip_id = scaleway_instance_ip.public_ip[count.index].id
  user_data = {
    DATABASE_URI = "postgres://${scaleway_rdb_instance.main.user_name}:${scaleway_rdb_instance.main.password}@${scaleway_rdb_instance.main.endpoint_ip}:${scaleway_rdb_instance.main.endpoint_port}/rdb"
  }
  provisioner "remote-exec" {
    inline = [
      "sudo apt-get install -y ca-certificates curl gnupg lsb-release",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg",
      "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",
      "sudo apt-get update",
      "sudo apt-get install -y docker-ce docker-ce-cli containerd.io",
      "docker run -d --name app -e DATABASE_URI=\"$(scw-userdata DATABASE_URI)\" -p 80:8080 --restart=always europe-west1-docker.pkg.dev/efrei-devops/efrei-devops/app:latest"   
    ]
    connection {
        type     = "ssh"
        password = ""
        host     = "${self.public_ip}"
        private_key = file("C:/Users/quent/.ssh/id_rsa")
    }
  }
}

resource "scaleway_lb_ip" "ip" {
}

resource "scaleway_lb" "base" {
  ip_id  = scaleway_lb_ip.ip.id
  zone = "fr-par-1"
  type   = "LB-S"
}

resource "scaleway_lb_backend" "backend01" {
  lb_id            = scaleway_lb.base.id
  name             = "backend01"
  forward_protocol = "http"
  forward_port     = "80"
  server_ips = scaleway_instance_ip.public_ip[*].address
  }

resource "scaleway_lb_frontend" "frontend01" {
  lb_id        = scaleway_lb.base.id
  backend_id   = scaleway_lb_backend.backend01.id
  name         = "frontend01"
  inbound_port = "80"
}
resource "scaleway_instance_security_group" "allow_all" {
}

resource "scaleway_instance_security_group" "web" {
  inbound_default_policy = "drop" # By default we drop incoming traffic that do not match any inbound_rule

  inbound_rule {
    action = "accept"
    port   = 22
    ip     = scaleway_instance_server.web[*].public_ip 
  }

  inbound_rule {
    action = "accept"
    port   = 80
  }

  inbound_rule {
    action     = "accept"
    protocol   = "UDP"
    port_range = "22-23"
  }
}