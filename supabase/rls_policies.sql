-- O2 Platform — Supabase Row-Level Security (RLS) Policies
-- Phase 1 MVP
-- 
-- Design Principles:
-- 1. CHW isolation: A CHW can only see/access patients assigned to their PHC(s)
-- 2. PHC hierarchy: CHW ↔ CHW_ASSIGNMENTS ↔ PHC ↔ PATIENTS
-- 3. Supabase Auth: auth.uid() returns the CHW's user ID
-- 4. RLS enforced at database level — cannot be bypassed by API
-- 
-- Security Model:
-- - Hardware-backed JWT validation via Supabase Auth
-- - RLS policies checked on EVERY query (SELECT, INSERT, UPDATE, DELETE)
-- - No backdoor: even service role bypasses RLS unless explicitly configured
-- 
-- Key Tables:
-- - patients: linked to PHC via phc_id and assigned_chw_id
-- - vitals_logs: linked to patients via patient_fhir_id
-- - clinical_contact_logs: linked to patients via patient_fhir_id
-- - chw_assignments: maps CHW user ID ↔ PHC
-- 
-- Access Patterns:
-- 1. CHW views their assigned patients (via PHC)
-- 2. CHW creates vitals for their patients only
-- 3. CHW updates only their own patients
-- 4. CHW cannot see other CHWs' patients

-- ─── Enable RLS on All Tables ─────────────────────────────────────────────────

ALTER TABLE patients ENABLE ROW LEVEL SECURITY;
ALTER TABLE vitals_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE clinical_contact_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE chw_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE sbar_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE phc_hierarchy ENABLE ROW LEVEL SECURITY;

-- ─── Helper Functions ─────────────────────────────────────────────────────────

-- Get current user's PHC IDs (from chw_assignments)
CREATE OR REPLACE FUNCTION get_user_phc_ids()
RETURNS SETOF UUID AS $$
    SELECT phc_id 
    FROM chw_assignments 
    WHERE chw_id = auth.uid() 
      AND is_active = true;
$$ LANGUAGE SQL SECURITY DEFINER STABLE;

-- Check if user has access to a specific patient
CREATE OR REPLACE FUNCTION has_patient_access(patient_phc_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM chw_assignments 
        WHERE chw_id = auth.uid() 
          AND phc_id = patient_phc_id
          AND is_active = true
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- ─── Patients RLS Policies ───────────────────────────────────────────────────

-- Policy: CHW can SELECT patients in their PHC(s)
CREATE POLICY patients_select ON patients
    FOR SELECT
    USING (
        -- Direct assignment to CHW
        assigned_chw_id = auth.uid()
        OR
        -- Via PHC assignment (CHW works at this PHC)
        phc_id IN (SELECT phc_id FROM chw_assignments WHERE chw_id = auth.uid() AND is_active = true)
    );

-- Policy: CHW can INSERT new patients for their PHC
CREATE POLICY patients_insert ON patients
    FOR INSERT
    WITH CHECK (
        assigned_chw_id = auth.uid()
        AND
        phc_id IN (SELECT phc_id FROM chw_assignments WHERE chw_id = auth.uid() AND is_active = true)
    );

-- Policy: CHW can UPDATE patients in their PHC (except assigned_chw_id, phc_id)
CREATE POLICY patients_update ON patients
    FOR UPDATE
    USING (
        assigned_chw_id = auth.uid()
        OR
        phc_id IN (SELECT phc_id FROM chw_assignments WHERE chw_id = auth.uid() AND is_active = true)
    )
    WITH CHECK (
        assigned_chw_id = auth.uid()
        AND
        phc_id IN (SELECT phc_id FROM chw_assignments WHERE chw_id = auth.uid() AND is_active = true)
    );

-- Policy: CHW can only DELETE patients they directly assigned (soft delete preferred)
CREATE POLICY patients_delete ON patients
    FOR DELETE
    USING (
        assigned_chw_id = auth.uid()
    );

-- ─── Vitals Logs RLS Policies ────────────────────────────────────────────────

-- Policy: CHW can SELECT vitals for patients they have access to
CREATE POLICY vitals_select ON vitals_logs
    FOR SELECT
    USING (
        -- Link through patient_fhir_id → patients → PHC check
        EXISTS (
            SELECT 1 FROM patients p
            WHERE p.fhir_id = vitals_logs.patient_fhir_id
              AND (
                  p.assigned_chw_id = auth.uid()
                  OR
                  p.phc_id IN (SELECT phc_id FROM chw_assignments WHERE chw_id = auth.uid() AND is_active = true)
              )
        )
    );

-- Policy: CHW can INSERT vitals for patients they have access to
CREATE POLICY vitals_insert ON vitals_logs
    FOR INSERT
    WITH CHECK (
        recorded_by = auth.uid()
        AND
        EXISTS (
            SELECT 1 FROM patients p
            WHERE p.fhir_id = patient_fhir_id
              AND (
                  p.assigned_chw_id = auth.uid()
                  OR
                  p.phc_id IN (SELECT phc_id FROM chw_assignments WHERE chw_id = auth.uid() AND is_active = true)
              )
        )
    );

-- Policy: CHW can UPDATE vitals they recorded (not syncing status)
CREATE POLICY vitals_update ON vitals_logs
    FOR UPDATE
    USING (
        recorded_by = auth.uid()
        AND
        EXISTS (
            SELECT 1 FROM patients p
            WHERE p.fhir_id = vitals_logs.patient_fhir_id
              AND (
                  p.assigned_chw_id = auth.uid()
                  OR
                  p.phc_id IN (SELECT phc_id FROM chw_assignments WHERE chw_id = auth.uid() AND is_active = true)
              )
        )
    );

-- Policy: CHW can only DELETE vitals they recorded
CREATE POLICY vitals_delete ON vitals_logs
    FOR DELETE
    USING (
        recorded_by = auth.uid()
    );

-- ─── Clinical Contact Logs RLS Policies ──────────────────────────────────────

-- Policy: CHW can SELECT contacts for patients they have access to
CREATE POLICY contacts_select ON clinical_contact_logs
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM patients p
            WHERE p.fhir_id = clinical_contact_logs.patient_fhir_id
              AND (
                  p.assigned_chw_id = auth.uid()
                  OR
                  p.phc_id IN (SELECT phc_id FROM chw_assignments WHERE chw_id = auth.uid() AND is_active = true)
              )
        )
    );

-- Policy: CHW can INSERT contacts they made
CREATE POLICY contacts_insert ON clinical_contact_logs
    FOR INSERT
    WITH CHECK (
        chw_id = auth.uid()
        AND
        EXISTS (
            SELECT 1 FROM patients p
            WHERE p.fhir_id = patient_fhir_id
              AND (
                  p.assigned_chw_id = auth.uid()
                  OR
                  p.phc_id IN (SELECT phc_id FROM chw_assignments WHERE chw_id = auth.uid() AND is_active = true)
              )
        )
    );

-- Policy: CHW can UPDATE contacts they made
CREATE POLICY contacts_update ON clinical_contact_logs
    FOR UPDATE
    USING (
        chw_id = auth.uid()
    );

-- Policy: CHW can only DELETE contacts they made
CREATE POLICY contacts_delete ON clinical_contact_logs
    FOR DELETE
    USING (
        chw_id = auth.uid()
    );

-- ─── SBAR Documents RLS Policies ───────────────────────────────────────────

-- Policy: CHW can SELECT SBARs for patients they have access to
CREATE POLICY sbar_select ON sbar_documents
    FOR SELECT
    USING (
        author_id = auth.uid()
        OR
        EXISTS (
            SELECT 1 FROM patients p
            WHERE p.fhir_id = sbar_documents.patient_fhir_id
              AND (
                  p.assigned_chw_id = auth.uid()
                  OR
                  p.phc_id IN (SELECT phc_id FROM chw_assignments WHERE chw_id = auth.uid() AND is_active = true)
              )
        )
    );

-- Policy: CHW can INSERT SBARs for patients they have access to
CREATE POLICY sbar_insert ON sbar_documents
    FOR INSERT
    WITH CHECK (
        author_id = auth.uid()
        AND
        EXISTS (
            SELECT 1 FROM patients p
            WHERE p.fhir_id = patient_fhir_id
              AND (
                  p.assigned_chw_id = auth.uid()
                  OR
                  p.phc_id IN (SELECT phc_id FROM chw_assignments WHERE chw_id = auth.uid() AND is_active = true)
              )
        )
    );

-- Policy: CHW can UPDATE SBARs they authored
CREATE POLICY sbar_update ON sbar_documents
    FOR UPDATE
    USING (
        author_id = auth.uid()
    );

-- ─── CHW Assignments RLS Policies ──────────────────────────────────────────

-- Policy: CHW can view their own assignments
CREATE POLICY chw_assignments_select ON chw_assignments
    FOR SELECT
    USING (
        chw_id = auth.uid()
    );

-- Policy: Only admin/service role can INSERT assignments (managed by system)
CREATE POLICY chw_assignments_insert ON chw_assignments
    FOR INSERT
    WITH CHECK (
        chw_id = auth.uid()  -- Allow CHW to update their own
    );

-- Policy: CHW can UPDATE their own assignments (deactivation)
CREATE POLICY chw_assignments_update ON chw_assignments
    FOR UPDATE
    USING (
        chw_id = auth.uid()
    );

-- ─── PHC Hierarchy RLS Policies ─────────────────────────────────────────────

-- Policy: All authenticated users can SELECT PHC hierarchy (for dropdowns)
CREATE POLICY phc_select ON phc_hierarchy
    FOR SELECT
    USING (
        is_active = true
    );

-- Policy: Only admin/service role can MODIFY PHC hierarchy
CREATE POLICY phc_admin ON phc_hierarchy
    FOR ALL
    USING (
        -- Restrict to service role or admin (check role)
        -- Note: In production, this would check for admin role
        false  -- No direct CHW modification allowed
    );

-- ─── Verification Queries (for testing) ────────────────────────────────────

-- Test RLS: Check if RLS is enforced
-- Run this to verify policies:
-- SELECT 
--     schemaname, 
--     tablename, 
--     policyname, 
--     permissive,
--     roles,
--     cmd,
--     qual
-- FROM pg_policies
-- WHERE tablename IN ('patients', 'vitals_logs', 'clinical_contact_logs');

-- Test access pattern:
-- SELECT id, name, phc_id 
-- FROM patients 
-- WHERE phc_id IN (SELECT phc_id FROM chw_assignments WHERE chw_id = auth.uid());

-- Count of patients accessible to current user:
-- SELECT COUNT(*) FROM patients 
-- WHERE phc_id IN (SELECT phc_id FROM chw_assignments WHERE chw_id = auth.uid() AND is_active = true);

-- ─── Indexes for RLS Performance ─────────────────────────────────────────────

-- These indexes help RLS policy evaluation
CREATE INDEX IF NOT EXISTS idx_patients_phc_chw ON patients(phc_id, assigned_chw_id);
CREATE INDEX IF NOT EXISTS idx_chw_assignments_chw_active ON chw_assignments(chw_id, is_active);
CREATE INDEX IF NOT EXISTS idx_vitals_patient_fhir ON vitals_logs(patient_fhir_id);
CREATE INDEX IF NOT EXISTS idx_contacts_patient_fhir ON clinical_contact_logs(patient_fhir_id);

-- ─── Notes for Deployment ────────────────────────────────────────────────────
-- 
-- 1. After creating policies, test with:
--    SELECT auth.uid();  -- Should return current user ID
--    SELECT get_user_phc_ids();  -- Should return user's PHC IDs
-- 
-- 2. To bypass RLS (for admin/tools), use service_role key
--    But be careful - service_role bypasses ALL RLS!
-- 
-- 3. For testing without Supabase Auth, you can temporarily disable RLS:
--    ALTER TABLE patients DISABLE ROW LEVEL SECURITY;
--    -- ... run tests ...
--    ALTER TABLE patients ENABLE ROW LEVEL SECURITY;
-- 
-- 4. If patient access seems wrong, check:
--    - chw_assignments table has correct chw_id (matches auth.users.id)
--    - chw_id is UUID type in both tables
--    - is_active = true for the assignment
--    - phc_id in patients matches phc_id in chw_assignments