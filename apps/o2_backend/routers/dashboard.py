"""
PHC Supervisor Dashboard — O2 Platform Phase 2
Flask/HTML dashboard showing aggregate patient data from SQLite.
No frontend framework needed — single HTML file + JSON API.
"""

import os
from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse
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


# ─── Extra API endpoints for dashboard ───────────────────────────────────────────

@router.get("/api/patients/{patient_id}/vitals")
async def get_patient_vitals(patient_id: str):
    """Get vitals history for a patient."""
    vitals = await vitals_repo.list_by_patient(patient_id, limit=10)
    return {"patient_id": patient_id, "vitals": vitals, "count": len(vitals)}


# ─── HTML Dashboard ─────────────────────────────────────────────────────────────

DASHBOARD_HTML = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>PHC Supervisor Dashboard — O2 Platform</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.7/dist/chart.umd.min.js"></script>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap" rel="stylesheet">
    <style>
        :root {
            --bg-primary: #0F172A;
            --bg-secondary: #1E293B;
            --bg-card: #1E293B;
            --bg-hover: #334155;
            --text-primary: #F1F5F9;
            --text-secondary: #94A3B8;
            --text-muted: #64748B;
            --accent-teal: #14B8A6;
            --accent-blue: #3B82F6;
            --color-emergency: #EF4444;
            --color-high: #F97316;
            --color-medium: #EAB308;
            --color-low: #22C55E;
            --border-color: #334155;
            --shadow: 0 4px 6px -1px rgba(0,0,0,0.3);
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: 'Inter', system-ui, -apple-system, sans-serif;
            background: var(--bg-primary);
            color: var(--text-primary);
            min-height: 100vh;
        }

        /* ─── Header ─────────────────────────────────────────── */
        .header {
            background: linear-gradient(135deg, #0F172A 0%, #1E293B 100%);
            border-bottom: 1px solid var(--border-color);
            padding: 16px 32px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            position: sticky; top: 0; z-index: 100;
            backdrop-filter: blur(12px);
        }
        .header-left { display: flex; align-items: center; gap: 16px; }
        .header-logo {
            width: 36px; height: 36px;
            background: linear-gradient(135deg, var(--accent-teal), var(--accent-blue));
            border-radius: 10px;
            display: flex; align-items: center; justify-content: center;
            font-weight: 800; font-size: 16px; color: white;
        }
        .header h1 { font-size: 18px; font-weight: 700; letter-spacing: -0.3px; }
        .header-sub { font-size: 12px; color: var(--text-secondary); margin-top: 2px; }
        .header-right { display: flex; align-items: center; gap: 16px; }
        .live-dot {
            width: 8px; height: 8px; border-radius: 50%;
            background: var(--color-low);
            animation: pulse-dot 2s infinite;
        }
        @keyframes pulse-dot {
            0%, 100% { opacity: 1; box-shadow: 0 0 0 0 rgba(34,197,94,0.4); }
            50% { opacity: 0.8; box-shadow: 0 0 0 6px rgba(34,197,94,0); }
        }
        .live-text { font-size: 12px; color: var(--text-secondary); }
        .clock { font-size: 13px; color: var(--text-secondary); font-variant-numeric: tabular-nums; }

        /* ─── Container ──────────────────────────────────────── */
        .container { max-width: 1400px; margin: 0 auto; padding: 24px 32px; }

        /* ─── Metrics ────────────────────────────────────────── */
        .metrics { display: grid; grid-template-columns: repeat(6, 1fr); gap: 16px; margin-bottom: 24px; }
        .metric-card {
            background: var(--bg-card);
            border: 1px solid var(--border-color);
            border-radius: 12px;
            padding: 20px;
            position: relative;
            overflow: hidden;
            transition: transform 0.2s, border-color 0.2s;
        }
        .metric-card:hover { transform: translateY(-2px); border-color: var(--accent-teal); }
        .metric-label {
            font-size: 11px; text-transform: uppercase;
            letter-spacing: 0.8px; color: var(--text-muted);
            margin-bottom: 8px; font-weight: 600;
        }
        .metric-value {
            font-size: 32px; font-weight: 800;
            font-variant-numeric: tabular-nums;
            line-height: 1;
        }
        .metric-value.emergency { color: var(--color-emergency); }
        .metric-value.high { color: var(--color-high); }
        .metric-value.medium { color: var(--color-medium); }
        .metric-value.low { color: var(--color-low); }
        .metric-value.total { color: var(--text-primary); }
        .metric-value.accent { color: var(--accent-teal); }
        .metric-bar {
            position: absolute; bottom: 0; left: 0; right: 0; height: 3px;
        }

        /* ─── Grid Layout ────────────────────────────────────── */
        .grid-2 { display: grid; grid-template-columns: 1fr 1fr; gap: 24px; margin-bottom: 24px; }
        .grid-3-1 { display: grid; grid-template-columns: 2fr 1fr; gap: 24px; margin-bottom: 24px; }

        /* ─── Section Cards ──────────────────────────────────── */
        .section {
            background: var(--bg-card);
            border: 1px solid var(--border-color);
            border-radius: 12px;
            overflow: hidden;
        }
        .section-header {
            padding: 16px 20px;
            border-bottom: 1px solid var(--border-color);
            display: flex; justify-content: space-between; align-items: center;
        }
        .section-title { font-size: 14px; font-weight: 600; display: flex; align-items: center; gap: 8px; }
        .section-body { padding: 0; }
        .section-body-padded { padding: 20px; }

        /* ─── Badge ──────────────────────────────────────────── */
        .badge {
            font-size: 11px; font-weight: 600;
            padding: 3px 10px; border-radius: 6px;
        }
        .badge-emergency { background: rgba(239,68,68,0.15); color: var(--color-emergency); }
        .badge-high { background: rgba(249,115,22,0.15); color: var(--color-high); }
        .badge-medium { background: rgba(234,179,8,0.15); color: var(--color-medium); }
        .badge-low { background: rgba(34,197,94,0.15); color: var(--color-low); }

        /* ─── Table ──────────────────────────────────────────── */
        table { width: 100%; border-collapse: collapse; }
        th {
            text-align: left; padding: 10px 16px;
            font-size: 11px; text-transform: uppercase;
            letter-spacing: 0.6px; color: var(--text-muted);
            font-weight: 600; background: rgba(0,0,0,0.2);
        }
        td {
            padding: 12px 16px; font-size: 13px;
            border-bottom: 1px solid var(--border-color);
            color: var(--text-secondary);
        }
        tr:hover td { background: var(--bg-hover); color: var(--text-primary); }
        td strong { color: var(--text-primary); font-weight: 600; }

        /* ─── Alert Feed ─────────────────────────────────────── */
        .alert-item {
            padding: 12px 16px;
            border-bottom: 1px solid var(--border-color);
            display: flex; gap: 12px; align-items: flex-start;
            transition: background 0.15s;
        }
        .alert-item:hover { background: var(--bg-hover); }
        .alert-icon {
            width: 32px; height: 32px; border-radius: 8px;
            display: flex; align-items: center; justify-content: center;
            font-size: 16px; flex-shrink: 0;
        }
        .alert-icon.emergency { background: rgba(239,68,68,0.15); }
        .alert-icon.high { background: rgba(249,115,22,0.15); }
        .alert-icon.medium { background: rgba(234,179,8,0.15); }
        .alert-icon.low { background: rgba(34,197,94,0.15); }
        .alert-title { font-size: 13px; font-weight: 500; color: var(--text-primary); }
        .alert-detail { font-size: 11px; color: var(--text-muted); margin-top: 2px; }

        /* ─── Chart Container ────────────────────────────────── */
        .chart-container { padding: 20px; display: flex; justify-content: center; align-items: center; }
        .chart-container canvas { max-height: 220px; }

        /* ─── Empty State ────────────────────────────────────── */
        .empty-state { text-align: center; padding: 40px 24px; color: var(--text-muted); font-size: 13px; }

        /* ─── Footer ─────────────────────────────────────────── */
        .footer {
            padding: 16px 32px;
            border-top: 1px solid var(--border-color);
            display: flex; justify-content: space-between; align-items: center;
            font-size: 11px; color: var(--text-muted);
        }

        /* ─── Animate-in ─────────────────────────────────────── */
        @keyframes fadeIn { from { opacity: 0; transform: translateY(8px); } to { opacity: 1; transform: translateY(0); } }
        .animate-in { animation: fadeIn 0.4s ease-out; }

        @media (max-width: 1024px) {
            .metrics { grid-template-columns: repeat(3, 1fr); }
            .grid-2, .grid-3-1 { grid-template-columns: 1fr; }
        }
    </style>
</head>
<body>
    <div class="header">
        <div class="header-left">
            <div class="header-logo">O₂</div>
            <div>
                <h1>PHC Supervisor Dashboard</h1>
                <div class="header-sub">O2 Platform — Maternal Health Monitoring System</div>
            </div>
        </div>
        <div class="header-right">
            <div style="display:flex;align-items:center;gap:6px;">
                <div class="live-dot"></div>
                <span class="live-text">Live</span>
            </div>
            <span class="clock" id="clock"></span>
        </div>
    </div>

    <div class="container">
        <!-- Metrics Row -->
        <div class="metrics" id="metrics">
            <div class="metric-card"><div class="metric-label">Loading...</div></div>
        </div>

        <!-- Charts + Alerts -->
        <div class="grid-2">
            <!-- Risk Distribution Chart -->
            <div class="section animate-in">
                <div class="section-header">
                    <span class="section-title">📊 Risk Distribution</span>
                </div>
                <div class="chart-container">
                    <canvas id="riskChart"></canvas>
                </div>
            </div>

            <!-- Live Alert Feed -->
            <div class="section animate-in">
                <div class="section-header">
                    <span class="section-title">🔔 Alert Feed</span>
                    <span class="badge badge-emergency" id="alert-count">0 alerts</span>
                </div>
                <div class="section-body" id="alert-feed" style="max-height:280px;overflow-y:auto;">
                    <div class="empty-state">No alerts</div>
                </div>
            </div>
        </div>

        <!-- Patient Table + Pending Schedules -->
        <div class="grid-3-1">
            <!-- All Patients -->
            <div class="section animate-in">
                <div class="section-header">
                    <span class="section-title">👩‍⚕️ Registered Patients</span>
                    <span class="badge badge-low" id="patient-count">0</span>
                </div>
                <div class="section-body" id="patient-table">
                    <div class="empty-state">Loading patients...</div>
                </div>
            </div>

            <!-- Pending Follow-ups -->
            <div class="section animate-in">
                <div class="section-header">
                    <span class="section-title">📋 Pending Follow-ups</span>
                </div>
                <div class="section-body" id="schedule-list" style="max-height:400px;overflow-y:auto;">
                    <div class="empty-state">Loading...</div>
                </div>
            </div>
        </div>

        <!-- Recent Visits -->
        <div class="section animate-in" style="margin-bottom:24px;">
            <div class="section-header">
                <span class="section-title">📍 Recent GPS-Tagged Visits (7 days)</span>
            </div>
            <div class="section-body" id="visits-table">
                <div class="empty-state">Loading visits...</div>
            </div>
        </div>
    </div>

    <div class="footer">
        <span>O2 Platform v1.0.0 — PHC001 Karnataka</span>
        <span id="last-updated">Refreshing...</span>
    </div>

    <script>
        let riskChart = null;

        function updateClock() {
            const now = new Date();
            document.getElementById('clock').textContent = now.toLocaleTimeString('en-IN', { hour12: true });
        }
        setInterval(updateClock, 1000);
        updateClock();

        function riskBadge(level) {
            const cls = { 'EMERGENCY': 'badge-emergency', 'HIGH': 'badge-high', 'MEDIUM': 'badge-medium', 'LOW': 'badge-low' };
            return `<span class="badge ${cls[level] || 'badge-low'}">${level}</span>`;
        }

        function timeAgo(dateStr) {
            const d = new Date(dateStr);
            const diff = Math.floor((Date.now() - d) / 1000);
            if (diff < 60) return 'just now';
            if (diff < 3600) return Math.floor(diff/60) + 'm ago';
            if (diff < 86400) return Math.floor(diff/3600) + 'h ago';
            return Math.floor(diff/86400) + 'd ago';
        }

        function abhaDisplay(abha) {
            if (!abha || abha.length < 6) return abha || 'N/A';
            return abha.slice(0,4) + '-' + abha.slice(4,8) + '-' + abha.slice(8);
        }

        async function loadDashboard() {
            try {
                // ─── Summary ────────────────────────────────────────
                const summary = await (await fetch('/dashboard/api/summary')).json();

                document.getElementById('metrics').innerHTML = `
                    <div class="metric-card">
                        <div class="metric-label">Total Patients</div>
                        <div class="metric-value total">${summary.total_patients}</div>
                        <div class="metric-bar" style="background:var(--accent-teal);"></div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-label">Emergency</div>
                        <div class="metric-value emergency">${summary.risk_breakdown.EMERGENCY}</div>
                        <div class="metric-bar" style="background:var(--color-emergency);"></div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-label">High Risk</div>
                        <div class="metric-value high">${summary.risk_breakdown.HIGH}</div>
                        <div class="metric-bar" style="background:var(--color-high);"></div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-label">Medium Risk</div>
                        <div class="metric-value medium">${summary.risk_breakdown.MEDIUM}</div>
                        <div class="metric-bar" style="background:var(--color-medium);"></div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-label">Low Risk</div>
                        <div class="metric-value low">${summary.risk_breakdown.LOW}</div>
                        <div class="metric-bar" style="background:var(--color-low);"></div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-label">This Week</div>
                        <div class="metric-value accent">${summary.visits_this_week}</div>
                        <div class="metric-bar" style="background:var(--accent-blue);"></div>
                    </div>
                `;

                // ─── Risk Chart ─────────────────────────────────────
                const ctx = document.getElementById('riskChart').getContext('2d');
                const chartData = [
                    summary.risk_breakdown.EMERGENCY || 0,
                    summary.risk_breakdown.HIGH || 0,
                    summary.risk_breakdown.MEDIUM || 0,
                    summary.risk_breakdown.LOW || 0,
                ];
                if (riskChart) riskChart.destroy();
                riskChart = new Chart(ctx, {
                    type: 'doughnut',
                    data: {
                        labels: ['Emergency', 'High', 'Medium', 'Low'],
                        datasets: [{
                            data: chartData,
                            backgroundColor: ['#EF4444', '#F97316', '#EAB308', '#22C55E'],
                            borderColor: '#1E293B',
                            borderWidth: 3,
                            hoverOffset: 6,
                        }]
                    },
                    options: {
                        responsive: true,
                        cutout: '65%',
                        plugins: {
                            legend: {
                                position: 'right',
                                labels: { color: '#94A3B8', font: { family: 'Inter', size: 12 }, padding: 12, usePointStyle: true, pointStyleWidth: 10 }
                            }
                        }
                    }
                });

                // ─── All Patients ───────────────────────────────────
                const allPats = await (await fetch('/dashboard/api/patients/all')).json();
                document.getElementById('patient-count').textContent = allPats.count;
                const patEl = document.getElementById('patient-table');
                if (allPats.patients.length === 0) {
                    patEl.innerHTML = '<div class="empty-state">No registered patients</div>';
                } else {
                    patEl.innerHTML = `<table>
                        <thead><tr><th>Name</th><th>ABHA</th><th>Risk</th><th>Phone</th><th>Registered</th></tr></thead>
                        <tbody>${allPats.patients.map(p => `<tr>
                            <td><strong>${p.name}</strong></td>
                            <td style="font-variant-numeric:tabular-nums;">${abhaDisplay(p.abha_number)}</td>
                            <td>${riskBadge(p.risk_level)}</td>
                            <td>${p.phone || '—'}</td>
                            <td>${timeAgo(p.created_at)}</td>
                        </tr>`).join('')}</tbody>
                    </table>`;
                }

                // ─── Alert Feed (from patients) ─────────────────────
                const alerts = allPats.patients
                    .filter(p => p.risk_level === 'EMERGENCY' || p.risk_level === 'HIGH')
                    .map(p => ({
                        level: p.risk_level,
                        title: p.risk_level === 'EMERGENCY'
                            ? `🚨 EMERGENCY — ${p.name}`
                            : `⚠️ HIGH RISK — ${p.name}`,
                        detail: p.risk_level === 'EMERGENCY'
                            ? 'Immediate referral required. Ambulance dispatched.'
                            : 'Urgent follow-up within 24 hours required.',
                        time: p.created_at,
                    }));
                document.getElementById('alert-count').textContent = alerts.length + ' alerts';
                const feedEl = document.getElementById('alert-feed');
                if (alerts.length === 0) {
                    feedEl.innerHTML = '<div class="empty-state">✅ No active alerts</div>';
                } else {
                    feedEl.innerHTML = alerts.map(a => `
                        <div class="alert-item">
                            <div class="alert-icon ${a.level.toLowerCase()}">${a.level === 'EMERGENCY' ? '🚨' : '⚠️'}</div>
                            <div>
                                <div class="alert-title">${a.title}</div>
                                <div class="alert-detail">${a.detail} · ${timeAgo(a.time)}</div>
                            </div>
                        </div>
                    `).join('');
                }

                // ─── Schedules ──────────────────────────────────────
                const scheds = await (await fetch('/dashboard/api/schedules/pending')).json();
                const schedEl = document.getElementById('schedule-list');
                if (scheds.schedules.length === 0) {
                    schedEl.innerHTML = '<div class="empty-state">No pending follow-ups</div>';
                } else {
                    schedEl.innerHTML = scheds.schedules.map(s => `
                        <div class="alert-item">
                            <div class="alert-icon medium">📋</div>
                            <div>
                                <div class="alert-title">${s.reason || 'Follow-up'}</div>
                                <div class="alert-detail">Scheduled: ${new Date(s.scheduled_at).toLocaleDateString('en-IN')} · ${s.auto_generated ? 'Auto-generated' : 'Manual'}</div>
                            </div>
                        </div>
                    `).join('');
                }

                // ─── Recent Visits ──────────────────────────────────
                const visits = await (await fetch('/dashboard/api/visits/recent?days=30')).json();
                const visEl = document.getElementById('visits-table');
                if (visits.visits.length === 0) {
                    visEl.innerHTML = '<div class="empty-state">No recent visits</div>';
                } else {
                    visEl.innerHTML = `<table>
                        <thead><tr><th>CHW</th><th>GPS Coordinates</th><th>Notes</th><th>Time</th></tr></thead>
                        <tbody>${visits.visits.map(v => `<tr>
                            <td><strong>${v.chw_id}</strong></td>
                            <td style="font-variant-numeric:tabular-nums;">${v.latitude.toFixed(4)}, ${v.longitude.toFixed(4)}</td>
                            <td>${(v.notes || '').slice(0, 80)}${(v.notes || '').length > 80 ? '...' : ''}</td>
                            <td>${timeAgo(v.recorded_at)}</td>
                        </tr>`).join('')}</tbody>
                    </table>`;
                }

                document.getElementById('last-updated').textContent =
                    `Last refresh: ${new Date().toLocaleTimeString('en-IN')} · Auto-refreshing every 10s`;

            } catch (e) {
                console.error('Dashboard load failed:', e);
            }
        }

        loadDashboard();
        setInterval(loadDashboard, 10000);
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


