"""Read-only, allowlisted reset credit metadata; never expose credit identifiers."""
import math


def normalize_reset_credits(raw, *, normalized=False):
    if not isinstance(raw, dict):
        return None
    count = raw.get('available_count' if normalized else 'availableCount')
    if isinstance(count, bool) or not isinstance(count, int) or count < 0:
        return None
    records = raw.get('expirations' if normalized else 'credits', [])
    if not isinstance(records, list):
        records = []
    dates = []
    for record in records:
        value = record if normalized else record.get('expiresAt') if isinstance(record, dict) else None
        if not isinstance(value, bool) and isinstance(value, (int, float)) and math.isfinite(value) and 0 < value < 253402300800:
            dates.append(value)
    return {'available_count': count, 'expirations': sorted(dates)}
