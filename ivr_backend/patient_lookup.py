"""
Patient Lookup Service — O2 IVR Backend

Maps caller phone number → patient ABHA → CHW WhatsApp number

Phase 1: Stub with mock data
Phase 2: Real Supabase Edge Function integration
"""

import httpx
from typing import Optional
import os


class PatientLookupService:
    """Lookup patient by caller ID (phone number)."""
    
    def __init__(self):
        self.supabase_url = os.getenv("SUPABASE_URL", "")
        self.supabase_key = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "")
    
    async def find_by_caller_id(self, caller_id: str) -> Optional[dict]:
        """
        Find patient by phone number.
        
        Returns:
            {
                "id": "patient-fhir-id",
                "name": "Patient Name",
                "chw_whatsapp": "+919876543210",
                "abha_id": "12-3456-7890-1234"
            }
        """
        # Phase 1: Return mock data
        # Phase 2: Query Supabase Edge Function
        mock_patients = {
            "+919876543210": {
                "id": "patient-001",
                "name": "Lakshmi Devi",
                "chw_whatsapp": "+919988776655",
                "abha_id": "12-3456-7890-1234"
            }
        }
        
        # Normalize phone number
        normalized = self._normalize_phone(caller_id)
        return mock_patients.get(normalized)
    
    def _normalize_phone(self, phone: str) -> str:
        """Normalize phone to E.164 format."""
        digits = ''.join(c for c in phone if c.isdigit())
        if digits.startswith("91") and len(digits) == 12:
            return f"+{digits}"
        return f"+91{digits[-10:]}"