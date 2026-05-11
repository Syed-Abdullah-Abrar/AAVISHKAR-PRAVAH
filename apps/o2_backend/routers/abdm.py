"""
ABDM Router — O2 Platform FastAPI Backend

Phase 2 U1: Local ABHA Generator
When USE_LIVE_ABDM=true (with NHA credentials), routes to live NHA API.
For hackathon demo: uses local ABHA generator with Mod97 validation.

Endpoints:
- POST /abdm/generate-abha — Generate new ABHA number
- POST /abdm/validate-abha — Validate ABHA checksum
- POST /abdm/register-patient — Register patient with ABHA
- GET /abdm/patient/{patient_id} — Get patient by ID
- GET /abdm/patient-by-abha/{abha} — Get patient by ABHA number
"""

import os
import uuid
from datetime import datetime
from typing import Optional
from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel

from services.abha_generator import (
    generate_abha_number,
    validate_abha,
    abha_to_uuid,
    generate_abha_with_name,
    format_abha_display,
)
from services.database import patient_repo

router = APIRouter(prefix="/abdm", tags=["abdm"])

USE_LIVE_ABDM = os.getenv("USE_LIVE_ABDM", "false").lower() == "true"


# --- Request/Response Models ---

class AbhaGenerateRequest(BaseModel):
    name: Optional[str] = None
    date_of_birth: Optional[str] = None
    gender: Optional[str] = None


class AbhaGenerateResponse(BaseModel):
    abha_number: str
    display_format: str
    valid: bool
    source: str


class AbhaValidateRequest(BaseModel):
    abha_number: str


class AbhaValidateResponse(BaseModel):
    abha_number: str
    valid: bool
    source: str
    display_format: Optional[str] = None


class PatientRegistrationRequest(BaseModel):
    abha_number: str
    name: str
    phone: Optional[str] = None
    date_of_birth: Optional[str] = None
    gender: Optional[str] = None
    emergency_contact: Optional[str] = None
    emergency_contact_phone: Optional[str] = None
    chw_telegram_id: Optional[str] = None
    emergency_contact_telegram: Optional[str] = None
    phc_id: str


class PatientRegistrationResponse(BaseModel):
    patient_id: str
    abha_number: str
    display_format: str
    name: str
    risk_level: str
    created_at: str


class PatientResponse(BaseModel):
    id: str
    abha_number: str
    display_format: str
    name: str
    phone: Optional[str]
    date_of_birth: Optional[str]
    gender: Optional[str]
    phc_id: str
    risk_level: str
    created_at: str


# --- Endpoints ---

@router.post("/generate-abha", response_model=AbhaGenerateResponse)
async def generate_abha(request: AbhaGenerateRequest):
    """
    Generate a new valid ABHA number with Mod97 checksum.
    
    Optionally include name/dob/gender to pre-fill registration data.
    """
    if request.name and request.date_of_birth and request.gender:
        result = generate_abha_with_name(request.name, request.date_of_birth, request.gender)
        return AbhaGenerateResponse(
            abha_number=result["abha_number"],
            display_format=format_abha_display(result["abha_number"]),
            valid=True,
            source="local_generator",
        )
    
    abha = generate_abha_number()
    return AbhaGenerateResponse(
        abha_number=abha,
        display_format=format_abha_display(abha),
        valid=True,
        source="local_generator",
    )


@router.post("/validate-abha", response_model=AbhaValidateResponse)
async def validate_abha_number(request: AbhaValidateRequest):
    """
    Validate an ABHA number using Mod97-10 algorithm.
    
    Returns validation status and formatted display.
    """
    abha = request.abha_number.strip()
    is_valid = validate_abha(abha)
    
    if not is_valid:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid ABHA checksum. Received: {abha}"
        )
    
    return AbhaValidateResponse(
        abha_number=abha,
        valid=True,
        source="local_validator",
        display_format=format_abha_display(abha),
    )


@router.post("/register-patient", response_model=PatientRegistrationResponse)
async def register_patient(request: PatientRegistrationRequest):
    """
    Register a new patient with their ABHA number.
    
    Validates ABHA checksum before storing.
    Creates a deterministic internal ID from ABHA.
    """
    abha = request.abha_number.strip()
    
    # Validate ABHA
    if not validate_abha(abha):
        raise HTTPException(
            status_code=400,
            detail=f"Invalid ABHA checksum: {abha}. Please provide a valid 14-digit ABHA."
        )
    
    # Check if patient with this ABHA already exists
    existing = await patient_repo.get_by_abha(abha)
    if existing:
        raise HTTPException(
            status_code=409,
            detail=f"Patient with ABHA {format_abha_display(abha)} already registered as ID: {existing['id']}"
        )
    
    # Create patient record
    patient_id = abha_to_uuid(abha)
    patient_data = {
        "id": patient_id,
        "abha_number": abha,
        "name": request.name,
        "phone": request.phone,
        "date_of_birth": request.date_of_birth,
        "gender": request.gender,
        "emergency_contact": request.emergency_contact,
        "emergency_contact_phone": request.emergency_contact_phone,
        "chw_telegram_id": request.chw_telegram_id,
        "emergency_contact_telegram": request.emergency_contact_telegram,
        "phc_id": request.phc_id,
        "risk_level": "LOW",
    }
    
    await patient_repo.create(patient_data)
    
    return PatientRegistrationResponse(
        patient_id=patient_id,
        abha_number=abha,
        display_format=format_abha_display(abha),
        name=request.name,
        risk_level="LOW",
        created_at=datetime.utcnow().isoformat(),
    )


@router.get("/patient/{patient_id}", response_model=PatientResponse)
async def get_patient(patient_id: str):
    """Get patient by internal ID."""
    patient = await patient_repo.get(patient_id)
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")
    
    return PatientResponse(
        id=patient["id"],
        abha_number=patient["abha_number"],
        display_format=format_abha_display(patient["abha_number"]),
        name=patient["name"],
        phone=patient.get("phone"),
        date_of_birth=patient.get("date_of_birth"),
        gender=patient.get("gender"),
        phc_id=patient["phc_id"],
        risk_level=patient["risk_level"],
        created_at=patient["created_at"],
    )


@router.get("/patient-by-abha/{abha}", response_model=PatientResponse)
async def get_patient_by_abha(abha: str):
    """Get patient by ABHA number."""
    abha = abha.strip()
    if not validate_abha(abha):
        raise HTTPException(status_code=400, detail="Invalid ABHA format")
    
    patient = await patient_repo.get_by_abha(abha)
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")
    
    return PatientResponse(
        id=patient["id"],
        abha_number=patient["abha_number"],
        display_format=format_abha_display(patient["abha_number"]),
        name=patient["name"],
        phone=patient.get("phone"),
        date_of_birth=patient.get("date_of_birth"),
        gender=patient.get("gender"),
        phc_id=patient["phc_id"],
        risk_level=patient["risk_level"],
        created_at=patient["created_at"],
    )


@router.get("/patients/phc/{phc_id}")
async def list_patients_by_phc(phc_id: str):
    """List all patients for a PHC."""
    patients = await patient_repo.list_by_phc(phc_id)
    return {
        "phc_id": phc_id,
        "count": len(patients),
        "patients": [
            {
                "id": p["id"],
                "abha_display": format_abha_display(p["abha_number"]),
                "name": p["name"],
                "risk_level": p["risk_level"],
                "created_at": p["created_at"],
            }
            for p in patients
        ]
    }


@router.get("/patients/phc/{phc_id}/high-risk")
async def list_high_risk_patients(phc_id: str):
    """List HIGH risk patients for a PHC."""
    patients = await patient_repo.list_high_risk(phc_id)
    return {
        "phc_id": phc_id,
        "count": len(patients),
        "patients": [
            {
                "id": p["id"],
                "abha_display": format_abha_display(p["abha_number"]),
                "name": p["name"],
                "risk_level": p["risk_level"],
                "phone": p.get("phone"),
                "chw_telegram_id": p.get("chw_telegram_id"),
            }
            for p in patients
        ]
    }


# --- Live ABDM Integration (when credentials available) ---

async def call_nha_api_verify_abha(abha: str) -> dict:
    """
    Call live NHA API to verify ABHA.
    
    Only called when USE_LIVE_ABDM=true.
    Requires NHA_CLIENT_ID, NHA_CLIENT_SECRET, NHA_HMAC_KEY.
    """
    import hmac
    import hashlib
    import time
    
    if not USE_LIVE_ABDM:
        raise RuntimeError("USE_LIVE_ABDM is not enabled")
    
    NHA_API_BASE = os.getenv("NHA_API_BASE_URL", "https://abdm.gov.in/api/v1")
    CLIENT_ID = os.getenv("NHA_CLIENT_ID")
    CLIENT_SECRET = os.getenv("NHA_CLIENT_SECRET")
    HMAC_KEY = os.getenv("NHA_HMAC_KEY")
    
    if not all([CLIENT_ID, CLIENT_SECRET, HMAC_KEY]):
        raise RuntimeError("NHA credentials not configured")
    
    timestamp = datetime.utcnow().isoformat()
    canonical = f"{CLIENT_ID}|{timestamp}|{abha}"
    signature = hmac.new(
        HMAC_KEY.encode(),
        canonical.encode(),
        hashlib.sha256
    ).digest().hex()
    
    # In production: use httpx or requests to call NHA API
    # This is the structure when the integration is enabled
    raise NotImplementedError("Live NHA API call - configure when credentials available")