from fastapi import FastAPI, File, UploadFile, HTTPException, Request
from fastapi.responses import FileResponse, JSONResponse
import logging
from logging.handlers import RotatingFileHandler
import shutil
from pathlib import Path

app = FastAPI()

# Setup logging
LOG_DIR = Path("logs")
LOG_DIR.mkdir(exist_ok=True)
logger = logging.getLogger("image_api")
logger.setLevel(logging.INFO)

fmt = logging.Formatter("%(asctime)s [%(levelname)s] %(name)s - %(message)s")

sh = logging.StreamHandler()
sh.setFormatter(fmt)
logger.addHandler(sh)

fh = RotatingFileHandler(str(LOG_DIR / "app.log"), maxBytes=5*1024*1024, backupCount=3)
fh.setFormatter(fmt)
logger.addHandler(fh)
# ------------------------------------------------------

UPLOAD_DIR = Path("uploads")
UPLOAD_DIR.mkdir(exist_ok=True)

@app.get("/")
def read_root():
    return {"status": "API is running"}

@app.post("/upload")
async def upload_image(request: Request, file: UploadFile = File(...)):
    # Validasi name file
    if not file.filename:
        logger.warning("Upload attempt with missing filename from %s", request.client.host)
        raise HTTPException(status_code=400, detail="Filename missing")

    file_path = UPLOAD_DIR / file.filename
    try:
        with file_path.open("wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
        logger.info("Uploaded file '%s' (%s) from %s", file.filename, file.content_type, request.client.host)
        return {"filename": file.filename, "message": "File uploaded successfully"}
    except Exception as e:
        logger.exception("Upload failed for '%s': %s", file.filename, e)
        raise HTTPException(status_code=500, detail="Internal Server Error")
    
@app.get("/files")
def list_file():
    files = [p.name for p in UPLOAD_DIR.iterdir() if p.is_file()]
    logger.info("List files requested: %d item(s)", len(files))
    return {"count" : len(files), "files": files}

@app.get("/files/{filename}")
def download_file(filename: str):
    target = (UPLOAD_DIR / filename).resolve()
    if UPLOAD_DIR.resolve() not in target.parents and target != UPLOAD_DIR.resolve():
        logger.warning("Path traversal blocked: %s", filename)
        raise HTTPException(status_code=400, detail="invalid path")
    if not target.exists():
        logger.info("Download not found: %s", filename)
        raise HTTPException(status_code=404, detail="File not found")
    logger.info("Download: %s", filename)
    return FileResponse(target)

# --- GLOBAL ERROR HANDLER (catch-all) ---
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.exception("Unhandled error on %s %s: %s", request.method, request.url.path, exc)
    return JSONResponse(status_code=500, content={"detail": "Internal Server Error"})
