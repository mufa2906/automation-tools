from pydantic import BaseModel
from datetime import datetime

class FileMetaBase(BaseModel):
    original_name: str
    content_type: str

class FileMetaCreate(FileMetaBase):
    uuid_name: str

class FileMetaResponse(FileMetaBase):
    id: int
    uuid_name: str
    created_at: datetime

    class Config:
        from_attributes = True  # pengganti orm_mode di v2
