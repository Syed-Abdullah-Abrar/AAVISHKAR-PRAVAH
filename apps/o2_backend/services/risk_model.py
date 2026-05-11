"""
Risk Model Service — O2 Platform FastAPI Backend

Phase 1: Rule-based mock (WHO guidelines)
Phase 2+: Quantized Gradient Boosting model

Risk Scoring:
- BP Systolic > 160: +3
- BP Systolic 140-160: +2
- BP Systolic 120-140: +1
- BP Diastolic > 100: +2
- BP Diastolic 90-100: +1
- Hemoglobin < 7.0: +3 (critical)
- Hemoglobin 7.0-11.0: +1
- Weight gain abnormal: +1
- Temperature > 38°C: +2
- Fetal HR < 110 or > 160: +2

Risk Levels:
- LOW: 0-1
- MEDIUM: 2-3
- HIGH: 4-5
- EMERGENCY: 6+
"""

from datetime import datetime
from typing import Optional

from models import (
    RiskAssessmentRequest,
    RiskAssessmentResponse,
    FlaggedFactor,
    VitalsInput,
)


# ─── Risk Thresholds (WHO Guidelines) ────────────────────────────────────────

BLOOD_PRESSURE_THRESHOLDS = {
    "systolic_high": 160,
    "systolic_elevated": 140,
    "systolic_normal": 120,
    "diastolic_high": 100,
    "diastolic_elevated": 90,
}

HEMOGLOBIN_THRESHOLDS = {
    "critical": 7.0,
    "low": 11.0,
}

WEIGHT_GAIN_PREGNANCY = {
    "underweight_bmi": 12.5,  # kg total
    "normal_bmi": 11.5,
    "overweight_bmi": 9.0,
    "obese_bmi": 6.0,
}

TEMPERATURE_THRESHOLD = 38.0

FETAL_HEART_RATE_THRESHOLDS = {
    "low": 110,
    "high": 160,
}


# ─── Risk Model Service ────────────────────────────────────────────────────────

class RiskModelService:
    """
    Rule-based risk assessment for maternal health.
    
    Phase 1: Uses clinical thresholds from WHO guidelines and
    Government of India Maternal Health protocols.
    
    Phase 2: Replace with quantized ML model for improved accuracy.
    """

    def __init__(self):
        self.name = "O2 Risk Model v1.0"
        self.version = "1.0.0"

    async def assess(
        self,
        patient_id: str,
        chw_id: str,
        vitals: list[VitalsInput],
        clinical_notes: Optional[str] = None,
        pregnancy_week: Optional[int] = None,
    ) -> RiskAssessmentResponse:
        """
        Assess risk based on vital signs.
        
        Returns traffic-light triage with flagged factors and recommendations.
        """
        total_score = 0
        flagged_factors = []
        recommendations = []

        for vital in vitals:
            score, flagged, recommendation = self._assess_vital(vital)
            total_score += score
            if flagged:
                flagged_factors.append(flagged)
            if recommendation:
                recommendations.append(recommendation)

        # Determine risk level
        risk_level, risk_color = self._calculate_risk_level(total_score)

        # Generate recommendations based on risk level
        recommendations.extend(self._get_risk_recommendations(risk_level))

        return RiskAssessmentResponse(
            patient_id=patient_id,
            risk_level=risk_level,
            risk_color=risk_color,
            confidence=0.85,  # Phase 1: fixed confidence
            total_score=total_score,
            flagged_factors=flagged_factors,
            recommendations=list(set(recommendations)),  # Dedupe
            assessment_timestamp=datetime.now(),
        )

    def _assess_vital(self, vital: VitalsInput) -> tuple[int, Optional[FlaggedFactor], Optional[str]]:
        """Assess a single vital sign and return (score, flagged_factor, recommendation)."""
        vital_type = vital.vital_type.lower()
        value = vital.value

        if vital_type == "blood_pressure":
            return self._assess_blood_pressure(value)
        elif vital_type == "hemoglobin":
            return self._assess_hemoglobin(value)
        elif vital_type == "heart_rate":
            return self._assess_heart_rate(value)
        elif vital_type == "temperature":
            return self._assess_temperature(value)
        elif vital_type == "weight":
            return self._assess_weight(value)
        elif vital_type == "fetal_heart_rate":
            return self._assess_fetal_hr(value)
        else:
            return 0, None, None

    def _assess_blood_pressure(self, value: str) -> tuple[int, Optional[FlaggedFactor], Optional[str]]:
        """Assess blood pressure reading."""
        try:
            parts = value.split("/")
            systolic = int(parts[0])
            diastolic = int(parts[1]) if len(parts) > 1 else 0
        except (ValueError, IndexError):
            return 0, None, None

        score = 0
        flagged = None
        recommendation = None

        # Systolic assessment
        if systolic > BLOOD_PRESSURE_THRESHOLDS["systolic_high"]:
            score += 3
            flagged = FlaggedFactor(
                vital_type="blood_pressure",
                value=value,
                expected_range=f"< {BLOOD_PRESSURE_THRESHOLDS['systolic_high']}/{BLOOD_PRESSURE_THRESHOLDS['diastolic_high']} mmHg",
                clinical_significance="Severely elevated BP indicates hypertensive crisis risk",
            )
            recommendation = "URGENT: BP severely elevated. Immediate referral to PHC within 2 hours."
        elif systolic >= BLOOD_PRESSURE_THRESHOLDS["systolic_elevated"]:
            score += 2
            flagged = FlaggedFactor(
                vital_type="blood_pressure",
                value=value,
                expected_range=f"< {BLOOD_PRESSURE_THRESHOLDS['systolic_elevated']}/{BLOOD_PRESSURE_THRESHOLDS['diastolic_elevated']} mmHg",
                clinical_significance="Elevated BP indicates gestational hypertension risk",
            )
            recommendation = "Schedule PHC visit within 48 hours for BP monitoring."
        elif systolic > BLOOD_PRESSURE_THRESHOLDS["systolic_normal"]:
            score += 1
            flagged = FlaggedFactor(
                vital_type="blood_pressure",
                value=value,
                expected_range=f"< {BLOOD_PRESSURE_THRESHOLDS['systolic_normal']} mmHg",
                clinical_significance="Elevated BP requires monitoring",
            )

        # Diastolic assessment
        if diastolic > BLOOD_PRESSURE_THRESHOLDS["diastolic_high"]:
            score += 2
        elif diastolic >= BLOOD_PRESSURE_THRESHOLDS["diastolic_elevated"]:
            score += 1

        return score, flagged, recommendation

    def _assess_hemoglobin(self, value: str) -> tuple[int, Optional[FlaggedFactor], Optional[str]]:
        """Assess hemoglobin level."""
        try:
            hb = float(value)
        except ValueError:
            return 0, None, None

        if hb < HEMOGLOBIN_THRESHOLDS["critical"]:
            return 3, FlaggedFactor(
                vital_type="hemoglobin",
                value=value,
                expected_range=f"> {HEMOGLOBIN_THRESHOLDS['critical']} g/dL",
                clinical_significance="Severe anemia requires immediate treatment",
            ), "EMERGENCY: Severe anemia. Refer to PHC for blood transfusion evaluation."
        elif hb < HEMOGLOBIN_THRESHOLDS["low"]:
            return 1, FlaggedFactor(
                vital_type="hemoglobin",
                value=value,
                expected_range=f"> {HEMOGLOBIN_THRESHOLDS['low']} g/dL",
                clinical_significance="Anemia requires iron supplementation and dietary counseling",
            ), "Continue iron supplementation. Schedule Hb check in 2 weeks."

        return 0, None, None

    def _assess_heart_rate(self, value: str) -> tuple[int, Optional[FlaggedFactor], Optional[str]]:
        """Assess heart rate."""
        try:
            hr = int(value)
        except ValueError:
            return 0, None, None

        if hr > 100:
            return 1, FlaggedFactor(
                vital_type="heart_rate",
                value=value,
                expected_range="60-100 bpm",
                clinical_significance="Tachycardia may indicate infection or anemia",
            ), "Monitor. If persists, evaluate for infection or anemia."
        elif hr < 60:
            return 1, FlaggedFactor(
                vital_type="heart_rate",
                value=value,
                expected_range="60-100 bpm",
                clinical_significance="Bradycardia in pregnancy requires evaluation",
            ), "Refer to PHC for cardiac evaluation."

        return 0, None, None

    def _assess_temperature(self, value: str) -> tuple[int, Optional[FlaggedFactor], Optional[str]]:
        """Assess body temperature."""
        try:
            temp = float(value)
        except ValueError:
            return 0, None, None

        if temp > TEMPERATURE_THRESHOLD:
            return 2, FlaggedFactor(
                vital_type="temperature",
                value=value,
                expected_range=f"< {TEMPERATURE_THRESHOLD} °C",
                clinical_significance="Fever may indicate infection requiring treatment",
            ), "Evaluate for infection. Give paracetamol. Follow up in 24 hours."

        return 0, None, None

    def _assess_weight(self, value: str) -> tuple[int, Optional[FlaggedFactor], Optional[str]]:
        """Assess weight (for pregnancy weight gain tracking)."""
        try:
            weight = float(value)
        except ValueError:
            return 0, None, None

        # Weight tracking is more complex - for now, no scoring
        return 0, None, None

    def _assess_fetal_hr(self, value: str) -> tuple[int, Optional[FlaggedFactor], Optional[str]]:
        """Assess fetal heart rate."""
        try:
            fhr = int(value)
        except ValueError:
            return 0, None, None

        if fhr < FETAL_HEART_RATE_THRESHOLDS["low"]:
            return 2, FlaggedFactor(
                vital_type="fetal_heart_rate",
                value=value,
                expected_range=f"{FETAL_HEART_RATE_THRESHOLDS['low']}-{FETAL_HEART_RATE_THRESHOLDS['high']} bpm",
                clinical_significance="Fetal bradycardia requires urgent evaluation",
            ), "URGENT: Refer to PHC for fetal monitoring."
        elif fhr > FETAL_HEART_RATE_THRESHOLDS["high"]:
            return 2, FlaggedFactor(
                vital_type="fetal_heart_rate",
                value=value,
                expected_range=f"{FETAL_HEART_RATE_THRESHOLDS['low']}-{FETAL_HEART_RATE_THRESHOLDS['high']} bpm",
                clinical_significance="Fetal tachycardia may indicate distress",
            ), "URGENT: Refer to PHC for fetal monitoring."

        return 0, None, None

    def _calculate_risk_level(self, score: int) -> tuple[str, str]:
        """Calculate risk level from total score."""
        if score >= 6:
            return "emergency", "red"
        elif score >= 4:
            return "high", "orange"
        elif score >= 2:
            return "medium", "yellow"
        else:
            return "low", "green"

    def _get_risk_recommendations(self, risk_level: str) -> list[str]:
        """Get recommendations based on risk level."""
        recommendations = {
            "low": [
                "Continue routine ANC schedule",
                "Next visit as scheduled",
            ],
            "medium": [
                "Increase monitoring frequency",
                "Schedule follow-up within 48 hours",
            ],
            "high": [
                "Urgent intervention required",
                "Schedule PHC visit within 24 hours",
            ],
            "emergency": [
                "IMMEDIATE REFERRAL to district hospital",
                "Call 108 ambulance if needed",
            ],
        }
        return recommendations.get(risk_level, [])