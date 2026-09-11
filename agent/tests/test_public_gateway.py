import importlib
import httpx
import pytest
from fastapi.testclient import TestClient
from codex_watch_agent import public_gateway as gateway

TOKEN = 'test_public_gateway_token_123456789'

@pytest.fixture
def client(monkeypatch):
    importlib.reload(gateway)
    monkeypatch.setattr(gateway.settings, 'watch_token', TOKEN)
    with TestClient(gateway.app) as client:
        yield client


def test_gateway_denies_missing_and_incorrect_credentials(client):
    for headers in ({}, {'x-watch-token': 'wrong'}, {'x-watch-token': 'x!' }):
        response = client.get('/watch', headers=headers)
        assert response.status_code == 401
        assert response.headers['cache-control'] == 'no-store'


def test_gateway_only_exposes_compact_api_and_minimal_health(client):
    assert client.get('/health').json() == {'ok': True}
    for route in ('/usage', '/v1/snapshot', '/docs', '/openapi.json', '/redoc'):
        assert client.get(route, headers={'x-watch-token': TOKEN}).status_code == 404
    assert client.post('/watch', headers={'x-watch-token': TOKEN}).status_code == 405


def test_gateway_keeps_token_local_and_validates_upstream(client, monkeypatch):
    async def get(self, url, **kwargs):
        assert url == f'http://127.0.0.1:{gateway.settings.port}/watch'
        assert kwargs['params'] == {'force': '1'}
        assert kwargs['headers'] == {'x-watch-token': TOKEN}
        return httpx.Response(200, request=httpx.Request('GET', url), json={
            'updated_at': '2026-09-11', 'codex': {'plan_type': 'prolite', 'error': None, 'buckets': []}})
    monkeypatch.setattr(httpx.AsyncClient, 'get', get)
    response = client.get('/watch?force=1&url=https://example.com', headers={'x-watch-token': TOKEN})
    assert response.status_code == 200
    assert response.json()['codex']['plan_type'] == 'prolite'
    assert TOKEN not in response.text
    assert response.headers['cache-control'] == 'no-store'


def test_gateway_does_not_expose_upstream_errors(client, monkeypatch):
    async def get(self, url, **kwargs):
        raise httpx.ConnectError('private diagnostics')
    monkeypatch.setattr(httpx.AsyncClient, 'get', get)
    response = client.get('/watch', headers={'x-watch-token': TOKEN})
    assert response.status_code == 503
    assert 'private diagnostics' not in response.text


def test_bark_configuration_requires_auth_and_never_echoes_key(client):
    from codex_watch_agent.task_events import load_notification_config, state_dir
    address = 'https://api.day.app/privateBarkDevice123/'
    assert client.post('/notifications/bark', json={'address': address}).status_code == 401
    headers = {'x-watch-token': TOKEN}
    response = client.post('/notifications/bark', headers=headers, json={'address': address})
    assert response.status_code == 200
    assert response.headers['cache-control'] == 'no-store'
    assert 'privateBark' not in response.text
    assert load_notification_config(state_dir())['provider'] == 'bark'
    for body in ['invalid', '[]', '{"address":"https://evil.example/privateBarkDevice123"}']:
        response = client.post('/notifications/bark', headers=headers, content=body)
        assert response.status_code == 400
        assert 'privateBark' not in response.text
    assert client.post('/notifications/bark', headers=headers, content='x'*4097).status_code == 413
