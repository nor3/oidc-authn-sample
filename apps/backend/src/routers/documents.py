import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter(prefix="/documents", tags=["documents"])

# デモ用インメモリストア
_store: dict[str, dict] = {}


class DocumentCreate(BaseModel):
    title: str
    content: str


class Document(BaseModel):
    id: str
    title: str
    content: str
    owner: str
    created_at: datetime


@router.get("", response_model=list[Document])
async def list_documents():
    return list(_store.values())


@router.post("", response_model=Document, status_code=201)
async def create_document(body: DocumentCreate):
    doc = {
        "id": str(uuid.uuid4()),
        "title": body.title,
        "content": body.content,
        "owner": "system",
        "created_at": datetime.now(timezone.utc),
    }
    _store[doc["id"]] = doc
    return doc


@router.get("/{doc_id}", response_model=Document)
async def get_document(doc_id: str):
    doc = _store.get(doc_id)
    if not doc:
        raise HTTPException(status_code=404, detail="Document not found")
    return doc


@router.put("/{doc_id}", response_model=Document)
async def update_document(doc_id: str, body: DocumentCreate):
    if doc_id not in _store:
        raise HTTPException(status_code=404, detail="Document not found")
    _store[doc_id].update({"title": body.title, "content": body.content})
    return _store[doc_id]


@router.delete("/{doc_id}", status_code=204)
async def delete_document(doc_id: str):
    if doc_id not in _store:
        raise HTTPException(status_code=404, detail="Document not found")
    del _store[doc_id]
