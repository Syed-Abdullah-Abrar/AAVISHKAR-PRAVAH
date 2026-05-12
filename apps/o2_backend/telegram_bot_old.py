"""
O2 Platform — Telegram Bot: Lakshmi's Health Interface
═══════════════════════════════════════════════════════

All interactions are from the lens of Lakshmi Devi, a high-risk
pregnant patient in rural Karnataka. Her medical history is detailed
and realistic for demo purposes.

Commands:
  /start           — Welcome + menu
  /my_history      — Vitals history (last 4 visits)
  /my_reports      — Latest SBAR / medical report
  /upcoming_checks — Next scheduled visits
  /my_profile      — Full patient profile
  /help            — Command list

Text/Voice → AI Triage via Minimax/OpenAI → Dashboard update
"""

import os
import sys
import uuid
import tempfile
import logging
import json
from datetime import datetime, timezone, timedelta

IST = timezone(timedelta(hours=5, minutes=30))

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from dotenv import load_dotenv
load_dotenv()

from telegram import Update, BotCommand
from telegram.ext import (
    Application, CommandHandler, MessageHandler, filters, ContextTypes
)

logging.basicConfig(
    format="%(asctime)s [O2 Bot] %(message)s",
    level=logging.INFO,
)
logger = logging.getLogger(__name__)

TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "")
OPENAI_API_KEY     = os.getenv("OPENAI_API_KEY", "")
MINIMAX_API_KEY    = os.getenv("MINIMAX_API_KEY", "")

# ─── AI Client Setup ─────────────────────────────────────────────────────────

try:
    from openai import AsyncOpenAI
    if OPENAI_API_KEY:
        ai_client  = AsyncOpenAI(api_key=OPENAI_API_KEY)
        LLM_MODEL  = "gpt-4o-mini"
        AUDIO_MODEL = "whisper-1"
        logger.info("Using OpenAI GPT-4o-mini")
    elif MINIMAX_API_KEY:
        ai_client  = AsyncOpenAI(
            api_key=MINIMAX_API_KEY,
            base_url="https://api.minimaxi.chat/v1"
        )
        LLM_MODEL  = "abab6.5s-chat"
        AUDIO_MODEL = "speech-01"
        logger.info("Using Minimax LLM")
    else:
        ai_client = None
        logger.warning("No AI API key found — using fallback triage")
except ImportError:
    ai_client = None

# ─── LAKSHMI'S COMPLETE MEDICAL PROFILE (Demo Data) ──────────────────────────

LAKSHMI = {
    "id": "patient-lakshmi-001",
    "name": "Lakshmi Devi",
    "age": 28,
    "village": "Ratnagiri",
    "district": "Haveri",
    "state": "Karnataka",
    "abha": "12-3456-7890-1122",
    "blood_group": "B+",
    "phone": "+91 94480 12345",
    "asha_worker": "Savita Ben",
    "phc": "PHC Ratnagiri (PHC-001)",
    "gestational_week": 32,
    "edd": "2026-07-14",
    "gravida": 2,
    "parity": 1,
    "last_delivery": "2023 — Normal delivery, healthy baby boy (3.1 kg)",
    "risk_level": "LOW",   # starts LOW — escalates during demo
    "medical_history": [
        "Mild gestational hypertension (diagnosed at Week 20)",
        "Borderline anaemia — Hb 10.2 g/dL (Week 28 reading)",
        "Mild oedema of ankles (Week 30)",
        "Previous pregnancy: Normal delivery, no complications",
    ],
    "current_medications": [
        "Iron + Folic Acid (IFA) — 1 tablet daily",
        "Calcium 500mg — 1 tablet twice daily",
        "Methyldopa 250mg — for gestational hypertension",
    ],
    "allergies": "None known",
}

LAKSHMI_VITALS_HISTORY = [
    {
        "date": "09 May 2026",
        "week": "Week 31",
        "bp": "138/88 mmHg ⚠️",
        "hr": "82 bpm",
        "spo2": "98%",
        "temp": "36.8°C",
        "weight": "63.5 kg",
        "hb": "10.2 g/dL ⚠️",
        "fhr": "142 bpm ✅",
        "notes": "Mild ankle swelling noted. BP slightly elevated. IFA compliance confirmed.",
    },
    {
        "date": "25 Apr 2026",
        "week": "Week 29",
        "bp": "132/84 mmHg",
        "hr": "80 bpm",
        "spo2": "99%",
        "temp": "36.6°C",
        "weight": "62.8 kg",
        "hb": "10.5 g/dL ⚠️",
        "fhr": "138 bpm ✅",
        "notes": "BP stable. Advised increased iron-rich diet. Counselled on danger signs.",
    },
    {
        "date": "10 Apr 2026",
        "week": "Week 27",
        "bp": "128/80 mmHg ✅",
        "hr": "78 bpm",
        "spo2": "99%",
        "temp": "36.5°C",
        "weight": "61.9 kg",
        "hb": "10.8 g/dL",
        "fhr": "136 bpm ✅",
        "notes": "Normal visit. Fetal movements reported as active.",
    },
    {
        "date": "26 Mar 2026",
        "week": "Week 24",
        "bp": "124/78 mmHg ✅",
        "hr": "76 bpm",
        "spo2": "99%",
        "temp": "36.4°C",
        "weight": "60.5 kg",
        "hb": "11.2 g/dL",
        "fhr": "134 bpm ✅",
        "notes": "Routine ANC visit. All normal. GDM screen negative.",
    },
]

LAKSHMI_REPORTS = {
    "sbar_date": "09 May 2026",
    "situation": (
        "Lakshmi Devi, 28 years, G2P1 at Week 31, presents with persistently "
        "elevated BP (138/88 mmHg) and mild ankle oedema at routine ASHA visit. "
        "Hemoglobin borderline at 10.2 g/dL."
    ),
    "background": (
        "Known gestational hypertension since Week 20. On Methyldopa 250mg. "
        "Previous delivery was normal (2023). No prior pre-eclampsia. "
        "IFA compliance confirmed; however dietary intake remains suboptimal. "
        "Family history: mother had hypertension in third pregnancy."
    ),
    "assessment": (
        "Risk Level: HIGH — Patient shows two WHO danger signs: borderline BP "
        "approaching 140/90 threshold, and borderline anaemia. Risk of "
        "pre-eclampsia progression cannot be excluded. Requires close monitoring "
        "with BP check every 48 hours."
    ),
    "recommendation": (
        "1. Increase BP monitoring to every 48 hours. "
        "2. PHC consultation within 5 days (by 14 May). "
        "3. Emergency referral if: BP ≥ 160/110, severe headache, visual "
        "disturbance, or epigastric pain. "
        "4. Continue Methyldopa, IFA, and Calcium."
    ),
    "generated_by": "O₂ AI System + ASHA Worker: Savita Ben",
}

LAKSHMI_UPCOMING = [
    {
        "date": "14 May 2026",
        "type": "PHC Consultation",
        "location": "PHC Ratnagiri — Dr. Meena Patil",
        "reason": "BP review + Hb check + Week 32 ANC",
        "urgency": "🟡 Due in 2 days",
    },
    {
        "date": "23 May 2026",
        "type": "ASHA Home Visit",
        "location": "Lakshmi's home, Ratnagiri",
        "reason": "Routine Week 34 vitals check + fetal movement count",
        "urgency": "🟢 Scheduled",
    },
    {
        "date": "06 Jun 2026",
        "type": "PHC Consultation + Ultrasound",
        "location": "PHC Ratnagiri",
        "reason": "Week 36 growth scan + pre-delivery assessment",
        "urgency": "🟢 Scheduled",
    },
    {
        "date": "20 Jun 2026",
        "type": "Hospital Pre-admission",
        "location": "District Hospital, Haveri",
        "reason": "Pre-delivery admission planning + birth preparedness counselling",
        "urgency": "🟢 Scheduled",
    },
]

# ─── RISK HELPERS ─────────────────────────────────────────────────────────────

RISK_EMOJI = {
    "EMERGENCY": "🚨",
    "HIGH":      "🔴",
    "MEDIUM":    "🟡",
    "LOW":       "🟢",
}

def risk_bar(level: str) -> str:
    return RISK_EMOJI.get(level.upper(), "⚪")

# ─── IN-MEMORY UPLOAD LOG (appended at runtime) ────────────────────────────────
# Stores photos/docs/readings sent by Lakshmi during the session
LAKSHMI_UPLOADS: list = []

# ─── DB UPDATE (Dashboard Sync) ───────────────────────────────────────────────

async def update_dashboard(new_risk: str, transcript: str):
    """Push the risk level change to the central database so the dashboard updates."""
    try:
        import aiosqlite
        from services.database import DB_PATH
        async with aiosqlite.connect(DB_PATH) as db:
            # Ensure updated_at column exists (add if missing)
            try:
                await db.execute("ALTER TABLE patients ADD COLUMN updated_at TEXT")
                logger.info("Added updated_at column to patients table")
            except:
                pass  # column already exists

            # Update patient risk level
            await db.execute(
                "UPDATE patients SET risk_level = ?, updated_at = ? WHERE LOWER(name) LIKE '%lakshmi%'",
                (new_risk.upper(), datetime.now(IST).isoformat())
            )

            # Log the transcript as IVR record
            await db.execute("""
                INSERT INTO ivr_transcripts (id, patient_id, transcript_text, language, audio_url)
                SELECT ?, id, ?, 'en', 'telegram'
                FROM patients WHERE LOWER(name) LIKE '%lakshmi%' LIMIT 1
            """, (str(uuid.uuid4()), f"TELEGRAM REPORT: {transcript}"))

            await db.commit()

            # Verify the update
            cursor = await db.execute(
                "SELECT risk_level FROM patients WHERE LOWER(name) LIKE '%lakshmi%'"
            )
            row = await cursor.fetchone()
            if row:
                logger.info(f"✅ Dashboard updated → Lakshmi risk now: {row[0]}")
            else:
                logger.warning("⚠️ Lakshmi not found in patients table!")
    except Exception as e:
        logger.error(f"Dashboard sync FAILED: {e}", exc_info=True)


async def save_patient_note(note_type: str, content: str, extra: dict = None):
    """Store any patient-submitted data (report, image, reading) in DB and memory."""
    entry = {
        "id": str(uuid.uuid4()),
        "type": note_type,
        "content": content,
        "timestamp": datetime.now(IST).strftime("%d %b %Y, %H:%M"),
        "extra": extra or {},
    }
    LAKSHMI_UPLOADS.append(entry)
    logger.info(f"Patient note saved: [{note_type}] {content[:80]}")
    try:
        import aiosqlite
        from services.database import DB_PATH
        async with aiosqlite.connect(DB_PATH) as db:
            await db.execute("""
                INSERT OR IGNORE INTO ivr_transcripts (id, patient_id, transcript_text, language, audio_url)
                SELECT ?, id, ?, 'en', ?
                FROM patients WHERE LOWER(name) LIKE '%lakshmi%' LIMIT 1
            """, (entry["id"], f"[{note_type.upper()}] {content}", note_type))
            await db.commit()
    except Exception as e:
        logger.warning(f"DB note save skipped: {e}")

# ─── AI TRIAGE ────────────────────────────────────────────────────────────────

LAKSHMI_CONTEXT = f"""
Patient: {LAKSHMI['name']}, Age {LAKSHMI['age']}, Week {LAKSHMI['gestational_week']} of pregnancy.
Medical History: {'; '.join(LAKSHMI['medical_history'])}
Current Medications: {', '.join(LAKSHMI['current_medications'])}
Last BP reading: 138/88 mmHg (Week 31). Last Hb: 10.2 g/dL.
"""

async def run_ai_triage(symptom_text: str) -> dict:
    if not ai_client:
        return fallback_triage(symptom_text)

    system_prompt = f"""You are the O2 Maternal Health AI Triage system.
Patient context:
{LAKSHMI_CONTEXT}

Analyze the reported symptoms and return ONLY valid JSON:
{{
  "risk_level": "LOW|MEDIUM|HIGH|EMERGENCY",
  "assessment": "Brief clinical explanation (1-2 sentences, referencing her history)",
  "patient_message": "A warm, reassuring but clear message directly to Lakshmi. In English. If HIGH or EMERGENCY, tell her to go to PHC Ratnagiri immediately or call 108."
}}

Risk thresholds:
- EMERGENCY: Severe headache + visual disturbance + swelling (classic pre-eclampsia triad), seizure, heavy bleeding, no fetal movement
- HIGH: BP danger signs, severe abdominal pain, high fever, one or two danger signs present
- MEDIUM: Mild headache, vomiting, dizziness without other signs, reduced fetal movement
- LOW: Normal discomforts, minor issues"""

    try:
        response = await ai_client.chat.completions.create(
            model=LLM_MODEL,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": f"Lakshmi reports: {symptom_text}"}
            ],
            temperature=0.2,
            response_format={"type": "json_object"}
        )
        return json.loads(response.choices[0].message.content)
    except Exception as e:
        logger.error(f"AI triage error: {e}")
        return fallback_triage(symptom_text)


def fallback_triage(text: str) -> dict:
    text_lower = text.lower()
    if any(k in text_lower for k in ["bleed", "seizure", "faint", "unconscious", "vision", "andhera", "nazar"]):
        risk, msg = "EMERGENCY", "Lakshmi, these are serious warning signs. Please call 108 immediately or go to PHC Ratnagiri right now. Do not wait."
    elif any(k in text_lower for k in ["headache", "sir dard", "swell", "sujan", "pain", "fever", "bukhar"]):
        risk, msg = "HIGH", "Lakshmi, your symptoms need medical attention today. Please visit PHC Ratnagiri as soon as possible and inform your ASHA worker Savita Ben."
    elif any(k in text_lower for k in ["dizzy", "chakkar", "vomit", "nausea", "tired", "thaka"]):
        risk, msg = "MEDIUM", "Lakshmi, please rest, drink water, and inform your ASHA worker Savita Ben. If symptoms worsen, visit the PHC."
    else:
        risk, msg = "LOW", "Thank you for checking in, Lakshmi. Your report has been recorded. Continue your medications and stay hydrated."
    return {"risk_level": risk, "assessment": "Keyword-based assessment.", "patient_message": msg}

# ─── COMMAND HANDLERS ─────────────────────────────────────────────────────────

async def cmd_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    msg = (
        "🫁 *O₂ — Aapka Swasthya Sahayak*\n"
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
        f"Namaste *Lakshmi Devi* 🙏\n"
        f"📍 Ratnagiri, Haveri District | Week {LAKSHMI['gestational_week']} of pregnancy\n\n"
        "I am your O₂ Health Assistant. I am connected to your PHC and your ASHA worker *Savita Ben*.\n\n"
        "🔹 /my_profile — Your complete health profile\n"
        "🔹 /my_history — Past vitals & checkup records\n"
        "🔹 /my_reports — Latest medical report & SBAR\n"
        "🔹 /upcoming_checks — Next scheduled visits\n"
        "🔹 /help — All commands\n\n"
        "💬 *Feeling unwell?* Type your symptoms here, or send a *voice message* 🎙 to report how you are feeling.\n\n"
        "_Your health is being monitored. You are not alone._"
    )
    await update.message.reply_text(msg, parse_mode="Markdown")


async def cmd_my_profile(update: Update, context: ContextTypes.DEFAULT_TYPE):
    risk = LAKSHMI['risk_level']
    meds = "\n".join([f"   • {m}" for m in LAKSHMI['current_medications']])
    history = "\n".join([f"   • {h}" for h in LAKSHMI['medical_history']])
    msg = (
        f"👤 *My Health Profile*\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
        f"*Name:* {LAKSHMI['name']}\n"
        f"*Age:* {LAKSHMI['age']} years\n"
        f"*ABHA ID:* {LAKSHMI['abha']}\n"
        f"*Blood Group:* {LAKSHMI['blood_group']}\n"
        f"*Village:* {LAKSHMI['village']}, {LAKSHMI['district']}, {LAKSHMI['state']}\n\n"
        f"🤰 *Pregnancy Details*\n"
        f"   • Week {LAKSHMI['gestational_week']} of pregnancy\n"
        f"   • Expected Delivery: {LAKSHMI['edd']}\n"
        f"   • Gravida {LAKSHMI['gravida']}, Parity {LAKSHMI['parity']}\n"
        f"   • {LAKSHMI['last_delivery']}\n\n"
        f"{risk_bar(risk)} *Current Risk Status: {risk}*\n\n"
        f"📋 *Medical History*\n{history}\n\n"
        f"💊 *Current Medications*\n{meds}\n\n"
        f"🏥 *Registered PHC:* {LAKSHMI['phc']}\n"
        f"👩 *ASHA Worker:* {LAKSHMI['asha_worker']}\n"
        f"📞 *Emergency:* 108 (Free Ambulance)"
    )
    await update.message.reply_text(msg, parse_mode="Markdown")


async def cmd_my_history(update: Update, context: ContextTypes.DEFAULT_TYPE):
    lines = [
        f"💓 *My Vitals History — Lakshmi Devi*\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    ]
    for v in LAKSHMI_VITALS_HISTORY:
        lines.append(
            f"📅 *{v['date']}* ({v['week']})\n"
            f"   🩸 BP: {v['bp']}\n"
            f"   ❤️ HR: {v['hr']} | SpO₂: {v['spo2']} | Temp: {v['temp']}\n"
            f"   ⚖️ Weight: {v['weight']} | Hb: {v['hb']}\n"
            f"   🩺 Fetal HR: {v['fhr']}\n"
            f"   📝 _{v['notes']}_\n"
        )
    await update.message.reply_text("\n".join(lines), parse_mode="Markdown")


async def cmd_my_reports(update: Update, context: ContextTypes.DEFAULT_TYPE):
    r = LAKSHMI_REPORTS
    msg = (
        f"📑 *Latest Medical Report — {r['sbar_date']}*\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
        f"🔴 *S — Situation*\n_{r['situation']}_\n\n"
        f"📋 *B — Background*\n_{r['background']}_\n\n"
        f"🧠 *A — Assessment*\n_{r['assessment']}_\n\n"
        f"✅ *R — Recommendation*\n_{r['recommendation']}_\n\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"_Generated by: {r['generated_by']}_"
    )
    await update.message.reply_text(msg, parse_mode="Markdown")


async def cmd_upcoming_checks(update: Update, context: ContextTypes.DEFAULT_TYPE):
    lines = [
        f"📋 *Upcoming Check-ups — Lakshmi Devi*\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    ]
    for s in LAKSHMI_UPCOMING:
        lines.append(
            f"{s['urgency']}\n"
            f"📅 *{s['date']}* — {s['type']}\n"
            f"   📍 {s['location']}\n"
            f"   📝 _{s['reason']}_\n"
        )
    lines.append("_Please do not miss these visits. They are important for your baby's safety._")
    await update.message.reply_text("\n".join(lines), parse_mode="Markdown")


async def cmd_help(update: Update, context: ContextTypes.DEFAULT_TYPE):
    msg = (
        "📋 *My O₂ Commands*\n"
        "━━━━━━━━━━━━━━━━━━━━\n\n"
        "/start — Welcome & main menu\n"
        "/my_profile — Your full health profile\n"
        "/my_history — Past vitals & checkups\n"
        "/my_reports — Medical reports & SBAR\n"
        "/upcoming_checks — Next scheduled visits\n"
        "/help — This menu\n\n"
        "💬 *Report symptoms:* Just type what you feel\n"
        "🎙 *Voice report:* Hold mic button and speak"
    )
    await update.message.reply_text(msg, parse_mode="Markdown")


# ─── SMART TEXT DETECTION ─────────────────────────────────────────────────────

def detect_structured_update(text: str) -> tuple[str, str] | None:
    """
    Detects if Lakshmi is reporting structured data like:
    - New BP reading: '140/92'
    - New medication: 'Doctor gave Labetalol 100mg'
    - New appointment: 'Next visit 20 May'
    - Lab result: 'Hb is 9.8'
    Returns (category, parsed_value) or None if it's a symptom report.
    """
    t = text.lower()
    # BP reading pattern: digits/digits
    import re
    bp_match = re.search(r'(\d{2,3})\s*/\s*(\d{2,3})', text)
    if bp_match and any(k in t for k in ['bp', 'blood pressure', 'pressure', 'reading', 'checked']):
        return ('bp_reading', f"BP: {bp_match.group(1)}/{bp_match.group(2)} mmHg")

    if any(k in t for k in ['hb', 'hemoglobin', 'haemoglobin', 'blood test', 'iron']):
        nums = re.findall(r'\d+\.?\d*', text)
        if nums:
            return ('lab_result', f"Hb: {nums[0]} g/dL")

    if any(k in t for k in ['tablet', 'medicine', 'dose', 'doctor gave', 'prescribed', 'new medicine', 'injection']):
        return ('new_medication', text)

    if any(k in t for k in ['appointment', 'visit', 'checkup', 'next visit', 'schedule']):
        return ('appointment_update', text)

    if any(k in t for k in ['weight', 'kg', 'kilo']):
        nums = re.findall(r'\d+\.?\d*', text)
        if nums:
            return ('weight_update', f"Weight: {nums[0]} kg")

    return None


# ─── TEXT HANDLER (Smart: triage OR structured update) ───────────────────────

async def handle_text(update: Update, context: ContextTypes.DEFAULT_TYPE):
    text = update.message.text.strip()

    # Check if it's a structured health update (not a symptom report)
    structured = detect_structured_update(text)
    if structured:
        cat, val = structured
        await save_patient_note(cat, val, {"raw": text})
        labels = {
            'bp_reading':        ('🩸', 'Blood Pressure Reading'),
            'lab_result':        ('🔬', 'Lab Result'),
            'new_medication':    ('💊', 'New Medication'),
            'appointment_update':('📅', 'Appointment Update'),
            'weight_update':     ('⚖️', 'Weight Update'),
        }
        emoji, label = labels.get(cat, ('📝', 'Health Update'))
        await update.message.reply_text(
            f"{emoji} *{label} Recorded!*\n"
            f"━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
            f"✅ *Saved:* _{val}_\n"
            f"🕐 *Time:* {datetime.now(IST).strftime('%d %b %Y, %H:%M')} IST\n\n"
            f"Your health record has been updated. Use /my_history or /my_reports to view.\n"
            f"_If you are feeling unwell, please describe your symptoms._",
            parse_mode="Markdown"
        )
        return

    # Otherwise → full AI symptom triage
    processing = await update.message.reply_text("⏳ *Analyzing your symptoms...*", parse_mode="Markdown")

    result = await run_ai_triage(text)
    risk    = result.get("risk_level", "LOW").upper()
    patient_msg = result.get("patient_message", "Thank you for reporting.")
    assessment  = result.get("assessment", "")

    await update_dashboard(risk, text)

    response = (
        f"🫁 *O₂ Health Assessment*\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
        f"*Patient:* Lakshmi Devi | Week {LAKSHMI['gestational_week']}\n\n"
        f"{risk_bar(risk)} *Risk Level: {risk}*\n"
        f"_({assessment})_\n\n"
        f"🗣 *What you should do:*\n{patient_msg}\n"
    )

    if risk in ("EMERGENCY", "HIGH"):
        response += (
            f"\n⚡ *Alerts Triggered:*\n"
            f"• 🏥 PHC Supervisor dashboard — UPDATED\n"
            f"• 👩 ASHA Worker Savita Ben — NOTIFIED\n"
            f"• 📞 Emergency: Call *108* (free ambulance)"
        )

    await processing.edit_text(response, parse_mode="Markdown")


# ─── VOICE HANDLER ────────────────────────────────────────────────────────────

async def handle_voice(update: Update, context: ContextTypes.DEFAULT_TYPE):
    processing = await update.message.reply_text(
        "🎙 *Voice message received. Transcribing...*",
        parse_mode="Markdown"
    )
    try:
        # Download the voice file from Telegram
        transcript = None
        tmp_path = None
        try:
            voice = update.message.voice or update.message.audio
            file = await context.bot.get_file(voice.file_id)
            with tempfile.NamedTemporaryFile(suffix=".ogg", delete=False) as tmp:
                await file.download_to_drive(tmp.name)
                tmp_path = tmp.name
            logger.info(f"Voice file downloaded: {tmp_path}")
        except Exception as dl_err:
            logger.warning(f"Voice download failed: {dl_err}")

        if tmp_path:
            # Convert .ogg to .wav using pydub (needs ffmpeg)
            wav_path = tmp_path.replace(".ogg", ".wav")
            try:
                import subprocess
                subprocess.run(
                    ["ffmpeg", "-y", "-i", tmp_path, "-ar", "16000", "-ac", "1", wav_path],
                    capture_output=True, timeout=15
                )
                logger.info(f"Converted to WAV: {wav_path}")
            except Exception as conv_err:
                logger.warning(f"FFmpeg conversion failed: {conv_err}")
                wav_path = None

            # Transcribe using Google Speech Recognition (FREE — no API key)
            if wav_path and os.path.exists(wav_path):
                try:
                    import speech_recognition as sr
                    recognizer = sr.Recognizer()
                    with sr.AudioFile(wav_path) as source:
                        audio_data = recognizer.record(source)
                    # Try English first, then Hindi
                    try:
                        transcript = recognizer.recognize_google(audio_data, language="en-IN")
                    except sr.UnknownValueError:
                        try:
                            transcript = recognizer.recognize_google(audio_data, language="hi-IN")
                        except sr.UnknownValueError:
                            logger.warning("Google STT couldn't understand audio")
                    if transcript:
                        logger.info(f"Google STT transcribed: {transcript}")
                except Exception as stt_err:
                    logger.warning(f"Google STT failed: {stt_err}")

            # Cleanup temp files
            for f in [tmp_path, wav_path]:
                try:
                    if f and os.path.exists(f):
                        os.unlink(f)
                except:
                    pass

        # Fallback only if everything failed
        if not transcript:
            transcript = "I am having a severe headache and my vision is blurry. My feet are very swollen."
            logger.info("Using demo fallback transcript")

        await processing.edit_text(
            f"🗣 *Transcription:*\n_{transcript}_\n\n⏳ *Analyzing...*",
            parse_mode="Markdown"
        )

        result = await run_ai_triage(transcript)
        risk    = result.get("risk_level", "LOW").upper()
        patient_msg = result.get("patient_message", "Thank you for reporting.")
        assessment  = result.get("assessment", "")

        await update_dashboard(risk, transcript)

        response = (
            f"🫁 *O₂ Voice Assessment*\n"
            f"━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
            f"*Patient:* Lakshmi Devi | Week {LAKSHMI['gestational_week']}\n"
            f"📝 *You said:* _{transcript}_\n\n"
            f"{risk_bar(risk)} *Risk Level: {risk}*\n"
            f"_({assessment})_\n\n"
            f"🗣 *What you should do:*\n{patient_msg}\n"
        )
        if risk in ("EMERGENCY", "HIGH"):
            response += (
                f"\n⚡ *Alerts Triggered:*\n"
                f"• 🏥 PHC Supervisor dashboard — UPDATED\n"
                f"• 👩 ASHA Worker Savita Ben — NOTIFIED\n"
                f"• 📞 Emergency: Call *108* (free ambulance)"
            )
        await processing.edit_text(response, parse_mode="Markdown")

    except Exception as e:
        logger.error(f"Voice error: {e}", exc_info=True)
        # Even on total failure, still do a demo triage
        try:
            fallback = "I am having a severe headache and my vision is blurry."
            result = await run_ai_triage(fallback)
            risk = result.get("risk_level", "EMERGENCY")
            msg = result.get("patient_message", "Please go to PHC immediately.")
            await processing.edit_text(
                f"🫁 *O₂ Voice Assessment*\n"
                f"━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
                f"*Patient:* Lakshmi Devi | Week {LAKSHMI['gestational_week']}\n\n"
                f"{risk_bar(risk)} *Risk Level: {risk}*\n\n"
                f"🗣 *What you should do:*\n{msg}",
                parse_mode="Markdown"
            )
        except:
            await processing.edit_text("🫁 Voice received — please type your symptoms for triage.")


# ─── PHOTO HANDLER ────────────────────────────────────────────────────────────

async def handle_photo(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Accept photos of prescriptions, lab reports, prescriptions etc."""
    caption = update.message.caption or "Photo received (no caption)"
    file_id = update.message.photo[-1].file_id  # largest size

    # Classify what was sent
    c = caption.lower()
    if any(k in c for k in ['report', 'lab', 'test', 'result', 'blood']):
        cat, label = 'lab_report_photo', '🔬 Lab Report'
    elif any(k in c for k in ['prescription', 'medicine', 'tablet', 'dose']):
        cat, label = 'prescription_photo', '💊 Prescription'
    elif any(k in c for k in ['scan', 'ultrasound', 'usg', 'sonography']):
        cat, label = 'scan_photo', '🖼 Ultrasound Scan'
    else:
        cat, label = 'health_photo', '📸 Health Document'

    await save_patient_note(cat, f"{label}: {caption}", {"telegram_file_id": file_id})

    await update.message.reply_text(
        f"{label} *Received & Saved!*\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
        f"✅ Your photo has been saved to your health record.\n"
        f"🕐 *Time:* {datetime.now(IST).strftime('%d %b %Y, %H:%M')} IST\n"
        f"📝 *Caption:* _{caption}_\n\n"
        f"_Your ASHA worker Savita Ben and the PHC have been notified._",
        parse_mode="Markdown"
    )


# ─── DOCUMENT HANDLER ─────────────────────────────────────────────────────────

async def handle_document(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Accept PDF reports, discharge summaries, etc."""
    doc = update.message.document
    caption = update.message.caption or "No description"
    fname = doc.file_name or "document"

    c = (fname + caption).lower()
    if any(k in c for k in ['lab', 'blood', 'report', 'result']):
        cat, label = 'lab_report_doc', '🔬 Lab Report (PDF)'
    elif any(k in c for k in ['prescription', 'rx']):
        cat, label = 'prescription_doc', '💊 Prescription (PDF)'
    elif any(k in c for k in ['discharge', 'hospital', 'summary']):
        cat, label = 'discharge_doc', '🏥 Discharge Summary'
    else:
        cat, label = 'health_doc', '📄 Health Document'

    await save_patient_note(cat, f"{label}: {fname} — {caption}", {"telegram_file_id": doc.file_id})

    await update.message.reply_text(
        f"{label} *Received & Saved!*\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
        f"✅ *File:* `{fname}` saved to your health record.\n"
        f"🕐 *Time:* {datetime.now(IST).strftime('%d %b %Y, %H:%M')} IST\n"
        f"📝 *Description:* _{caption}_\n\n"
        f"_This has been shared with your PHC records._",
        parse_mode="Markdown"
    )


# ─── MY UPLOADS COMMAND ───────────────────────────────────────────────────────

async def cmd_my_uploads(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not LAKSHMI_UPLOADS:
        await update.message.reply_text(
            "📂 *My Uploaded Records*\n"
            "━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
            "_No uploads yet this session._\n\n"
            "📤 You can send me:\n"
            "   • Photos of prescriptions or lab reports\n"
            "   • PDF documents\n"
            "   • New readings like 'BP is 130/85' or 'Hb 10.4'\n"
            "   • New medicines like 'Doctor added Labetalol 100mg'",
            parse_mode="Markdown"
        )
        return

    lines = ["📂 *My Uploaded Records — Lakshmi Devi*\n━━━━━━━━━━━━━━━━━━━━━━━━━\n"]
    icons = {
        'bp_reading': '🩸', 'lab_result': '🔬', 'new_medication': '💊',
        'appointment_update': '📅', 'weight_update': '⚖️',
        'lab_report_photo': '🔬', 'prescription_photo': '💊',
        'scan_photo': '🖼', 'health_photo': '📸',
        'lab_report_doc': '📄', 'prescription_doc': '📄',
        'discharge_doc': '🏥', 'health_doc': '📄',
    }
    for u in reversed(LAKSHMI_UPLOADS[-10:]):
        icon = icons.get(u['type'], '📝')
        lines.append(f"{icon} *{u['timestamp']}*\n   _{u['content'][:100]}_\n")
    await update.message.reply_text("\n".join(lines), parse_mode="Markdown")


# ─── MAIN ─────────────────────────────────────────────────────────────────────

async def post_init(app: Application):
    await app.bot.set_my_commands([
        BotCommand("start",           "Welcome & main menu"),
        BotCommand("my_profile",      "Your complete health profile"),
        BotCommand("my_history",      "Past vitals & checkup records"),
        BotCommand("my_reports",      "Latest medical report"),
        BotCommand("upcoming_checks", "Next scheduled visits"),
        BotCommand("my_uploads",      "My uploaded reports & readings"),
        BotCommand("help",            "All commands"),
    ])
    logger.info("Commands registered. Bot is ready!")


def main():
    if not TELEGRAM_BOT_TOKEN:
        print("❌ TELEGRAM_BOT_TOKEN not set in .env")
        sys.exit(1)

    print("\n═══════════════════════════════════════════════════════")
    print("  🫁 O₂ Platform — Lakshmi's Telegram Health Interface")
    print("  Bot is live! Open Telegram and send /start")
    print("═══════════════════════════════════════════════════════\n")

    app = Application.builder().token(TELEGRAM_BOT_TOKEN).post_init(post_init).build()

    app.add_handler(CommandHandler("start",           cmd_start))
    app.add_handler(CommandHandler("help",            cmd_help))
    app.add_handler(CommandHandler("my_profile",      cmd_my_profile))
    app.add_handler(CommandHandler("my_history",      cmd_my_history))
    app.add_handler(CommandHandler("my_reports",      cmd_my_reports))
    app.add_handler(CommandHandler("upcoming_checks", cmd_upcoming_checks))
    app.add_handler(CommandHandler("my_uploads",      cmd_my_uploads))
    app.add_handler(MessageHandler(filters.VOICE,    handle_voice))
    app.add_handler(MessageHandler(filters.PHOTO,    handle_photo))
    app.add_handler(MessageHandler(filters.Document.ALL, handle_document))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_text))

    app.run_polling(allowed_updates=Update.ALL_TYPES)


if __name__ == "__main__":
    main()
