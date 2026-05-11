"""
Telegram Alert Service — O2 Platform Phase 2
Multi-recipient alerts for CHW, PHC Supervisor, family, and emergency.
Routes IVR transcribed voice alerts via Telegram.
"""

import os
import httpx
from datetime import datetime, timezone
from typing import Optional

TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN")
TELEGRAM_API = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}"

# Multi-recipient groups for alerts
RECIPIENT_GROUPS = {
    "chw": "CHW Telegram ID for this patient",
    "phc_supervisor": os.getenv("PHC_SUPERVISOR_TELEGRAM_ID", ""),
    "emergency_contact": "Fetched per-patient from DB",
    "regional_hospital": os.getenv("REGIONAL_HOSPITAL_TELEGRAM", ""),
}

# Risk-based routing
ALERT_TIERS = {
    "EMERGENCY": ["chw", "phc_supervisor", "emergency_contact", "regional_hospital"],
    "HIGH": ["chw", "phc_supervisor"],
    "MEDIUM": ["chw", "emergency_contact"],
    "LOW": ["chw"],
}


def _escape_md(text: str) -> str:
    """Escape Telegram markdown."""
    return text.replace("_", "\\_").replace("*", "\\*").replace("[", "\\[")


async def send_telegram_message(chat_id: str, text: str, parse_mode: str = "Markdown") -> bool:
    """Send a message via Telegram bot."""
    if not TELEGRAM_BOT_TOKEN:
        print(f"[Telegram] Bot token not configured, skipping: {text[:50]}...")
        return False
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.post(
                f"{TELEGRAM_API}/sendMessage",
                json={
                    "chat_id": chat_id,
                    "text": _escape_md(text),
                    "parse_mode": parse_mode,
                },
                timeout=10.0,
            )
            return resp.status_code == 200
    except Exception as e:
        print(f"[Telegram] Send failed: {e}")
        return False


def build_alert_message(
    patient_name: str,
    risk_level: str,
    alert_type: str,
    details: str,
    vitals: dict = None,
) -> str:
    """Build formatted alert message with vitals."""
    emoji = {"EMERGENCY": "🚨", "HIGH": "⚠️", "MEDIUM": "📋", "LOW": "ℹ️"}.get(risk_level, "ℹ️")
    
    msg = f"{emoji} *O2 Platform Alert — {risk_level}*\n\n"
    msg += f"*Patient:* {patient_name}\n"
    msg += f"*Type:* {alert_type}\n"
    
    if vitals:
        msg += f"\n*Vitals:*\n"
        for k, v in vitals.items():
            if v:
                msg += f"  • {k}: {v}\n"
    
    msg += f"\n{details}\n"
    msg += f"\n_Sent: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}_"
    return msg


async def send_risk_alert(
    patient_id: str,
    patient_name: str,
    risk_level: str,
    alert_type: str,
    details: str,
    vitals: dict = None,
    patient_emergency_telegram: str = None,
    patient_emergency_name: str = None,
):
    """Send risk-based multi-recipient alert."""
    message = build_alert_message(patient_name, risk_level, alert_type, details, vitals)
    recipients = ALERT_TIERS.get(risk_level, ["chw"])
    results = {}

    for recipient in recipients:
        if recipient == "emergency_contact":
            if patient_emergency_telegram:
                results[recipient] = await send_telegram_message(patient_emergency_telegram, message)
        elif recipient == "chw":
            # CHW Telegram fetched separately from patient record
            pass  # Handled by caller with chw_telegram_id
        else:
            recipient_id = RECIPIENT_GROUPS.get(recipient, "")
            if recipient_id:
                results[recipient] = await send_telegram_message(recipient_id, message)

    return results


async def send_ivr_transcript_alert(
    patient_id: str,
    patient_name: str,
    transcript: str,
    language: str = "kn",
):
    """Alert when IVR call produces critical keywords."""
    keywords = ["help", "emergency", "bleeding", "pain", "fever", "not feeling", "difficulty", "can't", "hospital"]
    is_critical = any(k in transcript.lower() for k in keywords)
    
    level = "EMERGENCY" if is_critical else "MEDIUM"
    message = build_alert_message(
        patient_name, level, "IVR Voice Alert",
        f"*Transcript:*\n{transcript[:500]}",
    )
    
    recipients = ["chw"]
    if is_critical:
        recipients.extend(["phc_supervisor", "emergency_contact"])

    return {"message": message, "recipients": recipients, "is_critical": is_critical}


async def alert_chw_direct(
    chw_telegram_id: str,
    patient_name: str,
    message: str,
):
    """Send direct alert to CHW."""
    return await send_telegram_message(chw_telegram_id, message)


async def broadcast_to_phc_chws(phc_id: str, message: str, patients: list) -> dict:
    """Broadcast a message to all CHWs in a PHC."""
    chw_ids = set(p.get("chw_telegram_id") for p in patients if p.get("chw_telegram_id"))
    
    results = {}
    for chw_id in chw_ids:
        results[chw_id] = await send_telegram_message(chw_id, message)
    return results


async def build_daily_digest(phc_id: str, high_risk: list) -> str:
    """Build daily summary of all HIGH/EMERGENCY patients."""
    if not high_risk:
        return "✅ *Daily Digest:* No high-risk patients. All patients stable."

    msg = f"📊 *Daily Digest — {datetime.now(timezone.utc).strftime('%Y-%m-%d')}*\n\n"
    msg += f"🚨 *High Risk Patients ({len(high_risk)}):*\n\n"
    for p in high_risk[:10]:
        msg += f"• {p['name']} — {p['risk_level']}\n"
    return msg


async def send_daily_digest(phc_id: str, db):
    """Send daily digest to PHC supervisor."""
    supervisor_id = os.getenv("PHC_SUPERVISOR_TELEGRAM_ID")
    if not supervisor_id:
        return {"status": "no_recipient"}
    
    high_risk = await db.list_high_risk(phc_id)
    message = await build_daily_digest(phc_id, high_risk)
    sent = await send_telegram_message(supervisor_id, message)
    return {"status": "sent" if sent else "failed", "patient_count": len(high_risk)}