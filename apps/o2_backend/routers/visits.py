"""
Visits Router — O2 Platform Phase 2
GPS-tagged home visit logging + auto-scheduling from risk level.
"""

import os
import uuid
from datetime import datetime, timedelta
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional

from services.database import visit_repo, schedule_repo, patient_repo

router = APIRouter(prefix="/visits", tags=["Visits"])


class VisitLogRequest(BaseModel):
    patient_id: str
    latitude: float
    longitude: float
    chw_id: str
    notes: Optional[str] = None


class VisitLogResponse(BaseModel):
    visit_id: str
    patient_id: str
    latitude: float
    longitude: float
    recorded_at: str
    follow_up_scheduled: Optional[str] = None
    follow_up_reason: Optional[str] = None


class ScheduleRequest(BaseModel):
    patient_id: str
    scheduled_at: str  # ISO format
    reason: Optional[str] = None
    auto_generated: bool = False


# Auto-schedule rules based on risk
RISK_SCHEDULE = {
    "EMERGENCY": timedelta(hours=4),
    "HIGH": timedelta(hours=24),
    "MEDIUM": timedelta(days=3),
    "LOW": timedelta(days=7),
}


@router.post("/log", response_model=VisitLogResponse)
async def log_visit(req: VisitLogRequest):
    """Log GPS-tagged home visit and auto-schedule follow-up."""
    # Check patient exists
    patient = await patient_repo.get(req.patient_id)
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")

    # Create visit record
    visit_id = str(uuid.uuid4())
    await visit_repo.create({
        "id": visit_id,
        "patient_id": req.patient_id,
        "latitude": req.latitude,
        "longitude": req.longitude,
        "chw_id": req.chw_id,
        "notes": req.notes,
    })

    # Auto-schedule follow-up based on patient risk level
    risk = patient.get("risk_level", "LOW")
    schedule_delay = RISK_SCHEDULE.get(risk, timedelta(days=7))
    scheduled_at = datetime.utcnow() + schedule_delay

    schedule_id = str(uuid.uuid4())
    await schedule_repo.create({
        "id": schedule_id,
        "patient_id": req.patient_id,
        "scheduled_at": scheduled_at.isoformat(),
        "status": "pending",
        "auto_generated": 1,
        "reason": f"Auto-scheduled from {risk} risk visit",
    })

    return VisitLogResponse(
        visit_id=visit_id,
        patient_id=req.patient_id,
        latitude=req.latitude,
        longitude=req.longitude,
        recorded_at=datetime.utcnow().isoformat(),
        follow_up_scheduled=scheduled_at.isoformat(),
        follow_up_reason=f"Auto-scheduled {risk} follow-up",
    )


@router.get("/patient/{patient_id}")
async def list_patient_visits(patient_id: str):
    """List all visits for a patient."""
    visits = await visit_repo.list_by_patient(patient_id)
    return {"patient_id": patient_id, "visits": visits, "count": len(visits)}


@router.get("/phc/{phc_id}/recent")
async def list_recent_visits(phc_id: str, days: int = 7):
    """List recent visits for a PHC."""
    visits = await visit_repo.list_recent(phc_id, days)
    return {"phc_id": phc_id, "visits": visits, "count": len(visits)}


@router.get("/schedules/phc/{phc_id}/pending")
async def list_pending_schedules(phc_id: str):
    """List pending follow-up schedules for a PHC."""
    schedules = await schedule_repo.list_pending(phc_id)
    return {"phc_id": phc_id, "schedules": schedules, "count": len(schedules)}


@router.post("/schedules")
async def create_schedule(req: ScheduleRequest):
    """Manually create a follow-up schedule."""
    schedule_id = str(uuid.uuid4())
    await schedule_repo.create({
        "id": schedule_id,
        "patient_id": req.patient_id,
        "scheduled_at": req.scheduled_at,
        "status": "pending",
        "auto_generated": 1 if req.auto_generated else 0,
        "reason": req.reason,
    })
    return {"schedule_id": schedule_id, "status": "created"}