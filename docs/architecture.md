# O2 Platform — Architecture Diagrams

> Updated after Phase 1 implementation and 9-diagram-correction pass.

---

## System Architecture

```mermaid
flowchart TB
    subgraph FlutterApp["📱 Flutter CHW App"]
        subgraph FlutterCore["Core Layer"]
            BRICK["Brick ORM<br/>Offline-First Repository"]
            SQLCipher["SQLCipher<br/>AES-256 Encrypted DB"]
            AndroidKeyStore["Android Keystore<br/>Hardware-Backed Key Storage"]
            WorkManager["WorkManager<br/>WiFi + Charging Sync"]
            FHIRSerializer["FHIR Serializer<br/>R4 ↔ O2 Models"]
        end

        subgraph FlutterServices["Service Layer"]
            SyncEngine["Sync Engine<br/>Conflict Resolution + Retry"]
            PatientLookup["Patient Lookup<br/>Caller ID → Patient Record"]
            RiskEngine["Risk Engine<br/>Traffic-Light Triage"]
            EmergencyAlert["Emergency Alert<br/>HIGH/EMERGENCY → PHC Supervisor"]
            ABDMService["ABDM Service<br/>ABHA Mod 97 Validation"]
            VoiceWidget["Voice Widget<br/>Bhashini STT/TTS Stubs"]
        end

        subgraph FlutterModels["FHIR R4 Models"]
            Patient["Patient Resource"]
            Observation["Observation Resource<br/>(Vitals)"]
            DocumentRef["DocumentReference<br/>(SBAR)"]
        end

        SQLCipher -->|encryption key| AndroidKeyStore
        BRICK -->|local SQLite| SQLCipher
        WorkManager -->|sync task| SyncEngine
        SyncEngine -->|sync config| BRICK
        FHIRSerializer -->|serialize/deserialize| Patient
        FHIRSerializer -->|serialize/deserialize| Observation
        FHIRSerializer -->|serialize/deserialize| DocumentRef
    end

    subgraph APIGateway["🌐 API Gateway / Supabase"]
        Supabase["Supabase PostgreSQL<br/>PHC-Based RLS Isolation"]
        REST["REST API<br/>FHIR-Compliant Endpoints"]
        Realtime["Realtime Subscriptions<br/>Push Notifications"]
        
        SyncEngine -->|POST /sync| REST
        REST -->|sync trigger| SyncEngine
        Supabase -.->|data sync| REST
    end

    subgraph AIServer["🤖 AI Server (FastAPI)"]
        RISK["POST /risk<br/>Traffic-Light Triage"]
        SBAR["POST /sbar<br/>LLM Clinical Summary"]
        RiskModel["Risk Model Service<br/>WHO Thresholds Rule Engine"]
        SBARLLM["SBAR LLM Service<br/>OpenAI/Anthropic JSON Schema"]
        
        RISK -->|scoring| RiskModel
        SBAR -->|generation| SBARLLM
        RISK -.->|FHIR Observation| SBAR
    end

    subgraph IVRBackend["📞 IVR Backend (FastAPI)"]
        MissedCall["POST /twilio/missed-call<br/>Caller ID Webhook"]
        VoiceRec["POST /twilio/voice-recording<br/>Recording URL Webhook"]
        PatientLookupService["Patient Lookup Service<br/>CLI → Patient → CHW Mapping"]
        WhatsAppSender["WhatsApp Sender<br/>Voice Note to CHW"]
        EmergencyDetector["Emergency Detector<br/>EN/KN/HI Keyword Scan"]
        TwilioControl["Twilio Control<br/>Callbacks + Recordings"]
        
        MissedCall -->|CLI lookup| PatientLookupService
        VoiceRec -->|recording URL| WhatsAppSender
        PatientLookupService -->|CHW number| WhatsAppSender
        EmergencyDetector -->|alert trigger| EmergencyAlert
        TwilioControl -.->|missed call signal| MissedCall
        TwilioControl -.->|recording ready| VoiceRec
    end

    subgraph External["🔗 External Integrations"]
        Twilio["Twilio Cloud<br/>Voice + WhatsApp API"]
        WhatsApp["WhatsApp Business API<br/>Voice Notes to CHW"]
        Bhashini["Bhashini API<br/>STT + TTS (Phase 2)"]
        ABDMNHA["ABDM NHA API<br/>HPR/HFR (Phase 2)"]
        FHIRServer["FHIR R4 Server<br/>Health Information Highway"]
    end

    FlutterApp -->|sync when WiFi + charging| Supabase
    Supabase -->|FHIR bundle| AIServer
    AIServer -->|risk level + SBAR| FlutterApp
    FlutterApp -->|missed call| Twilio
    Twilio -->|callback| PatientLookupService
    WhatsAppSender -->|voice message| WhatsApp
    WhatsApp -->|voice note| WhatsAppSender
    VoiceWidget -.->|STT/TTS| Bhashini
    ABDMService -.->|HPR verify| ABDMNHA
    FHIRSerializer -.->|sync target| FHIRServer
```

---

## Risk Assessment Flow

```mermaid
sequenceDiagram
    participant CHW as CHW App
    participant API as Supabase REST
    participant RISK as /risk endpoint
    participant RM as RiskModel (WHO)
    participant APP as Flutter App

    CHW->>API: POST /sync {vitals}
    API->>RISK: VitalsInput
    RISK->>RM: Score vitals
    RM-->>RISK: RiskAssessmentResponse
    RISK-->>APP: traffic-light result
    APP->>APP: Display LOW/MEDIUM/HIGH/EMERGENCY
```

---

## IVR Missed-Call Flow

```mermaid
sequenceDiagram
    participant PT as Feature-Phone Patient
    participant TW as Twilio Cloud
    participant IVR as IVR Backend
    participant PL as PatientLookup
    participant WA as WhatsApp Sender
    participant CHW as CHW on WhatsApp

    PT->>TW: Missed call (zero balance)
    TW->>IVR: POST /missed-call {callerID}
    IVR->>PL: Lookup callerID → patient
    PL-->>IVR: patient → CHW WhatsApp
    IVR->>TW: Initiate free callback
    TW->>PT: Ring patient
    PT->>TW: Record voice message
    TW->>IVR: POST /voice-recording {URL}
    IVR->>WA: Forward recording URL
    WA->>CHW: WhatsApp voice note
```

---

## Emergency Triage Decision Tree

```mermaid
flowchart LR
    A["⚠️ Vitals Breach<br/>BP ≥ 160/100,<br/>Hb < 7 g/dL"] --> B{Risk Score ≥ 6?}
    B -->|Yes| C["🚨 EMERGENCY"]
    B -->|No| D{"Score 4-5?"}
    D -->|Yes| E["🟠 HIGH<br/>24h follow-up"]
    D -->|No| F{"Score 2-3?"}
    F -->|Yes| G["🟡 MEDIUM<br/>48h follow-up"]
    F -->|No| H["🟢 LOW<br/>7-day review"]
    
    C --> I["Alert CHW + PHC Supervisor"]
    C --> J["Emergency Contact Protocol"]
    C --> K["Generate SBAR → Refer"]
```

---

## Sync Architecture

```mermaid
flowchart TB
    subgraph Device["📱 CHW Device"]
        LocalDB["SQLite + SQLCipher<br/>Encrypted Local Store"]
        BrickRepo["Brick Repository<br/>Offline-First Pattern"]
        SyncWorker["WorkManager<br/>Periodic Background Task"]
        Queue["Sync Queue<br/>Pending Changes"]
    end

    subgraph Cloud["☁️ Supabase"]
        PG["PostgreSQL<br/>PHC-RLS Isolated"]
        Auth["Auth<br/>CHW Authentication"]
        Storage["Storage<br/>FHIR Bundles"]
        Edge["Edge Functions<br/>Webhook Handlers"]
    end

    SyncWorker -->|check constraints| Queue
    Queue -->|WiFi + Charging| BrickRepo
    BrickRepo -->|FHIR bundle| LocalDB
    LocalDB -->|sync upload| PG
    PG -->|sync download| LocalDB
    Edge -.->|trigger| PG
```

---

## ABDM Integration Flow

```mermaid
flowchart TB
    A["ABHA Number Input<br/>XXXX-XXXX-XXXX-XX"] --> B{Mod 97 Checksum<br/>number % 97 == 1?}
    B -->|Invalid| C["❌ Invalid ABHA"]
    B -->|Valid| D["HPR Verification<br/>Health Professional Registry"]
    D -->|Verified| E["HFR Linking<br/>Health Facility Registry"]
    D -->|Not Found| F["⚠️ Manual Verification"]
    E --> G["ABDM Record Link<br/>Consented Access"]
