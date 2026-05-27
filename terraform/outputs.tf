output "lb_public_ip" {
  description = "IP publique du load balancer (point d'entrée HTTPS)."
  value       = aws_instance.lb.public_ip
}

output "lb_url" {
  description = "URL HTTPS de l'application via sslip.io."
  value       = "https://${replace(aws_instance.lb.public_ip, ".", "-")}.sslip.io"
}

output "app_public_ips" {
  description = "IPs publiques des VMs applicatives."
  value       = aws_instance.app[*].public_ip
}

output "app_private_ips" {
  description = "IPs privées des VMs applicatives (upstreams du load balancer)."
  value       = aws_instance.app[*].private_ip
}

output "db_public_ip" {
  description = "IP publique de la VM base de données (administration SSH uniquement)."
  value       = aws_instance.db.public_ip
}

output "db_private_ip" {
  description = "IP privée de la base de données (utilisée par les apps)."
  value       = aws_instance.db.private_ip
}

output "citools_public_ip" {
  description = "IP publique de la VM usine logicielle (vide si désactivée)."
  value       = var.enable_citools ? aws_instance.citools[0].public_ip : ""
}

output "backup_bucket" {
  description = "Nom du bucket S3 de backups."
  value       = aws_s3_bucket.backups.bucket
}

# ============================================================================
# Génération de l'inventaire Ansible depuis les outputs ci-dessus.
# ============================================================================
resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../ansible/inventory/hosts.ini"
  content = templatefile("${path.module}/templates/inventory.tmpl", {
    lb_name        = aws_instance.lb.tags["Name"]
    lb_public_ip   = aws_instance.lb.public_ip
    db_name        = aws_instance.db.tags["Name"]
    db_public_ip   = aws_instance.db.public_ip
    db_private_ip  = aws_instance.db.private_ip
    ssh_user       = var.ansible_ssh_user
    backup_bucket  = aws_s3_bucket.backups.bucket
    aws_region     = var.region
    app_backends   = join(",", aws_instance.app[*].private_ip)
    citools_name   = var.enable_citools ? aws_instance.citools[0].tags["Name"] : ""
    citools_public_ip = var.enable_citools ? aws_instance.citools[0].public_ip : ""
    apps = [
      for a in aws_instance.app : {
        name       = a.tags["Name"]
        public_ip  = a.public_ip
        private_ip = a.private_ip
      }
    ]
  })
}
