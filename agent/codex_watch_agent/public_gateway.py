"""Small authenticated entry point for an HTTPS tunnel.

Run on loopback port 8788. Keep the existing LAN agent on 8787; the tunnel
must point here, rather than exposing diagnostics and raw usage endpoints.
"""
from typing import Annotated
import asyncio
import json

import httpx
import uvicorn
from fastapi import Depends, FastAPI, HTTPException, Query, Request
from fastapi.responses import JSONResponse

from .main import lifespan, require_token, settings
from .models import safe_error_summary
from .task_events import save_bark_config


app = FastAPI(lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)


@app.middleware("http")
async def prevent_caching(request, call_next):
    response = await call_next(request)
    response.headers["Cache-Control"] = "no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    return response


@app.get("/health")
async def health():
    return {"ok": True}


@app.get("/watch", dependencies=[Depends(require_token)])
async def watch(force: Annotated[bool, Query()] = False):
    try:
        # Never forward a caller-selected URL, path, or headers to the agent.
        async with httpx.AsyncClient(timeout=25, trust_env=False, follow_redirects=False) as client:
            upstream = await client.get(
                f"http://127.0.0.1:{settings.port}/watch",
                params={"force": "1" if force else "0"},
                headers={"x-watch-token": settings.watch_token.strip()},
            )
        upstream.raise_for_status()
        payload = upstream.json()
        if not isinstance(payload, dict) or not isinstance(payload.get("codex"), dict):
            raise ValueError("Invalid snapshot")
        # Compact payload has no credentials. Keep error details sanitized too.
        payload["codex"]["error"] = safe_error_summary(payload["codex"].get("error"))
        return JSONResponse(payload)
    except (httpx.HTTPError, ValueError):
        raise HTTPException(status_code=503, detail="Mac quota service unavailable") from None


@app.post('/notifications/bark', dependencies=[Depends(require_token)])
async def configure_bark(request: Request):
    body = bytearray()
    async for chunk in request.stream():
        body.extend(chunk)
        if len(body) > 4096:
            raise HTTPException(status_code=413, detail='Configuration too large')
    try:
        payload = json.loads(body)
        if not isinstance(payload, dict):
            raise ValueError()
        await asyncio.to_thread(save_bark_config, payload.get('address'))
    except (ValueError, IndexError):
        raise HTTPException(status_code=400, detail='Invalid Bark address') from None
    return {'ok': True, 'provider': 'bark'}


def run():
    uvicorn.run("codex_watch_agent.public_gateway:app", host="127.0.0.1", port=8788, access_log=False)


if __name__ == "__main__":
    run()
