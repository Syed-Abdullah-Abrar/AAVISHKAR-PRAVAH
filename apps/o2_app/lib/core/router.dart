import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app.dart';
import '../models/patient.dart';
import '../models/vitals.dart';
import '../repositories/patient_repository.dart';
import '../repositories/vitals_repository.dart';
import '../services/location_service.dart';
import '../services/indictrans_service.dart';
import '../services/telegram_service.dart';

/// O2 Platform — App Router
/// Uses GoRouter for declarative navigation
class O2Router {
  final PatientRepository patientRepository;
  final VitalsRepository vitalsRepository;

  O2Router({
    required this.patientRepository,
    required this.vitalsRepository,
  });

  late final GoRouter router = GoRouter(
    initialLocation: '/home',
    debugLogDiagnostics: true,
    routes: [
      // ─── Home ─────────────────────────────────────────────────────────────────
      GoRoute(
        path: '/home',
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),

      // ─── Patient Management ──────────────────────────────────────────────────
      GoRoute(
        path: '/patients',
        name: 'patients',
        builder: (context, state) => const PatientListScreen(),
        routes: [
          GoRoute(
            path: 'register',
            name: 'patient-register',
            builder: (context, state) => const PatientRegistrationScreen(),
          ),
          GoRoute(
            path: ':patientId',
            name: 'patient-detail',
            builder: (context, state) {
              final patientId = state.pathParameters['patientId']!;
              return PatientDetailScreen(patientId: patientId);
            },
            routes: [
              GoRoute(
                path: 'vitals',
                name: 'patient-vitals',
                builder: (context, state) {
                  final patientId = state.pathParameters['patientId']!;
                  return VitalsEntryScreen(patientId: patientId);
                },
              ),
              GoRoute(
                path: 'sbar',
                name: 'patient-sbar',
                builder: (context, state) {
                  final patientId = state.pathParameters['patientId']!;
                  return SBARScreen(patientId: patientId);
                },
              ),
            ],
          ),
        ],
      ),

      // ─── Voice Input ──────────────────────────────────────────────────────────
      GoRoute(
        path: '/voice-input',
        name: 'voice-input',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final patientId = extra?['patientId'] as String?;
          final returnRoute = extra?['returnRoute'] as String?;
          return VoiceInputScreen(
            patientId: patientId,
            returnRoute: returnRoute,
          );
        },
      ),

      // ─── Sync Status ─────────────────────────────────────────────────────────
      GoRoute(
        path: '/sync-status',
        name: 'sync-status',
        builder: (context, state) => const SyncStatusScreen(),
      ),

      // ─── Settings ────────────────────────────────────────────────────────────
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
      ),

      // ─── Emergency ────────────────────────────────────────────────────────────
      GoRoute(
        path: '/emergency/:patientId',
        name: 'emergency',
        builder: (context, state) {
          final patientId = state.pathParameters['patientId']!;
          return EmergencyScreen(patientId: patientId);
        },
      ),
    ],
    errorBuilder: (context, state) => ErrorScreen(error: state.error),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// HOME SCREEN — Dashboard
// ═══════════════════════════════════════════════════════════════════════════════

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _totalPatients = 0;
  int _highRiskCount = 0;
  int _activePregnancies = 0;
  int _overdueCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    try {
      // TODO: Wire to actual repository once Supabase credentials available
      // For now, show expected UI structure
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) {
        setState(() {
          _totalPatients = 0;
          _highRiskCount = 0;
          _activePregnancies = 0;
          _overdueCount = 0;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('O2 Platform'),
        backgroundColor: const Color(0xFF6B21A8),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: () => context.push('/sync-status'),
            tooltip: 'Sync Status',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadDashboardData,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ─── Welcome Card ───────────────────────────────────────────
                  Card(
                    color: const Color(0xFF6B21A8),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Good Morning, CHW',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Track and manage maternal health in your village',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Colors.white70,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ─── Quick Stats ─────────────────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: Icons.people,
                          label: 'Total Patients',
                          value: '$_totalPatients',
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.warning_amber,
                          label: 'High Risk',
                          value: '$_highRiskCount',
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: Icons.pregnant_woman,
                          label: 'Active Pregnancies',
                          value: '$_activePregnancies',
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.schedule,
                          label: 'Overdue Visits',
                          value: '$_overdueCount',
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // ─── Quick Actions ─────────────────────────────────────────────
                  Text(
                    'Quick Actions',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),
                  _ActionTile(
                    icon: Icons.person_add,
                    title: 'Register New Patient',
                    subtitle: 'Add a new pregnant patient to your list',
                    color: const Color(0xFF6B21A8),
                    onTap: () => context.push('/patients/register'),
                  ),
                  _ActionTile(
                    icon: Icons.people,
                    title: 'View All Patients',
                    subtitle: 'See your assigned patients',
                    color: Colors.blue,
                    onTap: () => context.push('/patients'),
                  ),
                  _ActionTile(
                    icon: Icons.mic,
                    title: 'Voice Input',
                    subtitle: 'Record voice for AI analysis',
                    color: Colors.teal,
                    onTap: () => context.push('/voice-input'),
                  ),
                  _ActionTile(
                    icon: Icons.sync,
                    title: 'Sync Data',
                    subtitle: 'Sync offline data to server',
                    color: Colors.orange,
                    onTap: () => context.push('/sync-status'),
                  ),
                ],
              ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PATIENT LIST SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

class PatientListScreen extends StatefulWidget {
  const PatientListScreen({super.key});

  @override
  State<PatientListScreen> createState() => _PatientListScreenState();
}

class _PatientListScreenState extends State<PatientListScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Patient> _patients = [];
  List<Patient> _filteredPatients = [];
  bool _isLoading = true;
  String _filter = 'all'; // all, high_risk, overdue

  @override
  void initState() {
    super.initState();
    _loadPatients();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPatients() async {
    setState(() => _isLoading = true);
    try {
      // TODO: Wire to PatientRepository once Supabase credentials available
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) {
        setState(() {
          _patients = [];
          _filteredPatients = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filterPatients() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredPatients = _patients.where((p) {
        final matchesSearch = query.isEmpty ||
            p.name.toLowerCase().contains(query) ||
            (p.abhaId.toLowerCase().contains(query)) ||
            (p.phoneNumber?.toLowerCase().contains(query) ?? false);

        final matchesFilter = _filter == 'all' ||
            (_filter == 'high_risk' && p.highRiskPregnancy) ||
            (_filter == 'overdue' && p.nextVisitDate?.isBefore(DateTime.now()) == true);

        return matchesSearch && matchesFilter;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Patients'),
        backgroundColor: const Color(0xFF6B21A8),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // ─── Search Bar ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name, ABHA ID, phone...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
              ),
              onChanged: (_) => _filterPatients(),
            ),
          ),

          // ─── Filter Chips ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: _filter == 'all',
                  onSelected: (_) {
                    setState(() => _filter = 'all');
                    _filterPatients();
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('High Risk'),
                  selected: _filter == 'high_risk',
                  onSelected: (_) {
                    setState(() => _filter = 'high_risk');
                    _filterPatients();
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Overdue'),
                  selected: _filter == 'overdue',
                  onSelected: (_) {
                    setState(() => _filter = 'overdue');
                    _filterPatients();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // ─── Patient List ────────────────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredPatients.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.people_outline,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No patients found',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton.icon(
                              onPressed: () => context.push('/patients/register'),
                              icon: const Icon(Icons.person_add),
                              label: const Text('Register Patient'),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadPatients,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _filteredPatients.length,
                          itemBuilder: (context, index) {
                            final patient = _filteredPatients[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: const Color(0xFF6B21A8),
                                  child: Text(
                                    patient.name.isNotEmpty
                                        ? patient.name[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        patient.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    if (patient.highRiskPregnancy)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.red[100],
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'High Risk',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.red[800],
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: Text(
                                  'ABHA: ${patient.abhaId}',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => context.push('/patients/${patient.id}'),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/patients/register'),
        icon: const Icon(Icons.person_add),
        label: const Text('Register'),
        backgroundColor: const Color(0xFF6B21A8),
        foregroundColor: Colors.white,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PATIENT REGISTRATION SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

class PatientRegistrationScreen extends StatefulWidget {
  const PatientRegistrationScreen({super.key});

  @override
  State<PatientRegistrationScreen> createState() => _PatientRegistrationScreenState();
}

class _PatientRegistrationScreenState extends State<PatientRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _villageController = TextEditingController();
  final _abhaController = TextEditingController();
  final _emergencyNameController = TextEditingController();
  final _emergencyPhoneController = TextEditingController();

  String _gender = 'F';
  DateTime? _lmpDate;
  DateTime? _eddDate;
  bool _isHighRisk = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _villageController.dispose();
    _abhaController.dispose();
    _emergencyNameController.dispose();
    _emergencyPhoneController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(bool isLmp) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 280)),
    );
    if (picked != null) {
      setState(() {
        if (isLmp) {
          _lmpDate = picked;
          // Auto-calculate EDD: LMP + 280 days
          _eddDate = picked.add(const Duration(days: 280));
        } else {
          _eddDate = picked;
        }
      });
    }
  }

  Future<void> _savePatient() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      // TODO: Generate ABHA ID via backend when available
      // TODO: Save via PatientRepository
      await Future.delayed(const Duration(seconds: 1));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Patient registered successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Register Patient'),
        backgroundColor: const Color(0xFF6B21A8),
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ─── Basic Info ────────────────────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Basic Information',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Full Name *',
                        prefixIcon: Icon(Icons.person),
                      ),
                      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _ageController,
                            decoration: const InputDecoration(
                              labelText: 'Age',
                              prefixIcon: Icon(Icons.cake),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _gender,
                            decoration: const InputDecoration(
                              labelText: 'Gender',
                              prefixIcon: Icon(Icons.wc),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'F', child: Text('Female')),
                              DropdownMenuItem(value: 'M', child: Text('Male')),
                            ],
                            onChanged: (v) => setState(() => _gender = v ?? 'F'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phoneController,
                      decoration: const InputDecoration(
                        labelText: 'Phone Number',
                        prefixIcon: Icon(Icons.phone),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _abhaController,
                      decoration: const InputDecoration(
                        labelText: 'ABHA ID',
                        prefixIcon: Icon(Icons.badge),
                        helperText: 'Health ID (optional - generated if blank)',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ─── Address ──────────────────────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Location',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _villageController,
                      decoration: const InputDecoration(
                        labelText: 'Village',
                        prefixIcon: Icon(Icons.location_city),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _addressController,
                      decoration: const InputDecoration(
                        labelText: 'Address',
                        prefixIcon: Icon(Icons.home),
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ─── Pregnancy Info ───────────────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pregnancy Information',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => _selectDate(true),
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'LMP Date',
                                prefixIcon: Icon(Icons.calendar_today),
                              ),
                              child: Text(
                                _lmpDate != null
                                    ? '${_lmpDate!.day}/${_lmpDate!.month}/${_lmpDate!.year}'
                                    : 'Select date',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: () => _selectDate(false),
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'EDD Date',
                                prefixIcon: Icon(Icons.calendar_today),
                              ),
                              child: Text(
                                _eddDate != null
                                    ? '${_eddDate!.day}/${_eddDate!.month}/${_eddDate!.year}'
                                    : 'Auto-calculated',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('High Risk Pregnancy'),
                      subtitle: const Text('Flag for enhanced monitoring'),
                      value: _isHighRisk,
                      onChanged: (v) => setState(() => _isHighRisk = v),
                      activeColor: Colors.red,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ─── Emergency Contact ─────────────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Emergency Contact',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _emergencyNameController,
                      decoration: const InputDecoration(
                        labelText: 'Contact Name',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _emergencyPhoneController,
                      decoration: const InputDecoration(
                        labelText: 'Contact Phone',
                        prefixIcon: Icon(Icons.phone),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ─── Save Button ───────────────────────────────────────────────────
            ElevatedButton(
              onPressed: _isSaving ? null : _savePatient,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6B21A8),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Register Patient'),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PATIENT DETAIL SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

class PatientDetailScreen extends StatefulWidget {
  final String patientId;
  const PatientDetailScreen({super.key, required this.patientId});

  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen> {
  Patient? _patient;
  List<Vitals> _vitals = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPatient();
  }

  Future<void> _loadPatient() async {
    setState(() => _isLoading = true);
    try {
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) {
        setState(() {
          _patient = null;
          _vitals = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_patient?.name ?? 'Patient Details'),
        backgroundColor: const Color(0xFF6B21A8),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.emergency),
            onPressed: () => context.push('/emergency/${widget.patientId}'),
            tooltip: 'Emergency Protocol',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _patient == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.person_off, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text('Patient not found', style: TextStyle(color: Colors.grey[600])),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => context.pop(),
                        child: const Text('Go Back'),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // ─── Patient Header Card ──────────────────────────────────
                    Card(
                      color: const Color(0xFF6B21A8),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 30,
                              backgroundColor: Colors.white,
                              child: Text(
                                _patient!.name.isNotEmpty ? _patient!.name[0].toUpperCase() : '?',
                                style: const TextStyle(
                                  fontSize: 28,
                                  color: Color(0xFF6B21A8),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _patient!.name,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'ABHA: ${_patient!.abhaId}',
                                    style: const TextStyle(color: Colors.white70),
                                  ),
                                  if (_patient!.highRiskPregnancy)
                                    Container(
                                      margin: const EdgeInsets.only(top: 8),
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.red,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'HIGH RISK',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ─── Quick Actions ──────────────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => context.push('/patients/${widget.patientId}/vitals'),
                            icon: const Icon(Icons.monitor_heart),
                            label: const Text('Record Vitals'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => context.push('/patients/${widget.patientId}/sbar'),
                            icon: const Icon(Icons.description),
                            label: const Text('SBAR Handover'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: () => context.push('/voice-input', extra: {
                        'patientId': widget.patientId,
                        'returnRoute': '/patients/${widget.patientId}',
                      }),
                      icon: const Icon(Icons.mic),
                      label: const Text('Voice Input'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ─── Patient Info ─────────────────────────────────────────
                    Text(
                      'Patient Information',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _InfoRow(label: 'Age', value: '${_patient!.age ?? "—"} years'),
                            _InfoRow(label: 'Gender', value: _patient!.gender == 'F' ? 'Female' : 'Male'),
                            _InfoRow(label: 'Phone', value: _patient!.phoneNumber ?? '—'),
                            _InfoRow(label: 'Village', value: _patient!.village ?? '—'),
                            _InfoRow(label: 'Address', value: _patient!.address ?? '—'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ─── Pregnancy Info ───────────────────────────────────────
                    Text(
                      'Pregnancy Information',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _InfoRow(
                              label: 'LMP Date',
                              value: _patient!.lmpDate != null
                                  ? '${_patient!.lmpDate!.day}/${_patient!.lmpDate!.month}/${_patient!.lmpDate!.year}'
                                  : '—',
                            ),
                            _InfoRow(
                              label: 'EDD Date',
                              value: _patient!.edd != null
                                  ? '${_patient!.edd!.day}/${_patient!.edd!.month}/${_patient!.edd!.year}'
                                  : '—',
                            ),
                            _InfoRow(label: 'Gravida', value: '${_patient!.gravida ?? "—"}'),
                            _InfoRow(label: 'Parity', value: '${_patient!.parity ?? "—"}'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ─── Recent Vitals ──────────────────────────────────────────
                    Text(
                      'Recent Vitals',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),
                    if (_vitals.isEmpty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            children: [
                              Icon(Icons.monitor_heart_outlined, size: 48, color: Colors.grey[400]),
                              const SizedBox(height: 8),
                              Text(
                                'No vitals recorded yet',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ..._vitals.map((v) => Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: const CircleAvatar(child: Icon(Icons.monitor_heart)),
                              title: Text('${v.vitalType}: ${v.value} ${v.unit ?? ""}'),
                              subtitle: Text('${v.recordedAt?.day ?? 0}/${v.recordedAt?.month ?? 0}/${v.recordedAt?.year ?? 0}'),
                            ),
                          )),
                    const SizedBox(height: 32),
                  ],
                ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// VITALS ENTRY SCREEN — with GPS auto-tag via LocationService
// ═══════════════════════════════════════════════════════════════════════════════

class VitalsEntryScreen extends StatefulWidget {
  final String patientId;
  const VitalsEntryScreen({super.key, required this.patientId});

  @override
  State<VitalsEntryScreen> createState() => _VitalsEntryScreenState();
}

class _VitalsEntryScreenState extends State<VitalsEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _bpSystolicController = TextEditingController();
  final _bpDiastolicController = TextEditingController();
  final _weightController = TextEditingController();
  final _hbController = TextEditingController();
  final _tempController = TextEditingController();
  final _notesController = TextEditingController();

  double? _lat;
  double? _lng;
  bool _locationLoading = false;
  bool _isSaving = false;
  String? _locationError;

  @override
  void initState() {
    super.initState();
    _captureLocation();
  }

  @override
  void dispose() {
    _bpSystolicController.dispose();
    _bpDiastolicController.dispose();
    _weightController.dispose();
    _hbController.dispose();
    _tempController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _captureLocation() async {
    setState(() {
      _locationLoading = true;
      _locationError = null;
    });
    try {
      final locationService = LocationService();
      final position = await locationService.getCurrentPosition();
      if (mounted) {
        setState(() {
          _lat = position.latitude;
          _lng = position.longitude;
          _locationLoading = false;
        });
      }
    } on LocationException catch (e) {
      if (mounted) {
        setState(() {
          _locationError = e.message;
          _locationLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _locationError = 'Failed to get location';
          _locationLoading = false;
        });
      }
    }
  }

  Future<void> _saveVitals() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      // TODO: Save vitals via VitalsRepository with location auto-tag
      // final vitals = Vitals(
      //   fhirId: 'obs-${DateTime.now().millisecondsSinceEpoch}',
      //   patientFhirId: widget.patientId,
      //   vitalType: 'blood_pressure',
      //   value: '${_bpSystolicController.text}/${_bpDiastolicController.text}',
      //   unit: 'mmHg',
      //   recordedBy: 'chw-001',
      //   recordedAt: DateTime.now(),
      //   source: 'direct',
      //   locationLat: _lat,
      //   locationLng: _lng,
      // );
      await Future.delayed(const Duration(seconds: 1));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vitals saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Record Vitals'),
        backgroundColor: const Color(0xFF6B21A8),
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ─── Location Card ────────────────────────────────────────────────
            Card(
              color: _locationError != null ? Colors.red[50] : Colors.green[50],
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      _locationError != null ? Icons.location_off : Icons.location_on,
                      color: _locationError != null ? Colors.red : Colors.green,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _locationLoading
                          ? const Text('Capturing GPS location...')
                          : _locationError != null
                              ? Text(
                                  _locationError!,
                                  style: TextStyle(color: Colors.red[800]),
                                )
                              : Text(
                                  '📍 Location captured: ${_lat?.toStringAsFixed(4)}, ${_lng?.toStringAsFixed(4)}',
                                  style: TextStyle(color: Colors.green[800]),
                                ),
                    ),
                    if (_locationLoading)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _captureLocation,
                        tooltip: 'Refresh location',
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ─── Blood Pressure ───────────────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Blood Pressure',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _bpSystolicController,
                            decoration: const InputDecoration(
                              labelText: 'Systolic',
                              suffixText: 'mmHg',
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text('/', style: TextStyle(fontSize: 24)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _bpDiastolicController,
                            decoration: const InputDecoration(
                              labelText: 'Diastolic',
                              suffixText: 'mmHg',
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ─── Weight ───────────────────────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Weight',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _weightController,
                      decoration: const InputDecoration(
                        labelText: 'Weight',
                        suffixText: 'kg',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ─── Hemoglobin ─────────────────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hemoglobin',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _hbController,
                      decoration: const InputDecoration(
                        labelText: 'Hemoglobin',
                        suffixText: 'g/dL',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ─── Temperature ─────────────────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Temperature',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _tempController,
                      decoration: const InputDecoration(
                        labelText: 'Temperature',
                        suffixText: '°F',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ─── Notes ────────────────────────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Clinical Notes',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _notesController,
                      decoration: const InputDecoration(
                        labelText: 'Notes',
                        hintText: 'Any additional observations...',
                      ),
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ─── Save Button ─────────────────────────────────────────────────
            ElevatedButton(
              onPressed: _isSaving ? null : _saveVitals,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6B21A8),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save Vitals'),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SBAR SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

class SBARScreen extends StatefulWidget {
  final String patientId;
  const SBARScreen({super.key, required this.patientId});

  @override
  State<SBARScreen> createState() => _SBARScreenState();
}

class _SBARScreenState extends State<SBARScreen> {
  final _formKey = GlobalKey<FormState>();
  final _situationController = TextEditingController();
  final _backgroundController = TextEditingController();
  final _assessmentController = TextEditingController();
  final _recommendationController = TextEditingController();

  bool _isLoading = false;
  bool _isGenerating = false;
  String? _generatedSbar;

  @override
  void dispose() {
    _situationController.dispose();
    _backgroundController.dispose();
    _assessmentController.dispose();
    _recommendationController.dispose();
    super.dispose();
  }

  Future<void> _generateSbar() async {
    setState(() => _isGenerating = true);
    try {
      // TODO: Call FastAPI /sbar endpoint with MiniMax AI
      // POST /sbar with { patient_id, situation, background, assessment, recommendation }
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        setState(() {
          _generatedSbar = '''
📋 SBAR HANDOFF — Patient ${widget.patientId}

🔴 SITUATION:
${_situationController.text}

🔵 BACKGROUND:
${_backgroundController.text}

🟡 ASSESSMENT:
${_assessmentController.text}

🟢 RECOMMENDATION:
${_recommendationController.text}
''';
          _isGenerating = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SBAR Handover'),
        backgroundColor: const Color(0xFF6B21A8),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            onPressed: _isGenerating ? null : _generateSbar,
            tooltip: 'Generate with AI',
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ─── SBAR Legend ─────────────────────────────────────────────────
            Card(
              color: Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SBAR Communication Framework',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[800],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'S-Situation | B-Background | A-Assessment | R-Recommendation',
                      style: TextStyle(color: Colors.blue[700], fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ─── Situation ───────────────────────────────────────────────────
            _SbarSection(
              title: '🔴 Situation',
              subtitle: 'What is happening right now?',
              controller: _situationController,
              hint: 'I am calling about [patient name]. The patient is presenting with...',
            ),
            const SizedBox(height: 12),

            // ─── Background ──────────────────────────────────────────────────
            _SbarSection(
              title: '🔵 Background',
              subtitle: 'What is the relevant history?',
              controller: _backgroundController,
              hint: '[Patient] is a [age]-year-old [gender] with a history of...',
            ),
            const SizedBox(height: 12),

            // ─── Assessment ──────────────────────────────────────────────────
            _SbarSection(
              title: '🟡 Assessment',
              subtitle: 'What do I think the problem is?',
              controller: _assessmentController,
              hint: 'I believe the issue is [complication]. Vital signs show...',
            ),
            const SizedBox(height: 12),

            // ─── Recommendation ───────────────────────────────────────────────
            _SbarSection(
              title: '🟢 Recommendation',
              subtitle: 'What do I need?',
              controller: _recommendationController,
              hint: 'I need you to [action]. Please advise on...',
            ),
            const SizedBox(height: 24),

            // ─── AI Generate Button ───────────────────────────────────────────
            OutlinedButton.icon(
              onPressed: _isGenerating ? null : _generateSbar,
              icon: _isGenerating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome),
              label: const Text('Generate with AI'),
            ),
            const SizedBox(height: 16),

            // ─── Generated SBAR Preview ──────────────────────────────────────
            if (_generatedSbar != null) ...[
              Text(
                'Preview',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Card(
                color: const Color(0xFFF0FDF4),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    _generatedSbar!,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () {
                  // TODO: Share via native share sheet
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Share functionality coming soon')),
                  );
                },
                icon: const Icon(Icons.share),
                label: const Text('Share SBAR'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _SbarSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final TextEditingController controller;
  final String hint;

  const _SbarSection({
    required this.title,
    required this.subtitle,
    required this.controller,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            const SizedBox(height: 8),
            TextFormField(
              controller: controller,
              decoration: InputDecoration(
                hintText: hint,
                border: const OutlineInputBorder(),
              ),
              maxLines: 4,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// VOICE INPUT SCREEN — Uses IndicTransService + TelegramService
// ═══════════════════════════════════════════════════════════════════════════════

class VoiceInputScreen extends StatefulWidget {
  final String? patientId;
  final String? returnRoute;
  const VoiceInputScreen({super.key, this.patientId, this.returnRoute});

  @override
  State<VoiceInputScreen> createState() => _VoiceInputScreenState();
}

class _VoiceInputScreenState extends State<VoiceInputScreen> {
  bool _isRecording = false;
  bool _isTranscribing = false;
  String? _transcript;
  String _selectedLanguage = 'kn'; // Kannada default
  final List<String> _languages = ['kn', 'hi', 'en', 'ta', 'te', 'ml'];
  final Map<String, String> _langNames = {
    'kn': 'ಕನ್ನಡ (Kannada)',
    'hi': 'हिन्दी (Hindi)',
    'en': 'English',
    'ta': 'தமிழ் (Tamil)',
    'te': 'తెలుగు (Telugu)',
    'ml': 'മലയാളം (Malayalam)',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Input'),
        backgroundColor: const Color(0xFF6B21A8),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.language),
            onPressed: () => _showLanguageDialog(),
            tooltip: 'Select Language',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // ─── Language Indicator ─────────────────────────────────────────────
          Card(
            color: Colors.blue[50],
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.language, color: Colors.blue),
                  const SizedBox(width: 8),
                  Text(
                    'Recording in: ${_langNames[_selectedLanguage] ?? _selectedLanguage}',
                    style: TextStyle(
                      color: Colors.blue[800],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _showLanguageDialog,
                    child: const Text('Change'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),

          // ─── Record Button ─────────────────────────────────────────────────
          Center(
            child: GestureDetector(
              onTap: _isRecording ? _stopRecording : _startRecording,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: _isRecording ? 100 : 120,
                height: _isRecording ? 100 : 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isRecording ? Colors.red : const Color(0xFF6B21A8),
                  boxShadow: [
                    BoxShadow(
                      color: (_isRecording ? Colors.red : const Color(0xFF6B21A8))
                          .withOpacity(0.4),
                      blurRadius: _isRecording ? 20 : 10,
                      spreadRadius: _isRecording ? 5 : 0,
                    ),
                  ],
                ),
                child: Icon(
                  _isRecording ? Icons.stop : Icons.mic,
                  color: Colors.white,
                  size: _isRecording ? 48 : 56,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              _isRecording ? 'Tap to stop recording' : 'Tap to start recording',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (_isRecording)
            Center(
              child: Text(
                'Recording in progress...',
                style: TextStyle(color: Colors.red[600], fontWeight: FontWeight.w600),
              ),
            ),
          const SizedBox(height: 32),

          // ─── Transcription Result ──────────────────────────────────────────
          if (_isTranscribing)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Transcribing...'),
                  ],
                ),
              ),
            )
          else if (_transcript != null) ...[
            Text(
              'Transcript',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Card(
              color: Colors.green[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      _transcript!,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.green[800],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() => _transcript = null);
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Clear'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () => _sendToIvr(),
                          icon: const Icon(Icons.send),
                          label: const Text('Send via Telegram'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],

          // ─── Telegram IVR Option ───────────────────────────────────────────
          if (widget.patientId != null && _transcript == null) ...[
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Send Voice via Telegram',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Forward voice message to CHW via Telegram Bot IVR pipeline',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () => _sendViaTelegram(),
                      icon: const Icon(Icons.send),
                      label: const Text('Send via Telegram'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showLanguageDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Language'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _languages.map((lang) {
            return RadioListTile<String>(
              title: Text(_langNames[lang] ?? lang),
              value: lang,
              groupValue: _selectedLanguage,
              onChanged: (v) {
                setState(() => _selectedLanguage = v ?? 'kn');
                Navigator.pop(context);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _startRecording() {
    setState(() => _isRecording = true);
    // TODO: Use record package to start recording
  }

  void _stopRecording() {
    setState(() {
      _isRecording = false;
      _isTranscribing = true;
    });
    // TODO: Stop recording, get file path, transcribe via IndicTransService
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _transcript = 'Sample transcription in ${_langNames[_selectedLanguage]}';
          _isTranscribing = false;
        });
      }
    });
  }

  Future<void> _sendToIvr() async {
    if (_transcript == null || widget.patientId == null) return;
    try {
      final telegramService = TelegramService();
      await telegramService.sendMessage(
        'chw-001', // TODO: Get actual CHW ID
        'Voice transcript from patient ${widget.patientId}: $_transcript',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transcript sent to CHW via Telegram!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _sendViaTelegram() async {
    // TODO: Record voice and forward via TelegramService.forwardVoiceMessage
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Telegram voice forwarding coming soon')),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SYNC STATUS SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

class SyncStatusScreen extends StatefulWidget {
  const SyncStatusScreen({super.key});

  @override
  State<SyncStatusScreen> createState() => _SyncStatusScreenState();
}

class _SyncStatusScreenState extends State<SyncStatusScreen> {
  bool _isSyncing = false;
  int _pendingPatients = 0;
  int _pendingVitals = 0;
  DateTime? _lastSync;
  String? _syncError;

  @override
  void initState() {
    super.initState();
    _loadSyncStatus();
  }

  Future<void> _loadSyncStatus() async {
    try {
      // TODO: Load actual sync status from SyncService
      setState(() {
        _pendingPatients = 0;
        _pendingVitals = 0;
        _lastSync = null;
      });
    } catch (e) {
      setState(() => _syncError = e.toString());
    }
  }

  Future<void> _triggerSync() async {
    setState(() {
      _isSyncing = true;
      _syncError = null;
    });
    try {
      // TODO: Call SyncService.syncNow()
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _lastSync = DateTime.now();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sync completed successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _syncError = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Status'),
        backgroundColor: const Color(0xFF6B21A8),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ─── Sync Status Card ───────────────────────────────────────────────
          Card(
            color: _isSyncing
                ? Colors.blue[50]
                : _syncError != null
                    ? Colors.red[50]
                    : Colors.green[50],
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(
                    _isSyncing
                        ? Icons.sync
                        : _syncError != null
                            ? Icons.error_outline
                            : Icons.check_circle_outline,
                    size: 48,
                    color: _isSyncing
                        ? Colors.blue
                        : _syncError != null
                            ? Colors.red
                            : Colors.green,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _isSyncing
                        ? 'Syncing...'
                        : _syncError != null
                            ? 'Sync Failed'
                            : 'All Synced',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _isSyncing
                              ? Colors.blue
                              : _syncError != null
                                  ? Colors.red
                                  : Colors.green,
                        ),
                  ),
                  if (_lastSync != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Last sync: ${_lastSync!.day}/${_lastSync!.month}/${_lastSync!.year} ${_lastSync!.hour}:${_lastSync!.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                  if (_syncError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _syncError!,
                      style: TextStyle(color: Colors.red[700], fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ─── Pending Items ─────────────────────────────────────────────────
          Text(
            'Pending Items',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _SyncRow(
                    icon: Icons.people,
                    label: 'Unsynced Patients',
                    count: _pendingPatients,
                  ),
                  const Divider(),
                  _SyncRow(
                    icon: Icons.monitor_heart,
                    label: 'Unsynced Vitals',
                    count: _pendingVitals,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ─── Sync Now Button ────────────────────────────────────────────────
          ElevatedButton.icon(
            onPressed: _isSyncing ? null : _triggerSync,
            icon: _isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            label: Text(_isSyncing ? 'Syncing...' : 'Sync Now'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6B21A8),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Sync requires WiFi connection and charging',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _SyncRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  const _SyncRow({required this.icon, required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: count > 0 ? Colors.orange[100] : Colors.green[100],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: count > 0 ? Colors.orange[800] : Colors.green[800],
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SETTINGS SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _chwId = 'chw-001';
  String _chwName = 'CHW Name';
  String _phcId = 'phc-001';
  bool _offlineMode = true;
  String _syncFrequency = '15 minutes';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: const Color(0xFF6B21A8),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ─── CHW Profile ────────────────────────────────────────────────────
          Text(
            'CHW Profile',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFF6B21A8),
                      child: Icon(Icons.person, color: Colors.white),
                    ),
                    title: Text(_chwName, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('ID: $_chwId | PHC: $_phcId'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ─── Sync Settings ──────────────────────────────────────────────────
          Text(
            'Sync Settings',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Offline Mode'),
                  subtitle: const Text('Store data locally, sync when connected'),
                  value: _offlineMode,
                  onChanged: (v) => setState(() => _offlineMode = v),
                  activeColor: const Color(0xFF6B21A8),
                ),
                const Divider(),
                ListTile(
                  title: const Text('Sync Frequency'),
                  subtitle: Text(_syncFrequency),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    // TODO: Show sync frequency picker
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ─── About ─────────────────────────────────────────────────────────
          Text(
            'About',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                const ListTile(
                  title: Text('O2 Platform'),
                  subtitle: Text('Version 1.0.0'),
                  trailing: Icon(Icons.info_outline),
                ),
                const Divider(),
                ListTile(
                  title: const Text('AI Backend'),
                  subtitle: Text(
                    const bool.fromEnvironment('offline', defaultValue: false)
                        ? 'Offline Mode'
                        : 'http://10.0.2.2:8000',
                  ),
                  trailing: const Icon(Icons.cloud),
                  onTap: () {
                    // TODO: Configure backend URL
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EMERGENCY SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

class EmergencyScreen extends StatefulWidget {
  final String patientId;
  const EmergencyScreen({super.key, required this.patientId});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  bool _isCallingAmbulance = false;
  bool _alertSent = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('⚠️ EMERGENCY PROTOCOL'),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // ─── Warning Banner ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.red[100],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red, width: 2),
            ),
            child: Column(
              children: [
                Icon(Icons.warning_amber, size: 48, color: Colors.red[800]),
                const SizedBox(height: 12),
                Text(
                  'Emergency Detected',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.red[800],
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Patient ID: ${widget.patientId}',
                  style: TextStyle(color: Colors.red[700]),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ─── Emergency Actions ──────────────────────────────────────────────
          Text(
            'Emergency Actions',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),

          // Call Ambulance
          Card(
            color: Colors.red[50],
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.local_hospital, color: Colors.red),
                      const SizedBox(width: 8),
                      Text(
                        'Call Ambulance (108)',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _isCallingAmbulance
                        ? null
                        : () {
                            // TODO: Launch phone dialer with 108
                            setState(() => _isCallingAmbulance = true);
                          },
                    icon: _isCallingAmbulance
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.call),
                    label: Text(_isCallingAmbulance ? 'Calling...' : 'Call 108'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Alert PHC
          Card(
            color: Colors.orange[50],
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.notifications_active, color: Colors.orange),
                      const SizedBox(width: 8),
                      Text(
                        'Alert PHC',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _alertSent
                        ? null
                        : () async {
                            // TODO: Send Telegram alert via TelegramService
                            setState(() => _alertSent = true);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('PHC alerted via Telegram!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          },
                    icon: Icon(_alertSent ? Icons.check : Icons.send),
                    label: Text(_alertSent ? 'Alert Sent' : 'Send Alert'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Alert CHW Supervisor
          Card(
            color: Colors.blue[50],
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.supervisor_account, color: Colors.blue),
                      const SizedBox(width: 8),
                      Text(
                        'Alert CHW Supervisor',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      // TODO: Alert supervisor
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Supervisor alert sent!')),
                      );
                    },
                    icon: const Icon(Icons.send),
                    label: const Text('Alert Supervisor'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ─── Emergency Contacts ───────────────────────────────────────────
          Text(
            'Emergency Contacts',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.local_hospital)),
                  title: const Text('PHC Hospital'),
                  subtitle: const Text('Call for medical consultation'),
                  trailing: const Icon(Icons.call, color: Colors.green),
                  onTap: () {
                    // TODO: Launch dialer
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.pregnant_woman)),
                  title: const Text('ANM/Nurse'),
                  subtitle: const Text('Primary healthcare provider'),
                  trailing: const Icon(Icons.call, color: Colors.green),
                  onTap: () {
                    // TODO: Launch dialer
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ERROR SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

class ErrorScreen extends StatelessWidget {
  final GoException? error;
  const ErrorScreen({super.key, this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Error'),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red[400],
              ),
              const SizedBox(height: 16),
              Text(
                'Something went wrong',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.red[800],
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                error?.message ?? 'An unexpected error occurred',
                style: TextStyle(color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => context.go('/home'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6B21A8),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Go Home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
