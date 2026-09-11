import pytest


@pytest.fixture(autouse=True)
def isolated_task_history(tmp_path, monkeypatch):
    # API tests must never read or write the user's running notification service.
    monkeypatch.setenv('CODEX_QUOTA_STATE_DIR', str(tmp_path / 'task-state'))
