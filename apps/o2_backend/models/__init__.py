"""
O2 Platform — Shared Pydantic Models
Central location for all request/response models used across routers and services.
Eliminates circular imports.
"""

from datetime import datetime
from typing import Optional, List
from pydantic import BaseModel, Field


# ─── Risk Assessment Models ──────────────────────────────────────────────────

class VitalsInput(BaseModel):
    """Patient vitals input for risk assessment."""

    patient_id: str = Field(..., description="FHIR Patient ID")
    vital_type: str = Field(..., description="Type of vital: blood_pressure, hemoglobin, etc.")
    value: str = Field(..., description="Vital value (e.g., '130/90' for BP, '11.5' for Hb)")
    unit: Optional[str] = Field(None, description="Unit of measurement (mmHg, g/dL, etc.)")
    recorded_at: datetime = Field(default_factory=datetime.now)

    @property
    def vital_type_key(self) -> str:
        return self.vital_type.lower().replace(" ", "_")


class FlaggedFactor(BaseModel):
    """A clinical factor that contributed to the risk score."""

    factor: str = Field(..., description="Name of the flagged factor (e.g., 'systolic_bp')")
    value: str = Field(..., description="The actual value recorded")
    threshold: str = Field(..., description="The clinical threshold that was breached")
    severity: str = Field(..., description="Severity: 'critical', 'warning', 'notice'")
    score_contribution: int = Field(..., description="Points added to risk score")


class RiskAssessmentRequest(BaseModel):
    """Full patient vitals for comprehensive risk assessment."""

    patient_id: str = Field(..., description="FHIR Patient ID")
    vitals: List[VitalsInput] = Field(..., description="List of vital sign recordings")
    weeks_pregnant: Optional[int] = Field(None, ge=0, le=45, description="Gestational age in weeks")
    previous_complications: Optional[List[str]] = Field(
        default_factory=list,
        description="List of previous pregnancy complications"
    )
    systolic_bp: Optional[int] = Field(None, description="Systolic blood pressure (mmHg)")
    diastolic_bp: Optional[int] = Field(None, description="Diastolic blood pressure (mmHg)")
    hemoglobin: Optional[float] = Field(None, description="Hemoglobin level (g/dL)")
    weight_kg: Optional[float] = Field(None, description="Current weight in kg")
    temperature_c: Optional[float] = Field(None, description="Body temperature in Celsius")
    fetal_heart_rate: Optional[int] = Field(None, description="Fetal heart rate (bpm)")
    timestamp: datetime = Field(default_factory=datetime.now)

    def to_vitals_summary(self) -> dict:
        """Convert to a flat dict for risk scoring."""
        return {
            "systolic_bp": self.systolic_bp,
            "diastolic_bp": self.diastolic_bp,
            "hemoglobin": self.hemoglobin,
            "weight_kg": self.weight_kg,
            "temperature_c": self.temperature_c,
            "fetal_heart_rate": self.fetal_heart_rate,
            "weeks_pregnant": self.weeks_pregnant,
        }


class RiskAssessmentResponse(BaseModel):
    """Traffic-light triage risk assessment response."""

    patient_id: str = Field(..., description="FHIR Patient ID")
    risk_level: str = Field(..., description="Risk level: LOW | MEDIUM | HIGH | EMERGENCY")
    risk_score: int = Field(..., ge=0, description="Numeric risk score (0-10+)")
    risk_factors: List[FlaggedFactor] = Field(
        default_factory=list,
        description="Clinical factors that contributed to the score"
    )
    recommendations: List[str] = Field(
        default_factory=list,
        description="Clinical recommendations based on risk level"
    )
    next_review_days: int = Field(
        ..., description="Days until next scheduled review based on risk"
    )
    timestamp: datetime = Field(default_factory=datetime.now)
    is_emergency: bool = Field(..., description="True if immediate referral required")


# ─── SBAR Generation Models ──────────────────────────────────────────────────

class SBARGenerationRequest(BaseModel):
    """Request for SBAR clinical summary generation."""

    patient_id: str = Field(..., description="FHIR Patient ID")
    patient_name: str = Field(..., description="Patient display name")
    weeks_pregnant: Optional[int] = Field(None, description="Gestational age in weeks")
    chief_complaint: str = Field(..., description="Primary reason for encounter")
    subjective: str = Field(..., description="Patient's history and complaints (S)")
    objective: str = Field(..., description="Clinical observations and vitals (O)")
    assessment: str = Field(..., description="Clinical assessment and diagnosis (A)")
    recommendation: str = Field(..., description="Treatment plan and recommendations (R)")
    risk_level: Optional[str] = Field(None, description="Current risk level if available")
    vital_signs_summary: Optional[str] = Field(None, description="Summary of recent vital signs")
    notes: Optional[str] = Field(None, description="Additional clinical notes")


class SBARSection(BaseModel):
    """Individual section of the SBAR summary."""

    label: str = Field(..., description="Section label (Situation, Background, etc.)")
    content: str = Field(..., description="Generated content for this section")
    key_points: List[str] = Field(
        default_factory=list,
        description="Bullet points for this section"
    )


class SBARGenerationResponse(BaseModel):
    """LLM-generated SBAR clinical summary response."""

    patient_id: str = Field(..., description="FHIR Patient ID")
    patient_name: str = Field(..., description="Patient display name")
    generated_at: datetime = Field(default_factory=datetime.now)
    situation: SBARSection = Field(..., description="Situation section")
    background: SBARSection = Field(..., description="Background section")
    assessment: SBARSection = Field(..., description="Assessment section")
    recommendation: SBARSection = Field(..., description="Recommendation section")
    full_text: str = Field(..., description="Complete SBAR as plain text")
    confidence_score: float = Field(
        ...,
        ge=0.0,
        le=1.0,
        description="LLM confidence in the generated summary"
    )
    model_used: str = Field(..., description="LLM model that generated the summary")


# ─── SBAR Models (from routers/sbar.py) ─────────────────────────────────────

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

    recent_vitals: list["VitalReading"]

    current_risk_level: str

    high_risk_factors: list[str] = []
    current_medications: list[str] = []
    allergies: list[str] = []

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


class SBARGenerationResponse(BaseModel):
    """Full SBAR generation response."""

    patient_id: str
    sbar: SBAROutput
    risk_level: str
    generated_at: datetime
    generating_chw_id: str
    document_id: str


# ─── Health Record Models ────────────────────────────────────────────────────

class HealthRecordRequest(BaseModel):
    """Request to fetch patient health record from ABDM."""

    patient_id: str = Field(..., description="ABHA number or health ID")
    purpose: str = Field(
        default="care",
        description="Purpose of access: care, consultation, emergency"
    )


class HealthRecordResponse(BaseModel):
    """Mock ABDM health record response."""

    abha_number: str = Field(..., description="ABHA number")
    name: str = Field(..., description="Patient name")
    year_of_birth: str = Field(..., description="Year of birth")
    gender: str = Field(..., description="Gender: M/F/O")
    health_id: str = Field(..., description="Health ID")
    linked_repositories: List[str] = Field(
        default_factory=list,
        description="List of linked health data repositories"
    )
    is_verified: bool = Field(..., description="ABHA verification status")
    fetched_at: datetime = Field(default_factory=datetime.now)