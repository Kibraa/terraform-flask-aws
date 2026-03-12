#!/bin/bash
# ============================================================================
# userdata.sh.tpl — Script de provisioning automatique de la VM
# ============================================================================
# Ce script est exécuté automatiquement au PREMIER démarrage de l'EC2.
# Il installe toutes les dépendances et lance l'application Flask.
# Les variables $${...} sont remplacées par Terraform (templatefile).
# ============================================================================

set -e
exec > /var/log/userdata.log 2>&1
echo "========== DÉBUT DU PROVISIONING =========="
echo "Date : $(date)"

# ---------------------
# 1. Mise à jour du système
# ---------------------
echo "[1/6] Mise à jour du système..."
apt-get update -y
apt-get upgrade -y

# ---------------------
# 2. Installation de Python et des outils
# ---------------------
echo "[2/6] Installation de Python et pip..."
apt-get install -y python3 python3-pip python3-venv git curl unzip nginx

# ---------------------
# 3. Installation de l'AWS CLI
# ---------------------
echo "[3/6] Installation de AWS CLI..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

# ---------------------
# 4. Création de l'application Flask
# ---------------------
echo "[4/6] Configuration de l'application Flask..."
mkdir -p /opt/flask-app
cd /opt/flask-app

# Créer l'environnement virtuel Python
python3 -m venv venv
source venv/bin/activate

# Installer les dépendances Python
pip install flask boto3 gunicorn psycopg2-binary flask-sqlalchemy flask-cors

# Créer le fichier de configuration
cat > /opt/flask-app/config.py << 'PYEOF'
import os

class Config:
    S3_BUCKET = os.environ.get('S3_BUCKET', '${s3_bucket_name}')
    AWS_REGION = os.environ.get('AWS_REGION', '${aws_region}')
    DB_ENABLED = os.environ.get('DB_ENABLED', '${db_enabled}').lower() == 'true'
    
    if DB_ENABLED:
        DB_HOST = os.environ.get('DB_HOST', '${db_host}')
        DB_NAME = os.environ.get('DB_NAME', '${db_name}')
        DB_USER = os.environ.get('DB_USER', '${db_username}')
        DB_PASS = os.environ.get('DB_PASS', '${db_password}')
        SQLALCHEMY_DATABASE_URI = f"postgresql://{DB_USER}:{DB_PASS}@{DB_HOST}:5432/{DB_NAME}"
    else:
        SQLALCHEMY_DATABASE_URI = "sqlite:///local.db"
    
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    MAX_CONTENT_LENGTH = 16 * 1024 * 1024  # 16 Mo max upload
PYEOF

# Créer l'application Flask principale
cat > /opt/flask-app/app.py << 'PYEOF'
"""
Application Flask avec intégration S3 et CRUD complet.
"""
import os
import uuid
import json
from datetime import datetime
from flask import Flask, request, jsonify, render_template_string
from flask_cors import CORS
from flask_sqlalchemy import SQLAlchemy
import boto3
from botocore.exceptions import ClientError
from config import Config

# --- Initialisation ---
app = Flask(__name__)
app.config.from_object(Config)
CORS(app)
db = SQLAlchemy(app)

# --- Client S3 ---
s3_client = boto3.client('s3', region_name=Config.AWS_REGION)

# =====================
# MODÈLES DE DONNÉES
# =====================
class FileMetadata(db.Model):
    """Stocke les métadonnées des fichiers uploadés dans S3."""
    __tablename__ = 'file_metadata'
    
    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    filename = db.Column(db.String(255), nullable=False)
    s3_key = db.Column(db.String(500), nullable=False)
    file_type = db.Column(db.String(50))
    file_size = db.Column(db.Integer)
    category = db.Column(db.String(50), default='uploads')  # images, logs, uploads
    description = db.Column(db.Text)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    def to_dict(self):
        return {
            'id': self.id,
            'filename': self.filename,
            's3_key': self.s3_key,
            'file_type': self.file_type,
            'file_size': self.file_size,
            'category': self.category,
            'description': self.description,
            'created_at': self.created_at.isoformat(),
            'updated_at': self.updated_at.isoformat()
        }

# Créer les tables au démarrage
with app.app_context():
    db.create_all()

# =====================
# PAGE D'ACCUEIL
# =====================
HOME_HTML = """
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <title>Flask Cloud App</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', sans-serif; background: #0f172a; color: #e2e8f0; }
        .container { max-width: 900px; margin: 0 auto; padding: 40px 20px; }
        h1 { font-size: 2.5rem; background: linear-gradient(135deg, #3b82f6, #8b5cf6);
             -webkit-background-clip: text; -webkit-text-fill-color: transparent; margin-bottom: 10px; }
        .subtitle { color: #94a3b8; font-size: 1.1rem; margin-bottom: 40px; }
        .card { background: #1e293b; border-radius: 12px; padding: 24px; margin-bottom: 20px;
                border: 1px solid #334155; }
        .card h2 { color: #3b82f6; margin-bottom: 12px; }
        .endpoint { background: #0f172a; padding: 10px 16px; border-radius: 8px; margin: 8px 0;
                    font-family: monospace; font-size: 0.9rem; }
        .method { display: inline-block; padding: 2px 8px; border-radius: 4px; font-weight: bold;
                  font-size: 0.75rem; margin-right: 8px; }
        .get { background: #065f46; color: #6ee7b7; }
        .post { background: #1e40af; color: #93c5fd; }
        .put { background: #92400e; color: #fcd34d; }
        .delete { background: #991b1b; color: #fca5a5; }
        .status { display: inline-block; background: #065f46; color: #6ee7b7; padding: 4px 12px;
                  border-radius: 20px; font-size: 0.85rem; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Flask Cloud App</h1>
        <p class="subtitle">Infrastructure déployée avec Terraform sur AWS</p>
        <p><span class="status">En ligne</span></p>
        
        <div class="card" style="margin-top: 30px;">
            <h2>API Endpoints</h2>
            <div class="endpoint"><span class="method get">GET</span> /api/health</div>
            <div class="endpoint"><span class="method get">GET</span> /api/files</div>
            <div class="endpoint"><span class="method post">POST</span> /api/files/upload</div>
            <div class="endpoint"><span class="method get">GET</span> /api/files/&lt;id&gt;</div>
            <div class="endpoint"><span class="method put">PUT</span> /api/files/&lt;id&gt;</div>
            <div class="endpoint"><span class="method delete">DELETE</span> /api/files/&lt;id&gt;</div>
            <div class="endpoint"><span class="method get">GET</span> /api/files/&lt;id&gt;/download</div>
            <div class="endpoint"><span class="method get">GET</span> /api/s3/list</div>
        </div>

        <div class="card">
            <h2>Configuration</h2>
            <div class="endpoint">S3 Bucket : {{ bucket }}</div>
            <div class="endpoint">Région : {{ region }}</div>
            <div class="endpoint">BDD : {{ db_status }}</div>
        </div>
    </div>
</body>
</html>
"""

@app.route('/')
def home():
    return render_template_string(HOME_HTML,
        bucket=Config.S3_BUCKET,
        region=Config.AWS_REGION,
        db_status='PostgreSQL (RDS)' if Config.DB_ENABLED else 'SQLite (local)'
    )

# =====================
# HEALTH CHECK
# =====================
@app.route('/api/health')
def health():
    """Vérifier que l'application et ses services fonctionnent."""
    status = {'app': 'ok', 'timestamp': datetime.utcnow().isoformat()}
    
    # Tester S3
    try:
        s3_client.head_bucket(Bucket=Config.S3_BUCKET)
        status['s3'] = 'ok'
    except Exception as e:
        status['s3'] = f'error: {str(e)}'
    
    # Tester la BDD
    try:
        db.session.execute(db.text('SELECT 1'))
        status['database'] = 'ok'
    except Exception as e:
        status['database'] = f'error: {str(e)}'
    
    return jsonify(status)

# =====================
# CRUD — FICHIERS
# =====================

# --- CREATE : Uploader un fichier ---
@app.route('/api/files/upload', methods=['POST'])
def upload_file():
    """Upload un fichier vers S3 et enregistre ses métadonnées."""
    if 'file' not in request.files:
        return jsonify({'error': 'Aucun fichier fourni'}), 400
    
    file = request.files['file']
    if file.filename == '':
        return jsonify({'error': 'Nom de fichier vide'}), 400
    
    category = request.form.get('category', 'uploads')
    description = request.form.get('description', '')
    
    # Générer un nom unique pour éviter les collisions
    file_id = str(uuid.uuid4())
    s3_key = f"{category}/{file_id}_{file.filename}"
    
    try:
        # Upload vers S3
        s3_client.upload_fileobj(
            file,
            Config.S3_BUCKET,
            s3_key,
            ExtraArgs={'ContentType': file.content_type}
        )
        
        # Sauvegarder les métadonnées en BDD
        metadata = FileMetadata(
            id=file_id,
            filename=file.filename,
            s3_key=s3_key,
            file_type=file.content_type,
            file_size=file.content_length or 0,
            category=category,
            description=description
        )
        db.session.add(metadata)
        db.session.commit()
        
        return jsonify({
            'message': 'Fichier uploadé avec succès',
            'file': metadata.to_dict()
        }), 201
    
    except ClientError as e:
        return jsonify({'error': f'Erreur S3 : {str(e)}'}), 500

# --- READ : Lister tous les fichiers ---
@app.route('/api/files', methods=['GET'])
def list_files():
    """Lister tous les fichiers avec filtrage optionnel par catégorie."""
    category = request.args.get('category')
    
    query = FileMetadata.query
    if category:
        query = query.filter_by(category=category)
    
    files = query.order_by(FileMetadata.created_at.desc()).all()
    return jsonify({
        'count': len(files),
        'files': [f.to_dict() for f in files]
    })

# --- READ : Récupérer un fichier par ID ---
@app.route('/api/files/<file_id>', methods=['GET'])
def get_file(file_id):
    """Récupérer les métadonnées d'un fichier spécifique."""
    file = FileMetadata.query.get(file_id)
    if not file:
        return jsonify({'error': 'Fichier non trouvé'}), 404
    return jsonify(file.to_dict())

# --- UPDATE : Modifier les métadonnées ---
@app.route('/api/files/<file_id>', methods=['PUT'])
def update_file(file_id):
    """Mettre à jour la description ou la catégorie d'un fichier."""
    file = FileMetadata.query.get(file_id)
    if not file:
        return jsonify({'error': 'Fichier non trouvé'}), 404
    
    data = request.get_json()
    if 'description' in data:
        file.description = data['description']
    if 'category' in data:
        # Déplacer dans S3 si la catégorie change
        old_key = file.s3_key
        new_key = f"{data['category']}/{file.id}_{file.filename}"
        try:
            s3_client.copy_object(
                Bucket=Config.S3_BUCKET,
                CopySource={'Bucket': Config.S3_BUCKET, 'Key': old_key},
                Key=new_key
            )
            s3_client.delete_object(Bucket=Config.S3_BUCKET, Key=old_key)
            file.s3_key = new_key
            file.category = data['category']
        except ClientError as e:
            return jsonify({'error': f'Erreur S3 : {str(e)}'}), 500
    
    db.session.commit()
    return jsonify({'message': 'Fichier mis à jour', 'file': file.to_dict()})

# --- DELETE : Supprimer un fichier ---
@app.route('/api/files/<file_id>', methods=['DELETE'])
def delete_file(file_id):
    """Supprimer un fichier de S3 et de la base de données."""
    file = FileMetadata.query.get(file_id)
    if not file:
        return jsonify({'error': 'Fichier non trouvé'}), 404
    
    try:
        s3_client.delete_object(Bucket=Config.S3_BUCKET, Key=file.s3_key)
    except ClientError:
        pass  # Le fichier n'existe peut-être plus dans S3
    
    db.session.delete(file)
    db.session.commit()
    return jsonify({'message': f'Fichier {file.filename} supprimé'})

# --- DOWNLOAD : Générer une URL temporaire de téléchargement ---
@app.route('/api/files/<file_id>/download', methods=['GET'])
def download_file(file_id):
    """Générer une URL pré-signée S3 pour télécharger le fichier."""
    file = FileMetadata.query.get(file_id)
    if not file:
        return jsonify({'error': 'Fichier non trouvé'}), 404
    
    try:
        url = s3_client.generate_presigned_url(
            'get_object',
            Params={'Bucket': Config.S3_BUCKET, 'Key': file.s3_key},
            ExpiresIn=3600  # URL valide 1 heure
        )
        return jsonify({'download_url': url, 'expires_in': 3600})
    except ClientError as e:
        return jsonify({'error': f'Erreur : {str(e)}'}), 500

# =====================
# OPÉRATIONS S3 DIRECTES
# =====================
@app.route('/api/s3/list', methods=['GET'])
def list_s3_objects():
    """Lister directement les objets dans le bucket S3."""
    prefix = request.args.get('prefix', '')
    try:
        response = s3_client.list_objects_v2(
            Bucket=Config.S3_BUCKET,
            Prefix=prefix,
            MaxKeys=100
        )
        objects = []
        for obj in response.get('Contents', []):
            objects.append({
                'key': obj['Key'],
                'size': obj['Size'],
                'last_modified': obj['LastModified'].isoformat()
            })
        return jsonify({'bucket': Config.S3_BUCKET, 'prefix': prefix, 'objects': objects})
    except ClientError as e:
        return jsonify({'error': str(e)}), 500

# =====================
# LANCEMENT
# =====================
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
PYEOF

# ---------------------
# 5. Créer le service systemd
# ---------------------
echo "[5/6] Configuration du service systemd..."
cat > /etc/systemd/system/flask-app.service << 'SVCEOF'
[Unit]
Description=Flask Cloud Application
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/flask-app
Environment=PATH=/opt/flask-app/venv/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=/opt/flask-app/venv/bin/gunicorn --workers 3 --bind 0.0.0.0:5000 app:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable flask-app
systemctl start flask-app

# ---------------------
# 6. Configurer Nginx comme reverse proxy
# ---------------------
echo "[6/6] Configuration de Nginx..."
cat > /etc/nginx/sites-available/flask-app << 'NGEOF'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        client_max_body_size 16M;
    }
}
NGEOF

rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/flask-app /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx

echo "========== PROVISIONING TERMINÉ =========="
echo "L'application Flask est accessible sur le port 80 et 5000"
