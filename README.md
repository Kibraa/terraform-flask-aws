# terraform-flask-aws

Déploiement automatisé d'une application Flask sur AWS avec Terraform (EC2 + S3 + RDS PostgreSQL).

## Lancer le projet

### 1. Configurer les variables

```bash
cd terraform/
cp terraform.tfvars.example terraform.tfvars
```

Éditer `terraform.tfvars` avec vos clés AWS et un nom de bucket unique :

```hcl
aws_access_key = "VOTRE_ACCESS_KEY"
aws_secret_key = "VOTRE_SECRET_KEY"
aws_region     = "eu-west-3"
s3_bucket_name = "flask-app-static-votre-nom-2025"
db_password    = "VotreMotDePasse123!"
```

### 2. Déployer

```bash
terraform init
terraform plan
terraform apply   # taper "yes" pour confirmer
```

Le déploiement prend ~15 min (RDS compris). À la fin, l'IP publique est affichée dans les outputs.

### 3. Tester l'application

```bash
# Attendre ~5 min que la VM finisse de s'installer, puis :
curl http://<IP>/api/health

# Uploader un fichier
curl -X POST http://<IP>/api/files/upload -F "file=@monfichier.txt" -F "category=uploads"

# Lister les fichiers
curl http://<IP>/api/files

# Supprimer un fichier
curl -X DELETE http://<IP>/api/files/<id>
```

La page d'accueil est accessible sur `http://<IP>` dans le navigateur.

### 4. Détruire l'infrastructure

```bash
terraform destroy   # taper "yes" pour confirmer
```

## Structure

```
terraform/                   → fichiers Terraform (main.tf, variables.tf, outputs.tf, provider.tf)
terraform/userdata.sh.tpl    → script de provisioning automatique de la VM
flask-app/                   → application Flask (API CRUD + intégration S3)
```
