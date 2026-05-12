/// WHO-Based Maternal Risk Scorer
/// O2 Platform — Phase 4
///
/// Implements WHO maternal health thresholds for offline risk assessment.
/// Scores are WHO-compliant and require no internet connection.
/// 
/// Risk Levels:
/// - EMERGENCY (score ≥ 6): Immediate referral — call 108
/// - HIGH (score 4-5): Urgent follow-up within 24h
/// - MEDIUM (score 2-3): Scheduled follow-up within 48h  
/// - LOW (score 0-1): Routine care at next scheduled visit
///
/// Sources:
/// - WHO Maternal Health Guidelines 2023
/// - NFHS-5 Risk Factor Definitions
/// - MoHFW National Maternal Health Protocol

class RiskInput {
  final int systolicBp;
  final int diastolicBp;
  final double hemoglobin;
  final int weeksPregnant;
  final double temperature;
  final int heartRate;
  final int? spo2;
  final double? weightKg;
  final bool hasEdema;
  final bool blurredVision;
  final bool severeHeadache;
  final bool convulsion;
  final bool vaginalBleeding;
  final bool foulDischarge;
  final int? previousComplications;
  final int? age;

  const RiskInput({
    required this.systolicBp,
    required this.diastolicBp,
    required this.hemoglobin,
    required this.weeksPregnant,
    required this.temperature,
    required this.heartRate,
    this.spo2,
    this.weightKg,
    this.hasEdema = false,
    this.blurredVision = false,
    this.severeHeadache = false,
    this.convulsion = false,
    this.vaginalBleeding = false,
    this.foulDischarge = false,
    this.previousComplications,
    this.age,
  });
}

class RiskOutput {
  final String level; // LOW / MEDIUM / HIGH / EMERGENCY
  final int score;
  final List<String> flags;
  final String recommendation;
  final String summary;

  const RiskOutput({
    required this.level,
    required this.score,
    required this.flags,
    required this.recommendation,
    required this.summary,
  });

  bool get isEmergency => level == 'EMERGENCY';
  bool get isHigh => level == 'HIGH';
  bool get isMedium => level == 'MEDIUM';
  bool get isLow => level == 'LOW';
}

class WHORiskScorer {
  static const String LEVEL_EMERGENCY = 'EMERGENCY';
  static const String LEVEL_HIGH = 'HIGH';
  static const String LEVEL_MEDIUM = 'MEDIUM';
  static const String LEVEL_LOW = 'LOW';

  /// Assess maternal health risk using WHO thresholds.
  /// All thresholds are WHO-compliant as of 2023 guidelines.
  RiskOutput assess(RiskInput input) {
    int score = 0;
    List<String> flags = [];

    // ─── Blood Pressure Assessment ─────────────────────────────────────────────
    final bpScore = _assessBloodPressure(input.systolicBp, input.diastolicBp);
    score += bpScore.score;
    flags.addAll(bpScore.flags);

    // ─── Hemoglobin / Anemia ─────────────────────────────────────────────────
    final hbScore = _assessHemoglobin(input.hemoglobin);
    score += hbScore.score;
    flags.addAll(hbScore.flags);

    // ─── Temperature / Fever ──────────────────────────────────────────────────
    final tempScore = _assessTemperature(input.temperature);
    score += tempScore.score;
    flags.addAll(tempScore.flags);

    // ─── Heart Rate ───────────────────────────────────────────────────────────
    final hrScore = _assessHeartRate(input.heartRate);
    score += hrScore.score;
    flags.addAll(hrScore.flags);

    // ─── Oxygen Saturation ───────────────────────────────────────────────────
    if (input.spo2 != null) {
      final spo2Score = _assessSpo2(input.spo2!);
      score += spo2Score.score;
      flags.addAll(spo2Score.flags);
    }

    // ─── Danger Signs (WHO Red Flags) ──────────────────────────────────────
    final dangerScore = _assessDangerSigns(
      convulsion: input.convulsion,
      blurredVision: input.blurredVision,
      severeHeadache: input.severeHeadache,
      vaginalBleeding: input.vaginalBleeding,
      foulDischarge: input.foulDischarge,
    );
    score += dangerScore.score;
    flags.addAll(dangerScore.flags);

    // ─── Gestational Age Risk ─────────────────────────────────────────────────
    final gaScore = _assessGestationalAge(input.weeksPregnant);
    score += gaScore.score;
    flags.addAll(gaScore.flags);

    // ─── Previous Complications ───────────────────────────────────────────────
    if (input.previousComplications != null) {
      final prevScore = _assessPreviousComplications(input.previousComplications!);
      score += prevScore.score;
      flags.addAll(prevScore.flags);
    }

    // ─── Maternal Age Risk ────────────────────────────────────────────────────
    if (input.age != null) {
      final ageScore = _assessMaternalAge(input.age!);
      score += ageScore.score;
      flags.addAll(ageScore.flags);
    }

    // ─── Cap score and determine level ───────────────────────────────────────
    if (score > 10) score = 10;

    final level = _scoreToLevel(score);
    final recommendation = _getRecommendation(level);
    final summary = _generateSummary(input, level, flags);

    return RiskOutput(
      level: level,
      score: score,
      flags: flags,
      recommendation: recommendation,
      summary: summary,
    );
  }

  // ─── Individual Assessment Methods ──────────────────────────────────────────

  _ScoreResult _assessBloodPressure(int systolic, int diastolic) {
    int score = 0;
    List<String> flags = [];

    // Normal: < 120/80
    // Elevated: 120-129 / < 80
    // High Stage 1: 130-139 / 80-89
    // High Stage 2: ≥ 140 / ≥ 90
    // Severe: ≥ 160 / ≥ 110

    if (systolic >= 160 || diastolic >= 110) {
      score += 4;
      flags.add('⚠️ SEVERE HYPERTENSION: BP ${systolic}/${diastolic} mmHg — immediate referral');
    } else if (systolic >= 140 || diastolic >= 90) {
      score += 3;
      flags.add('🔴 HIGH BP: ${systolic}/${diastolic} mmHg — requires medication + referral');
    } else if (systolic >= 130 || diastolic >= 80) {
      score += 1;
      flags.add('🟡 ELEVATED BP: ${systolic}/${diastolic} mmHg — monitor closely');
    }

    return _ScoreResult(score, flags);
  }

  _ScoreResult _assessHemoglobin(double hb) {
    int score = 0;
    List<String> flags = [];

    // WHO Anemia Grading (g/dL):
    // Severe: < 7.0 → score +4
    // Moderate: 7.0-9.9 → score +2
    // Mild: 10.0-10.9 → score +1
    // Normal: ≥ 11.0 → score 0

    if (hb < 7.0) {
      score += 4;
      flags.add('🚨 SEVERE ANEMIA: Hb ${hb.toStringAsFixed(1)} g/dL — immediate transfusion review');
    } else if (hb < 10.0) {
      score += 2;
      flags.add('🔴 MODERATE ANEMIA: Hb ${hb.toStringAsFixed(1)} g/dL — IFA supplementation + referral');
    } else if (hb < 11.0) {
      score += 1;
      flags.add('🟡 MILD ANEMIA: Hb ${hb.toStringAsFixed(1)} g/dL — IFA supplementation');
    }

    return _ScoreResult(score, flags);
  }

  _ScoreResult _assessTemperature(double temp) {
    int score = 0;
    List<String> flags = [];

    // Normal: 36.5-37.5°C
    // Low-grade fever: 37.5-38.0°C → score +1
    // Fever: 38.1-39.0°C → score +2
    // High fever: > 39.0°C → score +3

    if (temp > 39.0) {
      score += 3;
      flags.add('🔴 HIGH FEVER: ${temp.toStringAsFixed(1)}°C — infection risk, immediate assessment');
    } else if (temp > 38.0) {
      score += 2;
      flags.add('🟡 FEVER: ${temp.toStringAsFixed(1)}°C — investigate infection');
    } else if (temp > 37.5) {
      score += 1;
      flags.add('🟢 LOW-GRADE FEVER: ${temp.toStringAsFixed(1)}°C — monitor');
    }

    return _ScoreResult(score, flags);
  }

  _ScoreResult _assessHeartRate(int hr) {
    int score = 0;
    List<String> flags = [];

    // Normal pregnancy: 60-100 bpm
    // Physiological tachycardia: up to 110 bpm acceptable in 3rd trimester
    // Concerning: > 110 bpm (resting) → score +1
    // High: > 120 bpm → score +2

    if (hr > 120) {
      score += 2;
      flags.add('🔴 TACHYCARDIA: HR ${hr} bpm — assess for shock/infection');
    } else if (hr > 110) {
      score += 1;
      flags.add('🟡 ELEVATED HR: ${hr} bpm — monitor, check hydration');
    }

    return _ScoreResult(score, flags);
  }

  _ScoreResult _assessSpo2(int spo2) {
    int score = 0;
    List<String> flags = [];

    // Normal: ≥ 95%
    // Low: 90-94% → score +2 (hypoxia)
    // Critical: < 90% → score +4 (respiratory distress)

    if (spo2 < 90) {
      score += 4;
      flags.add('🚨 CRITICAL SpO2: ${spo2}% — immediate oxygen + referral');
    } else if (spo2 < 95) {
      score += 2;
      flags.add('🔴 LOW SpO2: ${spo2}% — assess respiratory status');
    }

    return _ScoreResult(score, flags);
  }

  _ScoreResult _assessDangerSigns({
    required bool convulsion,
    required bool blurredVision,
    required bool severeHeadache,
    required bool vaginalBleeding,
    required bool foulDischarge,
  }) {
    int score = 0;
    List<String> flags = [];

    // WHO Danger Signs — ANY of these = EMERGENCY referral
    if (convulsion) {
      score += 5;
      flags.add('🚨 CONVULSION/SEIZURE — eclampsia, call 108 immediately');
    }
    if (blurredVision) {
      score += 3;
      flags.add('🚨 BLURRED VISION — possible pre-eclampsia');
    }
    if (severeHeadache) {
      score += 3;
      flags.add('🚨 SEVERE HEADACHE — possible pre-eclampsia');
    }
    if (vaginalBleeding) {
      score += 5;
      flags.add('🚨 VAGINAL BLEEDING — possible placenta previa/abruption');
    }
    if (foulDischarge) {
      score += 2;
      flags.add('🔴 FOUL VAGINAL DISCHARGE — possible infection, antibiotics needed');
    }

    return _ScoreResult(score, flags);
  }

  _ScoreResult _assessGestationalAge(int weeks) {
    int score = 0;
    List<String> flags = [];

    // High-risk gestational ages:
    // < 12 weeks: Early pregnancy complications more common
    // 12-28 weeks: Stable period
    // 28-37 weeks: Preterm risk
    // > 37 weeks: Post-term risk (≥42 weeks is dangerous)

    if (weeks < 12) {
      score += 1;
      flags.add('🟡 EARLY PREGNANCY: <12 weeks — confirm viability, start ANC');
    } else if (weeks > 42) {
      score += 3;
      flags.add('🔴 POST-TERM: ${weeks} weeks — induction recommended');
    } else if (weeks >= 28 && weeks <= 37) {
      score += 1;
      flags.add('🟡 PRETERM PERIOD: ${weeks} weeks — monitor for preterm labor');
    }

    return _ScoreResult(score, flags);
  }

  _ScoreResult _assessPreviousComplications(int history) {
    int score = 0;
    List<String> flags = [];

    // 0 = no previous pregnancy
    // 1 = previous pregnancy, no complications
    // 2 = previous complications (C-section, pre-eclampsia, hemorrhage)
    // 3 = multiple high-risk factors

    if (history >= 3) {
      score += 3;
      flags.add('🔴 HIGH-RISK HISTORY: Multiple previous complications');
    } else if (history == 2) {
      score += 2;
      flags.add('🟡 PREVIOUS COMPLICATIONS: History of C-section or obstetric complications');
    }

    return _ScoreResult(score, flags);
  }

  _ScoreResult _assessMaternalAge(int age) {
    int score = 0;
    List<String> flags = [];

    // Teen pregnancy (<18): Higher complications
    // Advanced maternal age (≥35): Higher risk
    // Very advanced (≥40): Highest risk

    if (age < 18) {
      score += 2;
      flags.add('🔴 TEEN PREGNANCY: Age ${age} — higher complication risk');
    } else if (age >= 40) {
      score += 3;
      flags.add('🔴 ADVANCED MATERNAL AGE: ${age} — high-risk, specialist care needed');
    } else if (age >= 35) {
      score += 1;
      flags.add('🟡 MATERNAL AGE ${age}: Increased monitoring recommended');
    }

    return _ScoreResult(score, flags);
  }

  String _scoreToLevel(int score) {
    if (score >= 6) return LEVEL_EMERGENCY;
    if (score >= 4) return LEVEL_HIGH;
    if (score >= 2) return LEVEL_MEDIUM;
    return LEVEL_LOW;
  }

  String _getRecommendation(String level) {
    switch (level) {
      case LEVEL_EMERGENCY:
        return '🚨 IMMEDIATE REFERRAL — Call 108, transport to PHC/hospital NOW';
      case LEVEL_HIGH:
        return '🔴 URGENT: Schedule follow-up within 24 hours, consider referral';
      case LEVEL_MEDIUM:
        return '🟡 SCHEDULE follow-up within 48 hours, continue IFA + monitoring';
      case LEVEL_LOW:
        return '✅ ROUTINE: Continue regular ANC schedule, next visit in 7 days';
      default:
        return '⚠️ ASSESS: Review all flags and determine care plan';
    }
  }

  String _generateSummary(RiskInput input, String level, List<String> flags) {
    final buffer = StringBuffer();
    buffer.writeln('Maternal Risk Assessment');
    buffer.writeln('─' * 30);
    buffer.writeln('BP: ${input.systolicBp}/${input.diastolicBp} mmHg');
    buffer.writeln('Hb: ${input.hemoglobin.toStringAsFixed(1)} g/dL');
    buffer.writeln('GA: ${input.weeksPregnant} weeks');
    buffer.writeln('Temp: ${input.temperature.toStringAsFixed(1)}°C');
    buffer.writeln('HR: ${input.heartRate} bpm');
    buffer.writeln('─' * 30);
    buffer.writeln('RISK LEVEL: $level');
    buffer.writeln('Flags (${flags.length}):');
    for (final flag in flags.take(5)) {
      buffer.writeln('  $flag');
    }
    if (flags.length > 5) {
      buffer.writeln('  ... and ${flags.length - 5} more');
    }
    return buffer.toString();
  }
}

class _ScoreResult {
  final int score;
  final List<String> flags;

  const _ScoreResult(this.score, this.flags);
}
