from codex_watch_agent.reset_credits import normalize_reset_credits
from codex_watch_agent.models import QuotaStatus, UsageSnapshot
from codex_watch_agent.codex_rpc import normalize_rate_limits_for_command


def test_credit_metadata_is_allowlisted():
    raw = {'availableCount': 2, 'private': 'hidden', 'credits': [{'id': 'secret', 'expiresAt': 2000}, {'expiresAt': 1000}, {'expiresAt': 'bad'}]}
    assert normalize_reset_credits(raw) == {'available_count': 2, 'expirations': [1000, 2000]}


def test_unknown_zero_and_invalid_remain_distinct():
    for raw in [None, {}, {'availableCount': -1}, {'availableCount': True}]:
        assert normalize_reset_credits(raw) is None
    assert normalize_reset_credits({'availableCount': 0}) == {'available_count': 0, 'expirations': []}


def test_compact_preserves_optional_metadata():
    quota = QuotaStatus(provider='codex', label='Codex')
    assert UsageSnapshot(codex_quota=quota).compact()['reset_credits'] is None
    quota.reset_credits = {'available_count': 1, 'expirations': [2000]}
    assert UsageSnapshot(codex_quota=quota).compact()['reset_credits'] == quota.reset_credits

def test_command_normalization_retains_credits():
    result = normalize_rate_limits_for_command({'rateLimitResetCredits': {'availableCount': 1, 'credits': [{'expiresAt': 2000}]}})
    assert result['reset_credits'] == {'available_count': 1, 'expirations': [2000]}


def test_raw_and_command_quota_paths_match():
    from codex_watch_agent.quota import _normalize_codex_app_server, _normalize_quota
    raw = {'rateLimitResetCredits': {'availableCount': 1, 'credits': [{'expiresAt': 2000, 'id': 'private'}]}}
    direct = _normalize_codex_app_server(raw)
    command = _normalize_quota('codex', 'Codex', 'command', normalize_rate_limits_for_command(raw))
    assert direct.reset_credits == command.reset_credits == {'available_count': 1, 'expirations': [2000]}
