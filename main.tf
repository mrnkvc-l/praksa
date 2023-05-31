provider "google" {
  project     = "cloud-internship-luka"
  region      = "us-central1"
}

# Generating VPC and Subnets

resource "google_compute_network" "vpc-test" {
  name = "vpc-test"
  auto_create_subnetworks = true
}

# Firewall for allow-ssh and ports
resource "google_compute_firewall" "allow_ssh" {
  depends_on = [google_compute_network.vpc-test]
  name       = "allow-ssh"
  network    = google_compute_network.vpc-test.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "test_rule" {
  depends_on = [google_compute_network.vpc-test]
  name       = "test-rule"
  network    = google_compute_network.vpc-test.id

  allow {
    protocol = "tcp"
    ports    = ["3000-3001"]
  }

  source_ranges = ["0.0.0.0/0"]
}

# Create instance template

resource "google_compute_instance_template" "test_template" {
  depends_on = [google_compute_network.vpc-test]
  name        = "test-template"

  machine_type = "n1-standard-1"

  disk {
    source_image = "projects/cloud-internship-luka/global/images/projekat-image"
  }

  network_interface {
    network = google_compute_network.vpc-test.id
    
    access_config {
      // Ovde dodajte opcionalne parametre ako je potrebno
    }
  }

  tags = ["http-server"]

metadata_startup_script = <<SCRIPT
cd /home/mariinkovic_luka/luka/cloud_student_internship/
cat > frontend/.env.development << EOF
REACT_APP_API_URL=http://$(curl ifconfig.me. ):3001/api
EOF
sudo docker compose build
sudo docker compose up -d
                        SCRIPT
}

resource "google_compute_firewall" "http_firewall_rule" {
  depends_on = [google_compute_network.vpc-test]
  name       = "allow-http"
  network    = google_compute_network.vpc-test.id

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_tags = ["http-server"]
}


# Create group of instance

resource "google_compute_instance_group_manager" "test_instance_group" {
  depends_on = [google_compute_network.vpc-test, google_compute_instance_template.test_template]
  name              = "test-instance-group"
  zone              = "us-central1-a"
  base_instance_name = "test-instance"
  target_size       = 1

  named_port {
    name = "http"
    port = 3000
  }

  named_port {
    name = "http"
    port = 3001
  }

  version{
    instance_template = google_compute_instance_template.test_template.id
  }
}

# Create Health-Check
resource "google_compute_health_check" "hc-test" {
  name               = "hc-test"
  check_interval_sec = 10
  healthy_threshold  = 2
  http_health_check {
    port               = 3000
    port_specification = "USE_FIXED_PORT"
    proxy_header       = "NONE"
    request_path       = "/"
  }
  timeout_sec         = 5
  unhealthy_threshold = 2
}

# Create Backend service
resource "google_compute_backend_service" "backend-test" {
  name                            = "backend-test"
  connection_draining_timeout_sec = 0
  health_checks                   = [google_compute_health_check.hc-test.id]
  load_balancing_scheme           = "EXTERNAL_MANAGED"
  port_name                       = "http"
  protocol                        = "HTTP"
  session_affinity                = "NONE"
  timeout_sec                     = 30
  backend {
    group           = google_compute_instance_group_manager.test_instance_group.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}

resource "google_compute_url_map" "map-test" {
  name            = "map-test"
  default_service = google_compute_backend_service.backend-test.id
}

resource "google_compute_target_http_proxy" "proxy-test" {
  name    = "proxy-test"
  url_map = google_compute_url_map.map-test.id
}

resource "google_compute_global_address" "default" {
  name       = "lb-ipv4-1"
  ip_version = "IPV4"
}

resource "google_compute_global_forwarding_rule" "load-test" {
  name                  = "load-test"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "80-80"
  target                = google_compute_target_http_proxy.proxy-test.id
  ip_address            = google_compute_global_address.default.id
}