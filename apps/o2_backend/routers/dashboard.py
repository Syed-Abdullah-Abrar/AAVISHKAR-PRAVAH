"""
PHC Supervisor Dashboard — O2 Platform Phase 2
Flask/HTML dashboard showing aggregate patient data from SQLite.
No frontend framework needed — single HTML file + JSON API.
"""

import os
from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from datetime import datetime

from services.database import patient_repo, visit_repo, schedule_repo, vitals_repo

router = APIRouter(prefix="/dashboard", tags=["Dashboard"])

SUPERVISOR_PORT = int(os.getenv("SUPERVISOR_DASHBOARD_PORT", "8080"))
SUPERVISOR_PHC_ID = os.getenv("SUPERVISOR_PHC_ID", "PHC001")


# ─── JSON API endpoints ─────────────────────────────────────────────────────────

@router.get("/api/summary")
async def get_summary(phc_id: str = SUPERVISOR_PHC_ID):
    """Aggregate summary for PHC supervisor."""
    patients = await patient_repo.list_by_phc(phc_id)
    high_risk = [p for p in patients if p.get("risk_level") == "HIGH"]
    medium_risk = [p for p in patients if p.get("risk_level") == "MEDIUM"]
    low_risk = [p for p in patients if p.get("risk_level") == "LOW"]
    
    pending_schedules = await schedule_repo.list_pending(phc_id)
    recent_visits = await visit_repo.list_recent(phc_id, days=7)
    
    return {
        "phc_id": phc_id,
        "total_patients": len(patients),
        "risk_breakdown": {
            "HIGH": len(high_risk),
            "MEDIUM": len(medium_risk),
            "LOW": len(low_risk),
            "EMERGENCY": len([p for p in patients if p.get("risk_level") == "EMERGENCY"]),
        },
        "pending_follow_ups": len(pending_schedules),
        "visits_this_week": len(recent_visits),
        "generated_at": datetime.utcnow().isoformat(),
    }


@router.get("/api/patients/high-risk")
async def get_high_risk_patients(phc_id: str = SUPERVISOR_PHC_ID):
    """List all HIGH risk patients."""
    patients = await patient_repo.list_high_risk(phc_id)
    return {"patients": patients, "count": len(patients)}


@router.get("/api/patients/all")
async def get_all_patients(phc_id: str = SUPERVISOR_PHC_ID):
    """List all patients."""
    patients = await patient_repo.list_by_phc(phc_id)
    return {"patients": patients, "count": len(patients)}


@router.get("/api/schedules/pending")
async def get_pending_schedules(phc_id: str = SUPERVISOR_PHC_ID):
    """List pending follow-ups."""
    schedules = await schedule_repo.list_pending(phc_id)
    return {"schedules": schedules, "count": len(schedules)}


@router.get("/api/visits/recent")
async def get_recent_visits(phc_id: str = SUPERVISOR_PHC_ID, days: int = 7):
    """List recent visits."""
    visits = await visit_repo.list_recent(phc_id, days)
    return {"visits": visits, "count": len(visits)}


# ─── HTML Dashboard ─────────────────────────────────────────────────────────────

DASHBOARD_HTML = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>PHC Supervisor Dashboard — O2 Platform</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { font-family: system-ui, -apple-system, sans-serif; background: #f4f6f8; color: #1a1a2e; }
        .header { background: #1a1a2e; color: white; padding: 20px 32px; display: flex; justify-content: space-between; align-items: center; }
        .header h1 { font-size: 20px; font-weight: 600; }
        .header-meta { font-size: 12px; opacity: 0.7; }
        .container { max-width: 1200px; margin: 0 auto; padding: 24px; }
        
        .metrics { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 16px; margin-bottom: 24px; }
        .metric-card { background: white; border-radius: 12px; padding: 20px 24px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
        .metric-label { font-size: 11px; text-transform: uppercase; letter-spacing: 0.5px; color: #666; margin-bottom: 8px; }
        .metric-value { font-size: 36px; font-weight: 700; }
        .metric-value.high { color: #dc2626; }
        .metric-value.medium { color: #f59e0b; }
        .metric-value.low { color: #16a34a; }
        .metric-value.total { color: #1a1a2e; }
        
        .section { background: white; border-radius: 12px; padding: 24px; margin-bottom: 24px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
        .section-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 16px; }
        .section-title { font-size: 16px; font-weight: 600; }
        .badge { background: #dc2626; color: white; font-size: 11px; padding: 2px 8px; border-radius: 10px; }
        
        table { width: 100%; border-collapse: collapse; }
        th { text-align: left; padding: 10px 12px; font-size: 11px; text-transform: uppercase; letter-spacing: 0.5px; color: #666; border-bottom: 2px solid #f1f1f1; }
        td { padding: 12px; border-bottom: 1px solid #f1f1f1; font-size: 14px; }
        tr:hover { background: #fafafa; }
        
        .risk-tag { display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 11px; font-weight: 600; }
        .risk-HIGH { background: #fef2f2; color: #dc2626; }
        .risk-MEDIUM { background: #fffbeb; color: #f59e0b; }
        .risk-LOW { background: #f0fdf4; color: #16a34a; }
        .risk-EMERGENCY { background: #7f1d1d; color: white; }
        
        .empty-state { text-align: center; padding: 48px 24px; color: #888; }
        .empty-state svg { width: 48px; height: 48px; margin-bottom: 16px; opacity: 0.4; }
        
        .loading { text-align: center; padding: 48px; color: #888; }
        .refresh-btn { background: #1a1a2e; color: white; border: none; padding: 8px 16px; border-radius: 6px; cursor: pointer; font-size: 13px; }
        .refresh-btn:hover { background: #2a2a4e; }
        
        .timestamp { font-size: 11px; color: #888; margin-top: 8px; }
    </style>
</head>
<body>
    <div class="header">
        <div>
            <h1>📊 PHC Supervisor Dashboard</h1>
            <div class="header-meta">O2 Platform — Maternal Health Monitoring</div>
        </div>
        <div>
            <button class="refresh-btn" onclick="loadDashboard()">🔄 Refresh</button>
        </div>
    </div>
    
    <div class="container">
        <!-- Metrics Row -->
        <div class="metrics" id="metrics">
            <div class="loading">Loading...</div>
        </div>
        
        <!-- High Risk Patients -->
        <div class="section">
            <div class="section-header">
                <span class="section-title">🚨 High Risk Patients</span>
                <span class="badge" id="high-risk-count">0</span>
            </div>
            <div id="high-risk-table">
                <div class="loading">Loading...</div>
            </div>
        </div>
        
        <!-- Pending Follow-ups -->
        <div class="section">
            <div class="section-header">
                <span class="section-title">📋 Pending Follow-ups</span>
            </div>
            <div id="schedules-table">
                <div class="loading">Loading...</div>
            </div>
        </div>
        
        <!-- Recent Visits -->
        <div class="section">
            <div class="section-header">
                <span class="section-title">🏠 Recent Visits (7 days)</span>
            </div>
            <div id="visits-table">
                <div class="loading">Loading...</div>
            </div>
        </div>
        
        <div class="timestamp" id="last-updated"></div>
    </div>
    
    <script>
        const PHCS_ID = window.location.pathname.split('/')[3] || 'PHC001';
        
        async function loadDashboard() {
            try {
                // Load summary
                const summaryRes = await fetch(`/dashboard/api/summary?phc_id=${PHCS_ID}`);
                const summary = await summaryRes.json();
                
                // Metrics
                const metricsEl = document.getElementById('metrics');
                metricsEl.innerHTML = `
                    <div class="metric-card">
                        <div class="metric-label">Total Patients</div>
                        <div class="metric-value total">${summary.total_patients}</div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-label">High Risk</div>
                        <div class="metric-value high">${summary.risk_breakdown.HIGH}</div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-label">Medium Risk</div>
                        <div class="metric-value medium">${summary.risk_breakdown.MEDIUM}</div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-label">Low Risk</div>
                        <div class="metric-value low">${summary.risk_breakdown.LOW}</div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-label">Visits This Week</div>
                        <div class="metric-value total">${summary.visits_this_week}</div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-label">Pending Follow-ups</div>
                        <div class="metric-value total">${summary.pending_follow_ups}</div>
                    </div>
                `;
                
                // High risk patients
                const hrRes = await fetch(`/dashboard/api/patients/high-risk?phc_id=${PHCS_ID}`);
                const hrData = await hrRes.json();
                document.getElementById('high-risk-count').textContent = hrData.count;
                const hrEl = document.getElementById('high-risk-table');
                if (hrData.patients.length === 0) {
                    hrEl.innerHTML = '<div class="empty-state">✅ No high-risk patients</div>';
                } else {
                    hrEl.innerHTML = `
                        <table>
                            <thead><tr>
                                <th>Name</th><th>ABHA</th><th>Risk</th><th>Phone</th><th>CHW Telegram</th>
                            </tr></thead>
                            <tbody>
                                ${hrData.patients.map(p => `
                                    <tr>
                                        <td><strong>${p.name}</strong></td>
                                        <td>${p.abha_number ? p.abha_number.slice(0,4) + '-****' : 'N/A'}</td>
                                        <td><span class="risk-tag risk-${p.risk_level}">${p.risk_level}</span></td>
                                        <td>${p.phone || 'N/A'}</td>
                                        <td>${p.chw_telegram_id || 'N/A'}</td>
                                    </tr>
                                `).join('')}
                            </tbody>
                        </table>
                    `;
                }
                
                // Schedules
                const schedRes = await fetch(`/dashboard/api/schedules/pending?phc_id=${PHCS_ID}`);
                const schedData = await schedRes.json();
                const schedEl = document.getElementById('schedules-table');
                if (schedData.schedules.length === 0) {
                    schedEl.innerHTML = '<div class="empty-state">📋 No pending follow-ups</div>';
                } else {
                    schedEl.innerHTML = `
                        <table>
                            <thead><tr>
                                <th>Patient</th><th>Scheduled</th><th>Status</th><th>Reason</th><th>Auto-generated</th>
                            </tr></thead>
                            <tbody>
                                ${schedData.schedules.map(s => `
                                    <tr>
                                        <td>${s.patient_id ? s.patient_id.slice(0,8) + '...' : 'N/A'}</td>
                                        <td>${s.scheduled_at}</td>
                                        <td>${s.status}</td>
                                        <td>${s.reason || 'N/A'}</td>
                                        <td>${s.auto_generated ? '✓' : '✗'}</td>
                                    </tr>
                                `).join('')}
                            </tbody>
                        </table>
                    `;
                }
                
                // Recent visits
                const visitsRes = await fetch(`/dashboard/api/visits/recent?phc_id=${PHCS_ID}&days=7`);
                const visitsData = await visitsRes.json();
                const visitsEl = document.getElementById('visits-table');
                if (visitsData.visits.length === 0) {
                    visitsEl.innerHTML = '<div class="empty-state">🏠 No visits this week</div>';
                } else {
                    visitsEl.innerHTML = `
                        <table>
                            <thead><tr>
                                <th>Patient</th><th>GPS</th><th>CHW ID</th><th>Date</th>
                            </tr></thead>
                            <tbody>
                                ${visitsData.visits.map(v => `
                                    <tr>
                                        <td>${v.patient_id ? v.patient_id.slice(0,8) + '...' : 'N/A'}</td>
                                        <td>${v.latitude.toFixed(4)}, ${v.longitude.toFixed(4)}</td>
                                        <td>${v.chw_id}</td>
                                        <td>${v.recorded_at}</td>
                                    </tr>
                                `).join('')}
                            </tbody>
                        </table>
                    `;
                }
                
                document.getElementById('last-updated').textContent = 
                    `Last updated: ${new Date().toLocaleTimeString()}`;
            } catch (e) {
                console.error('Dashboard load failed:', e);
            }
        }
        
        loadDashboard();
        setInterval(loadDashboard, 60000); // Auto-refresh every minute
    </script>
</body>
</html>
"""


@router.get("/", response_class=HTMLResponse)
async def dashboard_home():
    """HTML dashboard for PHC supervisor."""
    return DASHBOARD_HTML


@router.get("/phc/{phc_id}", response_class=HTMLResponse)
async def dashboard_for_phc(phc_id: str):
    """Dashboard for specific PHC."""
    global SUPERVISOR_PHC_ID
    SUPERVISOR_PHC_ID = phc_id
    return DASHBOARD_HTML