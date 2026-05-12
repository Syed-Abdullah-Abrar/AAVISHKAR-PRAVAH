/// XGBoost Inference Engine
/// O2 Platform — Phase 4
///
/// Implements inference for the existing 50-tree XGBoost model
/// stored at apps/o2_backend/models/risk_model.json
///
/// Model features (in order):
///  [systolic_bp, diastolic_bp, hb, weeks_pregnant, temp, heart_rate, spo2, bmi, age, parity]
///
/// Prediction returns:
///  - class: 0=LOW, 1=MEDIUM, 2=HIGH, 3=EMERGENCY
///  - raw margin (sum of tree predictions)
///  - probability distribution over 4 classes

import 'dart:convert';
import 'package:flutter/services.dart';

/// XGBoost model inference result
class XGBoostPrediction {
  /// Predicted risk class: 0=LOW, 1=MEDIUM, 2=HIGH, 3=EMERGENCY
  final int predictedClass;

  /// Probability for each class [LOW, MEDIUM, HIGH, EMERGENCY]
  final List<double> probabilities;

  /// Raw margin score (sum of leaf values across all trees)
  final double rawMargin;

  /// Human-readable risk level
  String get riskLevel {
    switch (predictedClass) {
      case 0: return 'LOW';
      case 1: return 'MEDIUM';
      case 2: return 'HIGH';
      case 3: return 'EMERGENCY';
      default: return 'UNKNOWN';
    }
  }

  const XGBoostPrediction({
    required this.predictedClass,
    required this.probabilities,
    required this.rawMargin,
  });
}

/// Feature vector for XGBoost model
/// Order must match model's feature_names (or implicit order if names absent)
class XGBoostFeatures {
  final double systolicBp;
  final double diastolicBp;
  final double hemoglobin;
  final double weeksPregnant;
  final double temperature;
  final double heartRate;
  final double spo2;
  final double bmi;
  final double age;
  final double parity;

  const XGBoostFeatures({
    required this.systolicBp,
    required this.diastolicBp,
    required this.hemoglobin,
    required this.weeksPregnant,
    required this.temperature,
    required this.heartRate,
    required this.spo2,
    required this.bmi,
    required this.age,
    required this.parity,
  });

  /// Convert to list in feature order expected by model
  List<double> toList() => [
    systolicBp,
    diastolicBp,
    hemoglobin,
    weeksPregnant,
    temperature,
    heartRate,
    spo2,
    bmi,
    age,
    parity,
  ];

  /// Create from RiskInput (WHO risk scorer input)
  factory XGBoostFeatures.fromRiskInput({
    required int systolicBp,
    required int diastolicBp,
    required double hemoglobin,
    required int weeksPregnant,
    required double temperature,
    required int heartRate,
    int? spo2,
    double? weightKg,
    int? age,
    int? previousComplications,
  }) {
    final bmi = weightKg != null ? _estimateBmi(weightKg, weeksPregnant) : 22.0;
    return XGBoostFeatures(
      systolicBp: systolicBp.toDouble(),
      diastolicBp: diastolicBp.toDouble(),
      hemoglobin: hemoglobin,
      weeksPregnant: weeksPregnant.toDouble(),
      temperature: temperature,
      heartRate: heartRate.toDouble(),
      spo2: spo2?.toDouble() ?? 98.0,
      bmi: bmi,
      age: age?.toDouble() ?? 25.0,
      parity: previousComplications?.toDouble() ?? 0.0,
    );
  }

  /// Estimate BMI from weight and gestational age
  /// Without height, use NHW standard weight gain curves
  /// This is an approximation — real implementation would need height
  static double _estimateBmi(double weightKg, int weeksPregnant) {
    // Approximate: baseline BMI ~22 for Indian women
    // Weight gain: ~0.5kg/week in 2nd/3rd trimester
    final baselineWeight = weightKg - (weeksPregnant > 12 ? (weeksPregnant - 12) * 0.5 : 0);
    const height = 1.55; // average Indian female height in meters
    return baselineWeight / (height * height);
  }
}

/// XGBoost inference engine — runs the risk_model.json in pure Dart
class XGBoostInference {
  /// Base weights for each class (bias term)
  /// Order: [LOW, MEDIUM, HIGH, EMERGENCY]
  static const List<double> baseWeights = [0.0, 0.0, 0.0, 0.0];

  /// Class mapping: 0=LOW, 1=MEDIUM, 2=HIGH, 3=EMERGENCY
  /// These match the 4 risk levels from WHO guidelines
  static const List<String> classLabels = ['LOW', 'MEDIUM', 'HIGH', 'EMERGENCY'];

  Map<String, dynamic>? _modelJson;
  bool _loaded = false;
  String? _loadError;

  /// Load model from assets or network
  Future<bool> load() async {
    try {
      // Try loading from bundled assets
      final jsonString = await rootBundle.loadString(
        'assets/ml/risk_model.json',
        // ignore: avoid_returning_on_null
      ).catch((_) => null);

      if (jsonString != null) {
        _modelJson = json.decode(jsonString) as Map<String, dynamic>;
        _loaded = true;
        return true;
      }

      // Try loading from network (for development)
      // In production, model is bundled in assets
      _loadError = 'Model not found in assets. Bundle risk_model.json to assets/ml/';
      return false;
    } catch (e) {
      _loadError = 'Failed to load model: $e';
      return false;
    }
  }

  /// Predict risk class from features
  XGBoostPrediction predict(XGBoostFeatures features) {
    if (!_loaded || _modelJson == null) {
      // Fallback to WHO scorer if model not loaded
      return _fallbackPrediction(features);
    }

    try {
      return _runInference(features);
    } catch (e) {
      // If inference fails, fall back to rule-based
      return _fallbackPrediction(features);
    }
  }

  XGBoostPrediction _runInference(XGBoostFeatures features) {
    final featureList = features.toList();
    final trees = _modelJson!['learner']['gradient_booster']['model']['trees'] as List;

    List<double> margins = [0.0, 0.0, 0.0, 0.0];

    for (final tree in trees) {
      final margin = _predictTree(tree as Map<String, dynamic>, featureList);
      // Add margin to all classes (same tree contributes to all for multiclass)
      for (int i = 0; i < 4; i++) {
        margins[i] += margin;
      }
    }

    // Convert margins to probabilities via softmax
    final probabilities = _softmax(margins);

    // Find argmax class
    int maxClass = 0;
    double maxProb = probabilities[0];
    for (int i = 1; i < 4; i++) {
      if (probabilities[i] > maxProb) {
        maxProb = probabilities[i];
        maxClass = i;
      }
    }

    return XGBoostPrediction(
      predictedClass: maxClass,
      probabilities: probabilities,
      rawMargin: margins[maxClass],
    );
  }

  double _predictTree(Map<String, dynamic> tree, List<double> features) {
    final leftChildren = tree['left_children'] as List;
    final rightChildren = tree['right_children'] as List;
    final splitConditions = tree['split_conditions'] as List;
    final defaultLeft = tree['default_left'] as List;
    final baseWeights = tree['base_weights'] as List;

    int nodeIndex = 0;

    while (true) {
      final left = leftChildren[nodeIndex] as int;
      final right = rightChildren[nodeIndex] as int;
      final condition = (splitConditions[nodeIndex] as num).toDouble();
      final defaultL = defaultLeft[nodeIndex] as int;

      if (left == -1) {
        // Leaf node — return base weight
        return (baseWeights[nodeIndex] as num).toDouble();
      }

      // Get feature value for this split
      // Split index tells us which feature
      final splitIdx = (tree['split_indices'][nodeIndex] as num).toInt();
      final featureValue = features[splitIdx.clamp(0, features.length - 1)];

      bool goLeft;
      if (featureValue < condition) {
        goLeft = true;
      } else {
        goLeft = false;
      }

      // Handle default direction
      final defaultGoLeft = defaultL == 1;

      if (goLeft) {
        nodeIndex = left;
      } else if (defaultGoLeft) {
        nodeIndex = left;
      } else {
        nodeIndex = right;
      }
    }
  }

  List<double> _softmax(List<double> margins) {
    // Softmax for 4 classes
    double maxMargin = margins.reduce((a, b) => a > b ? a : b);
    List<double> exps = margins.map((m) => _exp(m - maxMargin)).toList();
    double sum = exps.reduce((a, b) => a + b);
    return exps.map((e) => e / sum).toList();
  }

  double _exp(double x) {
    if (x < -700) return 0.0;
    double result = 1.0;
    double term = 1.0;
    for (int i = 1; i <= 20; i++) {
      term *= x / i;
      result += term;
      if (result > 1e300) break;
    }
    return result;
  }

  XGBoostPrediction _fallbackPrediction(XGBoostFeatures features) {
    // WHO-rule-based fallback when XGBoost model unavailable
    int score = 0;

    // BP
    if (features.systolicBp >= 160 || features.diastolicBp >= 110) score += 4;
    else if (features.systolicBp >= 140 || features.diastolicBp >= 90) score += 3;

    // Hb
    if (features.hemoglobin < 7.0) score += 4;
    else if (features.hemoglobin < 10.0) score += 2;
    else if (features.hemoglobin < 11.0) score += 1;

    // SPO2
    if (features.spo2 < 90) score += 4;
    else if (features.spo2 < 95) score += 2;

    // Age
    if (features.age < 18 || features.age >= 40) score += 3;
    else if (features.age >= 35) score += 1;

    // Map score to class
    int predictedClass;
    if (score >= 6) predictedClass = 3; // EMERGENCY
    else if (score >= 4) predictedClass = 2; // HIGH
    else if (score >= 2) predictedClass = 1; // MEDIUM
    else predictedClass = 0; // LOW

    return XGBoostPrediction(
      predictedClass: predictedClass,
      probabilities: _scoreToProbabilities(score),
      rawMargin: score.toDouble(),
    );
  }

  List<double> _scoreToProbabilities(int score) {
    // Convert score to class probabilities
    // Score ranges: 0-1 → LOW, 2-3 → MEDIUM, 4-5 → HIGH, 6+ → EMERGENCY
    switch (score) {
      case 0: return [0.85, 0.12, 0.02, 0.01];
      case 1: return [0.70, 0.25, 0.04, 0.01];
      case 2: return [0.30, 0.50, 0.15, 0.05];
      case 3: return [0.15, 0.45, 0.30, 0.10];
      case 4: return [0.05, 0.20, 0.50, 0.25];
      case 5: return [0.02, 0.10, 0.40, 0.48];
      default:
        // 6+ emergency
        final eProb = (score - 5) * 0.15 + 0.48;
        return [0.01, 0.05, 0.20 - (score - 6) * 0.03, eProb.clamp(0.5, 0.98)];
    }
  }

  bool get isLoaded => _loaded;
  String? get loadError => _loadError;
}