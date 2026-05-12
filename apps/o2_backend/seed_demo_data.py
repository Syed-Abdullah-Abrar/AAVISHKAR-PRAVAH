"""
O2 Platform — Demo Seed Data
4 detailed patient stories for the 3-device pitch demo.

Usage:
    cd apps/o2_backend
    PYTHONPATH=. python seed_demo_data.py

Each patient has a medical narrative — not just numbers.
The data flows through O2's risk engine, dashboard, and IVR pipeline.
"""

import asyncio
import uuid
from datetime import datetime, timedelta
from services.database import init_db, patient_repo, vitals_repo, visit_repo, schedule_repo
from services.abha_generator import generate_abha_number, format_abha_display

# ═══════════════════════════════════════════════════════════════════════════════
# PATIENT STORIES
# ═══════════════════════════════════════════════════════════════════════════════

def build_patients():
    """
    4 real-world-inspired patient stories from rural Karnataka.
    Each represents a different risk tier in the O2 traffic-light triage.
    """

    now = datetime.utcnow()

    # ─── PATIENT 1: Lakshmi Devi — HIGH RISK ─────────────────────────────────
    # 28-year-old, 34 weeks pregnant, second pregnancy.
    # Presenting: elevated BP (gestational hypertension), borderline anemia.
    # History: previous pre-eclampsia in first pregnancy, C-section delivery.
    # Story: Lakshmi lives in Hampankatta village, 45 km from the nearest PHC.
    #        Her ASHA worker noticed swelling in her feet during a home visit.
    #        BP readings have been creeping up over the last 3 visits.
    #        She needs specialist referral but refuses to travel to the district hospital.
    p1_id = str(uuid.uuid4())
    p1_abha = generate_abha_number()
    patient1 = {
        "id": p1_id,
        "abha_number": p1_abha,
        "name": "Lakshmi Devi",
        "phone": "+919876543210",
        "date_of_birth": "1998-03-15",
        "gender": "female",
        "emergency_contact": "Ramesh Kumar (husband)",
        "emergency_contact_phone": "+919876543211",
        "chw_telegram_id": "",
        "emergency_contact_telegram": "",
        "phc_id": "PHC001",
        "risk_level": "HIGH",
    }
    # Vitals: 3 readings showing BP trend
    p1_vitals = [
        {
            "id": str(uuid.uuid4()),
            "patient_id": p1_id,
            "systolic_bp": 148, "diastolic_bp": 94,
            "heart_rate": 88, "spo2": 97,
            "temperature": 37.1, "weight_kg": 68.5, "height_cm": 155,
            "recorded_at": (now - timedelta(days=14)).isoformat(),
            "recorded_by": "CHW-001",
        },
        {
            "id": str(uuid.uuid4()),
            "patient_id": p1_id,
            "systolic_bp": 152, "diastolic_bp": 96,
            "heart_rate": 92, "spo2": 96,
            "temperature": 37.0, "weight_kg": 69.2, "height_cm": 155,
            "recorded_at": (now - timedelta(days=7)).isoformat(),
            "recorded_by": "CHW-001",
        },
        {
            "id": str(uuid.uuid4()),
            "patient_id": p1_id,
            "systolic_bp": 158, "diastolic_bp": 98,
            "heart_rate": 94, "spo2": 96,
            "temperature": 37.2, "weight_kg": 70.1, "height_cm": 155,
            "recorded_at": (now - timedelta(days=1)).isoformat(),
            "recorded_by": "CHW-001",
        },
    ]
    # Visit logs
    p1_visits = [
        {
            "id": str(uuid.uuid4()),
            "patient_id": p1_id,
            "latitude": 12.8714, "longitude": 74.8431,
            "chw_id": "CHW-001",
            "notes": "Home visit — patient reports headaches, swollen ankles. BP elevated. Advised PHC visit.",
        },
        {
            "id": str(uuid.uuid4()),
            "patient_id": p1_id,
            "latitude": 12.8720, "longitude": 74.8445,
            "chw_id": "CHW-001",
            "notes": "Follow-up — BP still rising. Patient reluctant to travel. Referred to PHC via SBAR.",
        },
    ]

    # ─── PATIENT 2: Fatima Begum — EMERGENCY ─────────────────────────────────
    # 32-year-old, 38 weeks pregnant, fourth pregnancy (gravida 4, para 3).
    # Presenting: severe anemia (Hb 6.8), tachycardia, weakness.
    # History: two previous PPH episodes, one stillbirth, chronic iron deficiency.
    # Story: Fatima is from a remote hamlet near Belthangady taluk.
    #        She skipped her last two scheduled visits because of harvest season.
    #        When the ASHA visited, she found Fatima extremely pale, barely able to stand.
    #        This is a medical emergency — she needs blood transfusion before delivery.
    p2_id = str(uuid.uuid4())
    p2_abha = generate_abha_number()
    patient2 = {
        "id": p2_id,
        "abha_number": p2_abha,
        "name": "Fatima Begum",
        "phone": "+919845123456",
        "date_of_birth": "1994-07-22",
        "gender": "female",
        "emergency_contact": "Abdul Kareem (husband)",
        "emergency_contact_phone": "+919845123457",
        "chw_telegram_id": "",
        "emergency_contact_telegram": "",
        "phc_id": "PHC001",
        "risk_level": "EMERGENCY",
    }
    p2_vitals = [
        {
            "id": str(uuid.uuid4()),
            "patient_id": p2_id,
            "systolic_bp": 105, "diastolic_bp": 68,
            "heart_rate": 112, "spo2": 93,
            "temperature": 37.8, "weight_kg": 52.3, "height_cm": 150,
            "recorded_at": (now - timedelta(days=3)).isoformat(),
            "recorded_by": "CHW-001",
        },
        {
            "id": str(uuid.uuid4()),
            "patient_id": p2_id,
            "systolic_bp": 98, "diastolic_bp": 62,
            "heart_rate": 118, "spo2": 91,
            "temperature": 38.1, "weight_kg": 51.8, "height_cm": 150,
            "recorded_at": (now - timedelta(hours=6)).isoformat(),
            "recorded_by": "CHW-001",
        },
    ]
    p2_visits = [
        {
            "id": str(uuid.uuid4()),
            "patient_id": p2_id,
            "latitude": 12.7510, "longitude": 75.2850,
            "chw_id": "CHW-001",
            "notes": "EMERGENCY visit — patient extremely pale, HR 118, SpO2 91%. Called 108 ambulance. Needs blood transfusion.",
        },
    ]

    # ─── PATIENT 3: Savitri Naik — MEDIUM RISK ──────────────────────────────
    # 24-year-old, 28 weeks pregnant, first pregnancy (primigravida).
    # Presenting: mild anemia (Hb 10.2), normal BP, occasional dizziness.
    # History: no prior complications, vegetarian diet (low iron intake).
    # Story: Savitri is a school teacher in Puttur. She's diligent about her
    #        antenatal visits but worried about her first pregnancy.
    #        The ASHA started her on iron+folic acid supplements 2 weeks ago.
    #        She needs monitoring but is not in immediate danger.
    p3_id = str(uuid.uuid4())
    p3_abha = generate_abha_number()
    patient3 = {
        "id": p3_id,
        "abha_number": p3_abha,
        "name": "Savitri Naik",
        "phone": "+919900112233",
        "date_of_birth": "2002-01-10",
        "gender": "female",
        "emergency_contact": "Ganesh Naik (father)",
        "emergency_contact_phone": "+919900112234",
        "chw_telegram_id": "",
        "emergency_contact_telegram": "",
        "phc_id": "PHC001",
        "risk_level": "MEDIUM",
    }
    p3_vitals = [
        {
            "id": str(uuid.uuid4()),
            "patient_id": p3_id,
            "systolic_bp": 118, "diastolic_bp": 76,
            "heart_rate": 78, "spo2": 98,
            "temperature": 36.8, "weight_kg": 58.0, "height_cm": 162,
            "recorded_at": (now - timedelta(days=10)).isoformat(),
            "recorded_by": "CHW-002",
        },
        {
            "id": str(uuid.uuid4()),
            "patient_id": p3_id,
            "systolic_bp": 120, "diastolic_bp": 78,
            "heart_rate": 76, "spo2": 98,
            "temperature": 36.7, "weight_kg": 59.1, "height_cm": 162,
            "recorded_at": (now - timedelta(days=2)).isoformat(),
            "recorded_by": "CHW-002",
        },
    ]
    p3_visits = [
        {
            "id": str(uuid.uuid4()),
            "patient_id": p3_id,
            "latitude": 12.7656, "longitude": 75.1986,
            "chw_id": "CHW-002",
            "notes": "Routine ANC visit — Hb 10.2, started IFA supplements. Patient reports occasional dizziness. Follow-up in 2 weeks.",
        },
    ]

    # ─── PATIENT 4: Meera Gowda — LOW RISK ──────────────────────────────────
    # 26-year-old, 20 weeks pregnant, second pregnancy.
    # Presenting: all vitals normal, healthy weight gain, no complaints.
    # History: uncomplicated first pregnancy, normal vaginal delivery.
    # Story: Meera lives near the PHC in Mangalore suburbs. She has good
    #        access to healthcare, attends all scheduled visits.
    #        Her ASHA worker visits weekly for routine monitoring.
    #        She represents the best-case scenario — the system should
    #        confirm LOW risk and schedule routine follow-up.
    p4_id = str(uuid.uuid4())
    p4_abha = generate_abha_number()
    patient4 = {
        "id": p4_id,
        "abha_number": p4_abha,
        "name": "Meera Gowda",
        "phone": "+919811223344",
        "date_of_birth": "2000-09-05",
        "gender": "female",
        "emergency_contact": "Priya Gowda (mother)",
        "emergency_contact_phone": "+919811223345",
        "chw_telegram_id": "",
        "emergency_contact_telegram": "",
        "phc_id": "PHC001",
        "risk_level": "LOW",
    }
    p4_vitals = [
        {
            "id": str(uuid.uuid4()),
            "patient_id": p4_id,
            "systolic_bp": 112, "diastolic_bp": 72,
            "heart_rate": 74, "spo2": 99,
            "temperature": 36.6, "weight_kg": 62.0, "height_cm": 160,
            "recorded_at": (now - timedelta(days=7)).isoformat(),
            "recorded_by": "CHW-002",
        },
        {
            "id": str(uuid.uuid4()),
            "patient_id": p4_id,
            "systolic_bp": 114, "diastolic_bp": 74,
            "heart_rate": 72, "spo2": 99,
            "temperature": 36.5, "weight_kg": 62.8, "height_cm": 160,
            "recorded_at": (now - timedelta(hours=12)).isoformat(),
            "recorded_by": "CHW-002",
        },
    ]
    p4_visits = [
        {
            "id": str(uuid.uuid4()),
            "patient_id": p4_id,
            "latitude": 12.9141, "longitude": 74.8560,
            "chw_id": "CHW-002",
            "notes": "Routine weekly visit — all vitals normal. Healthy weight gain. No complaints. Next visit in 7 days.",
        },
    ]

    # ─── Scheduled follow-ups ─────────────────────────────────────────────
    schedules = [
        {
            "id": str(uuid.uuid4()),
            "patient_id": p1_id,
            "scheduled_at": (now + timedelta(days=1)).isoformat(),
            "status": "pending",
            "auto_generated": 1,
            "reason": "HIGH risk — BP trend rising, needs 24h follow-up",
        },
        {
            "id": str(uuid.uuid4()),
            "patient_id": p2_id,
            "scheduled_at": (now + timedelta(hours=6)).isoformat(),
            "status": "pending",
            "auto_generated": 1,
            "reason": "EMERGENCY — post-ambulance follow-up, verify hospital admission",
        },
        {
            "id": str(uuid.uuid4()),
            "patient_id": p3_id,
            "scheduled_at": (now + timedelta(days=14)).isoformat(),
            "status": "pending",
            "auto_generated": 1,
            "reason": "MEDIUM risk — IFA supplement follow-up, recheck Hb",
        },
        {
            "id": str(uuid.uuid4()),
            "patient_id": p4_id,
            "scheduled_at": (now + timedelta(days=7)).isoformat(),
            "status": "pending",
            "auto_generated": 1,
            "reason": "Routine ANC — weekly check, LOW risk",
        },
    ]

    return (
        [patient1, patient2, patient3, patient4],
        p1_vitals + p2_vitals + p3_vitals + p4_vitals,
        p1_visits + p2_visits + p3_visits + p4_visits,
        schedules,
    )


async def seed():
    """Seed the database with demo patient stories."""
    await init_db()

    patients, vitals, visits, schedules = build_patients()

    print("\n═══════════════════════════════════════════════════════════")
    print("  O2 Platform — Seeding Demo Data")
    print("═══════════════════════════════════════════════════════════\n")

    for p in patients:
        try:
            await patient_repo.create(p)
            print(f"  ✅ Patient: {p['name']:20s} | ABHA: {format_abha_display(p['abha_number'])} | Risk: {p['risk_level']}")
        except Exception as e:
            print(f"  ⚠️  Patient {p['name']} already exists or error: {e}")

    print()
    for v in vitals:
        try:
            await vitals_repo.create(v)
            bp = f"{v.get('systolic_bp', '?')}/{v.get('diastolic_bp', '?')}"
            print(f"  💓 Vitals: BP {bp:7s} | HR {v.get('heart_rate', '?')} | SpO2 {v.get('spo2', '?')}%")
        except Exception as e:
            print(f"  ⚠️  Vitals error: {e}")

    print()
    for vis in visits:
        try:
            await visit_repo.create(vis)
            print(f"  📍 Visit:  GPS [{vis['latitude']:.4f}, {vis['longitude']:.4f}] | {vis.get('notes', '')[:60]}...")
        except Exception as e:
            print(f"  ⚠️  Visit error: {e}")

    print()
    for s in schedules:
        try:
            await schedule_repo.create(s)
            print(f"  📋 Schedule: {s['scheduled_at'][:10]} | {s.get('reason', '')[:60]}...")
        except Exception as e:
            print(f"  ⚠️  Schedule error: {e}")

    print("\n═══════════════════════════════════════════════════════════")
    print(f"  Done: {len(patients)} patients, {len(vitals)} vitals,")
    print(f"        {len(visits)} visits, {len(schedules)} schedules")
    print("═══════════════════════════════════════════════════════════\n")


if __name__ == "__main__":
    asyncio.run(seed())
