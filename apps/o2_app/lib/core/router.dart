import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app.dart';
import '../models/patient.dart';
import '../models/vitals.dart';
import '../repositories/patient_repository.dart';
import '../repositories/vitals_repository.dart';

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

/// ─── Placeholder Screens (to be implemented with full UI) ─────────────────────

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('O2 Platform')),
      body: const Center(child: Text('Home Screen — Coming Soon')),
    );
  }
}

class PatientListScreen extends StatelessWidget {
  const PatientListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Patients')),
      body: const Center(child: Text('Patient List — Coming Soon')),
    );
  }
}

class PatientRegistrationScreen extends StatelessWidget {
  const PatientRegistrationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register Patient')),
      body: const Center(child: Text('Registration Form — Coming Soon')),
    );
  }
}

class PatientDetailScreen extends StatelessWidget {
  final String patientId;
  const PatientDetailScreen({super.key, required this.patientId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Patient Details')),
      body: Center(child: Text('Patient ID: $patientId')),
    );
  }
}

class VitalsEntryScreen extends StatelessWidget {
  final String patientId;
  const VitalsEntryScreen({super.key, required this.patientId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Record Vitals')),
      body: Center(child: Text('Vitals for: $patientId')),
    );
  }
}

class SBARScreen extends StatelessWidget {
  final String patientId;
  const SBARScreen({super.key, required this.patientId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SBAR Handover')),
      body: Center(child: Text('SBAR for: $patientId')),
    );
  }
}

class VoiceInputScreen extends StatelessWidget {
  final String? patientId;
  final String? returnRoute;
  const VoiceInputScreen({super.key, this.patientId, this.returnRoute});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Voice Input')),
      body: const Center(child: Text('Voice Widget — Coming Soon')),
    );
  }
}

class SyncStatusScreen extends StatelessWidget {
  const SyncStatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sync Status')),
      body: const Center(child: Text('Sync Dashboard — Coming Soon')),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: const Center(child: Text('Settings — Coming Soon')),
    );
  }
}

class EmergencyScreen extends StatelessWidget {
  final String patientId;
  const EmergencyScreen({super.key, required this.patientId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('⚠️ EMERGENCY')),
      body: Center(child: Text('Emergency Protocol: $patientId')),
    );
  }
}

class ErrorScreen extends StatelessWidget {
  final GoException? error;
  const ErrorScreen({super.key, this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Error')),
      body: Center(child: Text('Error: ${error?.message ?? "Unknown"}')),
    );
  }
}