"""
Database Service — O2 Platform FastAPI Backend

SQLite database for hackathon demo.
When Supabase credentials are available, set USE_SUPABASE=true
and the repository interface stays the same.

Tables:
- patients: ABHA-linked patient records
- vitals: blood pressure, heart rate, SpO2 readings
- visits: GPS-tagged home visit logs
- visit_schedules: auto-scheduled follow-ups
- ivr_transcripts: IVR voice message transcriptions
- ml_risk_scores: shadow ML + rule-based risk scores
"""

import aiosqlite
import os
from typing import Optional, List, Dict, Any
from datetime import datetime

DB_PATH = os.getenv("DB_PATH", "o2_platform.db")


async def init_db():
    """Initialize SQLite database with all Phase 2 tables."""
    async with aiosqlite.connect(DB_PATH) as db:
        db.row_factory = aiosqlite.Row
        
        # Patients table
        await db.execute("""
            CREATE TABLE IF NOT EXISTS patients (
                id TEXT PRIMARY KEY,
                abha_number TEXT UNIQUE NOT NULL,
                name TEXT NOT NULL,
                phone TEXT,
                date_of_birth TEXT,
                gender TEXT,
                emergency_contact TEXT,
                emergency_contact_phone TEXT,
                chw_telegram_id TEXT,
                emergency_contact_telegram TEXT,
                phc_id TEXT NOT NULL,
                risk_level TEXT DEFAULT 'LOW',
                created_at TEXT DEFAULT (datetime('now'))
            )
        """)
        
        # Indexes for patients
        await db.execute("CREATE INDEX IF NOT EXISTS idx_patients_abha ON patients(abha_number)")
        await db.execute("CREATE INDEX IF NOT EXISTS idx_patients_phc ON patients(phc_id)")
        await db.execute("CREATE INDEX IF NOT EXISTS idx_patients_risk ON patients(risk_level)")
        
        # Vitals table
        await db.execute("""
            CREATE TABLE IF NOT EXISTS vitals (
                id TEXT PRIMARY KEY,
                patient_id TEXT NOT NULL,
                systolic_bp INTEGER,
                diastolic_bp INTEGER,
                heart_rate INTEGER,
                spo2 INTEGER,
                temperature REAL,
                weight_kg REAL,
                height_cm REAL,
                recorded_at TEXT DEFAULT (datetime('now')),
                recorded_by TEXT,
                sync_status TEXT DEFAULT 'synced',
                FOREIGN KEY (patient_id) REFERENCES patients(id)
            )
        """)
        await db.execute("CREATE INDEX IF NOT EXISTS idx_vitals_patient ON vitals(patient_id)")
        await db.execute("CREATE INDEX IF NOT EXISTS idx_vitals_date ON vitals(recorded_at)")
        
        # Visits table (GPS-tagged home visits)
        await db.execute("""
            CREATE TABLE IF NOT EXISTS visits (
                id TEXT PRIMARY KEY,
                patient_id TEXT NOT NULL,
                latitude REAL NOT NULL,
                longitude REAL NOT NULL,
                chw_id TEXT NOT NULL,
                recorded_at TEXT DEFAULT (datetime('now')),
                sync_status TEXT DEFAULT 'synced',
                notes TEXT,
                FOREIGN KEY (patient_id) REFERENCES patients(id)
            )
        """)
        await db.execute("CREATE INDEX IF NOT EXISTS idx_visits_patient ON visits(patient_id)")
        await db.execute("CREATE INDEX IF NOT EXISTS idx_visits_date ON visits(recorded_at)")
        
        # Visit schedules (auto-scheduled follow-ups)
        await db.execute("""
            CREATE TABLE IF NOT EXISTS visit_schedules (
                id TEXT PRIMARY KEY,
                patient_id TEXT NOT NULL,
                scheduled_at TEXT NOT NULL,
                status TEXT DEFAULT 'pending',
                auto_generated INTEGER DEFAULT 1,
                reason TEXT,
                created_at TEXT DEFAULT (datetime('now')),
                FOREIGN KEY (patient_id) REFERENCES patients(id)
            )
        """)
        await db.execute("CREATE INDEX IF NOT EXISTS idx_schedule_date ON visit_schedules(scheduled_at)")
        
        # IVR transcripts
        await db.execute("""
            CREATE TABLE IF NOT EXISTS ivr_transcripts (
                id TEXT PRIMARY KEY,
                patient_id TEXT NOT NULL,
                audio_url TEXT,
                transcript_text TEXT,
                language TEXT DEFAULT 'kn',
                caller_number TEXT,
                created_at TEXT DEFAULT (datetime('now')),
                FOREIGN KEY (patient_id) REFERENCES patients(id)
            )
        """)
        
        # ML risk scores (shadow mode)
        await db.execute("""
            CREATE TABLE IF NOT EXISTS ml_risk_scores (
                id TEXT PRIMARY KEY,
                patient_id TEXT NOT NULL,
                ml_probability REAL,
                rule_based_level TEXT,
                ml_level TEXT,
                features_json TEXT,
                outcome_label TEXT,
                created_at TEXT DEFAULT (datetime('now')),
                FOREIGN KEY (patient_id) REFERENCES patients(id)
            )
        """)
        await db.execute("CREATE INDEX IF NOT EXISTS idx_ml_patient ON ml_risk_scores(patient_id)")
        
        await db.commit()
        print(f"[DB] Initialized SQLite database at {DB_PATH}")


class PatientRepository:
    """Patient CRUD operations on SQLite."""
    
    def __init__(self, db_path: str = DB_PATH):
        self.db_path = db_path
    
    async def create(self, patient: dict) -> str:
        """Create a new patient record."""
        async with aiosqlite.connect(self.db_path) as db:
            await db.execute("""
                INSERT INTO patients (id, abha_number, name, phone, date_of_birth, gender,
                    emergency_contact, emergency_contact_phone, chw_telegram_id,
                    emergency_contact_telegram, phc_id, risk_level)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                patient["id"],
                patient["abha_number"],
                patient["name"],
                patient.get("phone"),
                patient.get("date_of_birth"),
                patient.get("gender"),
                patient.get("emergency_contact"),
                patient.get("emergency_contact_phone"),
                patient.get("chw_telegram_id"),
                patient.get("emergency_contact_telegram"),
                patient["phc_id"],
                patient.get("risk_level", "LOW"),
            ))
            await db.commit()
            return patient["id"]
    
    async def get(self, patient_id: str) -> Optional[dict]:
        """Get patient by ID."""
        async with aiosqlite.connect(self.db_path) as db:
            db.row_factory = aiosqlite.Row
            cursor = await db.execute(
                "SELECT * FROM patients WHERE id = ?", (patient_id,)
            )
            row = await cursor.fetchone()
            return dict(row) if row else None
    
    async def get_by_abha(self, abha: str) -> Optional[dict]:
        """Get patient by ABHA number."""
        async with aiosqlite.connect(self.db_path) as db:
            db.row_factory = aiosqlite.Row
            cursor = await db.execute(
                "SELECT * FROM patients WHERE abha_number = ?", (abha,)
            )
            row = await cursor.fetchone()
            return dict(row) if row else None
    
    async def list_by_phc(self, phc_id: str) -> List[dict]:
        """List all patients for a PHC."""
        async with aiosqlite.connect(self.db_path) as db:
            db.row_factory = aiosqlite.Row
            cursor = await db.execute(
                "SELECT * FROM patients WHERE phc_id = ? ORDER BY created_at DESC",
                (phc_id,)
            )
            return [dict(row) for row in await cursor.fetchall()]
    
    async def list_high_risk(self, phc_id: str) -> List[dict]:
        """List HIGH risk patients for a PHC."""
        async with aiosqlite.connect(self.db_path) as db:
            db.row_factory = aiosqlite.Row
            cursor = await db.execute(
                "SELECT * FROM patients WHERE phc_id = ? AND risk_level = 'HIGH' ORDER BY created_at DESC",
                (phc_id,)
            )
            return [dict(row) for row in await cursor.fetchall()]
    
    async def update_risk(self, patient_id: str, risk_level: str):
        """Update patient risk level."""
        async with aiosqlite.connect(self.db_path) as db:
            await db.execute(
                "UPDATE patients SET risk_level = ? WHERE id = ?",
                (risk_level, patient_id)
            )
            await db.commit()
    
    async def update_telegram_id(self, patient_id: str, chw_telegram_id: str):
        """Update CHW Telegram ID for patient."""
        async with aiosqlite.connect(self.db_path) as db:
            await db.execute(
                "UPDATE patients SET chw_telegram_id = ? WHERE id = ?",
                (chw_telegram_id, patient_id)
            )
            await db.commit()


class VitalsRepository:
    """Vitals CRUD operations."""
    
    def __init__(self, db_path: str = DB_PATH):
        self.db_path = db_path
    
    async def create(self, vital: dict) -> str:
        """Record a new vitals reading."""
        async with aiosqlite.connect(self.db_path) as db:
            await db.execute("""
                INSERT INTO vitals (id, patient_id, systolic_bp, diastolic_bp,
                    heart_rate, spo2, temperature, weight_kg, height_cm,
                    recorded_at, recorded_by)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                vital["id"],
                vital["patient_id"],
                vital.get("systolic_bp"),
                vital.get("diastolic_bp"),
                vital.get("heart_rate"),
                vital.get("spo2"),
                vital.get("temperature"),
                vital.get("weight_kg"),
                vital.get("height_cm"),
                vital.get("recorded_at", datetime.utcnow().isoformat()),
                vital.get("recorded_by"),
            ))
            await db.commit()
            return vital["id"]
    
    async def get_latest(self, patient_id: str) -> Optional[dict]:
        """Get most recent vitals for a patient."""
        async with aiosqlite.connect(self.db_path) as db:
            db.row_factory = aiosqlite.Row
            cursor = await db.execute(
                "SELECT * FROM vitals WHERE patient_id = ? ORDER BY recorded_at DESC LIMIT 1",
                (patient_id,)
            )
            row = await cursor.fetchone()
            return dict(row) if row else None
    
    async def list_by_patient(self, patient_id: str, limit: int = 30) -> List[dict]:
        """List vitals history for a patient."""
        async with aiosqlite.connect(self.db_path) as db:
            db.row_factory = aiosqlite.Row
            cursor = await db.execute(
                "SELECT * FROM vitals WHERE patient_id = ? ORDER BY recorded_at DESC LIMIT ?",
                (patient_id, limit)
            )
            return [dict(row) for row in await cursor.fetchall()]


class VisitRepository:
    """Visit log CRUD operations."""
    
    def __init__(self, db_path: str = DB_PATH):
        self.db_path = db_path
    
    async def create(self, visit: dict) -> str:
        """Log a GPS-tagged visit."""
        async with aiosqlite.connect(self.db_path) as db:
            await db.execute("""
                INSERT INTO visits (id, patient_id, latitude, longitude, chw_id, notes)
                VALUES (?, ?, ?, ?, ?, ?)
            """, (
                visit["id"],
                visit["patient_id"],
                visit["latitude"],
                visit["longitude"],
                visit["chw_id"],
                visit.get("notes"),
            ))
            await db.commit()
            return visit["id"]
    
    async def list_by_patient(self, patient_id: str) -> List[dict]:
        """List all visits for a patient."""
        async with aiosqlite.connect(self.db_path) as db:
            db.row_factory = aiosqlite.Row
            cursor = await db.execute(
                "SELECT * FROM visits WHERE patient_id = ? ORDER BY recorded_at DESC",
                (patient_id,)
            )
            return [dict(row) for row in await cursor.fetchall()]
    
    async def list_recent(self, phc_id: str, days: int = 7) -> List[dict]:
        """List recent visits across all patients in a PHC."""
        async with aiosqlite.connect(self.db_path) as db:
            db.row_factory = aiosqlite.Row
            cursor = await db.execute("""
                SELECT v.* FROM visits v
                JOIN patients p ON v.patient_id = p.id
                WHERE p.phc_id = ?
                AND v.recorded_at > datetime('now', ?)
                ORDER BY v.recorded_at DESC
            """, (phc_id, f"-{days} days"))
            return [dict(row) for row in await cursor.fetchall()]


class ScheduleRepository:
    """Visit schedule CRUD operations."""
    
    def __init__(self, db_path: str = DB_PATH):
        self.db_path = db_path
    
    async def create(self, schedule: dict) -> str:
        """Create a scheduled follow-up."""
        async with aiosqlite.connect(self.db_path) as db:
            await db.execute("""
                INSERT INTO visit_schedules (id, patient_id, scheduled_at, status, auto_generated, reason)
                VALUES (?, ?, ?, ?, ?, ?)
            """, (
                schedule["id"],
                schedule["patient_id"],
                schedule["scheduled_at"],
                schedule.get("status", "pending"),
                schedule.get("auto_generated", 1),
                schedule.get("reason"),
            ))
            await db.commit()
            return schedule["id"]
    
    async def list_pending(self, phc_id: str) -> List[dict]:
        """List pending follow-ups for a PHC."""
        async with aiosqlite.connect(self.db_path) as db:
            db.row_factory = aiosqlite.Row
            cursor = await db.execute("""
                SELECT s.* FROM visit_schedules s
                JOIN patients p ON s.patient_id = p.id
                WHERE p.phc_id = ?
                AND s.status = 'pending'
                AND s.scheduled_at > datetime('now')
                ORDER BY s.scheduled_at ASC
            """, (phc_id,))
            return [dict(row) for row in await cursor.fetchall()]


class MLRiskRepository:
    """ML risk score logging."""
    
    def __init__(self, db_path: str = DB_PATH):
        self.db_path = db_path
    
    async def create(self, score: dict) -> str:
        """Log shadow ML risk score alongside rule-based."""
        async with aiosqlite.connect(self.db_path) as db:
            await db.execute("""
                INSERT INTO ml_risk_scores (id, patient_id, ml_probability, rule_based_level,
                    ml_level, features_json, outcome_label)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, (
                score["id"],
                score["patient_id"],
                score.get("ml_probability"),
                score.get("rule_based_level"),
                score.get("ml_level"),
                score.get("features_json"),
                score.get("outcome_label"),
            ))
            await db.commit()
            return score["id"]
    
    async def get_latest(self, patient_id: str) -> Optional[dict]:
        """Get most recent ML risk score for a patient."""
        async with aiosqlite.connect(self.db_path) as db:
            db.row_factory = aiosqlite.Row
            cursor = await db.execute(
                "SELECT * FROM ml_risk_scores WHERE patient_id = ? ORDER BY created_at DESC LIMIT 1",
                (patient_id,)
            )
            row = await cursor.fetchone()
            return dict(row) if row else None
    
    async def get_with_outcomes(self, min_samples: int = 50) -> List[dict]:
        """Get scored patients with outcome labels for retraining."""
        async with aiosqlite.connect(self.db_path) as db:
            db.row_factory = aiosqlite.Row
            cursor = await db.execute("""
                SELECT * FROM ml_risk_scores
                WHERE outcome_label IS NOT NULL
                LIMIT ?
            """, (min_samples,))
            return [dict(row) for row in await cursor.fetchall()]


# Module-level singleton instances
patient_repo = PatientRepository()
vitals_repo = VitalsRepository()
visit_repo = VisitRepository()
schedule_repo = ScheduleRepository()
ml_risk_repo = MLRiskRepository()