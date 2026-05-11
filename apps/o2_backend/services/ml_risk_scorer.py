"""
XGBoost Shadow ML Risk Scorer — O2 Platform Phase 2

Runs XGBoost model in shadow mode alongside rule-based WHO thresholds.
Both scores returned in API response; rule-based used for clinical decisions.
ML score logged for future retraining when outcome labels are available.

Features (9 dims):
- systolic_bp, diastolic_bp, heart_rate, spo2, temperature,
- weight_kg, height_cm, age, gestation_weeks

Shadow mode: ML scores computed but not used for decisions until validated.
"""

import os
import json
import numpy as np
from typing import Optional

try:
    import xgboost as xgb
    HAS_XGB = True
except ImportError:
    HAS_XGB = False

MODEL_PATH = os.getenv("XGBOOST_MODEL_PATH", "models/risk_model.json")
MODEL_TRAINED = False  # Will be set True after first train


class XGBoostRiskScorer:
    """Shadow ML risk scorer using XGBoost."""

    FEATURES = [
        "systolic_bp", "diastolic_bp", "heart_rate", "spo2",
        "temperature", "weight_kg", "height_cm", "age", "gestation_weeks",
    ]

    def __init__(self, model_path: str = MODEL_PATH):
        self.model_path = model_path
        self.model = None
        if HAS_XGB:
            self._load_model()

    def _load_model(self):
        """Load XGBoost model from disk."""
        try:
            self.model = xgb.XGBClassifier()
            self.model.load_model(self.model_path)
            print(f"[ML] Loaded XGBoost model from {self.model_path}")
        except Exception as e:
            print(f"[ML] No saved model at {self.model_path}, using untrained model: {e}")
            self.model = None

    def _extract_features(self, vitals: dict, patient: dict = None) -> np.ndarray:
        """Build 9-feature vector from vitals and patient data."""
        feat = []
        for f in self.FEATURES:
            if f in vitals:
                feat.append(float(vitals[f]))
            elif patient and f in patient:
                feat.append(float(patient[f]))
            else:
                feat.append(0.0)
        return np.array([feat])

    def _prob_to_level(self, prob: float) -> str:
        """Convert ML probability to risk level."""
        if prob > 0.4:
            return "HIGH"
        elif prob > 0.15:
            return "MEDIUM"
        return "LOW"

    def _rule_based_level(self, vitals: dict) -> str:
        """Phase 1 rule-based WHO thresholds."""
        sbp = vitals.get("systolic_bp", 0)
        dbp = vitals.get("diastolic_bp", 0)
        hr = vitals.get("heart_rate", 0)
        spo2 = vitals.get("spo2", 0)
        temp = vitals.get("temperature", 0)

        # EMERGENCY thresholds
        if sbp >= 160 or dbp >= 110 or spo2 < 88 or temp > 40 or temp < 35:
            return "EMERGENCY"
        # HIGH thresholds
        if sbp >= 140 or dbp >= 90 or hr > 110 or spo2 < 92 or temp > 38.5:
            return "HIGH"
        # MEDIUM thresholds
        if sbp >= 130 or dbp >= 85 or hr > 100 or spo2 < 95:
            return "MEDIUM"
        return "LOW"

    def score(self, vitals: dict, patient: dict = None) -> dict:
        """
        Run shadow ML alongside rule-based scoring.
        Returns both scores; rule-based used for decisions.
        """
        X = self._extract_features(vitals, patient)
        rule_level = self._rule_based_level(vitals)

        ml_prob = None
        ml_level = None

        if self.model is not None:
            try:
                ml_prob = float(self.model.predict_proba(X)[0][1])
                ml_level = self._prob_to_level(ml_prob)
            except Exception as e:
                print(f"[ML] Prediction failed: {e}")

        return {
            "ml_probability": round(ml_prob, 3) if ml_prob is not None else None,
            "ml_level": ml_level,
            "rule_based_level": rule_level,
            "final_decision": rule_level,  # Always use rule-based for now
            "shadow_mode": True,
            "features": dict(zip(self.FEATURES, X[0].tolist())),
        }

    def train(self, X_train: np.ndarray, y_train: np.ndarray):
        """Train XGBoost model on labeled outcomes."""
        if not HAS_XGB:
            print("[ML] XGBoost not installed, skipping training")
            return

        self.model = xgb.XGBClassifier(
            n_estimators=50,
            max_depth=4,
            learning_rate=0.1,
            eval_metric="logloss",
        )
        self.model.fit(X_train, y_train)
        self.model.save_model(self.model_path)
        global MODEL_TRAINED
        MODEL_TRAINED = True
        print(f"[ML] Model trained on {len(X_train)} samples, saved to {self.model_path}")


def create_synthetic_training_data(n: int = 200) -> tuple:
    """Generate synthetic labeled training data for initial model."""
    np.random.seed(42)
    X = []
    y = []

    for _ in range(n):
        sbp = np.random.randint(90, 180)
        dbp = np.random.randint(60, 120)
        hr = np.random.randint(60, 130)
        spo2 = np.random.randint(85, 100)
        temp = np.random.uniform(35.5, 40.0)
        weight = np.random.uniform(45, 90)
        height = np.random.uniform(140, 170)
        age = np.random.randint(18, 40)
        gest = np.random.randint(8, 38)

        X.append([sbp, dbp, hr, spo2, temp, weight, height, age, gest])

        # Label: 1 = refer (HIGH/EMERGENCY), 0 = routine
        label = 0
        if sbp >= 160 or dbp >= 110 or spo2 < 88:
            label = 1
        elif sbp >= 140 or dbp >= 90 or hr > 110:
            label = 1
        elif np.random.random() < 0.2:  # Some noise
            label = 1

        y.append(label)

    return np.array(X), np.array(y)


async def init_model():
    """Initialize XGBoost model with synthetic data."""
    if not HAS_XGB:
        print("[ML] XGBoost not available, ML scoring disabled")
        return

    if os.path.exists(MODEL_PATH):
        print(f"[ML] Model already exists at {MODEL_PATH}")
        return

    print("[ML] Training initial model with synthetic data...")
    X, y = create_synthetic_training_data(200)
    scorer = XGBoostRiskScorer()
    scorer.train(X, y)


# Module-level singleton
scorer = XGBoostRiskScorer()