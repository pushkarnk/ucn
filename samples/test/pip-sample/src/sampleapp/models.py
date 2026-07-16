"""Domain models for the sample app."""

from pydantic import BaseModel, Field


class Greeting(BaseModel):
    id: int
    content: str


class Health(BaseModel):
    status: str = "healthy"


class Echo(BaseModel):
    message: str = Field(min_length=1)
