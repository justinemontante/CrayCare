"""Post-training holdout audit against the source's rule-generated class labels.

The source labels are never model inputs and never choose the training subset,
features, cutoff, or thresholds. They are used only for a labeled holdout
agreement report and must not be described as independent biological truth.
"""
import argparse
import json
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.metrics import confusion_matrix, precision_recall_fscore_support

from training_data import prepare_history


def evaluate(source_path, model_path):
    source = pd.read_csv(source_path)
    if 'class' not in source:
        raise ValueError('The original source CSV must include its class column.')
    raw_time = pd.to_datetime(source['timestamp'], errors='coerce')
    if raw_time.isna().any():
        raise ValueError('Invalid timestamps found in source dataset.')
    original_labels = pd.DataFrame({'timestamp': raw_time, 'source_class': source['class'].astype(str)})
    original_labels = original_labels.set_index('timestamp')['source_class']
    from prepare_fishpond_candidate import prepare_dataset
    sensors = prepare_dataset(source_path)
    sensors['timestamp'] = pd.to_datetime(sensors['timestamp'])
    bucket = original_labels.to_frame().resample(
        '10min', origin='start_day', closed='left', label='right'
    )
    counts = bucket.size()
    labels = bucket.source_class.agg(
        lambda values: values.iloc[0] if len(values) == 2 and values.nunique() == 1 else 'Transition_or_incomplete'
    )
    sensors['source_class_eval'] = labels.reindex(
        pd.DatetimeIndex(sensors.timestamp)
    ).to_numpy()
    rows, features = prepare_history(sensors, version=2)
    bundle = joblib.load(model_path)
    hold_start = pd.Timestamp(bundle['split_at_utc']) + pd.Timedelta(minutes=bundle['purge_minutes'])
    hold = rows.timestamp >= hold_start
    scores = -bundle['model'].score_samples(features.loc[hold])
    predicted = scores > float(bundle['decision_threshold_raw'])
    classes = rows.loc[hold, 'source_class_eval'].astype(str).to_numpy()
    known = np.isin(classes, ['Normal', 'Caution', 'Warning', 'Severe'])
    if not known.any():
        raise ValueError('No complete two-reading source labels occur in the holdout.')
    actual = (classes[known] != 'Normal').astype(int)
    guessed = predicted[known].astype(int)
    precision, recall, f1, _ = precision_recall_fscore_support(
        actual, guessed, average='binary', zero_division=0
    )
    matrix = confusion_matrix(actual, guessed, labels=[0, 1])
    per_class = {}
    for label in ['Normal', 'Caution', 'Warning', 'Severe']:
        mask = known & (classes == label)
        per_class[label] = {
            'rows': int(mask.sum()),
            'flagged_unusual': int(predicted[mask].sum()),
            'flag_fraction': float(predicted[mask].mean()) if mask.any() else None,
        }
    return {
        'dataset_doi': '10.5281/zenodo.19210095',
        'dataset_license': 'CC BY 4.0',
        'target_label_origin': 'source rule-based multi-sensor class; post-hoc holdout reference only',
        'model_training_labels_used': False,
        'feature_columns': bundle['features'],
        'holdout_start_utc': hold_start.isoformat(),
        'labeled_holdout_rows': int(known.sum()),
        'transition_or_incomplete_label_rows_excluded': int((~known).sum()),
        'holdout_source_class_counts': {
            label: int((classes[known] == label).sum())
            for label in ['Normal', 'Caution', 'Warning', 'Severe']
        },
        'holdout_contains_reference_normal_rows': bool((classes[known] == 'Normal').any()),
        'binary_mapping': {'Normal': 'reference normal', 'Caution/Warning/Severe': 'reference degraded'},
        'positive_predictive_value_vs_source_rules': float(precision),
        'degraded_row_detection_fraction_vs_source_rules': float(recall),
        'f1_vs_source_rules': float(f1),
        'confusion_matrix_rows_actual_normal_degraded_cols_predicted_normal_unusual': matrix.tolist(),
        'per_source_class': per_class,
        'limitations': [
            'This is agreement with the dataset authors’ rule-generated labels, not independent ground truth or crayfish validation.',
            'Source labels depend on seven sensor values while CrayCare model inputs include four; transitions between 5-minute records are excluded.',
            'The chronological holdout contains no Normal examples, so it cannot estimate specificity or meaningful overall accuracy.',
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dataset', required=True)
    parser.add_argument('--model', required=True)
    parser.add_argument('--report', required=True)
    args = parser.parse_args()
    result = evaluate(args.dataset, args.model)
    Path(args.report).write_text(json.dumps(result, indent=2, allow_nan=False) + '\n', encoding='utf-8')
    print(json.dumps(result, indent=2, allow_nan=False))


if __name__ == '__main__':
    main()
