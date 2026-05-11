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
from pydantic import BaseModel, Field, field_validator
from typing import Optional
from datetime import datetime

from services.risk_model import RiskModelService

router = APIRouter()
risk_service = RiskModelService()


# ─── Request/Response Models ─────────────────────────────────────────────────

class VitalsInput(BaseModel):
    """Patient vitals input for risk assessment."""
    
    patient_id: str = Field(..., description="FHIR Patient ID")
    vital_type: str = Field(..., description="Type of vital: blood_pressure, hemoglobin, etc.")
    value: str = Field(..., description="Vital value (e.g., '130/90' for BP, '11.5' for Hb)")
    unit: Optional[str] = Field(None, description="Unit of measurement (mmHg, g/dL, etc.)")
    recorded_at: datetime = Field(default_factory=datetime.now)
    
    @field_validator("vital_type")
    @classmethod
    def validate_vital_type(cls, v: str) -> str:
        allowed = [
            "blood_pressure", "heart_rate", "temperature",
            "weight", "height", "hemoglobin", "blood_sugar",
            "fetal_heart_rate"
        ]
        if v.lower() not in allowed:
            raise ValueError(f"vital_type must be one of {allowed}")
        return v.lower()


class RiskAssessmentRequest(BaseModel):
    """Full risk assessment request with multiple vitals."""
    
    patient_id: str = Field(..., description="FHIR Patient ID")
    chw_id: str = Field(..., description="CHW ID who recorded vitals")
    vitals: list[VitalsInput] = Field(..., description="List of vital signs")
    clinical_notes: Optional[str] = Field(None, description="Additional clinical context")
    pregnancy_week: Optional[int] = Field(None, ge=1, le=42, description="Gestational age in weeks")


class FlaggedFactor(BaseModel):
    """A clinical factor contributing to elevated risk."""
    
    vital_type: str
    value: str
    expected_range: str
    clinical_significance: str


class RiskAssessmentResponse(BaseModel):
    """Risk assessment response with traffic-light triage."""
    
    patient_id: str
    risk_level: str = Field(..., pattern="^(low|medium|high|emergency)$")
    risk_color: str = Field(..., description="UI color: green, yellow, orange, red")
    confidence: float = Field(..., ge=0.0, le=1.0)
    total_score: int
    flagged_factors: list[FlaggedFactor]
    recommendations: list[str]
    assessment_timestamp: datetime
    
    class Config:
        json_schema_extra = {
            "example": {
                "patient_id": "patient-123",
                "risk_level": "medium",
                "risk_color": "yellow",
                "confidence": 0.85,
                "total_score": 3,
                "flagged_factors": [
                    {
                        "vital_type": "blood_pressure",
                        "value": "150/95",
                        "expected_range": "< 140/90",
                        "clinical_significance": "Elevated BP indicates gestational hypertension risk"
                    }
                ],
                "recommendations": [
                    "Schedule follow-up within 48 hours",
                    "Monitor BP at home twice daily",
                    "Refer to PHC if BP persists above 150/100"
                ],
                "assessment_timestamp": "2026-05-11T12:00:00Z"
            }
        }


# ─── API Endpoint ─────────────────────────────────────────────────────────────

@router.post(
    "",
    response_model=RiskAssessmentResponse,
    summary="Assess patient risk level",
    description="""
    Assess maternal health risk based on vital signs.
    
    **Risk Levels:**
    - **LOW (Green)**: Score 0-1, routine ANC schedule
    - **MEDIUM (Yellow)**: Score 2-3, follow-up within 48 hours
    - **HIGH (Orange)**: Score 4-5, urgent follow-up within 24 hours  
    - **EMERGENCY (Red)**: Score 6+, immediate referral to PHC
    
    **Clinical Guidelines:**
    Based on WHO Maternal Health Guidelines and Government of India ANC protocols.
    """,
)
async def assess_risk(
    request: RiskAssessmentRequest,
    x_api_key: str = Header(..., description="API key for authentication"),
) -> RiskAssessmentResponse:
    """
    Assess risk level for a patient based on vital signs.
    
    Takes multiple vital readings and returns a traffic-light triage
    assessment with specific flagged factors and recommendations.
    """
    # Validate API key
    # In production: validate against stored keys
    if not x_api_key:
        raise HTTPException(status_code=401, detail="API key required")
    
    try:
        # Run risk assessment
        result = await risk_service.assess(
            patient_id=request.patient_id,
            chw_id=request.chw_id,
            vitals=request.vitals,
            clinical_notes=request.clinical_notes,
            pregnancy_week=request.pregnancy_week,
        )
        return result
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Risk assessment failed: {str(e)}")


@router.get(
    "/levels",
    summary="Get risk level definitions",
    description="Returns definitions of all risk levels used in assessment",
)
async def get_risk_levels():
    """Get descriptions of risk levels for CHW reference."""
    return {
        "low": {
            "color": "green",
            "score_range": "0-1",
            "action": "Continue routine ANC schedule",
            "follow_up": "Next scheduled visit"
        },
        "medium": {
            "color": "yellow",
            "score_range": "2-3",
            "action": "Increased monitoring",
            "follow_up": "Within 48 hours"
        },
        "high": {
            "color": "orange",
            "score_range": "4-5",
            "action": "Urgent intervention",
            "follow_up": "Within 24 hours"
        },
        "emergency": {
            "color": "red",
            "score_range": "6+",
            "action": "Immediate referral",
            "follow_up": "Now"
        }
    }