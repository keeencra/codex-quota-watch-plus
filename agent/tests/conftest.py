import pytest


@pytest.fixture(autouse=True)
def isolated_task_history(tmp_path, monkeypatch):
    # API tests must never read or write the user's running notification service.
    monkeypatch.setenv('CODEX_QUOTA_STATE_DIR', str(tmp_path / 'task-state'))


@pytest.fixture(autouse=True)
def isolated_deepseek_key(tmp_path, monkeypatch):
    from codex_watch_agent import deepseek
    monkeypatch.delenv('DEEPSEEK_API_KEY', raising=False)
    monkeypatch.setattr(deepseek, 'KEY_PATH', tmp_path / 'deepseek-api-key')
