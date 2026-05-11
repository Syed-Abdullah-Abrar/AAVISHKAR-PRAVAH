"""
Risk Assessment Router — O2 Platform FastAPI Backend

POST /risk
Accepts patient vital signs, returns traffic-light triage risk assessment.

Phase 1: Rule-based mock (no real ML model)
Phase 2+: Quantized Gradient Boosting model on-device

Risk Levels:
- LOW: Score 0-1, routine care
- MEDIUM: Score 2-3, scheduled follow-up within 48h
- HIGH: Score 4-5, urgent follow-up within 24h
- EMERGENCY: Score 6+, immediate referral
"""

from fastapi import APIRouter, HTTPException, Header
from typing import Optional

from models import (
    RiskAssessmentRequest,
    RiskAssessmentResponse,
    VitalsInput,
    FlaggedFactor,
)
from services.risk_model import RiskModelService

router = APIRouter()
risk_service = RiskModelService()


@router.post("/risk", response_model=RiskAssessmentResponse)
async def assess_risk(
    request: RiskAssessmentRequest,
    x_chw_id: Optional[str] = Header(None, description="CHW ID for audit"),
):
    """
    Assess maternal health risk from vital signs.

    Returns traffic-light triage:
    - LOW (0-1): Routine care, next visit in 7 days
    - MEDIUM (2-3): Schedule follow-up within 48h
    - HIGH (4-5): Urgent follow-up within 24h
    - EMERGENCY (6+): Immediate referral to PHC/hospital
    """
    try:
        result = risk_service.assess(request)
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/risk/levels")
async def get_risk_levels():
    """Return the risk level definitions and thresholds."""
    return {
        "levels": [
            {
                "level": "LOW",
                "score_range": "0-1",
                "action": "Routine care at next scheduled visit",
                "next_review_days": 7,
            },
            {
                "level": "MEDIUM",
                "score_range": "2-3",
                "action": "Schedule follow-up within 48 hours",
                "next_review_days": 2,
            },
            {
                "level": "HIGH",
                "score_range": "4-5",
                "action": "Urgent follow-up within 24 hours",
                "next_review_days": 1,
            },
            {
                "level": "EMERGENCY",
                "score_range": "6+",
                "action": "Immediate referral to PHC/hospital",
                "next_review_days": 0,
            },
        ],
        "scoring": {
            "systolic_bp_above_160": 3,
            "systolic_bp_140_160": 2,
            "systolic_bp_120_140": 1,
            "diastolic_bp_above_100": 2,
            "diastolic_bp_90_100": 1,
            "hemoglobin_below_7": 3,
            "hemoglobin_7_to_11": 1,
            "weight_gain_abnormal": 1,
            "temperature_above_38": 2,
            "fetal_hr_out_of_range": 2,
        },
    }