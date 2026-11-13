# FastAPI on uvicorn (uvloop + httptools when installed): GET /plain answers "ok".
# bench/run.sh starts it as: uvicorn app:app --workers N (N = COMPARE_WORKERS,
# 0 = every core), without access logs.
from fastapi import FastAPI
from fastapi.responses import PlainTextResponse

app = FastAPI()


@app.get("/plain", response_class=PlainTextResponse)
async def plain() -> str:
    return "ok"
