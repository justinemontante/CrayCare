"""Validate source freshness and cadence before running row-based ML features."""

import math


def anomaly_window(frame, now_epoch):
    """Return a contiguous 10-minute suffix, its status, and source timestamp.

    No interpolation: offline gaps must not masquerade as one/two-hour trends.
    At most twelve observations are used, matching the longest feature window.
    """
    if frame.empty or "timestamp" not in frame:
        return frame.iloc[:0], "insufficient", None
    rows = frame[frame["timestamp"].apply(
        lambda value: isinstance(value, (int, float)) and math.isfinite(value)
        and value <= now_epoch + 60
    )].sort_values("timestamp").copy()
    if rows.empty:
        return rows, "insufficient", None
    # Two legitimate readings straddling a bucket boundary can be 598 seconds
    # apart yet floor into the same bucket. Deduplicate timestamps, not buckets.
    rows = rows.drop_duplicates("timestamp", keep="last")
    last_at = float(rows["timestamp"].iloc[-1])
    if now_epoch - last_at > 20 * 60:
        return rows.iloc[:0], "stale", last_at
    gaps = rows["timestamp"].diff()
    # A nominal 600s interval allows sensor/network jitter, not missing buckets.
    discontinuities = [i for i in range(1, len(rows)) if not 480 <= gaps.iloc[i] <= 720]
    if discontinuities:
        rows = rows.iloc[discontinuities[-1]:]
    rows = rows.tail(12).reset_index(drop=True)
    return rows, "ready" if len(rows) >= 12 else "insufficient", last_at
