from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from app.db.repositories.user_repo import UserRepository
from app.db.session import async_session_factory

router = APIRouter(tags=["users"])


class UserResponse(BaseModel):
    id: str
    device_id: str
    display_name: str | None
    preferences: dict | None
    relationship_status: str | None
    extracted_facts: dict | None


class UpdateUserRequest(BaseModel):
    display_name: str | None = None
    preferences: dict | None = None
    relationship_status: str | None = None


@router.get("/{device_id}", response_model=UserResponse)
async def get_user(device_id: str):
    async with async_session_factory() as session:
        repo = UserRepository(session)
        user = await repo.get_or_create(device_id)
        return user


@router.put("/{user_id}", response_model=UserResponse)
async def update_user(user_id: str, body: UpdateUserRequest):
    async with async_session_factory() as session:
        repo = UserRepository(session)
        updates = body.model_dump(exclude_none=True)
        user = await repo.update_profile(user_id, **updates)
        if user is None:
            raise HTTPException(status_code=404, detail="User not found")
        return user
