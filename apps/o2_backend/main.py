"""
O2 Platform — FastAPI Backend
Main Application Entry Point

Phase 1 MVP:
- POST /risk — Risk Assessment (rule-based mock)
- POST /sbar — SBAR Clinical Handover Generation (LLM)
- GET /health — Health check

All endpoints return structured JSON.
LLM integration with strict output schema validation.
"""

import os
from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException, Header, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from dotenv import load_dotenv

from routers import risk, sbar, abdm, visits, dashboard, ivr
from services.database import init_db
from services.ml_risk_scorer import init_model

# Load environment variables
load_dotenv()

# ─── App Lifespan ─────────────────────────────────────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Startup and shutdown events for the FastAPI application.
    Initialize services on startup, cleanup on shutdown.
    """
    # Startup
    print("[O2 Backend] Starting O2 FastAPI Server...")
    print(f"[O2 Backend] Environment: {os.getenv('ENV', 'development')}")
    print(f"[O2 Backend] AI Provider: {os.getenv('AI_PROVIDER', 'openai')}")
    
    # Phase 2: Initialize SQLite database + ML model
    await init_db()
    await init_model()
    
    yield
    
    # Shutdown
    print("[O2 Backend] Shutting down O2 FastAPI Server...")

# ─── FastAPI Application ───────────────────────────────────────────────────────

app = FastAPI(
    title="O2 Platform AI Backend",
    description="""
    ## O2 Platform — AI Inference Server
    
    Provides clinical decision support for Community Health Workers:
    
    ### Risk Assessment
    - Accepts patient vital signs
    - Returns traffic-light triage: Low / Medium / High / Emergency
    - Based on WHO maternal health guidelines
    
    ### SBAR Clinical Handover
    - Accepts longitudinal patient data
    - Generates structured SBAR clinical handover documents
    - LLM-powered with strict output schema validation
    
    ### Authentication
    All endpoints require `X-API-Key` header with valid API key.
    """,
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
    lifespan=lifespan,
)

# ─── CORS Configuration ───────────────────────────────────────────────────────

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # DEMO ONLY — lock down post-pitch
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ─── API Routers ──────────────────────────────────────────────────────────────

app.include_router(risk.router, prefix="/risk", tags=["Risk Assessment"])
app.include_router(sbar.router, prefix="/sbar", tags=["SBAR Generation"])
app.include_router(abdm.router, tags=["ABDM / ABHA"])
app.include_router(visits.router, prefix="/visits", tags=["Visits / GPS"])
app.include_router(dashboard.router, tags=["Supervisor Dashboard"])
app.include_router(ivr.router, tags=["IVR / Telegram"])

# ─── Health Check ─────────────────────────────────────────────────────────────

@app.get("/health", tags=["Health"])
async def health_check():
    """
    Health check endpoint for load balancers and monitoring.
    Returns server status and version.
    """
    return {
        "status": "healthy",
        "service": "o2-ai-backend",
        "version": "1.0.0",
        "environment": os.getenv("ENV", "development"),
    }

# ─── Root Endpoint ───────────────────────────────────────────────────────────

@app.get("/", tags=["Root"])
async def root():
    """
    Root endpoint with API information.
    """
    return {
        "name": "O2 Platform AI Backend",
        "version": "1.0.0",
        "docs": "/docs",
        "health": "/health",
    }

# ─── Error Handlers ──────────────────────────────────────────────────────────

@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    """Handle HTTP exceptions with structured JSON response."""
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "error": exc.detail,
            "status_code": exc.status_code,
        },
    )

@app.exception_handler(Exception)
async def general_exception_handler(request: Request, exc: Exception):
    """Handle unexpected exceptions."""
    print(f"[O2 Backend] Unexpected error: {exc}")
    return JSONResponse(
        status_code=500,
        content={
            "error": "Internal server error",
            "detail": str(exc) if os.getenv("ENV") == "development" else "See server logs",
        },
    )

# ─── Startup ────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
        log_level="info",
    )