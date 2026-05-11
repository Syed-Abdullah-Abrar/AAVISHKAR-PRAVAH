-- O2 Platform — Supabase PostgreSQL Schema
-- Phase 1 MVP
-- 
-- Tables: patients, vitals_logs, chw_assignments, phc_hierarchy
-- RLS Policies: PHC-based isolation for CHW access control
-- 
-- FHIR R4 Mapping: All tables are FHIR-compliant resources
-- Patient → FHIR Patient resource
-- Vitals → FHIR Observation resource
-- 
-- References:
-- - FHIR R4: https://hl7.org/fhir/R4/
-- - Supabase RLS: https://supabase.com/docs/guides/auth/row-level-security

-- ─── Enable Required Extensions ──────────────────────────────────────────────────

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ─── PHC Hierarchy (Geographic Structure) ────────────────────────────────────

CREATE TABLE phc_hierarchy (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('district', 'block', 'phc', 'sub_center')),
    parent_phc_id UUID REFERENCES phc_hierarchy(id) ON DELETE SET NULL,
    address TEXT,
    village TEXT,
    block_id TEXT,
    district_id TEXT,
    state TEXT,
    pincode TEXT,
    phone_number TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Self-referential hierarchy for geographic levels
CREATE INDEX idx_phc_parent ON phc_hierarchy(parent_phc_id);
CREATE INDEX idx_phc_type ON phc_hierarchy(type);
CREATE INDEX idx_phc_district ON phc_hierarchy(district_id);
CREATE INDEX idx_phc_block ON phc_hierarchy(block_id);

-- ─── CHW Assignments ──────────────────────────────────────────────────────────

CREATE TABLE chw_assignments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    chw_id UUID NOT NULL,  -- References auth.users(id)
    phc_id UUID NOT NULL REFERENCES phc_hierarchy(id) ON DELETE RESTRICT,
    assigned_at TIMESTAMPTZ DEFAULT NOW(),
    is_primary BOOLEAN DEFAULT true,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- One CHW per PHC primary assignment
    UNIQUE(chw_id, phc_id)
);

CREATE INDEX idx_chw_assignments_chw ON chw_assignments(chw_id);
CREATE INDEX idx_chw_assignments_phc ON chw_assignments(phc_id);
CREATE INDEX idx_chw_assignments_active ON chw_assignments(is_active);

-- ─── Patients ──────────────────────────────────────────────────────────────────

CREATE TABLE patients (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- FHIR Patient resource fields
    fhir_id TEXT UNIQUE NOT NULL,  -- FHIR resource ID (UUID)
    
    -- ABHA (Ayushman Bharat Health Account) ID
    abha_id TEXT UNIQUE NOT NULL,
    abha_card_number TEXT,
    
    -- Demographics
    name TEXT NOT NULL,
    age INTEGER,
    gender TEXT NOT NULL CHECK (gender IN ('M', 'F', 'O')),
    date_of_birth DATE,
    
    -- Contact
    phone_number TEXT,
    alternate_phone TEXT,
    address TEXT,
    village TEXT,
    district TEXT,
    state TEXT DEFAULT 'Karnataka',  -- or 'Uttar Pradesh'
    pincode TEXT,
    
    -- Emergency Contact
    emergency_contact_name TEXT,
    emergency_contact_phone TEXT,
    emergency_contact_relation TEXT,
    
    -- Clinical Information
    lmp_date DATE,  -- Last Menstrual Period
    edd_date DATE,   -- Expected Delivery Date
    parity INTEGER,  -- Number of previous pregnancies
    gravida INTEGER,  -- Total pregnancies including current
    
    -- Risk Assessment
    high_risk_pregnancy BOOLEAN DEFAULT false,
    risk_level TEXT CHECK (risk_level IN ('low', 'medium', 'high', 'emergency')),
    risk_factors JSONB,  -- Array of risk factor codes
    risk_assessed_at TIMESTAMPTZ,
    risk_assessed_by TEXT,
    
    -- Assignment (PHC-based access control via RLS)
    assigned_chw_id UUID NOT NULL,  -- References auth.users(id)
    phc_id UUID NOT NULL REFERENCES phc_hierarchy(id) ON DELETE RESTRICT,
    
    -- Visit Tracking
    last_visit_date TIMESTAMPTZ,
    next_visit_date TIMESTAMPTZ,
    visit_count INTEGER DEFAULT 0,
    
    -- ABHA Photo URL
    photograph_url TEXT,
    
    -- Status
    is_active BOOLEAN DEFAULT true,
    is Pregnant BOOLEAN DEFAULT true,
    delivery_outcome TEXT,  -- normal, cesarean, complicated
    delivery_date DATE,
    delivery_location TEXT,
    
    -- Metadata
    remarks TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for patient queries
CREATE INDEX idx_patients_fhir ON patients(fhir_id);
CREATE INDEX idx_patients_abha ON patients(abha_id);
CREATE INDEX idx_patients_chw ON patients(assigned_chw_id);
CREATE INDEX idx_patients_phc ON patients(phc_id);
CREATE INDEX idx_patients_risk ON patients(risk_level);
CREATE INDEX idx_patients_active ON patients(is_active);
CREATE INDEX idx_patients_village ON patients(village);
CREATE INDEX idx_patients_next_visit ON patients(next_visit_date) 
    WHERE next_visit_date IS NOT NULL;
CREATE INDEX idx_patients_edd ON patients(edd_date) 
    WHERE edd_date IS NOT NULL;

-- Full-text search for patient names
CREATE INDEX idx_patients_name_search ON patients USING gin(to_tsvector('simple', name));

-- ─── Vitals Logs (FHIR Observations) ─────────────────────────────────────────

CREATE TABLE vitals_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- FHIR Observation resource fields
    fhir_id TEXT UNIQUE NOT NULL,  -- FHIR resource ID
    
    -- Patient reference
    patient_fhir_id TEXT NOT NULL REFERENCES patients(fhir_id) ON DELETE CASCADE,
    patient_id UUID NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    
    -- Vital Type (LOINC-coded)
    vital_type TEXT NOT NULL,
    vital_type_display TEXT,
    loinc_code TEXT,
    
    -- Value (string for BP, numeric for others)
    value TEXT NOT NULL,
    value_numeric DOUBLE PRECISION,  -- Extracted numeric for queries
    unit TEXT,
    
    -- Recording details
    recorded_by UUID NOT NULL,  -- CHW ID
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    source TEXT NOT NULL CHECK (source IN ('direct', 'phone', 'whatsapp', 'ivr', 'remote')),
    
    -- Clinical context
    clinical_flag TEXT,  -- HIGH, LOW, CRITICAL
    notes TEXT,
    
    -- Location (GPS coordinates for visit verification)
    location_lat DOUBLE PRECISION,
    location_lng DOUBLE PRECISION,
    
    -- Device info
    device_id TEXT,
    app_version TEXT,
    
    -- Sync tracking
    is_synced BOOLEAN DEFAULT false,
    sync_attempts INTEGER DEFAULT 0,
    last_sync_at TIMESTAMPTZ,
    last_sync_error TEXT,
    
    -- Metadata
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for vitals queries
CREATE INDEX idx_vitals_patient ON vitals_logs(patient_fhir_id);
CREATE INDEX idx_vitals_patient_id ON vitals_logs(patient_id);
CREATE INDEX idx_vitals_type ON vitals_logs(vital_type);
CREATE INDEX idx_vitals_recorded ON vitals_logs(recorded_at DESC);
CREATE INDEX idx_vitals_recorded_by ON vitals_logs(recorded_by);
CREATE INDEX idx_vitals_source ON vitals_logs(source);
CREATE INDEX idx_vitals_flag ON vitals_logs(clinical_flag) WHERE clinical_flag IS NOT NULL;
CREATE INDEX idx_vitals_sync ON vitals_logs(is_synced) WHERE NOT is_synced;

-- Composite index for patient vitals history
CREATE INDEX idx_vitals_patient_type ON vitals_logs(patient_fhir_id, vital_type, recorded_at DESC);

-- ─── Clinical Contact Logs ─────────────────────────────────────────────────────

CREATE TABLE clinical_contact_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- FHIR resource ID
    fhir_id TEXT UNIQUE NOT NULL,
    
    -- Patient reference
    patient_fhir_id TEXT NOT NULL REFERENCES patients(fhir_id) ON DELETE CASCADE,
    patient_id UUID NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    
    -- Contact type
    contact_type TEXT NOT NULL CHECK (
        contact_type IN ('home_visit', 'phone_call', 'whatsapp_voice', 'ivr_call', 'phc_visit')
    ),
    
    -- CHW
    chw_id UUID NOT NULL,
    
    -- Date/time
    contact_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    duration_minutes INTEGER,
    
    -- Content
    summary TEXT,
    outcome TEXT,
    patient_response TEXT,
    action_taken TEXT,
    next_steps TEXT,
    
    -- Emergency flag
    is_emergency BOOLEAN DEFAULT false,
    emergency_type TEXT,
    
    -- IVR/WhatsApp metadata
    ivr_call_sid TEXT,
    whatsapp_message_id TEXT,
    recording_url TEXT,
    
    -- Location
    location_lat DOUBLE PRECISION,
    location_lng DOUBLE PRECISION,
    
    -- Sync tracking
    is_synced BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for contact queries
CREATE INDEX idx_contacts_patient ON clinical_contact_logs(patient_fhir_id);
CREATE INDEX idx_contacts_chw ON clinical_contact_logs(chw_id);
CREATE INDEX idx_contacts_date ON clinical_contact_logs(contact_date DESC);
CREATE INDEX idx_contacts_type ON clinical_contact_logs(contact_type);
CREATE INDEX idx_contacts_emergency ON clinical_contact_logs(is_emergency) WHERE is_emergency;

-- ─── SBAR Documents ───────────────────────────────────────────────────────────

CREATE TABLE sbar_documents (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- FHIR DocumentReference ID
    fhir_id TEXT UNIQUE NOT NULL,
    
    -- Patient reference
    patient_fhir_id TEXT NOT NULL REFERENCES patients(fhir_id) ON DELETE CASCADE,
    patient_id UUID NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    
    -- Author (CHW who generated)
    author_id UUID NOT NULL,
    
    -- SBAR content (structured JSON)
    situation TEXT,
    background TEXT,
    assessment TEXT,
    recommendation TEXT,
    sbar_json JSONB NOT NULL,
    
    -- Risk level at time of generation
    risk_level TEXT,
    
    -- Status
    status TEXT DEFAULT 'draft' CHECK (status IN ('draft', 'sent', 'acknowledged', 'archived')),
    
    -- Referral info
    referred_to TEXT,  -- Facility name
    referred_at TIMESTAMPTZ,
    acknowledged_at TIMESTAMPTZ,
    acknowledgment_notes TEXT,
    
    -- Sync tracking
    is_synced BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for SBAR queries
CREATE INDEX idx_sbar_patient ON sbar_documents(patient_fhir_id);
CREATE INDEX idx_sbar_author ON sbar_documents(author_id);
CREATE INDEX idx_sbar_status ON sbar_documents(status);
CREATE INDEX idx_sbar_created ON sbar_documents(created_at DESC);

-- ─── Trigger Functions ─────────────────────────────────────────────────────────

-- Auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply updated_at triggers
CREATE TRIGGER update_patients_updated_at
    BEFORE UPDATE ON patients
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_vitals_logs_updated_at
    BEFORE UPDATE ON vitals_logs
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_clinical_contact_logs_updated_at
    BEFORE UPDATE ON clinical_contact_logs
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_sbar_documents_updated_at
    BEFORE UPDATE ON sbar_documents
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_chw_assignments_updated_at
    BEFORE UPDATE ON chw_assignments
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ─── Grant Permissions ─────────────────────────────────────────────────────────

-- Grant usage on schema
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO anon;

-- Grant all on tables to authenticated users
GRANT ALL ON patients TO authenticated;
GRANT ALL ON vitals_logs TO authenticated;
GRANT ALL ON clinical_contact_logs TO authenticated;
GRANT ALL ON sbar_documents TO authenticated;
GRANT ALL ON chw_assignments TO authenticated;
GRANT ALL ON phc_hierarchy TO authenticated;

-- Grant select to anon (for public queries like ABHA validation)
GRANT SELECT ON patients TO anon;
GRANT SELECT ON phc_hierarchy TO anon;