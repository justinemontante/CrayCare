"""Validate source freshness and cadence before running row-based ML features."""

import math
from numbers import Real


def anomaly_window(frame, now_epoch):
    """Return a fresh 12-reading window, its status, and source timestamp.

    One missed ten-minute slot is tolerated in the trailing 12 observations.
    Larger or repeated gaps restart the usable suffix; readings are never
    interpolated. At most twelve observations are used, matching the longest
    feature window.
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
    # Allow normal jitter and one missed ten-minute record (up to ~22 minutes).
    # Anything longer starts a new suffix rather than implying continuity.
    discontinuities = [i for i in range(1, len(rows)) if not 480 <= gaps.iloc[i] <= 1320]
    if discontinuities:
        rows = rows.iloc[discontinuities[-1]:]
    rows = rows.tail(12).reset_index(drop=True)
    trailing_gaps = rows["timestamp"].diff().dropna()
    missed_slots = int((trailing_gaps > 720).sum())
    ready = len(rows) >= 12 and missed_slots <= 1
    return rows, "ready" if ready else "insufficient", last_at
