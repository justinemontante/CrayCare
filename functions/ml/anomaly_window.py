"""Prepare recent sensor history for WQAD inference."""

import math
from numbers import Real


def anomaly_window(frame, now_epoch):
    """Keep real readings from two hours and allow inference with sparse data.

    A result is ready when at least three distinct readings exist in the most
    recent hour. Missing observations do not reset the window and are never
    interpolated. The latest reading must still be recent, and the feature
    builder uses actual timestamps when calculating changes and trends.
    """
    if frame.empty or "timestamp" not in frame:
        return frame.iloc[:0], "insufficient", None
    # DataFrame columns commonly contain numpy integer/float scalars.  Those
    # are ``Real`` values even though they are not instances of Python's
    # built-in ``int``/``float`` classes; rejecting them would make every
    # valid exported history row look like missing data.
    def usable_timestamp(value):
        if not isinstance(value, Real):
            return False
        numeric = float(value)
        return math.isfinite(numeric) and numeric <= now_epoch + 60

    rows = frame[frame["timestamp"].apply(usable_timestamp)].sort_values("timestamp").copy()
    if rows.empty:
        return rows, "insufficient", None
    # Two legitimate readings straddling a bucket boundary can be 598 seconds
    # apart yet floor into the same bucket. Deduplicate timestamps, not buckets.
    rows = rows.drop_duplicates("timestamp", keep="last")
    last_at = float(rows["timestamp"].iloc[-1])
    if now_epoch - last_at > 20 * 60:
        return rows.iloc[:0], "stale", last_at
    rows = rows[rows["timestamp"] >= last_at - 120 * 60].copy()
    rows = rows.reset_index(drop=True)
    recent_cutoff = last_at - 60 * 60
    recent_count = int((rows["timestamp"] >= recent_cutoff).sum())
    ready = recent_count >= 3
    return rows, "ready" if ready else "insufficient", last_at
