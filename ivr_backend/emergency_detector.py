"""
Emergency Detector — O2 IVR Backend

Phase 1: Keyword matching on transcribed text
Phase 2: Real-time speech-to-text + ML keyword detection
"""

EMERGENCY_KEYWORDS = {
    "en": ["blood", "pain", "unconscious", "bleeding", "seizure", "fainted"],
    "kn": ["ರಕ್ತ", "ನೋವು", "ವಿಷಾಣ", "ರಕ್ತಸ್ರಾವ", "ಸೆಳೆವು"],
    "hi": ["खून", "दर्द", "बेहोश", "खून आना", "दौरा"],
}


class EmergencyDetector:
    """Detect emergency keywords in voice recordings."""
    
    async def check_recording(self, recording_url: str) -> bool:
        """
        Check if recording contains emergency keywords.
        
        Phase 1: Mock - always returns False
        Phase 2: Real STT + keyword detection
        """
        # Phase 1: No real detection
        return False  # Always normal in Phase 1
    
    def detect_keywords(self, text: str) -> list[str]:
        """Detect emergency keywords in text."""
        text_lower = text.lower()
        found = []
        for lang, keywords in EMERGENCY_KEYWORDS.items():
            for kw in keywords:
                if kw.lower() in text_lower:
                    found.append(kw)
        return found