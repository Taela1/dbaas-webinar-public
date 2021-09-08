variable "project" {
 default = "dbaas-webinar"
}

variable "exoscale_api_key" { type = string }
variable "exoscale_api_secret" { type = string }

locals {
  zone = "de-fra-1"
}

terraform {
  required_providers {
    exoscale = {
      source  = "exoscale/exoscale"
      version = "0.28.0"
    }
  }
}


provider "exoscale" {
  key    = var.exoscale_api_key
  secret = var.exoscale_api_secret
}

resource "exoscale_security_group" "sks" {
  name = "${var.project}-sks"
}

resource "exoscale_security_group_rules" "sks" {
  security_group = exoscale_security_group.sks.name

  ingress {
    description              = "Calico traffic"
    protocol                 = "UDP"
    ports                    = ["4789"]
    user_security_group_list = [exoscale_security_group.sks.name]
  }

  ingress {
    description = "Nodes logs/exec"
    protocol  = "TCP"
    ports     = ["10250"]
    user_security_group_list = [exoscale_security_group.sks.name]
  }

  ingress {
    description = "NodePort services"
    protocol    = "TCP"
    cidr_list   = ["0.0.0.0/0", "::/0"]
    ports       = ["30000-32767"]
  }
}

resource "exoscale_sks_cluster" "prod" {
  zone    = local.zone
  name    = "${var.project}-prod"
  version = "1.22.1"
}

output "sks_endpoint" {
  value = exoscale_sks_cluster.prod.endpoint
}

resource "exoscale_sks_nodepool" "nodepool" {
  zone               = local.zone
  cluster_id         = exoscale_sks_cluster.prod.id
  name               = "${var.project}-nodepool"
  instance_type      = "standard.small"
  size               = 2
  security_group_ids = [exoscale_security_group.sks.id]
}

resource "exoscale_database" "pgprod" {
  zone = local.zone
  name = "${var.project}-prod"
  type = "pg"
  plan = "startup-4"

  maintenance_dow  = "sunday"
  maintenance_time = "23:00:00"

  termination_protection = true

  user_config = jsonencode({
    pg_version    = "13"
    backup_hour   = 1
    backup_minute = 0
    ip_filter     = ["194.182.171.150/32"]
    pglookout     = {
      max_failover_replication_time_lag = 60
    }
  })
}

output "database_uri" {
  value = exoscale_database.pgprod.uri
  sensitive = true
}
