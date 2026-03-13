import os
import uuid
from datetime import datetime

import boto3
from botocore.exceptions import ClientError
from flask import Flask, jsonify, render_template_string, request
from flask_cors import CORS
from flask_sqlalchemy import SQLAlchemy

from config import Config

app = Flask(__name__)
app.config.from_object(Config)
CORS(app)
db = SQLAlchemy(app)

s3_client = boto3.client("s3", region_name=Config.AWS_REGION)


class FileMetadata(db.Model):
    __tablename__ = "file_metadata"

    id = db.Column(
        db.String(36), primary_key=True, default=lambda: str(uuid.uuid4())
    )
    filename = db.Column(db.String(255), nullable=False)
    s3_key = db.Column(db.String(500), nullable=False)
    file_type = db.Column(db.String(50))
    file_size = db.Column(db.Integer)
    category = db.Column(db.String(50), default="uploads")
    description = db.Column(db.Text)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(
        db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow
    )

    def to_dict(self):
        return {
            "id": self.id,
            "filename": self.filename,
            "s3_key": self.s3_key,
            "file_type": self.file_type,
            "file_size": self.file_size,
            "category": self.category,
            "description": self.description,
            "created_at": self.created_at.isoformat(),
            "updated_at": self.updated_at.isoformat(),
        }


with app.app_context():
    db.create_all()


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
             -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
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
        <p class="subtitle">Infrastructure deployee avec Terraform sur AWS</p>
        <p style="margin-bottom:30px"><span class="status">En ligne</span></p>
        <div class="card">
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
            <div class="endpoint">Region : {{ region }}</div>
            <div class="endpoint">BDD : {{ db_status }}</div>
        </div>
    </div>
</body>
</html>
"""


@app.route("/")
def home():
    return render_template_string(
        HOME_HTML,
        bucket=Config.S3_BUCKET,
        region=Config.AWS_REGION,
        db_status="PostgreSQL (RDS)" if Config.DB_ENABLED else "SQLite (local)",
    )


@app.route("/api/health")
def health():
    status = {"app": "ok", "timestamp": datetime.utcnow().isoformat()}
    try:
        s3_client.head_bucket(Bucket=Config.S3_BUCKET)
        status["s3"] = "ok"
    except Exception as e:
        status["s3"] = f"error: {str(e)}"
    try:
        db.session.execute(db.text("SELECT 1"))
        status["database"] = "ok"
    except Exception as e:
        status["database"] = f"error: {str(e)}"
    return jsonify(status)


@app.route("/api/files/upload", methods=["POST"])
def upload_file():
    if "file" not in request.files:
        return jsonify({"error": "Aucun fichier fourni"}), 400
    file = request.files["file"]
    if file.filename == "":
        return jsonify({"error": "Nom de fichier vide"}), 400

    category = request.form.get("category", "uploads")
    description = request.form.get("description", "")
    file_id = str(uuid.uuid4())
    s3_key = f"{category}/{file_id}_{file.filename}"

    try:
        s3_client.upload_fileobj(
            file,
            Config.S3_BUCKET,
            s3_key,
            ExtraArgs={"ContentType": file.content_type},
        )
        metadata = FileMetadata(
            id=file_id,
            filename=file.filename,
            s3_key=s3_key,
            file_type=file.content_type,
            file_size=file.content_length or 0,
            category=category,
            description=description,
        )
        db.session.add(metadata)
        db.session.commit()
        return jsonify({"message": "Fichier uploade", "file": metadata.to_dict()}), 201
    except ClientError as e:
        return jsonify({"error": f"Erreur S3 : {str(e)}"}), 500


@app.route("/api/files", methods=["GET"])
def list_files():
    category = request.args.get("category")
    query = FileMetadata.query
    if category:
        query = query.filter_by(category=category)
    files = query.order_by(FileMetadata.created_at.desc()).all()
    return jsonify({"count": len(files), "files": [f.to_dict() for f in files]})


@app.route("/api/files/<file_id>", methods=["GET"])
def get_file(file_id):
    file = FileMetadata.query.get(file_id)
    if not file:
        return jsonify({"error": "Fichier non trouve"}), 404
    return jsonify(file.to_dict())


@app.route("/api/files/<file_id>", methods=["PUT"])
def update_file(file_id):
    file = FileMetadata.query.get(file_id)
    if not file:
        return jsonify({"error": "Fichier non trouve"}), 404
    data = request.get_json()
    if "description" in data:
        file.description = data["description"]
    if "category" in data:
        old_key = file.s3_key
        new_key = f"{data['category']}/{file.id}_{file.filename}"
        try:
            s3_client.copy_object(
                Bucket=Config.S3_BUCKET,
                CopySource={"Bucket": Config.S3_BUCKET, "Key": old_key},
                Key=new_key,
            )
            s3_client.delete_object(Bucket=Config.S3_BUCKET, Key=old_key)
            file.s3_key = new_key
            file.category = data["category"]
        except ClientError as e:
            return jsonify({"error": f"Erreur S3 : {str(e)}"}), 500
    db.session.commit()
    return jsonify({"message": "Fichier mis a jour", "file": file.to_dict()})


@app.route("/api/files/<file_id>", methods=["DELETE"])
def delete_file(file_id):
    file = FileMetadata.query.get(file_id)
    if not file:
        return jsonify({"error": "Fichier non trouve"}), 404
    try:
        s3_client.delete_object(Bucket=Config.S3_BUCKET, Key=file.s3_key)
    except ClientError:
        pass
    db.session.delete(file)
    db.session.commit()
    return jsonify({"message": f"Fichier {file.filename} supprime"})


@app.route("/api/files/<file_id>/download", methods=["GET"])
def download_file(file_id):
    file = FileMetadata.query.get(file_id)
    if not file:
        return jsonify({"error": "Fichier non trouve"}), 404
    try:
        url = s3_client.generate_presigned_url(
            "get_object",
            Params={"Bucket": Config.S3_BUCKET, "Key": file.s3_key},
            ExpiresIn=3600,
        )
        return jsonify({"download_url": url, "expires_in": 3600})
    except ClientError as e:
        return jsonify({"error": f"Erreur : {str(e)}"}), 500


@app.route("/api/s3/list", methods=["GET"])
def list_s3_objects():
    prefix = request.args.get("prefix", "")
    try:
        response = s3_client.list_objects_v2(
            Bucket=Config.S3_BUCKET, Prefix=prefix, MaxKeys=100
        )
        objects = [
            {
                "key": obj["Key"],
                "size": obj["Size"],
                "last_modified": obj["LastModified"].isoformat(),
            }
            for obj in response.get("Contents", [])
        ]
        return jsonify({"bucket": Config.S3_BUCKET, "prefix": prefix, "objects": objects})
    except ClientError as e:
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
