# ============================================================================
# outputs.tf — Résultats affichés après le déploiement
# ============================================================================
# Après 'terraform apply', ces valeurs sont affichées dans le terminal.
# Elles contiennent les informations essentielles pour accéder aux ressources.
# ============================================================================

# ---------------------
# EC2 — Machine Virtuelle
# ---------------------
output "ec2_public_ip" {
  description = "Adresse IP publique de la VM (pour accéder à l'application)"
  value       = aws_instance.flask_server.public_ip
}

output "ec2_public_dns" {
  description = "Nom DNS public de la VM"
  value       = aws_instance.flask_server.public_dns
}

output "app_url" {
  description = "URL pour accéder à l'application Flask"
  value       = "http://${aws_instance.flask_server.public_ip}"
}

output "flask_api_url" {
  description = "URL de l'API Flask (port 5000)"
  value       = "http://${aws_instance.flask_server.public_ip}:5000"
}

output "ssh_command" {
  description = "Commande SSH pour se connecter à la VM"
  value       = "ssh -i ~/.ssh/id_rsa ubuntu@${aws_instance.flask_server.public_ip}"
}

# ---------------------
# S3 — Stockage Cloud
# ---------------------
output "s3_bucket_name" {
  description = "Nom du bucket S3"
  value       = aws_s3_bucket.static_files.id
}

output "s3_bucket_arn" {
  description = "ARN du bucket S3"
  value       = aws_s3_bucket.static_files.arn
}

output "s3_bucket_region" {
  description = "Région du bucket S3"
  value       = aws_s3_bucket.static_files.region
}

# ---------------------
# RDS — Base de Données (si activée)
# ---------------------
output "rds_endpoint" {
  description = "Endpoint de connexion à la base de données RDS"
  value       = var.db_enabled ? aws_db_instance.flask_db[0].endpoint : "Base de données non activée"
}

output "rds_hostname" {
  description = "Hostname de la base de données"
  value       = var.db_enabled ? aws_db_instance.flask_db[0].address : "N/A"
}

# ---------------------
# Résumé
# ---------------------
output "deployment_summary" {
  description = "Résumé complet du déploiement"
  value = <<-EOT
    
    ╔══════════════════════════════════════════════════╗
    ║     DÉPLOIEMENT RÉUSSI !                        ║
    ╠══════════════════════════════════════════════════╣
    ║                                                  ║
    ║  Application : http://${aws_instance.flask_server.public_ip}
    ║  API Health  : http://${aws_instance.flask_server.public_ip}/api/health
    ║  SSH         : ssh ubuntu@${aws_instance.flask_server.public_ip}
    ║  S3 Bucket   : ${aws_s3_bucket.static_files.id}
    ║  BDD         : ${var.db_enabled ? aws_db_instance.flask_db[0].endpoint : "Non activée"}
    ║                                                  ║
    ╚══════════════════════════════════════════════════╝
  EOT
}
