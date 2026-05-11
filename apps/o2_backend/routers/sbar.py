"""
SBAR Clinical Handover Router — O2 Platform FastAPI Backend

POST /sbar
Accepts longitudinal patient data, generates structured SBAR clinical handover document.

SBAR Format:
- Situation: Brief statement of current status
- Background: Relevant clinical history
- Assessment: Clinical impression and risk level
- Recommendation: Specific actionable next steps

LLM-powered with strict JSON schema validation.
"""

from fastapi import APIRouter, HTTPException, Header
from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime
from services.sbar_llm import SBARLLMService

router = APIRouter()
sbar_service = SBARLLMService()


# ─── Request/Response Models ─────────────────────────────────────────────────

class VitalReading(BaseModel):
    """Single vital sign reading."""
    vital_type: str
    value: str
    recorded_at: str


class PatientHistory(BaseModel):
    """Patient longitudinal data for SBAR generation."""
    
    patient_id: str
    name: str
    age: int
    gestational_week: Optional[int] = None
    abha_id: str
    
    # Recent vitals
    recent_vitals: list[VitalReading]
    
    # Risk history
    current_risk_level: str
    
    # Clinical notes
    high_risk_factors: list[str] = []
    current_medications: list[str] = []
    allergies: list[str] = []
    
    # Previous SBARs if any
    previous_sbar_summary: Optional[str] = None


class SBARGenerationRequest(BaseModel):
    """Request to generate SBAR clinical handover document."""
    
    patient: PatientHistory
    generating_chw_id: str
    generating_chw_name: str
    generating_facility: str = "PHC"
    referral_reason: Optional[str] = None


class SBAROutput(BaseModel):
    """Structured SBAR clinical handover document."""
    
    situation: str = Field(..., max_length=200)
    background: str = Field(..., max_length=500)
    assessment: str = Field(..., max_length=500)
    recommendation: str = Field(..., max_length=300)
    
    class Config:
        json_schema_extra = {
            "example": {
                "situation": "28-year-old pregnant woman, G2P1 at 34 weeks gestation, presenting with elevated BP (150/95 mmHg) detected during home visit.",
                "background": "Second pregnancy, no previous complications. First BP reading elevated at 32 weeks. No history of diabetes or pre-eclampsia. Family history of hypertension in mother.",
                "assessment": "Moderate risk for gestational hypertension. BP consistently elevated across two readings 48 hours apart. No proteinuria. Fetal movements normal. Risk level: Medium-High.",
                "recommendation": "1) Schedule PHC visit within 48 hours for BP monitoring and urine protein test. 2) CHW to monitor BP twice daily and record in O2 app. 3) If BP exceeds 160/110 or proteinuria develops, initiate emergency referral to district hospital."
            }
        }


class SBARGenerationResponse(BaseModel):
    """Full SBAR generation response."""
    
    patient_id: str
    sbar: SBAROutput
    risk_level: str
    generated_at: datetime
    generating_chw_id: str
    document_id: str  # FHIR DocumentReference ID


# ─── API Endpoint ─────────────────────────────────────────────────────────────

@router.post(
    "",
    response_model=SBARGenerationResponse,
    summary="Generate SBAR clinical handover document",
    description="""
    Generate a structured SBAR clinical handover document from patient longitudinal data.
    
    **SBAR Format:**
    - **Situation**: Brief, clear statement of current status
    - **Background**: Relevant clinical history and context
    - **Assessment**: Clinical impression including risk level
    - **Recommendation**: Specific, actionable next steps
    
    **Output:** Strict JSON matching SBAR schema (no free text outside structure).
    
    **Clinical Use:** Referral to PHC, specialist consultation, emergency handover.
    """,
)
async def generate_sbar(
    request: SBARGenerationRequest,
    x_api_key: str = Header(..., description="API key for authentication"),
) -> SBARGenerationResponse:
    """
    Generate SBAR clinical handover document for a patient.
    
    Takes longitudinal patient data (vitals history, risk factors, medications)
    and generates a structured SBAR document for clinical handover.
    """
    if not x_api_key:
        raise HTTPException(status_code=401, detail="API key required")
    
    try:
        result = await sbar_service.generate_sbar(
            patient_data=request.patient,
            chw_id=request.generating_chw_id,
            chw_name=request.generating_chw_name,
            facility=request.generating_facility,
            referral_reason=request.referral_reason,
        )
        return result
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"SBAR generation failed: {str(e)}")


@router.get(
    "/format",
    summary="Get SBAR format description",
    description="Returns description of SBAR format for CHW reference",
)
async def get_sbar_format():
    """Get SBAR format guide for Community Health Workers."""
    return {
        "title": "SBAR Clinical Handover",
        "description": "Structured communication for clinical referrals",
        "sections": {
            "S - Situation": {
                "description": "What is happening right now?",
                "prompt": "State the patient's current status in one or two sentences. Include key vital signs.",
                "example": "28-year-old pregnant woman at 34 weeks with elevated BP (150/95)"
            },
            "B - Background": {
                "description": "What is the relevant history?",
                "prompt": "Include relevant clinical history, previous readings, risk factors, medications.",
                "example": "Second pregnancy, BP elevated since 32 weeks, no prior complications"
            },
            "A - Assessment": {
                "description": "What do I think is happening?",
                "prompt": "Give your clinical impression including risk level.",
                "example": "Risk for gestational hypertension, needs monitoring"
            },
            "R - Recommendation": {
                "description": "What do I need?",
                "prompt": "List specific, actionable next steps with timeframes.",
                "example": "PHC visit within 48h, twice-daily BP monitoring, escalate if BP > 160/110"
            }
        }
    }