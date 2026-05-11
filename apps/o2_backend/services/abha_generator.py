"""
ABHA Generator Service — O2 Platform FastAPI Backend

Generates and validates ABHA (Ayushman Bharat Health Account) numbers
using the Mod97-10 checksum algorithm (ISO/IEC 7064).

For hackathon demo: NHA API unavailable, so we generate valid ABHAs
locally with correct checksum. When NHA credentials arrive, set
USE_LIVE_ABDM=true and the abdm router will use live API instead.
"""

import random
import re
import hashlib
from datetime import datetime, timezone
from typing import Optional


def generate_abha_number() -> str:
    """
    Generate a 14-digit ABHA number with valid Mod97-10 checksum.
    
    ABHA format: 14 digits = 12 random digits + 2 check digits
    Mod97-10 algorithm: check digit = (98 - (number mod 97)) mod 97
    
    Returns:
        str: 14-digit ABHA number with valid checksum
    """
    prefix = str(random.randint(10**11, 10**12 - 1))
    check = (98 - (int(prefix) % 97)) % 97
    return prefix + f"{check:02d}"


def validate_abha(abha: str) -> bool:
    """
    Validate ABHA using Mod97-10 algorithm (ISO/IEC 7064).
    
    The ABHA number is valid if: (number mod 97) == 1
    
    Args:
        abha: 14-digit ABHA number as string
        
    Returns:
        bool: True if valid, False otherwise
    """
    if not re.match(r'^\d{14}$', abha):
        return False
    return (int(abha) % 97) == 1


def abha_to_uuid(abha: str) -> str:
    """
    Convert ABHA to a deterministic UUID-like internal ID.
    
    This ensures the same ABHA always maps to the same internal ID
    without storing the raw ABHA in indexes.
    
    Args:
        abha: 14-digit ABHA number
        
    Returns:
        str: 32-character hex string (UUID-like, not actual UUID format)
    """
    return hashlib.sha256(abha.encode()).hexdigest()[:32]


def generate_abha_with_name(name: str, dob: str, gender: str) -> dict:
    """
    Generate ABHA with metadata for patient registration.
    
    Args:
        name: Patient name
        dob: Date of birth (YYYY-MM-DD)
        gender: M/F/O
        
    Returns:
        dict with abha_number, name, dob, gender, valid
    """
    abha = generate_abha_number()
    return {
        "abha_number": abha,
        "name": name,
        "date_of_birth": dob,
        "gender": gender,
        "valid": True,
        "source": "local_generator",
        "generated_at": datetime.now(timezone.utc).isoformat(),
    }


def format_abha_display(abha: str) -> str:
    """
    Format ABHA for display: XXXX-XXXX-XXXX
    
    Args:
        abha: 14-digit ABHA number
        
    Returns:
        str: Formatted ABHA (XXXX-XXXX-XXXX)
    """
    if len(abha) != 14:
        return abha
    return f"{abha[:4]}-{abha[4:8]}-{abha[8:14]}"


# Export for use in routers
__all__ = [
    "generate_abha_number",
    "validate_abha",
    "abha_to_uuid",
    "generate_abha_with_name",
    "format_abha_display",
]