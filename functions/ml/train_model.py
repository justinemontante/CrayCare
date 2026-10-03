"""Fit Isolation Forest, calibrate on later unseen rows, then evaluate holdout.

The model and its cutoff never fit the final evaluation partition. No class
labels or safety thresholds enter fitting/calibration. Existing output paths
require --replace so an experiment cannot silently overwrite the active model.
"""
import argparse
import hashlib
import json
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
import sklearn
from sklearn.ensemble import IsolationForest

from anomaly_features import SENSORS
from training_data import prepare_history


def train(dataset, train_days=5, calibration_fraction=.25, percentile=98.0,
          origin='external_freshwater_fishpond_proxy_unvalidated'):
    dataset = Path(dataset)
    source = pd.read_csv(dataset)
    rows, features = prepare_history(source, version=2)
    # Use the first usable endpoint, as the previous trainer did. It is not a
    # label-selected healthy period. Input selection must be documented.
    test_at = rows.timestamp.min() + pd.Timedelta(days=train_days)
    reference = rows.timestamp < test_at
    reference_positions = np.flatnonzero(reference)
    fit_count = int(len(reference_positions) * (1 - calibration_fraction))
    if fit_count < 100 or fit_count >= len(reference_positions):
        raise ValueError('Need at least 100 fit rows and a later calibration block.')
    calibration_at = rows.timestamp.iloc[reference_positions[fit_count]]
    # At most one missed 10-minute slot: earliest point in a 12-row window
    # can be 132 minutes earlier (11 intervals at the maximum allowed jitter).
    # A 144-minute purge is conservative; no raw input windows cross splits.
    purge = pd.Timedelta(minutes=144)
    fit_mask = rows.timestamp < calibration_at
    cal_mask = (rows.timestamp >= calibration_at + purge) & (rows.timestamp < test_at)
    test_mask = rows.timestamp >= test_at + purge
    fit, cal, test = features[fit_mask], features[cal_mask], features[test_mask]
    if len(cal) < 30 or len(test) < 30:
        raise ValueError('Need at least 30 calibration and 30 later evaluation rows after purging.')
    model = IsolationForest(n_estimators=300, max_samples=min(256, len(fit)),
                            max_features=1.0, contamination='auto', random_state=42, n_jobs=-1)
    model.fit(fit)
    scores = -model.score_samples(cal)
    # Strict greater-than handles ties without making identical baseline
    # readings anomalous. Quantile policy is fixed before holdout evaluation.
    cutoff = float(np.quantile(scores, percentile / 100.0, method='higher'))
    test_scores = -model.score_samples(test)
    predicted = test_scores > cutoff
    medians = fit.median()
    scales = (fit - medians).abs().median() * 1.4826
    scales = scales.where(scales > 1e-8, fit.std()).replace(0, 1.0).fillna(1.0)
    bundle = {
        'model': model, 'feature_version': 2, 'sensors': SENSORS,
        'features': list(features.columns), 'algorithm': 'IsolationForest',
        'trained_at_utc': pd.Timestamp.now(tz='UTC').isoformat(),
        'training_data_origin': origin, 'training_labels_used': False,
        'training_rows': len(fit), 'calibration_rows': len(cal), 'holdout_rows': len(test),
        'decision_basis': 'independent_chronological_calibration_percentile',
        'decision_percentile': percentile, 'decision_threshold_raw': cutoff,
        'raw_score_method': 'negative_score_samples',
        'calibration_scores': np.sort(scores),
        'feature_medians': medians.to_dict(),
        'robust_centers': medians.to_dict(), 'robust_scales': scales.to_dict(),
        'trend_deadbands': {s: float(fit[s + '_trend30m'].abs().quantile(.25)) for s in SENSORS},
        'contributor_method': 'positive_sensor_block_median_replacement_score_reduction',
        'analysis_window_minutes': 120, 'minimum_history_rows': 12,
        'validation_strategy': 'chronological_fit_then_calibration_then_purged_holdout',
        'calibration_start_utc': calibration_at.isoformat(), 'split_at_utc': test_at.isoformat(),
        'purge_minutes': 144, 'holdout_alert_fraction': float(predicted.mean()),
        'evaluation_label_origin': 'none',
        'dataset_sha256': hashlib.sha256(dataset.read_bytes()).hexdigest(),
        'sklearn_version': sklearn.__version__,
        'prototype_metrics': {'precision': None, 'recall': None, 'f1': None},
    }
    daily = pd.DataFrame({'day': rows.loc[test_mask, 'timestamp'].dt.strftime('%Y-%m-%d'),
                          'unusual': predicted}).groupby('day').unusual.agg(['count', 'sum', 'mean'])
    drift = ((test.median() - fit.median()) / scales).abs().sort_values(ascending=False)
    report = {
        'algorithm': bundle['algorithm'], 'feature_version': 2,
        'data_origin': origin, 'dataset_sha256': bundle['dataset_sha256'],
        'fit_rows': len(fit), 'calibration_rows': len(cal), 'holdout_rows': len(test),
        'fit_end_utc': rows.loc[fit_mask, 'timestamp'].max().isoformat(),
        'calibration_first_utc': rows.loc[cal_mask, 'timestamp'].min().isoformat(),
        'calibration_last_utc': rows.loc[cal_mask, 'timestamp'].max().isoformat(),
        'holdout_first_utc': rows.loc[test_mask, 'timestamp'].min().isoformat(),
        'holdout_last_utc': rows.loc[test_mask, 'timestamp'].max().isoformat(),
        'cutoff_percentile': percentile, 'cutoff_raw': cutoff,
        'calibration_alert_fraction': float(np.mean(scores > cutoff)),
        'holdout_alert_fraction': float(predicted.mean()),
        'holdout_daily': daily.reset_index().to_dict(orient='records'),
        'largest_holdout_reference_shifts': drift.head(8).to_dict(),
        'limitations': ['Alert fraction is not accuracy or a measured false-positive rate.',
            'Reference data may contain degraded conditions; class labels were not used.',
            'Temporal dependence and distribution shift invalidate an assumed fixed false-alarm guarantee.',
            'Public fishpond proxy has not been validated on the target crayfish tank.'],
    }
    return bundle, report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dataset', required=True)
    parser.add_argument('--output', default=str(Path(__file__).with_name('wqad_candidate.joblib')))
    parser.add_argument('--report', help='JSON evaluation report path')
    parser.add_argument('--train-days', type=float, default=5)
    parser.add_argument('--calibration-fraction', type=float, default=.25)
    parser.add_argument('--percentile', type=float, default=98)
    parser.add_argument('--sensors', default=','.join(SENSORS))
    parser.add_argument('--replace', action='store_true')
    parser.add_argument('--origin', required=True, choices=['real_field_unvalidated',
        'synthetic_bootstrap_not_field_validated', 'external_freshwater_fishpond_proxy_unvalidated'])
    args = parser.parse_args()
    if args.sensors.split(',') != SENSORS:
        parser.error('Use exactly temp,pH,DO,turbidity.')
    if args.train_days <= 0 or not 0 < args.calibration_fraction < .5 or not 90 <= args.percentile < 100:
        parser.error('Check positive train-days, calibration fraction (0,.5), and percentile [90,100).')
    if Path(args.output).exists() and not args.replace:
        parser.error('Output already exists; use a new candidate path or explicitly pass --replace.')
    bundle, report = train(args.dataset, args.train_days, args.calibration_fraction, args.percentile, args.origin)
    joblib.dump(bundle, args.output, compress=3)
    if args.report:
        Path(args.report).write_text(json.dumps(report, indent=2, allow_nan=False) + '\n', encoding='utf-8')
    print(json.dumps(report, indent=2, allow_nan=False))
    print(f'Saved {args.output}. Holdout alert fraction is not accuracy.')


if __name__ == '__main__':
    main()
