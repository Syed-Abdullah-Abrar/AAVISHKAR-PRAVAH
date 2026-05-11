/// ABDM Service — O2 Platform CHW App
/// 
/// Mock implementations of ABDM (Ayushman Bharat Digital Mission) APIs.
/// Phase 1: All methods return mock data with documented contracts.
/// Phase 2: Replace with real HTTP calls to ABDM APIs.
/// 
/// ABDM APIs:
/// - HPR: Healthcare Professionals Registry (verify CHW)
/// - HFR: Health Facility Registry (link clinic)
/// - ABHA: Ayushman Bharat Health Account (validate patient ABHA ID)
/// 
/// ABDM Reference: https://abdm.gov.in/

/// HPR Verification Result
class HprVerificationResult {
  final bool verified;
  final String? workerName;
  final String? workerId;
  final String? error;

  const HprVerificationResult({
    required this.verified,
    this.workerName,
    this.workerId,
    this.error,
  });

  factory HprVerificationResult.mock({String? name}) {
    return HprVerificationResult(
      verified: true,
      workerName: name ?? 'Test Worker',
      workerId: 'HPR-TEST-001',
    );
  }
}

/// HFR Link Result
class HfrLinkResult {
  final bool linked;
  final String? facilityName;
  final String? facilityId;
  final String? error;

  const HfrLinkResult({
    required this.linked,
    this.facilityName,
    this.facilityId,
    this.error,
  });

  factory HfrLinkResult.mock({String? name}) {
    return HfrLinkResult(
      linked: true,
      facilityName: name ?? 'Test PHC',
      facilityId: 'HFR-TEST-001',
    );
  }
}

/// ABHA Validation Result
class AbhaValidationResult {
  final bool valid;
  final String? abhaId;
  final String? error;

  const AbhaValidationResult({
    required this.valid,
    this.abhaId,
    this.error,
  });

  factory AbhaValidationResult.valid(String id) {
    return AbhaValidationResult(valid: true, abhaId: id);
  }

  factory AbhaValidationResult.invalid(String error) {
    return AbhaValidationResult(valid: false, error: error);
  }
}

/// ABDM Service
/// 
/// Mock ABDM compliance layer for Phase 1.
/// 
/// Usage:
/// ```dart
/// final abdm = AbdmService();
/// 
/// // Verify CHW on HPR
/// final hpr = await abdm.verifyHpr('HPR-12345');
/// 
/// // Link clinic on HFR
/// final hfr = await abdm.linkHfr('HFR-67890');
/// 
/// // Validate ABHA ID
/// final abha = await abdm.validateAbhaId('12-3456-7890-1234');
/// ```
class AbdmService {
  /// Verify Healthcare Professional on HPR
  /// 
  /// ABDM API Contract (Phase 2):
  /// POST /v3/prm/doctors/{hpId}
  /// Headers: Authorization: Bearer <token>
  /// Response: { hpId, name, verified, status }
  Future<HprVerificationResult> verifyHpr(String workerId) async {
    // Phase 1: Mock implementation
    // Simulates network delay
    await Future.delayed(const Duration(milliseconds: 100));
    
    // Always return verified in Phase 1
    return HprVerificationResult.mock(
      name: 'ASHA Worker',
    );
  }

  /// Link Health Facility on HFR
  /// 
  /// ABDM API Contract (Phase 2):
  /// POST /v3/facilities/{facilityId}/link
  /// Headers: Authorization: Bearer <token>
  /// Response: { facilityId, linked, status }
  Future<HfrLinkResult> linkHfr(String facilityId) async {
    // Phase 1: Mock implementation
    await Future.delayed(const Duration(milliseconds: 100));
    
    return HfrLinkResult.mock(
      name: 'Primary Health Centre',
    );
  }

  /// Validate ABHA ID checksum
  /// 
  /// ABDM ABHA ID Format: XX-XXXX-XXXX-XXXX
  /// Last digit is checksum using Mod 97 algorithm
  /// 
  /// ABDM API Contract (Phase 2):
  /// POST /v3/hip/links/discover
  /// Headers: Authorization: Bearer <token>
  /// Body: { healthId: "XX-XXXX-XXXX-XXXX" }
  Future<AbhaValidationResult> validateAbhaId(String abhaId) async {
    // Phase 1: Local checksum validation only
    
    // Basic format check
    if (!_isValidFormat(abhaId)) {
      return AbhaValidationResult.invalid('Invalid ABHA format');
    }
    
    // Checksum validation (Mod 97)
    if (!_validateChecksum(abhaId)) {
      return AbhaValidationResult.invalid('Invalid ABHA checksum');
    }
    
    return AbhaValidationResult.valid(abhaId);
  }

  bool _isValidFormat(String abhaId) {
    // Format: XX-XXXX-XXXX-XXXX (14 digits + 3 dashes)
    final regex = RegExp(r'^\d{2}-\d{4}-\d{4}-\d{4}$');
    return regex.hasMatch(abhaId);
  }

  bool _validateChecksum(String abhaId) {
    // ABDM checksum: Mod 97 algorithm
    // Remove dashes
    final digits = abhaId.replaceAll('-', '');
    if (digits.length != 14) return false;
    
    try {
      // Mod 97 check
      final number = int.parse(digits);
      return number % 97 == 1;
    } catch (_) {
      return false;
    }
  }
}

/// Singleton
final abdmService = AbdmService();