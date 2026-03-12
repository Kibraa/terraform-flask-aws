import os


class Config:
    """Configuration de l'application Flask."""

    S3_BUCKET = os.environ.get("S3_BUCKET", "flask-app-static-files-2025")
    AWS_REGION = os.environ.get("AWS_REGION", "eu-west-3")
    DB_ENABLED = os.environ.get("DB_ENABLED", "true").lower() == "true"

    if DB_ENABLED:
        DB_HOST = os.environ.get("DB_HOST", "localhost")
        DB_NAME = os.environ.get("DB_NAME", "flaskdb")
        DB_USER = os.environ.get("DB_USER", "flaskadmin")
        DB_PASS = os.environ.get("DB_PASS", "password")
        SQLALCHEMY_DATABASE_URI = (
            f"postgresql://{DB_USER}:{DB_PASS}@{DB_HOST}:5432/{DB_NAME}"
        )
    else:
        SQLALCHEMY_DATABASE_URI = "sqlite:///local.db"

    SQLALCHEMY_TRACK_MODIFICATIONS = False
    MAX_CONTENT_LENGTH = 16 * 1024 * 1024  # 16 Mo max
