"""Validate a real-time, two-hour sensor window before WQAD inference."""

import math
from numbers import Real


def anomaly_window(frame, now_epoch):
    """Use actual capture times, not an assumed ten-minute record count.

    This matches the v3 training warm-up (six rows spanning 110 minutes) and
    uses a two-hour rolling window. A gap over 2.2 times the observed cadence
    restarts the window; missing observations are never interpolated.
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
    gaps = rows["timestamp"].diff()
    positive_gaps = gaps[gaps > 0]
    cadence = float(positive_gaps.median()) if not positive_gaps.empty else 600.0
    if not 480 <= cadence <= 1800:
        return rows, "insufficient", last_at
    discontinuities = [i for i in range(1, len(rows)) if gaps.iloc[i] <= 0 or gaps.iloc[i] > cadence * 2.2]
    if discontinuities:
        rows = rows.iloc[discontinuities[-1]:]
    rows = rows.reset_index(drop=True)
    ready = len(rows) >= 6 and last_at - float(rows["timestamp"].iloc[0]) >= 110 * 60
    return rows, "ready" if ready else "insufficient", last_at
