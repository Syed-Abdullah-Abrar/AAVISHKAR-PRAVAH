"""
WhatsApp Sender Service — O2 IVR Backend

Sends voice messages to CHW via WhatsApp Business API.

Phase 1: Stub with logging
Phase 2: Real WhatsApp Business API integration
"""

import httpx
import os
from typing import Optional


class WhatsAppSenderService:
    """Send WhatsApp voice messages to CHW."""
    
    def __init__(self):
        self.whatsapp_business_url = os.getenv("WHATSAPP_BUSINESS_URL", "")
        self.whatsapp_token = os.getenv("WHATSAPP_BUSINESS_TOKEN", "")
    
    async def send_voice_to_chw(
        self,
        chw_whatsapp: str,
        recording_url: str,
        patient_name: str,
    ) -> dict:
        """
        Send patient voice recording to CHW via WhatsApp.
        
        Returns: {"message_sid": "mock-sid-xxx"}
        """
        # Phase 1: Mock - log and return
        print(f"[WhatsApp] Sending voice to {chw_whatsapp}")
        print(f"[WhatsApp] Patient: {patient_name}")
        print(f"[WhatsApp] Recording: {recording_url}")
        
        return {"message_sid": f"mock-{recording_url[-20:]}"}
    
    async def send_emergency_alert(
        self,
        chw_whatsapp: str,
        patient_name: str,
        recording_url: str,
    ) -> dict:
        """
        Send emergency alert to CHW.
        
        Bypasses normal queue - immediate delivery.
        """
        print(f"[WhatsApp] EMERGENCY to {chw_whatsapp}")
        print(f"[WhatsApp] Patient: {patient_name} - URGENT")
        
        return {"message_sid": f"emergency-{recording_url[-20:]}"}
    
    async def _send_whatsapp_message(self, to: str, body: str) -> dict:
        """Real WhatsApp API call (Phase 2)."""
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{self.whatsapp_business_url}/messages",
                headers={
                    "Authorization": f"Bearer {self.whatsapp_token}",
                    "Content-Type": "application/json",
                },
                json={
                    "messaging_product": "whatsapp",
                    "to": to,
                    "type": "text",
                    "text": {"body": body},
                },
            )
            return response.json()