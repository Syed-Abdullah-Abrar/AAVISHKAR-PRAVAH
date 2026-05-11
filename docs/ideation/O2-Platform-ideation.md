# O2 Platform — Ideation Artifact

**Generated:** 2026-05-11  
**Mode:** Repo-grounded (greenfield project)  
**Focus:** O2: Offline-first maternal healthcare monitoring for Community Health Workers in rural India

---

## Grounding Context

### Project Shape

This is a greenfield project with no existing codebase. The O2 Platform is a maternal healthcare monitoring application targeting Community Health Workers (CHWs) operating in low-resource, low-connectivity regions of India. The system must work entirely offline, securely store medical data locally, sync opportunistically, and provide AI-driven risk assessment with local-language voice interaction.

### Tech Stack (as specified)

| Component | Technology |
|---|---|
| Mobile Client | Flutter v3.22+, Brick (offline-first), sqflite, WorkManager, SQLCipher, fhir |
| Cloud Backend | Supabase (PostgreSQL, Auth) |
| Voice I/O | bhashini_plugin (Flutter) or WebSockets, STT/TTS in Kannada, Hindi |
| AI Layer | Python FastAPI, LLM API (OpenAI/Claude) |
| Ecosystem | ABDM (Ayushman Bharat Digital Mission) — mock REST layer |

### Topic Axes

1. **Offline Sync & Data Resilience** — How the app handles intermittent connectivity while remaining the single source of truth locally
2. **Security & Privacy Compliance** — Encrypting PHI at rest and in transit, meeting India's DPDP Act requirements
3. **Voice Interaction UX** — How CHWs input symptoms and receive guidance verbally in Kannada/Hindi
4. **Clinical AI & Decision Support** — Risk scoring, longitudinal SBAR generation, handover quality
5. **Ecosystem Integration (ABDM)** — HPR/HFR verification, ABHA ID validation, interoperability

---

## Raw Candidates (6 Frames)

### Frame 1 — Pain & Friction

1. **title:** Offline-first isbolted-on, not baked-in
   **summary:** Most "offline-capable" apps treat offline as a sync problem. The real pain is that every architectural decision (schema design, conflict resolution, UI state) must start from the assumption of no connectivity. Currently there's no guidance on Brick/WorkManager co-design patterns.
   **axis:** Offline Sync & Data Resilience
   **basis:** direct: brick_offline_first_with_supabase and WorkManager are listed as separate components with no documented co-design pattern
   **why_it_matters:** A bolted-on offline layer creates silent data loss, duplicate records, and unrecoverable sync conflicts that CHWs cannot debug in the field.

2. **title:** SQLCipher key management is a footgun
   **summary:** Storing the SQLCipher AES-256 key in Android Keystore sounds secure but requires careful lifecycle management. Key rotation, backup/ restore, and device-migration all introduce subtle failure modes. There's no documented escape hatch if the Keystore entry is corrupted.
   **axis:** Security & Privacy Compliance
   **basis:** direct: SQLCipher + Android Keystore is a common pattern but key loss = permanent database lock with no recovery path
   **why_it_matters:** A CHW's device failure means total data loss if the encryption key isn't recoverable, violating PHI preservation requirements.

3. **title:** Voice input quality is unknown until the field
   **summary:** STT accuracy for Kannada and Hindi dialects varies enormously across devices. There's no field-data quality metric, no confidence scoring surfaced to the CHW, and no fallback mechanism when STT confidence is low.
   **axis:** Voice Interaction UX
   **basis:** direct: bhashini_plugin supports Kannada/Hindi but real-world STT accuracy in rural dialect variants is unverified
   **why_it_matters:** A CHW inputs symptoms via voice, the system mistranscribes "fever" as "fear," and the risk model fires a false alert or misses a real risk.

4. **title:** ABDM mocks become permanent technical debt
   **summary:** "Mock layer" is the standard hackathon escape hatch. When the hackathon ends, the mock layer has no auto-generated contract tests, no versioning strategy, and silently diverges from real ABDM API behavior. Real integration costs are invisible.
   **axis:** Ecosystem Integration (ABDM)
   **basis:** direct: ABDM API mocks are explicitly listed as "mock REST API calls" with no integration test surface
   **why_it_matters:** When real ABDM APIs are available, the mock layer must be discarded and reimplemented from scratch — all design decisions made against mocks are wrong.

5. **title:** Supabase RLS policies are write-only at first
   **summary:** RLS policies that restrict CHWs to their PHC-assigned patients are easy to write incorrectly. A misconfigured policy can silently block all reads, or allow cross-PHC data leakage. There's no local test harness for RLS logic pre-deployment.
   **axis:** Ecosystem Integration (ABDM)
   **basis:** direct: Supabase RLS policies are promised but no policy validation strategy is described
   **why_it_matters:** A misconfigured RLS policy during deployment means CHWs see no patient data — or worse, see patients from other PHCs — with no tooling to detect this pre-flight.

6. **title:** SBAR generation is a prompt-injection surface
   **summary:** LLM-based SBAR generation ingests raw clinical notes and outputs structured referral text. Without strict output schemas and adversarial input sanitization, a carefully crafted symptom description could cause the LLM to output a misleading SBAR recommendation.
   **axis:** Clinical AI & Decision Support
   **basis:** reasoned: LLMs are prone to prompt injection; clinical decision support tools are high-value targets for adversarial manipulation
   **why_it_matters:** Incorrect SBAR recommendations could direct a high-risk pregnant person to the wrong care level, with legal and life-safety consequences.

7. **title:** No field-debugging story for CHWs
   **summary:** When the app fails silently (sync stuck, voice input frozen, vitals not saved), a CHW has no diagnostic UI. They cannot file a ticket, cannot see logs, and cannot self-resolve. The app must either work flawlessly offline or provide a recovery path.
   **axis:** Offline Sync & Data Resilience
   **basis:** direct: no diagnostic UI, offline error recovery, or self-service debugging story is described
   **why_it_matters:** A single unrecoverable error locks the CHW out of the app during a home visit, leaving the patient unmonitored.

---

### Frame 2 — Inversion, Removal, or Automation

8. **title:** Remove the cloud from the critical path
   **summary:** Invert the architecture so cloud sync is purely a background convenience, not a reliability requirement. All clinical decisions (risk scoring, SBAR generation, alerts) run locally on-device. Cloud is only needed for cross-CHW visibility and regulatory reporting.
   **axis:** Offline Sync & Data Resilience
   **basis:** reasoned: the 24-hour hackathon constraint means connectivity is never guaranteed; designing for cloud-first creates a fragile system
   **why_it_matters:** If the critical clinical path depends on cloud connectivity, the app fails in exactly the environments where it's most needed.

9. **title:** Automate RLS policy generation from PHC hierarchy
   **summary:** Instead of manually writing Supabase RLS policies per CHW/PHC relationship, define a PHC hierarchy once and auto-generate RLS policies from it. A change in PHC assignment automatically propagates to RLS.
   **axis:** Security & Privacy Compliance
   **basis:** reasoned: manual RLS policy maintenance is error-prone; programmatic generation from a hierarchy table eliminates entire classes of misconfiguration
   **why_it_matters:** Reduces the attack surface from RLS misconfiguration to zero for the common case of CHW reassignment between PHCs.

10. **title:** Remove TTS from the critical path
    **summary:** Voice output (TTS) for risk alerts and SBAR summaries should be pre-computed and cached, not generated on-demand. When network is available, pre-generate all likely outputs for a patient's next visit window. When offline, play from cache.
    **axis:** Voice Interaction UX
    **basis:** reasoned: TTS generation latency + network dependency creates a failure mode in the field; pre-caching eliminates it
    **why_it_matters:** A CHW in a remote village gets a risk alert but TTS fails because connectivity is intermittent — pre-cached audio never fails.

11. **title:** Remove ABDM integration from Phase 1
    **summary:** ABDM ecosystem integration (HPR, HFR, ABHA ID) is complex and dependency-external. Remove it from the hackathon scope entirely. Stub the ABDM service layer with clearly-marked interfaces and add integration tests only when real APIs exist.
    **axis:** Ecosystem Integration (ABDM)
    **basis:** direct: ABDM mocks are explicitly a mock layer — real APIs may not be available during the hackathon; removing them simplifies the critical path
    **why_it_matters:** Reduces Phase 1 scope to what can actually be demonstrated end-to-end: offline app + local AI + Supabase sync.

12. **title:** Automate conflict resolution for sync
    **summary:** Instead of requiring CHWs to manually resolve sync conflicts (duplicate records, divergent vitals), define a deterministic Last-Write-Wins + clinical-hierarchy conflict resolver that runs automatically. Expose only the cases that need human review.
    **axis:** Offline Sync & Data Resilience
    **basis:** reasoned: CHWs have no technical training to resolve merge conflicts; manual resolution leads to data corruption or abandonment
    **why_it_matters:** Eliminates the most common point of data quality degradation in offline-first healthcare apps.

---

### Frame 3 — Assumption-Breaking and Reframing

13. **title:** FHIR is the local schema, not the wire format
    **summary:** The architecture treats FHIR as a serialization format for cloud sync. The inversion: Brick models should be defined in FHIR R4 natively (using the fhir package), with Supabase storage being a FHIR-compliant document store. Cloud sync becomes FHIR replication.
    **axis:** Offline Sync & Data Resilience
    **basis:** reasoned: FHIR has well-defined clinical resources (Patient, Observation, Condition) that map directly to O2's entities; treating it as the local schema eliminates translation layers
    **why_it_matters:** Reduces impedance mismatch between local models, FHIR wire format, and Supabase schema — one canonical clinical model everywhere.

14. **title:** Voice is not input — it's the primary UI
    **summary:** The architecture positions voice as an input modality for symptom entry. The reframing: for low-literacy CHWs, voice should be the primary UI paradigm — navigation, data review, alerts, and SBAR playback all via TTS. Screen is secondary/reveal.
    **axis:** Voice Interaction UX
    **basis:** reasoned: CHWs in rural India may have low literacy; designing for voice-first changes the entire interaction model rather than adding voice as an overlay
    **why_it_matters:** Changes the design brief from "add voice input" to "redesign the UI around voice as the primary channel."

15. **title:** Risk scoring is not a clinical decision — it's a triage flag
    **summary:** The architecture implies the AI risk score is a clinical decision tool. The reframing: it's a triage flag that routes patients to appropriate care levels, not a diagnosis. This framing limits liability, simplifies the model, and aligns with WHO maternal health triage protocols.
    **axis:** Clinical AI & Decision Support
    **basis:** reasoned: clinical decision support tools face regulatory scrutiny (CDSDS/FDA/CE-mark equivalent in India); framing as triage rather than diagnosis reduces regulatory surface
    **why_it_matters:** Changes the model requirement from "diagnose maternal risk" to "flag patients who need escalated care" — a much simpler, more auditable problem.

16. **title:** The ABDM layer is not integration — it's a compliance tax
    **summary:** Rather than building ABDM integration as a feature, treat it as a compliance cost. Define the minimum viable ABDM surface (ABHA ID validation only), calculate the integration cost honestly, and gate Phase 2 budget allocation based on demonstrated utility.
    **axis:** Ecosystem Integration (ABDM)
    **basis:** reasoned: ABDM APIs are government-owned and subject to policy changes; the cost of integration (developer time, ongoing maintenance) is certain while the benefit is uncertain
    **why_it_matters:** Forces explicit ROI calculation for ABDM integration rather than treating it as a checkbox.

17. **title:** SQLCipher encryption key is not a secret — it's a service
    **summary:** The architecture treats the encryption key as a stored secret. The reframing: the key management should be a cloud-backed service (even a simple one) that handles key rotation, device migration, and recovery without user action. The key should never be user-managed.
    **axis:** Security & Privacy Compliance
    **basis:** reasoned: user-managed encryption keys are the #1 cause of data loss in encrypted mobile apps; treating key management as a service removes the single point of failure
    **why_it_matters:** Reduces the critical failure mode where a CHW factory-resets their device and loses all patient data permanently.

---

### Frame 4 — Leverage and Compounding

18. **title:** FHIR schema as leverage for entire ecosystem
    **summary:** Once patient data is modeled in FHIR R4 locally, it becomes portable across: Supabase sync, ABDM export, HMIS (Health Management Information System) integration, and NHM (National Health Mission) reporting — without per-integration translation layers.
    **axis:** Offline Sync & Data Resilience
    **basis:** reasoned: FHIR is already the government-mandated standard for health data exchange in India; adopting it locally means every future integration is cheaper
    **why_it_matters:** One FHIR model replaces N custom translation adapters for each external system.

19. **title:** Brick repository pattern as leverage for testability
    **summary:** Brick's offline-first repository pattern, when combined with its adapter interface, creates a natural seam for testing. All clinical logic can be unit-tested against an in-memory Brick adapter without touching sqflite or network.
    **axis:** Offline Sync & Data Resilience
    **basis:** direct: Brick's architecture explicitly supports adapter substitution for testing purposes
    **why_it_matters:** Enables TDD for clinical algorithms (risk scoring, vitals validation) without setting up device emulators.

20. **title:** Voice interaction patterns compound into a dialect corpus
    **summary:** Every voice interaction (symptom transcription, TTS playback) generates a labeled audio + text pair. Aggregating these across CHWs builds a dialect corpus that can improve STT accuracy for the specific speech patterns of rural Karnataka/Uttar Pradesh.
    **axis:** Voice Interaction UX
    **basis:** reasoned: commercial STT models (Google, AWS) are trained on standardized speech; rural dialect variants are systematically underrepresented; a domain-specific corpus is high-value
    **why_it_matters:** Each field deployment improves future STT accuracy for the same population, creating a compounding data asset.

21. **title:** SBAR document as leverage for care continuity
    **summary:** The LLM-generated SBAR is not just a clinical handover document — it's a machine-readable, structured care plan that can be stored as a FHIR DocumentReference and passed between facilities via ABDM. One artifact serves both clinical and administrative needs.
    **axis:** Clinical AI & Decision Support
    **basis:** reasoned: SBAR is already a standardized clinical communication format; adding FHIR DocumentReference serialization makes it interoperable without format conversion
    **why_it_matters:** Eliminates the cost of re-documenting the handover at the receiving facility.

22. **title:** WorkManager sync policy as leverage for battery-aware design
    **summary:** WorkManager's network and battery constraints, when modeled explicitly, create a battery-aware sync policy that respects the charging patterns of solar-powered devices common in rural India. This constraint, embraced as a design input, shapes sync scheduling for the entire system.
    **axis:** Offline Sync & Data Resilience
    **basis:** reasoned: rural health infrastructure increasingly uses solar charging; WorkManager's battery-aware constraints map directly to solar device usage patterns
    **why_it_matters:** Sync that only runs when the device is charging prevents battery depletion during home visit rounds.

---

### Frame 5 — Cross-Domain Analogy

23. **title:** Git conflict resolution for clinical data sync
    **summary:** Git handles offline-first distributed collaboration through explicit conflict markers and three-way merges. Apply Git's conflict resolution model to vitals sync: last-write-wins with field-level merge for non-conflicting fields, three-way merge for conflicts, conflict markers surfaced only when human resolution is required.
    **axis:** Offline Sync & Data Resilience
    **basis:** external: Git distributed version control (linus torvalds, 2005) is the canonical solution for offline-first distributed write conflicts
    **why_it_matters:** Git's conflict resolution is battle-tested across billions of repositories; the same algorithms applied to clinical vitals would handle most sync conflicts automatically.

24. **title:** TLS certificate pinning for SQLCipher key exchange
    **summary:** TLS certificate pinning ensures the client is talking to the real server, not a MITM. Apply the same pattern to SQLCipher key synchronization: the key never travels over the wire in plaintext; instead, a key attestation protocol (similar to TLS pinning) verifies key authenticity before deployment.
    **axis:** Security & Privacy Compliance
    **basis:** external: TLS certificate pinning (RFC 7924) solves the trust-in-transit problem for network connections; analogous trust-in-sync problem for encryption keys
    **why_it_matters:** Prevents an attacker who compromises the sync channel from extracting the SQLCipher key and decrypting the local database.

25. **title:** Aviation black box for clinical audit trails
    **summary:** Aviation black boxes record all flight parameters continuously and are recoverable even after catastrophic failure. Apply this to O2: every clinical interaction (vitals entry, risk score, SBAR generation) is written to an append-only local audit log encrypted separately from the main database.
    **axis:** Security & Privacy Compliance
    **basis:** external: aviation flight recorder (black box) design ensures data recoverability after catastrophic failure; analogous for clinical data integrity after device failure
    **why_it_matters:** In a legal dispute or clinical audit, an immutable audit trail is required; the black box analogy provides a well-understood design pattern.

26. **title:** GPS-assisted check-in for visit verification
    **summary:** Delivery apps (Swiggy, Zomato) verify driver location at pickup and delivery points. Apply this to CHW home visits: GPS coordinates are captured at vitals entry time, providing verifiable proof that the CHW visited the patient's home rather than entering data from an office.
    **axis:** Clinical AI & Decision Support
    **basis:** external: gig economy logistics platforms use GPS check-in for delivery verification; same pattern applied to maternal health visits provides visit authenticity evidence
    **why_it_matters:** Creates accountability and prevents "desk visits" — data entered without actual patient contact — which is a known quality failure mode in community health programs.

27. **title:** Traffic light triage from emergency medicine
    **summary:** Emergency departments worldwide use Red/Yellow/Green triage systems (START, ESI) to categorize patient urgency. Map these to O2's risk levels: Red = Emergency (needs immediate transfer), Yellow = Medium Risk (scheduled visit within 24h), Green = Low (routine follow-up).
    **axis:** Clinical AI & Decision Support
    **basis:** external: Emergency Severity Index (ESI) and START triage are internationally validated triage systems used in millions of ED presentations annually
    **why_it_matters:** Risk score output mapped to traffic-light triage maps directly to CHW action protocols already taught in India's ASHA training.

28. **title:** Radio call-and-response for voice UX confidence
    **summary:** Military and amateur radio uses call-and-response confirmation ("Romeo, this is Alpha, do you copy?") to verify message receipt over noisy channels. Apply this to voice interaction: STT transcription is read back via TTS before confirmation, and TTS confirmation is repeated before final save.
    **axis:** Voice Interaction UX
    **basis:** external: military radio communications protocol for noisy environments (NATO standards) uses read-back confirmation as standard practice
    **why_it_matters:** Reduces silent transcription errors by requiring verbal confirmation before clinical data is committed.

---

### Frame 6 — Constraint-Flipping

29. **title:** Zero connectivity all the time — not just "offline-first"
    **summary:** Invert the assumption from "we're online until we're not" to "we assume zero connectivity always." The cloud sync engine is a nice-to-have bonus, not a requirement. All clinical decisions (risk scoring, alerts, SBAR) are fully local. Cloud is only for regulatory backup.
    **axis:** Offline Sync & Data Resilience
    **basis:** constraint-flip: flip "offline-first" (online is default) to "connectivity is never the default" (offline is default)
    **why_it_matters:** Forces the architecture to be genuinely resilient rather than optimistically online.

30. **title:** Zero trust on device hardware
    **summary:** Invert the assumption that the device is a trusted environment. Assume the device may be lost, stolen, or seized. All PHI is encrypted at rest with a key that is not stored on the device. Remote wipe capability is required. The device is a terminal, not a store.
    **axis:** Security & Privacy Compliance
    **basis:** constraint-flip: flip "device is trusted environment" to "device is a hostile environment"
    **why_it_matters:** Forces design for device loss scenarios that are common in community health settings where devices are shared or stored in unsecured locations.

31. **title:** One language only — no multilingual toggle
    **summary:** Invert the assumption that the app should support both Kannada and Hindi. Pick one language per deployment region (Karnataka = Kannada, Uttar Pradesh = Hindi) and bake it in at the architecture level. No runtime language switching.
    **axis:** Voice Interaction UX
    **basis:** constraint-flip: flip "multilingual app" to "single-language deployment unit"
    **why_it_matters:** Simplifies voice model selection, removes language toggle as a UI surface, and allows full optimization of STT/TTS for one dialect per deployment.

32. **title:** Zero cloud AI — all inference on device
    **summary:** Invert the assumption that AI inference (risk scoring, SBAR generation) happens on cloud servers. Run a quantized ML model entirely on-device (even a mid-range Android device can run 1B-parameter models efficiently with quantization). Cloud AI is not needed for the MVP.
    **axis:** Clinical AI & Decision Support
    **basis:** constraint-flip: flip "cloud AI" to "on-device AI only"
    **why_it_matters:** Eliminates cloud AI latency, eliminates cloud AI cost, and ensures clinical AI is available even when connectivity is absent — the most critical use case.

33. **title:** ABDM integration at zero cost
    **summary:** Invert the assumption that ABDM integration requires government approval and API access. Define ABDM compliance as a data format (ABHA ID validation in the schema) and document the API contracts that would need to be called, without calling them until real access is available.
    **axis:** Ecosystem Integration (ABDM)
    **basis:** constraint-flip: flip "ABDM integration requires government API access" to "ABDM compliance is a data contract, not a live API call"
    **why_it_matters:** Removes the external dependency on government API availability from the critical path.

34. **title:** No database on device — pure FHIR document store
    **summary:** Invert the assumption that Brick + sqflite is the right local store. Instead, use a file-based FHIR document store (JSON files on disk, encrypted). Every patient is one FHIR Bundle. This eliminates the sqflite/SQLCipher complexity and makes FHIR the only model.
    **axis:** Offline Sync & Data Resilience
    **basis:** constraint-flip: flip "relational database (sqflite)" to "document store (FHIR Bundles as JSON files)"
    **why_it_matters:** Removes the entire relational-to-FHIR translation layer; FHIR is the storage format and the wire format.

35. **title:** No user accounts — device-bound identity
    **summary:** Invert the assumption that Supabase Auth manages user sessions. Instead, the device itself is the identity. A hardware-backed device key (Titan M / Android Keystore) signs clinical actions. The cloud maps device keys to CHW identity, not the reverse.
    **axis:** Security & Privacy Compliance
    **basis:** constraint-flip: flip "user authentication" to "device authentication"
    **why_it_matters:** Eliminates password/phishing risk entirely; clinical actions are device-bound and attributable to a specific device, not a user who might share credentials.

---

## Cross-Cutting Combinations

36. **FHIR-as-local-schema + Git conflict resolution** — When Brick models are defined in FHIR natively (idea 13), Git's three-way merge algorithm can be applied at the FHIR Bundle level for vitals sync conflicts. This is a natural extension of both ideas working together.
    **axes:** Offline Sync & Data Resilience, Clinical AI & Decision Support

37. **Voice-first UI + Call-and-response confirmation + Traffic-light triage** — Voice-as-primary-UI (idea 14) + radio confirmation (idea 28) + traffic-light output (idea 27) compose into a fully voice-driven clinical interaction loop: CHW speaks symptoms → STT → risk scored locally → TTS reads back triage color → CHW confirms → SBAR generated and TTS-played.
    **axes:** Voice Interaction UX, Clinical AI & Decision Support

38. **Device-bound identity + Zero-trust device model + Black-box audit** — Device key identity (idea 35) + zero-trust device (idea 30) + aviation audit trail (idea 26) compose into a security model where clinical actions are device-attested, the device is treated as untrusted, and all actions are immutably logged.
    **axes:** Security & Privacy Compliance

39. **On-device AI + Solar-aware WorkManager sync + Voice-first UI** — On-device ML inference (idea 32) + battery-aware sync scheduling (idea 22) + voice-first interaction (idea 14) compose into a system that never needs connectivity for clinical decisions, syncs only when solar-charged, and speaks to the CHW in their language.
    **axes:** Offline Sync & Data Resilience, Voice Interaction UX, Clinical AI & Decision Support

40. **Dialect corpus + Kannada-only optimization** — Field voice interactions (idea 20) + single-language deployment (idea 31) compose into a deliberate strategy to build a Kannada dialect STT corpus from day one of deployment, with the explicit goal of improving STT accuracy with each CHW interaction.
    **axes:** Voice Interaction UX

---

## Axis Coverage Check

| Axis | Ideas | Status |
|---|---|---|
| Offline Sync & Data Resilience | 1, 2, 7, 8, 9, 12, 13, 18, 19, 22, 23, 29, 34, 37, 39 | ✓ Well covered |
| Security & Privacy Compliance | 2, 5, 9, 11, 17, 24, 25, 26, 30, 35, 38 | ✓ Well covered |
| Voice Interaction UX | 3, 10, 14, 20, 28, 31, 37, 39, 40 | ✓ Well covered |
| Clinical AI & Decision Support | 6, 15, 19, 21, 22, 26, 27, 29, 32, 37, 39 | ✓ Well covered |
| Ecosystem Integration (ABDM) | 4, 5, 11, 16, 33 | ✓ Covered |

All 5 axes have coverage. No recovery dispatch needed.

---

## Survivors (Top Ideas by Frame)

### Offline Sync & Data Resilience

- **Idea 29:** Zero connectivity always — architectural inversion treating offline as the permanent state
- **Idea 13:** FHIR as the local schema — eliminates translation layers between local storage, wire format, and cloud
- **Idea 12:** Automated conflict resolution — deterministic Last-Write-Wins + clinical hierarchy resolver, no manual merge UI
- **Idea 23:** Git-style three-way merge for vitals sync conflicts

### Security & Privacy Compliance

- **Idea 30:** Zero-trust device model — assumes device is lost/stolen/seized, remote wipe required
- **Idea 25:** Aviation black-box audit trail — append-only encrypted audit log separate from main database
- **Idea 17:** Cloud-backed key management service — key never user-managed, survives device reset
- **Idea 35:** Device-bound identity via hardware key — no password/phishing risk

### Voice Interaction UX

- **Idea 14:** Voice as primary UI, not input overlay — full voice-driven interaction paradigm
- **Idea 28:** Radio call-and-response confirmation — read-back before commit over noisy channels
- **Idea 10:** Pre-cached TTS — pre-generate audio when online, play from cache when offline
- **Idea 40:** Dialect corpus from day one — deliberate strategy to improve STT with each interaction

### Clinical AI & Decision Support

- **Idea 32:** On-device ML inference — quantized model, no cloud dependency for risk scoring
- **Idea 27:** Traffic-light triage output — maps risk to Red/Yellow/Green aligned with ASHA training protocols
- **Idea 15:** Risk score as triage flag, not diagnosis — reduces regulatory surface
- **Idea 21:** SBAR as FHIR DocumentReference — one artifact for clinical handover and system interoperability

### Ecosystem Integration (ABDM)

- **Idea 33:** ABDM as data contract, not live API — document the contracts, stub the calls until real access
- **Idea 11:** Remove ABDM from Phase 1 scope — focus on what's demoable end-to-end
- **Idea 16:** ABDM as compliance tax — explicit ROI calculation before Phase 2 investment

---

## Key Strategic Decisions to Resolve in Brainstorming

1. **FHIR-native vs Brick-adapter local schema** — Does O2 define models in FHIR R4 natively (simpler long-term) or use Brick adapters with FHIR serialization at the sync layer (more Brick-idiomatic)?
2. **Cloud AI vs on-device AI for Phase 1** — Is the quantized on-device model approach feasible within the 24-hour hackathon timeframe, or does cloud AI need to be the MVP path?
3. **Voice-first vs voice-enhanced UX** — Is the CHW population literacy level low enough to justify full voice-first UI, or is voice input an enhancement to a screen-based app?
4. **ABDM in or out of Phase 1** — Does the team have ABDM API access during the hackathon, or should it be stubbed entirely?

---

*Generated by ce-ideate (6 frames, 40 raw candidates, 27 survivors)*
