"""
バックエンドAPIのユニットテスト。
OPA_MIDDLEWARE=false (デフォルト) の状態でAPIのCRUD動作を検証する。
"""

import pytest
from httpx import AsyncClient

from src.routers.documents import _store


@pytest.fixture(autouse=True)
def clear_store():
    """テスト毎にストアをリセットする"""
    _store.clear()
    yield
    _store.clear()


@pytest.mark.asyncio
async def test_health(client: AsyncClient):
    resp = await client.get("/health")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"


@pytest.mark.asyncio
async def test_list_documents_empty(client: AsyncClient):
    resp = await client.get("/api/v1/documents")
    assert resp.status_code == 200
    assert resp.json() == []


@pytest.mark.asyncio
async def test_create_document(client: AsyncClient):
    payload = {"title": "テストDoc", "content": "内容"}
    resp = await client.post("/api/v1/documents", json=payload)
    assert resp.status_code == 201
    data = resp.json()
    assert data["title"] == "テストDoc"
    assert "id" in data


@pytest.mark.asyncio
async def test_get_document(client: AsyncClient):
    # 作成
    create_resp = await client.post(
        "/api/v1/documents", json={"title": "Doc1", "content": "内容1"}
    )
    doc_id = create_resp.json()["id"]

    # 取得
    resp = await client.get(f"/api/v1/documents/{doc_id}")
    assert resp.status_code == 200
    assert resp.json()["id"] == doc_id


@pytest.mark.asyncio
async def test_get_document_not_found(client: AsyncClient):
    resp = await client.get("/api/v1/documents/nonexistent-id")
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_update_document(client: AsyncClient):
    create_resp = await client.post(
        "/api/v1/documents", json={"title": "Old", "content": "Old content"}
    )
    doc_id = create_resp.json()["id"]

    resp = await client.put(
        f"/api/v1/documents/{doc_id}",
        json={"title": "New", "content": "New content"},
    )
    assert resp.status_code == 200
    assert resp.json()["title"] == "New"


@pytest.mark.asyncio
async def test_delete_document(client: AsyncClient):
    create_resp = await client.post(
        "/api/v1/documents", json={"title": "ToDelete", "content": "bye"}
    )
    doc_id = create_resp.json()["id"]

    resp = await client.delete(f"/api/v1/documents/{doc_id}")
    assert resp.status_code == 204

    # 削除後は404
    get_resp = await client.get(f"/api/v1/documents/{doc_id}")
    assert get_resp.status_code == 404


@pytest.mark.asyncio
async def test_list_after_create(client: AsyncClient):
    await client.post("/api/v1/documents", json={"title": "A", "content": "a"})
    await client.post("/api/v1/documents", json={"title": "B", "content": "b"})

    resp = await client.get("/api/v1/documents")
    assert resp.status_code == 200
    assert len(resp.json()) == 2
