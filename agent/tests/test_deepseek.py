import asyncio
import json

import httpx
import pytest

from codex_watch_agent import deepseek
from codex_watch_agent.models import UsageSnapshot, QuotaStatus


def payload(total='12.3456', currency='CNY'):
    return {'is_available': True, 'balance_infos': [dict(currency=currency, total_balance=total,
            granted_balance='2.00', topped_up_balance='10.3456')]}


def test_precise_multi_currency_and_zero_balance():
    data = payload('0.0000')
    data['is_available'] = False
    data['balance_infos'] += payload('0.123456', 'USD')['balance_infos']
    balance = deepseek.parse_balance(data)
    assert balance.is_available is False
    assert [row.total_balance for row in balance.balance_infos] == ['0.0000', '0.123456']
    snapshot = UsageSnapshot(codex_quota=QuotaStatus(provider='codex', label='Codex'), deepseek=balance)
    assert snapshot.compact()['deepseek']['balance_infos'][1]['currency'] == 'USD'
    assert snapshot.snapshot()['deepseek']['status'] == 'ok'


@pytest.mark.parametrize('bad', ['NaN', 'Infinity', '1e99999999', '0e99999999', 'secret', '', '1.1234567890123'])
def test_rejects_malformed_amounts(bad):
    with pytest.raises(ValueError):
        deepseek.parse_balance(payload(bad))


def test_missing_key_does_not_request_network(monkeypatch):
    def fail(**kw):
        raise AssertionError('Network should not be called')
    monkeypatch.setattr(deepseek.httpx, 'AsyncClient', fail)
    assert asyncio.run(deepseek.get_deepseek_balance()).status == 'not_configured'


@pytest.mark.parametrize('status', [200, 401, 403, 429, 500, 302])
def test_fixed_endpoint_auth_and_redacted_errors(monkeypatch, status):
    key = 'fake-test-key-not-a-credential'
    monkeypatch.setenv('DEEPSEEK_API_KEY', key)
    def handler(request):
        assert str(request.url) == deepseek.BALANCE_URL
        assert request.headers['authorization'] == 'Bearer ' + key
        return httpx.Response(status, json=payload() if status == 200 else {'error': key},
                              headers={'location': 'https://example.com/'})
    client = httpx.AsyncClient
    monkeypatch.setattr(deepseek.httpx, 'AsyncClient', lambda **kw: client(transport=httpx.MockTransport(handler), **kw))
    result = asyncio.run(deepseek.get_deepseek_balance())
    assert result.status == ('ok' if status == 200 else 'error')
    assert key not in result.model_dump_json()
    if status != 200:
        assert result.balance_infos == [] and result.updated_at is None


def test_network_failure_keeps_codex_snapshot(monkeypatch):
    import codex_watch_agent.main as main
    from codex_watch_agent.scanner import ScanResult
    from codex_watch_agent.models import TokenStats
    monkeypatch.setenv('DEEPSEEK_API_KEY', 'fake-key')
    def handler(request):
        raise httpx.ReadTimeout('fake-key must never be exposed')
    client = httpx.AsyncClient
    monkeypatch.setattr(deepseek.httpx, 'AsyncClient', lambda **kw: client(transport=httpx.MockTransport(handler), **kw))
    async def quota(_):
        return QuotaStatus(provider='codex', label='Codex', status='ok', remaining_percent=59)
    monkeypatch.setattr(main, 'get_codex_quota', quota)
    monkeypatch.setattr(main, 'scan_usage_dir', lambda *a, **kw: ScanResult(today=TokenStats(), hourly=[]))
    result = asyncio.run(main.build_snapshot()).compact()
    assert result['codex']['remaining_percent'] == 59
    assert result['deepseek']['status'] == 'error'
    assert 'fake-key' not in json.dumps(result)
