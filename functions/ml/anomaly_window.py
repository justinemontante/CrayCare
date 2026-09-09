"""Validate source freshness and cadence before running row-based ML features."""

import math
from numbers import Real


def anomaly_window(frame, now_epoch):
    """Return a contiguous 10-minute suffix, its status, and source timestamp.

    No interpolation: offline gaps must not masquerade as one/two-hour trends.
    At most twelve observations are used, matching the longest feature window.
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
    gaps = rows["timestamp"].diff()
    # A nominal 600s interval allows sensor/network jitter, not missing buckets.
    discontinuities = [i for i in range(1, len(rows)) if not 480 <= gaps.iloc[i] <= 720]
    if discontinuities:
        rows = rows.iloc[discontinuities[-1]:]
    rows = rows.tail(12).reset_index(drop=True)
    return rows, "ready" if len(rows) >= 12 else "insufficient", last_at
