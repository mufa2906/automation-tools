from fastapi import FastAPI, File, UploadFile, HTTPException, Depends, Request
from fastapi.responses import FileResponse, JSONResponse
import logging
from logging.handlers import RotatingFileHandler
import shutil
from pathlib import Path
import uuid

from sqlalchemy.orm import Session
from . import models, schemas
from .database import engine, SessionLocal

# --- Setup DB ---
models.Base.metadata.create_all(bind=engine)

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# --- Setup FastAPI ---
app = FastAPI()

# --- Setup Logging ---
LOG_DIR = Path("logs")
LOG_DIR.mkdir(exist_ok=True)
logger = logging.getLogger("file_api")
logger.setLevel(logging.INFO)
fmt = logging.Formatter("%(asctime)s [%(levelname)s] %(name)s - %(message)s")

sh = logging.StreamHandler()
sh.setFormatter(fmt)
logger.addHandler(sh)

fh = RotatingFileHandler(str(LOG_DIR / "app.log"), maxBytes=5*1024*1024, backupCount=3)
fh.setFormatter(fmt)
logger.addHandler(fh)

# --- Setup Upload Folder ---
UPLOAD_DIR = Path("uploads")
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)

@app.get("/")
def root():
    return {"status": "API running"}

@app.post("/upload", response_model=schemas.FileMetaResponse)
async def upload_file(
    request: Request,
    file: UploadFile = File(...),
    db: Session = Depends(get_db)
):
    if not file.filename:
        logger.warning("Missing filename from %s", request.client.host)
        raise HTTPException(status_code=400, detail="Filename missing")

    # generate uuid name
    unique_name = f"{uuid.uuid4().hex}{Path(file.filename).suffix}"
    file_path = UPLOAD_DIR / unique_name

    try:
        with file_path.open("wb") as buffer:
            shutil.copyfileobj(file.file, buffer)

        db_file = models.FileMeta(
            uuid_name=unique_name,
            original_name=file.filename,
            content_type=file.content_type,
        )
        db.add(db_file)
        db.commit()
        db.refresh(db_file)

        logger.info("Uploaded %s as %s", file.filename, unique_name)
        return db_file

    except Exception as e:
        logger.exception("Upload failed: %s", e)
        raise HTTPException(status_code=500, detail="Internal Server Error")

@app.get("/files")
def list_files(db: Session = Depends(get_db)):
    files = db.query(models.FileMeta).all()
    return {"count": len(files), "files": files}

@app.get("/files/{uuid_name}")
def download_file(uuid_name: str, db: Session = Depends(get_db)):
    db_file = db.query(models.FileMeta).filter(models.FileMeta.uuid_name == uuid_name).first()
    if not db_file:
        raise HTTPException(status_code=404, detail="File not found")

    target = UPLOAD_DIR / db_file.uuid_name
    if not target.exists():
        raise HTTPException(status_code=404, detail="File missing in storage")

    return FileResponse(target, media_type=db_file.content_type, filename = f"{db_file.original_name}_{db_file.uuid_name}")

@app.exception_handler(Exception)
async def global_error(request: Request, exc: Exception):
    logger.exception("Unhandled error on %s %s: %s", request.method, request.url.path, exc)
    return JSONResponse(status_code=500, content={"detail": "Internal Server Error"})
