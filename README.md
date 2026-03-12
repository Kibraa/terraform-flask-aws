# Déploiement Automatisé d'une Infrastructure Cloud avec Terraform

Projet complet de déploiement d'une application **Flask** sur **AWS** avec **Terraform**, incluant une VM (EC2), un stockage cloud (S3), une base de données (RDS PostgreSQL) et un backend avec CRUD.

---

## Architecture du Projet

```
┌─────────────────────────────────────────────────────────┐
│                        AWS Cloud                         │
│                                                          │
│  ┌─────────────────── VPC (10.0.0.0/16) ──────────────┐ │
│  │                                                      │ │
│  │  ┌──────────────────────────────────────┐            │ │
│  │  │     Subnet Public (10.0.1.0/24)      │            │ │
│  │  │                                      │            │ │
│  │  │  ┌──────────────────────────────┐    │            │ │
│  │  │  │    EC2 (Ubuntu 22.04)        │    │            │ │
│  │  │  │    - Flask + Gunicorn        │    │            │ │
│  │  │  │    - Nginx (reverse proxy)   │    │            │ │
│  │  │  │    - IP publique             │    │            │ │
│  │  │  └──────────┬───────────────────┘    │            │ │
│  │  └─────────────┼───────────────────────-┘            │ │
│  │                │                                      │ │
│  │         ┌──────┴──────┐                               │ │
│  │         │             │                               │ │
│  │    ┌────▼────┐   ┌────▼──────────────────────┐       │ │
│  │    │   S3    │   │  Subnet Privé (RDS)        │       │ │
│  │    │ Bucket  │   │  ┌──────────────────────┐  │       │ │
│  │    │-images/ │   │  │  PostgreSQL (RDS)    │  │       │ │
│  │    │-logs/   │   │  │  Port 5432           │  │       │ │
│  │    │-uploads/│   │  └──────────────────────┘  │       │ │
│  │    └─────────┘   └────────────────────────────┘       │ │
│  └──────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

---

## Structure des Fichiers

```
terraform-flask-aws/
├── terraform/
│   ├── provider.tf              # Configuration du provider AWS
│   ├── main.tf                  # Ressources : VPC, EC2, S3, RDS, IAM
│   ├── variables.tf             # Déclaration des variables
│   ├── outputs.tf               # Sorties après déploiement
│   ├── userdata.sh.tpl          # Script de provisioning de la VM
│   └── terraform.tfvars.example # Exemple de variables (à copier)
├── flask-app/
│   ├── app.py                   # Application Flask (CRUD + S3)
│   ├── config.py                # Configuration de l'app
│   ├── requirements.txt         # Dépendances Python
│   └── test_api.sh              # Script de tests de l'API
├── scripts/
│   └── deploy.sh                # Script de déploiement rapide
├── .gitignore
└── README.md                    # Ce fichier
```

---

## Prérequis

Avant de commencer, vous devez avoir installé :

| Outil | Version min. | Installation |
|-------|-------------|-------------|
| Terraform | >= 1.5.0 | [terraform.io/downloads](https://www.terraform.io/downloads) |
| AWS CLI | >= 2.0 | [docs.aws.amazon.com/cli](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) |
| Git | >= 2.0 | `sudo apt install git` |
| Clé SSH | — | `ssh-keygen -t rsa -b 4096` |

Vous devez aussi avoir un **compte AWS** avec les droits suffisants (EC2, S3, RDS, IAM, VPC).

---

## Étape 1 : Préparer l'Environnement

### 1.1 Installer Terraform

```bash
# Linux / WSL
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# Vérifier l'installation
terraform -version
```

### 1.2 Configurer AWS CLI

```bash
# Installer AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Configurer les credentials
aws configure
# → AWS Access Key ID: VOTRE_CLE
# → AWS Secret Access Key: VOTRE_SECRET
# → Default region name: eu-west-3
# → Default output format: json
```

### 1.3 Générer une clé SSH (si vous n'en avez pas)

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
```

### 1.4 Cloner le projet

```bash
git clone https://github.com/VOTRE-USERNAME/terraform-flask-aws.git
cd terraform-flask-aws
```

---

## Étape 2 : Configurer les Variables Terraform

```bash
cd terraform/

# Copier le fichier d'exemple
cp terraform.tfvars.example terraform.tfvars

# Éditer avec vos valeurs
nano terraform.tfvars
```

**Remplissez les champs suivants dans `terraform.tfvars` :**

```hcl
aws_access_key = "AKIAXXXXXXXXXXXXXXXX"
aws_secret_key = "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
aws_region     = "eu-west-3"
s3_bucket_name = "flask-app-static-VOTRE-NOM-UNIQUE"
db_password    = "UnMotDePasseSecurise123!"
```

> **IMPORTANT** : Le nom du bucket S3 doit être unique au niveau mondial. Ajoutez votre nom ou un identifiant unique.

---

## Étape 3 : Déployer l'Infrastructure

### 3.1 Initialiser Terraform

```bash
terraform init
```

Cette commande télécharge le provider AWS et prépare le répertoire de travail. Vous devriez voir :

```
Terraform has been successfully initialized!
```

### 3.2 Visualiser le plan d'exécution

```bash
terraform plan
```

Cette commande montre **ce que Terraform va créer** sans rien modifier. Vérifiez qu'il prévoit de créer environ 15-20 ressources.

### 3.3 Appliquer le déploiement

```bash
terraform apply
```

Terraform demande une confirmation. Tapez `yes` et appuyez sur Entrée.

**Le déploiement prend environ 5 à 10 minutes** (la RDS est la plus longue à créer).

### 3.4 Résultat attendu

À la fin, Terraform affiche les outputs :

```
Apply complete! Resources: ~18 added, 0 changed, 0 destroyed.

Outputs:

app_url = "http://XX.XX.XX.XX"
ec2_public_ip = "XX.XX.XX.XX"
s3_bucket_name = "flask-app-static-files-xxx"
ssh_command = "ssh -i ~/.ssh/id_rsa ubuntu@XX.XX.XX.XX"
```

---

## Étape 4 : Tester l'Application

### 4.1 Attendre le provisioning

Après le `terraform apply`, la VM met **2 à 3 minutes** supplémentaires pour installer Flask et démarrer l'application (le script `userdata.sh` s'exécute au premier boot).

```bash
# Se connecter en SSH pour vérifier les logs
ssh -i ~/.ssh/id_rsa ubuntu@$(terraform output -raw ec2_public_ip)

# Sur la VM, vérifier le log du provisioning
sudo cat /var/log/userdata.log

# Vérifier que Flask tourne
sudo systemctl status flask-app
```

### 4.2 Tester la page d'accueil

Ouvrez votre navigateur à l'adresse affichée par `app_url` :

```
http://XX.XX.XX.XX
```

### 4.3 Tester l'API avec curl

```bash
# Health check
curl http://XX.XX.XX.XX/api/health

# Uploader un fichier
curl -X POST http://XX.XX.XX.XX/api/files/upload \
  -F "file=@monimage.jpg" \
  -F "category=images" \
  -F "description=Photo de test"

# Lister les fichiers
curl http://XX.XX.XX.XX/api/files

# Récupérer un fichier par ID
curl http://XX.XX.XX.XX/api/files/VOTRE-FILE-ID

# Modifier un fichier
curl -X PUT http://XX.XX.XX.XX/api/files/VOTRE-FILE-ID \
  -H "Content-Type: application/json" \
  -d '{"description": "Description mise à jour"}'

# Télécharger un fichier (URL pré-signée S3)
curl http://XX.XX.XX.XX/api/files/VOTRE-FILE-ID/download

# Supprimer un fichier
curl -X DELETE http://XX.XX.XX.XX/api/files/VOTRE-FILE-ID

# Lister directement les objets S3
curl http://XX.XX.XX.XX/api/s3/list
curl "http://XX.XX.XX.XX/api/s3/list?prefix=images/"
```

### 4.4 Tester via l'AWS Console

1. **EC2** : Vérifiez que l'instance est `running` dans la console EC2.
2. **S3** : Vérifiez que le bucket contient les dossiers `images/`, `logs/`, `uploads/`.
3. **RDS** : Vérifiez que l'instance PostgreSQL est `available`.

---

## Étape 5 : Détruire l'Infrastructure

Quand vous avez terminé vos tests, **détruisez tout** pour éviter des frais :

```bash
terraform destroy
```

Tapez `yes` pour confirmer. Terraform supprime toutes les ressources dans l'ordre inverse de leur création.

---

## Résumé des Commandes Terraform

| Commande | Description |
|----------|-------------|
| `terraform init` | Initialise le projet et télécharge les plugins |
| `terraform plan` | Affiche un aperçu des changements à appliquer |
| `terraform apply` | Crée ou met à jour l'infrastructure |
| `terraform output` | Affiche les valeurs de sortie |
| `terraform show` | Affiche l'état actuel de l'infrastructure |
| `terraform destroy` | Supprime toute l'infrastructure |
| `terraform fmt` | Formate les fichiers .tf |
| `terraform validate` | Vérifie la syntaxe des fichiers |

---

## API Endpoints

| Méthode | Endpoint | Description |
|---------|----------|-------------|
| `GET` | `/` | Page d'accueil HTML |
| `GET` | `/api/health` | Vérification de l'état de santé |
| `GET` | `/api/files` | Lister tous les fichiers |
| `POST` | `/api/files/upload` | Uploader un fichier |
| `GET` | `/api/files/<id>` | Récupérer un fichier |
| `PUT` | `/api/files/<id>` | Modifier les métadonnées |
| `DELETE` | `/api/files/<id>` | Supprimer un fichier |
| `GET` | `/api/files/<id>/download` | URL de téléchargement S3 |
| `GET` | `/api/s3/list` | Lister les objets S3 |

---

## Problèmes Courants et Solutions

### L'application ne répond pas après `terraform apply`
Le script `userdata.sh` prend 2-3 minutes. Connectez-vous en SSH et vérifiez `/var/log/userdata.log`.

### Erreur "bucket already exists"
Le nom du bucket S3 doit être **unique mondialement**. Changez `s3_bucket_name` dans `terraform.tfvars`.

### Erreur SSH "Permission denied"
Vérifiez que le chemin `ssh_public_key_path` pointe bien vers votre clé publique et que la clé privée correspondante existe.

### La RDS n'est pas accessible
C'est normal, la RDS est dans un subnet **privé**. Seule la VM EC2 peut y accéder (via le Security Group).

### Erreur "Cannot find version X.X for postgres"
Certaines versions PostgreSQL ne sont pas disponibles dans toutes les régions. Utiliser `aws rds describe-db-engine-versions --engine postgres` pour lister les versions disponibles. En eu-west-3, utiliser la version **16.6**.

### Erreur "not eligible for Free Tier" sur EC2
En eu-west-3 (Paris), utiliser `t3.micro` et non `t2.micro`.

### Erreur "InvalidParameterValue" sur le Security Group
AWS n'accepte pas les caractères accentués dans les descriptions de Security Groups. Utiliser uniquement des caractères ASCII.

### Coûts AWS
- **EC2 t3.micro** : Gratuit (Free Tier en eu-west-3, 750h/mois la première année)
- **RDS db.t3.micro** : Gratuit (Free Tier, 750h/mois)
- **S3** : Gratuit jusqu'à 5 Go
- **Pensez à `terraform destroy` quand vous avez fini !**

---

## Technologies Utilisées

- **Terraform** v1.5+ — Infrastructure as Code
- **AWS** — Provider Cloud (EC2, S3, RDS, VPC, IAM)
- **Flask** — Framework web Python
- **Gunicorn** — Serveur WSGI Python
- **Nginx** — Reverse proxy
- **PostgreSQL** — Base de données relationnelle (via RDS)
- **boto3** — SDK AWS pour Python (interactions S3)

---

## Auteur

Projet réalisé dans le cadre d'un exercice DevOps — Déploiement automatisé avec Terraform.
