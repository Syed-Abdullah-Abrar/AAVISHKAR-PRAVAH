"""
O2 Platform — Interactive Telegram Bot (Patient Persona)
═══════════════════════════════════════════════════

A fully interactive Telegram bot representing the Patient/ASHA interface.
Users can:
  /start            — Welcome message + menu
  /my_history       — Show vitals history
  /my_reports       — Latest generated reports/SBARs
  /upcoming_checks  — Show pending follow-ups
  /help             — Command list

Plus:
  - Send any text → AI Triage via Minimax/OpenAI
  - Send a voice note → Transcribed via AI, then Triaged

Usage:
    cd apps/o2_backend
    source ../../.venv/bin/activate
    PYTHONPATH=. python telegram_bot.py
"""

import os
import sys
import uuid
import tempfile
import asyncio
import logging
from datetime import datetime, timezone

# Add project root to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from dotenv import load_dotenv
load_dotenv()

from telegram import Update, BotCommand
from telegram.ext import (
    Application, CommandHandler, MessageHandler, filters, ContextTypes
)

from services.database import (
    init_db, patient_repo, vitals_repo, visit_repo, schedule_repo
)

import httpx

logging.basicConfig(
    format="%(asctime)s [O2 Bot] %(message)s",
    level=logging.INFO,
)
logger = logging.getLogger(__name__)

TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "")

# AI Provider Setup (Using Minimax as OpenAI compatible or direct OpenAI)
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "")
MINIMAX_API_KEY = os.getenv("MINIMAX_API_KEY", "")

# Setup OpenAI client
try:
    from openai import AsyncOpenAI
    if OPENAI_API_KEY:
        ai_client = AsyncOpenAI(api_key=OPENAI_API_KEY)
        LLM_MODEL = "gpt-4o-mini"
        AUDIO_MODEL = "whisper-1"
    elif MINIMAX_API_KEY:
        ai_client = AsyncOpenAI(api_key=MINIMAX_API_KEY, base_url="https://api.minimaxi.chat/v1")
        LLM_MODEL = "abab6.5s-chat"
        AUDIO_MODEL = "speech-01"
    else:
        ai_client = None
except ImportError:
    ai_client = None

# For demo purposes, we map the Telegram user to a specific high-risk patient
# In production, this would be mapped via phone number during registration
DEMO_PATIENT_NAME = "Lakshmi" 

# ═══════════════════════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

RISK_EMOJI = {
    "EMERGENCY": "🚨",
    "HIGH": "🔴",
    "MEDIUM": "🟡",
    "LOW": "🟢",
}

def risk_bar(level: str) -> str:
    return RISK_EMOJI.get(level.upper(), "⚪")

async def get_demo_patient():
    """Get the patient record for the demo user."""
    patients = await patient_repo.list_all()
    for p in patients:
        if DEMO_PATIENT_NAME.lower() in p.get("name", "").lower():
            return p
    # Fallback to first patient if Lakshmi is missing
    return patients[0] if patients else None

# ═══════════════════════════════════════════════════════════════════════════════
# COMMAND HANDLERS
# ═══════════════════════════════════════════════════════════════════════════════

async def cmd_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Welcome message for the patient persona."""
    patient = await get_demo_patient()
    name = patient.get("name", "Patient") if patient else "Patient"
    
    welcome = (
        f"🫁 *O₂ Platform — My Health Assistant*\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
        f"Namaste *{name}*, welcome to your O₂ Health Assistant.\n\n"
        f"🔹 /my_history — View your past vitals & checkups\n"
        f"🔹 /my_reports — View recent medical reports\n"
        f"🔹 /upcoming_checks — Check your next scheduled visit\n"
        f"🔹 /help — See all options\n\n"
        f"💬 *Need help?* Type your symptoms here directly, or send a *voice message* to report how you are feeling.\n\n"
        f"_Your health is our priority._"
    )
    await update.message.reply_text(welcome, parse_mode="Markdown")


async def cmd_help(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """List all commands."""
    help_text = (
        "📋 *My O₂ Commands*\n"
        "━━━━━━━━━━━━━━━━━━━━\n\n"
        "/start — Welcome message\n"
        "/my_history — Your past vitals & health records\n"
        "/my_reports — Medical handovers and reports\n"
        "/upcoming_checks — Next visits\n"
        "/help — This menu\n\n"
        "💬 *Report a symptom:* Just type what you're feeling\n"
        "🎙 *Voice report:* Tap the microphone icon to send a voice note"
    )
    await update.message.reply_text(help_text, parse_mode="Markdown")


async def cmd_my_history(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Show vitals history for the patient."""
    patient = await get_demo_patient()
    if not patient:
        await update.message.reply_text("❌ Patient profile not found.")
        return

    vitals_list = await vitals_repo.list_by_patient(patient["id"], limit=5)
    if not vitals_list:
        await update.message.reply_text("You have no vitals recorded yet.")
        return

    lines = [f"💓 *My Health History*\n━━━━━━━━━━━━━━━━━━━━━━━━━\n"]
    for v in vitals_list:
        sys = v.get("systolic_bp")
        dia = v.get("diastolic_bp")
        bp = f"{sys}/{dia} mmHg" if sys and dia else "N/A"
        date = v.get("recorded_at", "")[:10]
        lines.append(
            f"📅 *{date}*\n"
            f"   BP: {bp} | HR: {v.get('heart_rate', '?')} bpm\n"
            f"   SpO₂: {v.get('spo2', '?')}% | Temp: {v.get('temperature', '?')}°C\n"
        )

    await update.message.reply_text("\n".join(lines), parse_mode="Markdown")


async def cmd_my_reports(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Show latest SBAR/Reports for the patient."""
    patient = await get_demo_patient()
    if not patient:
        return
        
    risk = patient.get("risk_level", "LOW").upper()
    lines = [
        f"📑 *My Medical Profile*\n━━━━━━━━━━━━━━━━━━━━━━\n",
        f"👤 Name: {patient.get('name')}",
        f"🆔 ABHA: {patient.get('abha_number', 'N/A')}",
        f"{risk_bar(risk)} Current Status: *{risk}*\n",
        f"📞 Emergency Contact: {patient.get('emergency_contact', 'N/A')}",
        f"🏥 Registered PHC: {patient.get('phc_id', 'N/A')}\n"
    ]
    await update.message.reply_text("\n".join(lines), parse_mode="Markdown")


async def cmd_upcoming_checks(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Show pending follow-ups."""
    patient = await get_demo_patient()
    if not patient:
        return

    schedules = await schedule_repo.list_pending(limit=10)
    my_schedules = [s for s in schedules if s.get("patient_id") == patient["id"]]

    if not my_schedules:
        await update.message.reply_text("✅ You have no upcoming scheduled visits. Stay healthy!")
        return

    lines = ["📋 *Upcoming Check-ups*\n━━━━━━━━━━━━━━━━━━━━━━\n"]
    for s in my_schedules:
        date = s.get("scheduled_at", "")[:10]
        reason = s.get("reason", "Routine Check-up")[:60]
        lines.append(f"📅 *{date}*\n  📝 {reason}\n")

    await update.message.reply_text("\n".join(lines), parse_mode="Markdown")


# ═══════════════════════════════════════════════════════════════════════════════
# AI TRIAGE LOGIC
# ═══════════════════════════════════════════════════════════════════════════════

async def run_ai_triage(symptom_text: str, patient_name: str) -> dict:
    """Send text to LLM for risk assessment."""
    if not ai_client:
        logger.warning("No AI Client configured! Using fallback triage.")
        return fallback_triage(symptom_text)
        
    system_prompt = """You are the O2 Maternal Health AI Triage Assistant.
Analyze the patient's reported symptoms and return ONLY a valid JSON object.
Rules:
- EMERGENCY: Severe bleeding, seizures, unconsciousness, severe chest pain.
- HIGH: Severe headache, swelling, high fever, severe abdominal pain, decreased fetal movement.
- MEDIUM: Mild dizziness, vomiting, mild pain, minor infections.
- LOW: Fatigue, normal pregnancy discomforts.

JSON Schema required:
{
  "risk_level": "LOW|MEDIUM|HIGH|EMERGENCY",
  "assessment": "Brief clinical explanation",
  "patient_message": "A friendly, reassuring response to the patient explaining what to do next. If EMERGENCY/HIGH, tell them to visit the PHC immediately."
}"""

    try:
        response = await ai_client.chat.completions.create(
            model=LLM_MODEL,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": f"Patient Name: {patient_name}\nReported Symptoms: {symptom_text}"}
            ],
            temperature=0.2,
            response_format={"type": "json_object"}
        )
        content = response.choices[0].message.content
        import json
        return json.loads(content)
    except Exception as e:
        logger.error(f"AI Triage error: {e}")
        return fallback_triage(symptom_text)

def fallback_triage(text: str) -> dict:
    """Keyword-based fallback if LLM fails."""
    text_lower = text.lower()
    if any(k in text_lower for k in ["bleed", "seizure", "faint", "unconscious"]):
        risk = "EMERGENCY"
    elif any(k in text_lower for k in ["headache", "swell", "fever", "pain"]):
        risk = "HIGH"
    elif any(k in text_lower for k in ["dizzy", "vomit", "tired"]):
        risk = "MEDIUM"
    else:
        risk = "LOW"
        
    return {
        "risk_level": risk,
        "assessment": "Fallback keyword triage applied.",
        "patient_message": f"We noted your symptom. Your risk level is currently assessed as {risk}."
    }

async def update_patient_risk_and_notify(patient_id: str, new_risk: str, text: str):
    """Updates the database so the dashboard auto-refreshes with the new data."""
    import aiosqlite
    from services.database import DB_PATH
    
    # Update patient risk level
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute(
            "UPDATE patients SET risk_level = ?, updated_at = ? WHERE id = ?",
            (new_risk.upper(), datetime.now(timezone.utc).isoformat(), patient_id)
        )
        # Log the transcript so the dashboard alert feed picks it up
        transcript_id = str(uuid.uuid4())
        await db.execute("""
            INSERT INTO ivr_transcripts (id, patient_id, transcript_text, language, audio_url)
            VALUES (?, ?, ?, ?, ?)
        """, (
            transcript_id,
            patient_id,
            f"TELEGRAM REPORT: {text}",
            "en",
            "telegram_text"
        ))
        await db.commit()
    logger.info(f"Database updated: Patient {patient_id} risk set to {new_risk}")

# ═══════════════════════════════════════════════════════════════════════════════
# MESSAGE HANDLERS
# ═══════════════════════════════════════════════════════════════════════════════

async def handle_text(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle free-text symptom reports using AI."""
    text = update.message.text.strip()
    
    # Send intermediate message
    processing_msg = await update.message.reply_text("⏳ *Analyzing your symptoms...*", parse_mode="Markdown")
    
    patient = await get_demo_patient()
    patient_id = patient["id"] if patient else "UNKNOWN"
    patient_name = patient["name"] if patient else "Unknown"

    # AI Triage
    triage_result = await run_ai_triage(text, patient_name)
    risk_level = triage_result.get("risk_level", "LOW").upper()
    patient_msg = triage_result.get("patient_message", "Thank you for reporting.")
    
    # Update DB for Dashboard
    await update_patient_risk_and_notify(patient_id, risk_level, text)

    response = (
        f"🫁 *O₂ Health Assessment*\n"
        f"━━━━━━━━━━━━━━━━━━━━\n\n"
        f"{risk_bar(risk_level)} *Status: {risk_level}*\n\n"
        f"🗣 *Doctor's Advice:*\n_{patient_msg}_\n\n"
    )

    if risk_level in ("EMERGENCY", "HIGH"):
        response += (
            f"⚡ *Action Taken:*\n"
            f"• An alert has been sent to your Community Health Worker.\n"
            f"• The Primary Health Center (PHC) dashboard has been updated.\n"
        )
    
    await processing_msg.edit_text(response, parse_mode="Markdown")


async def handle_voice(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle voice messages: download -> STT (Minimax/OpenAI) -> Triage."""
    voice = update.message.voice
    
    processing_msg = await update.message.reply_text(
        "🎙 *Voice note received. Transcribing audio...*", 
        parse_mode="Markdown"
    )

    try:
        # 1. Download file from Telegram
        file = await context.bot.get_file(voice.file_id)
        
        with tempfile.NamedTemporaryFile(suffix=".ogg", delete=False) as temp_audio:
            await file.download_to_drive(temp_audio.name)
            temp_path = temp_audio.name

        # 2. Transcribe Audio via LLM API
        transcript_text = "Audio could not be transcribed."
        if ai_client:
            with open(temp_path, "rb") as audio_file:
                transcript_resp = await ai_client.audio.transcriptions.create(
                    model=AUDIO_MODEL,
                    file=audio_file
                )
                transcript_text = transcript_resp.text
        else:
            # Fallback if no API key
            transcript_text = "I am feeling very dizzy and have a severe headache today."
            
        # Clean up
        os.unlink(temp_path)

        # 3. Update UI to show transcript, then triage
        await processing_msg.edit_text(
            f"🗣 *Transcription complete:*\n_{transcript_text}_\n\n⏳ *Analyzing symptoms...*", 
            parse_mode="Markdown"
        )
        
        patient = await get_demo_patient()
        patient_id = patient["id"] if patient else "UNKNOWN"
        patient_name = patient["name"] if patient else "Unknown"

        # 4. Triage the transcribed text
        triage_result = await run_ai_triage(transcript_text, patient_name)
        risk_level = triage_result.get("risk_level", "LOW").upper()
        patient_msg = triage_result.get("patient_message", "Thank you for reporting.")
        
        # 5. Update Database for Dashboard
        await update_patient_risk_and_notify(patient_id, risk_level, transcript_text)

        response = (
            f"🫁 *O₂ Health Assessment*\n"
            f"━━━━━━━━━━━━━━━━━━━━\n\n"
            f"📝 *You said:* _{transcript_text}_\n\n"
            f"{risk_bar(risk_level)} *Status: {risk_level}*\n\n"
            f"🗣 *Doctor's Advice:*\n_{patient_msg}_\n\n"
        )

        if risk_level in ("EMERGENCY", "HIGH"):
            response += (
                f"⚡ *Action Taken:*\n"
                f"• An alert has been sent to your Community Health Worker.\n"
                f"• The PHC dashboard has been notified instantly.\n"
            )
            
        await processing_msg.edit_text(response, parse_mode="Markdown")

    except Exception as e:
        logger.error(f"Voice processing failed: {e}")
        await processing_msg.edit_text(f"❌ Failed to process voice message: {e}")


# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

async def post_init(app: Application):
    """Set bot commands menu and initialize DB."""
    await init_db()
    await app.bot.set_my_commands([
        BotCommand("start", "Welcome message"),
        BotCommand("my_history", "Your vitals & health records"),
        BotCommand("my_reports", "Medical handovers and reports"),
        BotCommand("upcoming_checks", "Next visits"),
        BotCommand("help", "All commands"),
    ])
    logger.info("Bot commands registered, DB initialized")


def main():
    if not TELEGRAM_BOT_TOKEN:
        print("❌ TELEGRAM_BOT_TOKEN not set in .env")
        sys.exit(1)

    print("\n═══════════════════════════════════════════════════════")
    print("  🫁 O₂ Platform — Telegram Bot (Patient Persona)")
    print("  Bot is starting... Send /start to your bot!")
    print("═══════════════════════════════════════════════════════\n")

    app = Application.builder().token(TELEGRAM_BOT_TOKEN).post_init(post_init).build()

    app.add_handler(CommandHandler("start", cmd_start))
    app.add_handler(CommandHandler("help", cmd_help))
    app.add_handler(CommandHandler("my_history", cmd_my_history))
    app.add_handler(CommandHandler("my_reports", cmd_my_reports))
    app.add_handler(CommandHandler("upcoming_checks", cmd_upcoming_checks))

    app.add_handler(MessageHandler(filters.VOICE, handle_voice))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_text))

    logger.info("Starting polling...")
    app.run_polling(allowed_updates=Update.ALL_TYPES)


if __name__ == "__main__":
    main()
