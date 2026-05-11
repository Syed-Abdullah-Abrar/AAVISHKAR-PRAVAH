# O2 Platform — IVR Communication Layer
## Requirements Document

**Date:** 2026-05-11  
**Tier:** Deep — product (new capability added to O2 Platform)  
**Status:** Draft

---

## 1. Problem Statement

Rural families — particularly pregnant women in low-connectivity regions of India — have no reliable, zero-cost way to reach their assigned Community Health Worker (CHW). They lack smartphones (no O2 app), may be semi-literate (no SMS), and cannot afford airtime. Meanwhile, CHWs lose patient contact between scheduled visits, leading to undetected risk escalation.

The IVR Communication Layer bridges this gap: a pregnant woman gives a missed call to a toll-free number, the system calls her back for free, she speaks her concern, and her CHW receives it as a WhatsApp voice message — with no app installation required on her end.

---

## 2. Target Users

### Primary Actor: Pregnant Woman / Rural Family Member
- Uses a basic feature phone (no smartphone, no internet data)
- May be semi-literate or illiterate
- Cannot afford airtime charges
- Registered in O2 via ABHA number; phone number mapped to her ABHA record

### Secondary Actor: Community Health Worker (CHW / ASHA)
- Has a smartphone with WhatsApp
- Receives patient voice messages as WhatsApp audio
- Uses O2 app for patient record management
- Responds to patient via WhatsApp voice note

### System Actor: IVR Platform (Twilio / Exotel / custom)
- Cloud-hosted voice application
- Receives missed calls, initiates callbacks, plays IVR prompts, records audio
- Forwards audio to WhatsApp via WhatsApp Business API
- Queries patient lookup service for caller ID → CHW mapping

---

## 3. Core User Flows

### Flow 1: Patient Initiates Contact (Missed Call → Callback → Voice Message)

```
PRECONDITIONS:
- Pregnant woman has a feature phone
- Her phone number is registered in O2's patient-CHW mapping table
- She has consented to callback contact

STEPS:
1. Woman gives a missed call to toll-free IVR number
2. IVR platform detects caller ID, disconnects immediately (no airtime to her)
3. IVR platform queries Patient Lookup Service: caller_ID → (patient_ABHA, assigned_CHW)
4. IVR platform initiates a free callback to the woman
5. System plays brief IVR greeting in regional language (Kannada or Hindi): "Namasthey, O2 se baat karne ke liye dhanyavaad. Aapki call record ki ja rahi hai."
6. Woman speaks her symptom, concern, or request (no keypad interaction)
7. IVR platform records audio
8. After recording (max 60 seconds or silence detection), system plays confirmation: "Aapka sanvedana record ho gaya. Aapki CHW ko mail kar diya gaya hai."
9. IVR platform uploads audio to WhatsApp Business API → sends as voice message to CHW's WhatsApp number
10. CHW receives WhatsApp voice message notification

POSTCONDITIONS:
- CHW has received patient's voice message on WhatsApp
- Message is timestamped and linked to patient's ABHA record in O2
- No airtime cost to the woman
```

### Flow 2: CHW Responds via WhatsApp Voice Note

```
PRECONDITIONS:
- CHW has received WhatsApp voice message from patient
- CHW has patient record open in O2 app (or opens it)

STEPS:
1. CHW taps play on the voice message, listens to patient's concern
2. CHW opens patient record in O2 app
3. CHW taps "Record Response" in O2 app or switches to WhatsApp
4. CHW records a WhatsApp voice note as response
5. Voice note is sent to patient's WhatsApp number (previously registered in O2)
6. Patient receives CHW's voice response on her feature phone via WhatsApp (if she has smartphone) or as a callback audio message

POSTCONDITIONS:
- Patient receives CHW's verbal guidance
- Interaction is logged in O2 as a clinical contact record
```

### Flow 3: Emergency Detection and Escalation

```
PRECONDITIONS:
- Patient speaks a keyword indicating emergency during IVR recording

STEPS:
1. During Step 7 (Flow 1), real-time speech analysis detects emergency keywords (e.g., "blood", "pain", "unconscious", regional equivalents)
2. IVR platform immediately routes call to CHW (bypass queued callback)
3. If CHW does not answer within 60 seconds, system escalates to PHC supervisor
4. O2 app receives push notification: "URGENT from [Patient Name] — Emergency keyword detected"
5. CHW or supervisor initiates emergency visit protocol

POSTCONDITIONS:
- Emergency is flagged in O2 with high priority
- SBAR generated for emergency referral if CHW escalates
```

---

## 4. Scope Boundaries

### In Scope (Phase 1)

- Missed-call trigger → callback flow
- IVR voice recording (max 60 seconds) in Kannada and Hindi
- WhatsApp voice message delivery to CHW
- Caller ID → patient → CHW mapping lookup
- Patient confirmation message after recording
- CHW response via WhatsApp voice note
- Basic emergency keyword detection (limited vocabulary)
- Interaction logged as clinical contact record in O2

### Deferred for Later

- Two-way real-time voice call between patient and CHW
- IVR menu with keypad (DTMF) options
- SMS fallback for patients without WhatsApp
- Multi-language beyond Kannada and Hindi (Bengali, Marathi, etc.)
- WhatsApp Business API official number provisioning and WhatsApp policy compliance
- AI-based symptom triage from recorded audio (beyond keyword detection)
- Patient-initiated appointment scheduling via IVR

### Outside This Product's Identity

- General telemedicine platform (not just maternal health)
- Patient-to-provider video consultations
- Non-health communication (nutrition advice, government schemes)

---

## 5. Success Criteria

| Criterion | Target |
|---|---|
| Missed-call-to-voice-delivery latency | < 90 seconds from missed call to CHW receiving WhatsApp message |
| IVR callback completion rate | > 95% of callbacks answered within 3 retries |
| CHW response rate | > 80% of voice messages receive a CHW response within 24 hours |
| Patient airtime cost | ₹0 — system must not charge patient airtime |
| Emergency keyword recall | > 90% recall on top 20 emergency keywords in Kannada and Hindi |
| WhatsApp message delivery success | > 99% of voice messages delivered to CHW's WhatsApp |

---

## 6. Key Assumptions

1. **Patient phone number is pre-registered** in O2's patient record (collected at ABHA registration). The IVR platform can query this mapping via a Patient Lookup Service API.

2. **WhatsApp Business API access** is available and a business number is provisioned. This is a third-party dependency outside O2's code.

3. **CHW has WhatsApp** installed and uses it as their primary communication tool. This is already the de facto communication channel for most ASHAs in India.

4. **Regional language TTS for IVR prompts** is powered by ElevenLabs (or equivalent). IVR greeting and confirmation messages are pre-recorded or generated via TTS.

5. **Caller ID is reliably available** on India's GSM network (missed-call caller ID is consistently transmitted). This is the foundational assumption for the entire flow.

6. **Patient consent for callback** is captured during ABHA registration. No separate consent flow is needed for Phase 1.

---

## 7. Technical Dependencies (External)

| Dependency | Purpose | Risk if unavailable |
|---|---|---|
| Twilio / Exotel / custom VoIP | IVR platform — missed call detection, callback, voice recording | Critical path — must be resolved in Phase 1 |
| WhatsApp Business API | Forward voice recordings to CHW's WhatsApp | Critical path — alternate: SMS fallback |
| ElevenLabs (or equivalent) | Generate IVR prompts in Kannada/Hindi TTS | Medium — pre-recorded prompts are fallback |
| Patient Lookup Service (O2 backend) | Map caller ID → patient ABHA → CHW WhatsApp number | Critical path — must be in Phase 1 Supabase schema |
| Emergency keyword library | Kannada/Hindi keyword list for speech detection | Medium — manual review is fallback |

---

## 8. Product Positioning

> O2's IVR layer does not replace the O2 app — it extends the platform's reach to patients who cannot use the app at all. The CHW's primary interface remains the O2 app; the IVR layer is an inbound communication bridge that feeds into it.

---

*Generated by ce-brainstorm (IVR Communication Layer)*
