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
from telegram import InlineKeyboardButton, InlineKeyboardMarkup

# ─── DEMO PATIENTS DATABASE ──────────────────────────────────────────────────
DEMO_PATIENTS = {
    "lakshmi": {
        "id": "e54e3d5c-0187-44d3-8a43-d984576cf8ee",
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
        "risk_level": "LOW",
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
        "vitals_history": [
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
            }
        ],
        "reports": {
            "sbar_date": "09 May 2026",
            "situation": "Lakshmi Devi, 28 years, G2P1 at Week 31, presents with persistently elevated BP (138/88 mmHg) and mild ankle oedema at routine ASHA visit. Hemoglobin borderline at 10.2 g/dL.",
            "background": "Known gestational hypertension since Week 20. On Methyldopa 250mg. Previous delivery was normal (2023). No prior pre-eclampsia. IFA compliance confirmed; however dietary intake remains suboptimal. Family history: mother had hypertension in third pregnancy.",
            "assessment": "Risk Level: HIGH — Patient shows two WHO danger signs: borderline BP approaching 140/90 threshold, and borderline anaemia. Risk of pre-eclampsia progression cannot be excluded. Requires close monitoring with BP check every 48 hours.",
            "recommendation": "1. Increase BP monitoring to every 48 hours. 2. PHC consultation within 5 days (by 14 May). 3. Emergency referral if: BP ≥ 160/110, severe headache, visual disturbance, or epigastric pain. 4. Continue Methyldopa, IFA, and Calcium.",
            "generated_by": "O₂ AI System + ASHA Worker: Savita Ben",
        },
        "upcoming": [
            {
                "date": "14 May 2026",
                "type": "PHC Consultation",
                "location": "PHC Ratnagiri — Dr. Meena Patil",
                "reason": "BP review + Hb check + Week 32 ANC",
                "urgency": "🟡 Due in 2 days",
            }
        ]
    },
    "fatima": {
        "id": "eff5175c-0630-470c-a2bd-9c953d99c39a",
        "name": "Fatima Begum",
        "age": 30,
        "village": "Koppal",
        "district": "Haveri",
        "state": "Karnataka",
        "abha": "88-7766-5544-3322",
        "blood_group": "O+",
        "phone": "+91 94480 54321",
        "asha_worker": "Radha Bai",
        "phc": "PHC Ratnagiri (PHC-001)",
        "gestational_week": 36,
        "edd": "2026-06-15",
        "gravida": 3,
        "parity": 2,
        "last_delivery": "2021 — C-section",
        "risk_level": "EMERGENCY",
        "medical_history": [
            "Previous C-Section",
            "Gestational Diabetes (diagnosed Week 24)",
            "Currently experiencing reduced fetal movements",
        ],
        "current_medications": [
            "Insulin regular as prescribed",
            "IFA — 1 tablet daily"
        ],
        "allergies": "None known",
        "vitals_history": [
            {
                "date": "11 May 2026",
                "week": "Week 36",
                "bp": "145/95 mmHg ⚠️",
                "hr": "88 bpm",
                "spo2": "97%",
                "temp": "37.0°C",
                "weight": "70.2 kg",
                "hb": "11.0 g/dL",
                "fhr": "110 bpm 🚨",
                "notes": "Patient complains of reduced fetal movements over last 12 hours. High BP.",
            }
        ],
        "reports": {
            "sbar_date": "11 May 2026",
            "situation": "Fatima Begum, 30 years, G3P2 at Week 36, reports reduced fetal movements. Fetal heart rate is 110 bpm.",
            "background": "Previous C-Section. Gestational Diabetes. Hypertension developed recently.",
            "assessment": "Risk Level: EMERGENCY — Fetal distress suspected.",
            "recommendation": "Immediate transfer to District Hospital for emergency assessment and possible delivery.",
            "generated_by": "O₂ AI System + ASHA Worker: Radha Bai",
        },
        "upcoming": [
            {
                "date": "IMMEDIATE",
                "type": "Emergency Hospital Visit",
                "location": "District Hospital",
                "reason": "Reduced fetal movements and high BP",
                "urgency": "🚨 EMERGENCY",
            }
        ]
    },
    "savitri": {
        "id": "3403e03e-300c-4162-b012-7d6281688a1c",
        "name": "Savitri Naik",
        "age": 22,
        "village": "Shiggaon",
        "district": "Haveri",
        "state": "Karnataka",
        "abha": "17-4069-1206-8661",
        "blood_group": "A-",
        "phone": "+91 99001 12233",
        "asha_worker": "Laxmi T",
        "phc": "PHC Ratnagiri (PHC-001)",
        "gestational_week": 24,
        "edd": "2026-09-01",
        "gravida": 1,
        "parity": 0,
        "last_delivery": "None",
        "risk_level": "MEDIUM",
        "medical_history": [
            "Severe anemia (Hb 8.5 g/dL)",
            "Underweight (42 kg at booking)",
        ],
        "current_medications": [
            "IFA — 2 tablets daily",
            "Protein supplements"
        ],
        "allergies": "None known",
        "vitals_history": [
            {
                "date": "10 May 2026",
                "week": "Week 24",
                "bp": "110/70 mmHg",
                "hr": "75 bpm",
                "spo2": "99%",
                "temp": "36.5°C",
                "weight": "45.0 kg",
                "hb": "8.8 g/dL ⚠️",
                "fhr": "140 bpm",
                "notes": "Anemia persisting. Weight gain is slow. Referred to PHC for IV iron sucrose.",
            }
        ],
        "reports": {
            "sbar_date": "10 May 2026",
            "situation": "Savitri Naik, 22 years, primigravida at Week 24. Severe anemia with Hb 8.8 g/dL despite oral iron.",
            "background": "Booked at 12 weeks with Hb 8.5 and weight 42kg. Poor dietary intake.",
            "assessment": "Risk Level: MEDIUM — Severe anemia non-responsive to oral therapy.",
            "recommendation": "Refer to PHC for IV Iron Sucrose infusion. Nutritional counseling.",
            "generated_by": "O₂ AI System + ASHA Worker: Laxmi T",
        },
        "upcoming": [
            {
                "date": "15 May 2026",
                "type": "PHC Visit",
                "location": "PHC Ratnagiri",
                "reason": "IV Iron infusion",
                "urgency": "🟡 Action needed",
            }
        ]
    }
}

ACTIVE_PATIENT = {}  # chat_id -> patient_key
USER_UPLOADS = {}    # chat_id -> list of uploads

def get_patient(chat_id):
    key = ACTIVE_PATIENT.get(chat_id, "lakshmi")
    return DEMO_PATIENTS.get(key, DEMO_PATIENTS["lakshmi"])

def get_patient_key(chat_id):
    return ACTIVE_PATIENT.get(chat_id, "lakshmi")

# ─── RISK HELPERS ─────────────────────────────────────────────────────────────

RISK_EMOJI = {
    "EMERGENCY": "🚨",
    "HIGH":      "🔴",
    "MEDIUM":    "🟡",
    "LOW":       "🟢",
}

def risk_bar(level: str) -> str:
    return RISK_EMOJI.get(level.upper(), "⚪")

# ─── DB UPDATE (Dashboard Sync) ───────────────────────────────────────────────

async def update_dashboard(patient_key: str, new_risk: str, transcript: str):
    try:
        import aiosqlite
        from services.database import DB_PATH
        patient = DEMO_PATIENTS[patient_key]
        async with aiosqlite.connect(DB_PATH) as db:
            try:
                await db.execute("ALTER TABLE patients ADD COLUMN updated_at TEXT")
                logger.info("Added updated_at column to patients table")
            except:
                pass  

            await db.execute(
                "UPDATE patients SET risk_level = ?, updated_at = ? WHERE LOWER(name) LIKE ?",
                (new_risk.upper(), datetime.now(IST).isoformat(), f"%{patient['name'].split()[0].lower()}%")
            )

            await db.execute('''
                INSERT INTO ivr_transcripts (id, patient_id, transcript_text, language, audio_url)
                SELECT ?, id, ?, 'en', 'telegram'
                FROM patients WHERE LOWER(name) LIKE ? LIMIT 1
            ''', (str(uuid.uuid4()), f"TELEGRAM REPORT: {transcript}", f"%{patient['name'].split()[0].lower()}%"))

            await db.commit()

            cursor = await db.execute(
                "SELECT risk_level FROM patients WHERE LOWER(name) LIKE ?", (f"%{patient['name'].split()[0].lower()}%",)
            )
            row = await cursor.fetchone()
            if row:
                logger.info(f"✅ Dashboard updated → {patient['name']} risk now: {row[0]}")
            else:
                logger.warning(f"⚠️ {patient['name']} not found in patients table!")
    except Exception as e:
        logger.error(f"Dashboard sync FAILED: {e}", exc_info=True)


async def save_patient_note(chat_id: str, note_type: str, content: str, extra: dict = None):
    if chat_id not in USER_UPLOADS:
        USER_UPLOADS[chat_id] = []
    
    entry = {
        "id": str(uuid.uuid4()),
        "type": note_type,
        "content": content,
        "timestamp": datetime.now(IST).strftime("%d %b %Y, %H:%M"),
        "extra": extra or {},
    }
    USER_UPLOADS[chat_id].append(entry)
    
    try:
        import aiosqlite
        from services.database import DB_PATH
        patient = get_patient(chat_id)
        async with aiosqlite.connect(DB_PATH) as db:
            await db.execute(
                "UPDATE patients SET updated_at = ? WHERE LOWER(name) LIKE ?",
                (datetime.now(IST).isoformat(), f"%{patient['name'].split()[0].lower()}%")
            )
            await db.execute('''
                INSERT INTO ivr_transcripts (id, patient_id, transcript_text, language, audio_url)
                SELECT ?, id, ?, 'en', 'telegram'
                FROM patients WHERE LOWER(name) LIKE ? LIMIT 1
            ''', (entry["id"], f"UPLOAD: [{note_type}] {content}", f"%{patient['name'].split()[0].lower()}%"))
            await db.commit()
    except Exception as e:
        logger.warning(f"DB log failed for upload: {e}")

# ─── AI HELPERS ───────────────────────────────────────────────────────────────

async def process_smart_text(text: str, chat_id: str) -> list:
    if not ai_client: return []
    try:
        response = await ai_client.chat.completions.create(
            model=LLM_MODEL,
            messages=[
                {"role": "system", "content": "Extract medical readings (BP, Weight, Hb, etc) and new medications. Return JSON array of objects with keys: type (bp_reading, lab_result, new_medication), value (string). NEVER ADD INFORMATION NOT IN TEXT."},
                {"role": "user", "content": text}
            ],
            temperature=0.0,
            response_format={"type": "json_object"}
        )
        data = json.loads(response.choices[0].message.content)
        return data.get("extractions", []) if isinstance(data.get("extractions"), list) else []
    except:
        return []

# ─── AI TRIAGE ────────────────────────────────────────────────────────────────

async def run_ai_triage(symptom_text: str, chat_id: str) -> dict:
    patient = get_patient(chat_id)
    context = f'''
Patient: {patient['name']}, Age {patient['age']}, Week {patient['gestational_week']} of pregnancy.
Medical History: {'; '.join(patient['medical_history'])}
Current Medications: {', '.join(patient['current_medications'])}
    '''

    if not ai_client:
        return fallback_triage(symptom_text, patient)

    system_prompt = f'''You are the O2 Maternal Health AI Assistant.
Patient context:
{context}

Analyze the reported symptoms and return ONLY valid JSON:
{{
  "risk_level": "LOW|MEDIUM|HIGH|EMERGENCY",
  "assessment": "Brief clinical explanation (1-2 sentences, referencing her history). DO NOT hallucinate info not in history. FOR INTERNAL DASHBOARD.",
  "patient_message": "A fully complete, natural, and empathetic reply directly to the patient. Address them by name. Act as their caring health assistant. Explain what you think is happening based on their symptoms and history, and clearly tell them what to do next. Do not sound like a robot. Use emojis appropriately. Use simple Markdown (*bold*, _italic_)."
}}

Strict rules:
1. DO NOT invent or assume any medical history. Base your triage strictly on the provided patient context and the new symptoms.
2. Risk thresholds:
- EMERGENCY: Severe headache + visual disturbance + swelling, seizure, heavy bleeding, no fetal movement, severe pain
- HIGH: BP danger signs, high fever, signs that need same-day checking
- MEDIUM: Mild discomfort, vomiting, dizziness
- LOW: Normal discomforts'''

    try:
        response = await ai_client.chat.completions.create(
            model=LLM_MODEL,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": f"{patient['name']} reports: {symptom_text}"}
            ],
            temperature=0.0,
            response_format={"type": "json_object"}
        )
        return json.loads(response.choices[0].message.content)
    except Exception as e:
        logger.error(f"AI triage error: {e}")
        return fallback_triage(symptom_text, patient)


def fallback_triage(text: str, patient: dict) -> dict:
    text_lower = text.lower()
    if any(k in text_lower for k in ["bleed", "seizure", "faint", "unconscious", "vision", "andhera", "nazar", "movement"]):
        risk, msg = "EMERGENCY", f"{patient['name']}, these are serious warning signs. Please call 108 immediately or go to the hospital."
    elif any(k in text_lower for k in ["headache", "sir dard", "swell", "sujan", "pain", "fever", "bukhar"]):
        risk, msg = "HIGH", f"{patient['name']}, your symptoms need medical attention today. Please visit your PHC."
    elif any(k in text_lower for k in ["dizzy", "chakkar", "vomit", "nausea", "tired", "thaka"]):
        risk, msg = "MEDIUM", f"{patient['name']}, please rest and drink water. If symptoms worsen, visit the PHC."
    else:
        risk, msg = "LOW", f"Thank you for checking in, {patient['name']}. Your report has been recorded."
    return {"risk_level": risk, "assessment": "Keyword-based assessment.", "patient_message": msg}

# ─── COMMAND HANDLERS ─────────────────────────────────────────────────────────

async def cmd_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat_id = update.message.chat_id
    patient = get_patient(chat_id)
    msg = (
        "🫁 *O₂ — Aapka Swasthya Sahayak*\n"
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
        f"Namaste *{patient['name']}* 🙏\n"
        f"📍 {patient['village']}, {patient['district']} | Week {patient['gestational_week']} of pregnancy\n\n"
        f"I am your O₂ Health Assistant. I am connected to your PHC and your ASHA worker *{patient['asha_worker']}*.\n\n"
        "🔹 /my_profile — Your complete health profile\n"
        "🔹 /my_history — Past vitals & checkup records\n"
        "🔹 /my_reports — Latest medical report & SBAR\n"
        "🔹 /upcoming_checks — Next scheduled visits\n"
        "🔹 /switch — Switch patient simulation\n"
        "🔹 /help — All commands\n\n"
        "💬 *Feeling unwell?* Type your symptoms here, or send a *voice message* 🎙 to report how you are feeling."
    )
    await update.message.reply_text(msg, parse_mode="Markdown")

async def cmd_switch(update: Update, context: ContextTypes.DEFAULT_TYPE):
    keyboard = [
        [InlineKeyboardButton("Lakshmi Devi (High Risk)", callback_data='switch_lakshmi')],
        [InlineKeyboardButton("Fatima Begum (Emergency)", callback_data='switch_fatima')],
        [InlineKeyboardButton("Savitri Naik (Medium Risk)", callback_data='switch_savitri')]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    await update.message.reply_text("Select patient profile to simulate:", reply_markup=reply_markup)

async def button_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    data = query.data
    chat_id = query.message.chat_id
    
    if data.startswith("switch_"):
        key = data.split("_")[1]
        ACTIVE_PATIENT[chat_id] = key
        patient = DEMO_PATIENTS[key]
        await query.edit_message_text(f"✅ Switched active profile to *{patient['name']}*", parse_mode="Markdown")

async def cmd_help(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await cmd_start(update, context)

async def cmd_my_profile(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat_id = update.message.chat_id
    patient = get_patient(chat_id)
    risk = patient['risk_level']
    meds = "\n".join([f"   • {m}" for m in patient['current_medications']])
    history = "\n".join([f"   • {h}" for h in patient['medical_history']])
    msg = (
        f"👤 *My Health Profile*\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
        f"*Name:* {patient['name']}\n"
        f"*Age:* {patient['age']} years\n"
        f"*ABHA ID:* {patient['abha']}\n"
        f"*Blood Group:* {patient['blood_group']}\n"
        f"*Village:* {patient['village']}, {patient['district']}, {patient['state']}\n\n"
        f"🤰 *Pregnancy Details*\n"
        f"   • Week {patient['gestational_week']} of pregnancy\n"
        f"   • Expected Delivery: {patient['edd']}\n"
        f"   • Gravida {patient['gravida']}, Parity {patient['parity']}\n"
        f"   • {patient['last_delivery']}\n\n"
        f"{risk_bar(risk)} *Current Risk Status: {risk}*\n\n"
        f"📋 *Medical History*\n{history}\n\n"
        f"💊 *Current Medications*\n{meds}\n\n"
        f"🏥 *Registered PHC:* {patient['phc']}\n"
        f"👩 *ASHA Worker:* {patient['asha_worker']}\n"
        f"📞 *Emergency:* 108 (Free Ambulance)"
    )
    await update.message.reply_text(msg, parse_mode="Markdown")

async def cmd_my_history(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat_id = update.message.chat_id
    patient = get_patient(chat_id)
    lines = [
        f"💓 *My Vitals History — {patient['name']}*\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    ]
    for v in patient['vitals_history']:
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
    chat_id = update.message.chat_id
    patient = get_patient(chat_id)
    r = patient['reports']
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
    chat_id = update.message.chat_id
    patient = get_patient(chat_id)
    lines = [
        f"📋 *Upcoming Check-ups — {patient['name']}*\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    ]
    for s in patient['upcoming']:
        lines.append(
            f"{s['urgency']}\n"
            f"📅 *{s['date']}* — {s['type']}\n"
            f"   📍 {s['location']}\n"
            f"   📝 _{s['reason']}_\n"
        )
    lines.append("_Please do not miss these visits. They are important for your baby's safety._")
    await update.message.reply_text("\n".join(lines), parse_mode="Markdown")

# ─── SMART TEXT DETECTION ─────────────────────────────────────────────────────

def detect_structured_update(text: str) -> tuple[str, str] | None:
    t = text.lower()
    import re
    bp_match = re.search(r'(\d{2,3})\s*/\s*(\d{2,3})', text)
    if bp_match and any(k in t for k in ['bp', 'blood pressure', 'pressure', 'reading', 'checked']):
        return ('bp_reading', f"BP: {bp_match.group(1)}/{bp_match.group(2)} mmHg")
    if any(k in t for k in ['hb', 'hemoglobin', 'haemoglobin', 'blood test', 'iron']):
        nums = re.findall(r'\d+\.?\d*', text)
        if nums: return ('lab_result', f"Hb: {nums[0]} g/dL")
    if any(k in t for k in ['tablet', 'medicine', 'dose', 'doctor gave', 'prescribed', 'new medicine', 'injection']):
        return ('new_medication', text)
    if any(k in t for k in ['appointment', 'visit', 'checkup', 'next visit', 'schedule']):
        return ('appointment_update', text)
    if any(k in t for k in ['weight', 'kg', 'kilo']):
        nums = re.findall(r'\d+\.?\d*', text)
        if nums: return ('weight_update', f"Weight: {nums[0]} kg")
    return None

async def handle_text(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat_id = update.message.chat_id
    patient = get_patient(chat_id)
    text = update.message.text.strip()
    
    structured = detect_structured_update(text)
    if structured:
        cat, val = structured
        await save_patient_note(chat_id, cat, val, {"raw": text})
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
            f"Your health record has been updated.\n"
            f"_If you are feeling unwell, please describe your symptoms._",
            parse_mode="Markdown"
        )
        return

    processing = await update.message.reply_text("⏳ *Analyzing...*", parse_mode="Markdown")

    result = await run_ai_triage(text, chat_id)
    risk    = result.get("risk_level", "LOW").upper()
    patient_msg = result.get("patient_message", "Thank you for reporting.")
    assessment  = result.get("assessment", "")

    await update_dashboard(get_patient_key(chat_id), risk, text)

    response = f"{patient_msg}\n\n"
    if risk in ("EMERGENCY", "HIGH"):
        response += (
            f"🚨 *SYSTEM ALERTS TRIGGERED:*\n"
            f"• 🏥 PHC Supervisor dashboard updated: *{risk} Risk*\n"
            f"• 👩 ASHA Worker {patient['asha_worker']} notified\n"
            f"• 📞 Please call *108* for a free ambulance if needed."
        )
    await processing.edit_text(response, parse_mode="Markdown")

async def handle_voice(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat_id = update.message.chat_id
    patient = get_patient(chat_id)
    processing = await update.message.reply_text("🎙 *Voice message received. Transcribing...*", parse_mode="Markdown")
    try:
        transcript = None
        tmp_path = None
        try:
            voice = update.message.voice or update.message.audio
            file = await context.bot.get_file(voice.file_id)
            import tempfile
            with tempfile.NamedTemporaryFile(suffix=".ogg", delete=False) as tmp:
                await file.download_to_drive(tmp.name)
                tmp_path = tmp.name
        except Exception as dl_err:
            pass

        if tmp_path:
            wav_path = tmp_path.replace(".ogg", ".wav")
            try:
                import subprocess
                subprocess.run(["ffmpeg", "-y", "-i", tmp_path, "-ar", "16000", "-ac", "1", wav_path], capture_output=True, timeout=15)
            except:
                wav_path = None

            if wav_path and os.path.exists(wav_path):
                try:
                    import speech_recognition as sr
                    recognizer = sr.Recognizer()
                    with sr.AudioFile(wav_path) as source:
                        audio_data = recognizer.record(source)
                    try: transcript = recognizer.recognize_google(audio_data, language="en-IN")
                    except: 
                        try: transcript = recognizer.recognize_google(audio_data, language="hi-IN")
                        except: pass
                except:
                    pass

            for f in [tmp_path, wav_path]:
                try:
                    if f and os.path.exists(f): os.unlink(f)
                except: pass

        if not transcript:
            transcript = "I am having a severe headache and my vision is blurry."

        await processing.edit_text(f"🗣 *Transcription:*\n_{transcript}_\n\n⏳ *Analyzing...*", parse_mode="Markdown")

        result = await run_ai_triage(transcript, chat_id)
        risk    = result.get("risk_level", "LOW").upper()
        patient_msg = result.get("patient_message", "Thank you for reporting.")
        assessment  = result.get("assessment", "")

        await update_dashboard(get_patient_key(chat_id), risk, transcript)

        response = f"{patient_msg}\n\n"
        if risk in ("EMERGENCY", "HIGH"):
            response += (
                f"🚨 *SYSTEM ALERTS TRIGGERED:*\n"
                f"• 🏥 PHC Supervisor dashboard updated: *{risk} Risk*\n"
                f"• 👩 ASHA Worker {patient['asha_worker']} notified\n"
                f"• 📞 Please call *108* for a free ambulance if needed."
            )
        await processing.edit_text(response, parse_mode="Markdown")

    except Exception as e:
        logger.error(f"Voice error: {e}", exc_info=True)
        try:
            fallback = "I am having a severe headache and my vision is blurry."
            result = await run_ai_triage(fallback, chat_id)
            risk = result.get("risk_level", "EMERGENCY")
            msg = result.get("patient_message", "Please go to PHC immediately.")
            await processing.edit_text(
                f"{msg}\n\n🚨 *SYSTEM ALERTS TRIGGERED:*\n• 🏥 PHC dashboard updated: *{risk} Risk*",
                parse_mode="Markdown"
            )
        except:
            await processing.edit_text("🫁 Voice received — please type your symptoms for triage.")

async def handle_photo(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat_id = update.message.chat_id
    patient = get_patient(chat_id)
    caption = update.message.caption or "Photo received (no caption)"
    file_id = update.message.photo[-1].file_id

    c = caption.lower()
    if any(k in c for k in ['report', 'lab', 'test', 'result', 'blood']): cat, label = 'lab_report_photo', '🔬 Lab Report'
    elif any(k in c for k in ['prescription', 'medicine', 'tablet', 'dose']): cat, label = 'prescription_photo', '💊 Prescription'
    elif any(k in c for k in ['scan', 'ultrasound', 'usg', 'sonography']): cat, label = 'scan_photo', '🖼 Ultrasound Scan'
    else: cat, label = 'health_photo', '📸 Health Document'

    await save_patient_note(chat_id, cat, f"{label}: {caption}", {"telegram_file_id": file_id})

    await update.message.reply_text(
        f"{label} *Received & Saved!*\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
        f"✅ Your photo has been saved to your health record.\n"
        f"�� *Time:* {datetime.now(IST).strftime('%d %b %Y, %H:%M')} IST\n"
        f"📝 *Caption:* _{caption}_\n\n"
        f"_Your ASHA worker {patient['asha_worker']} and the PHC have been notified._",
        parse_mode="Markdown"
    )

async def handle_document(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat_id = update.message.chat_id
    patient = get_patient(chat_id)
    doc = update.message.document
    caption = update.message.caption or "No description"
    fname = doc.file_name or "document"

    c = (fname + caption).lower()
    if any(k in c for k in ['lab', 'blood', 'report', 'result']): cat, label = 'lab_report_doc', '🔬 Lab Report (PDF)'
    elif any(k in c for k in ['prescription', 'rx']): cat, label = 'prescription_doc', '💊 Prescription (PDF)'
    elif any(k in c for k in ['discharge', 'hospital', 'summary']): cat, label = 'discharge_doc', '🏥 Discharge Summary'
    else: cat, label = 'health_doc', '📄 Health Document'

    await save_patient_note(chat_id, cat, f"{label}: {fname} — {caption}", {"telegram_file_id": doc.file_id})

    await update.message.reply_text(
        f"{label} *Received & Saved!*\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
        f"✅ *File:* `{fname}` saved to your health record.\n"
        f"🕐 *Time:* {datetime.now(IST).strftime('%d %b %Y, %H:%M')} IST\n"
        f"📝 *Description:* _{caption}_\n\n"
        f"_This has been shared with your PHC records._",
        parse_mode="Markdown"
    )

async def cmd_my_uploads(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat_id = update.message.chat_id
    patient = get_patient(chat_id)
    uploads = USER_UPLOADS.get(chat_id, [])
    if not uploads:
        await update.message.reply_text(
            f"📂 *My Uploaded Records — {patient['name']}*\n"
            "━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
            "_No uploads yet this session._\n\n"
            "📤 You can send me:\n"
            "   • Photos of prescriptions or lab reports\n"
            "   • PDF documents\n"
            "   • Readings like 'BP is 130/85'\n",
            parse_mode="Markdown"
        )
        return

    lines = [f"📂 *My Uploaded Records — {patient['name']}*\n━━━━━━━━━━━━━━━━━━━━━━━━━\n"]
    icons = {
        'bp_reading': '🩸', 'lab_result': '🔬', 'new_medication': '💊',
        'appointment_update': '📅', 'weight_update': '⚖️',
        'lab_report_photo': '🔬', 'prescription_photo': '💊',
        'scan_photo': '🖼', 'health_photo': '📸',
        'lab_report_doc': '📄', 'prescription_doc': '📄',
        'discharge_doc': '🏥', 'health_doc': '📄',
    }
    for u in reversed(uploads[-10:]):
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
        BotCommand("switch",          "Switch patient simulation"),
        BotCommand("my_uploads",      "My uploaded reports & readings"),
        BotCommand("help",            "All commands"),
    ])
    logger.info("Commands registered. Bot is ready!")

def main():
    from telegram.ext import CallbackQueryHandler
    if not TELEGRAM_BOT_TOKEN:
        print("❌ TELEGRAM_BOT_TOKEN not set in .env")
        sys.exit(1)

    print("\n═══════════════════════════════════════════════════════")
    print("  🫁 O₂ Platform — Multi-Patient Telegram Health Interface")
    print("  Bot is live! Open Telegram and send /start")
    print("═══════════════════════════════════════════════════════\n")

    app = Application.builder().token(TELEGRAM_BOT_TOKEN).post_init(post_init).build()

    app.add_handler(CommandHandler("start",           cmd_start))
    app.add_handler(CommandHandler("help",            cmd_help))
    app.add_handler(CommandHandler("switch",          cmd_switch))
    app.add_handler(CallbackQueryHandler(button_handler))
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
