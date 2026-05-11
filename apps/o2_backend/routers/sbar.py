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
from typing import Optional
from datetime import datetime

from models import SBARGenerationRequest, SBARGenerationResponse
from services.sbar_llm import SBARLLMService

router = APIRouter()
sbar_service = SBARLLMService()


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