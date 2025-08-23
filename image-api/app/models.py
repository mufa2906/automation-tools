from sqlalchemy import Column, Integer, String, DateTime
from sqlalchemy.sql import func
from .database import Base

class FileMeta(Base):
    __tablename__ = "files"

    id = Column(Integer, primary_key=True, index=True)
    uuid_name = Column(String, unique=True, index=True, nullable=False)
    original_name = Column(String, nullable=False)
    content_type = Column(String, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
