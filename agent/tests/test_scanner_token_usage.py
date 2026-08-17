import json

from codex_watch_agent.scanner import _tokens_from_obj, scan_usage_dir


def test_codex_token_usage_prefers_last_usage_over_cumulative_total() -> None:
    stats, _ = _tokens_from_obj(
        {
            "timestamp": "2026-06-12T01:00:00Z",
            "payload": {
                "info": {
                    "total_token_usage": {
                        "input_tokens": 1000,
                        "cached_input_tokens": 700,
                        "output_tokens": 300,
                    },
                    "last_token_usage": {
                        "input_tokens": 10,
                        "cached_input_tokens": 7,
                        "output_tokens": 3,
                    },
                }
            },
        }
    )

    assert stats.input_tokens == 10
    assert stats.cache_read_tokens == 7
    assert stats.output_tokens == 3


def test_token_usage_ignores_nested_iteration_breakdown() -> None:
    stats, _ = _tokens_from_obj(
        {
            "timestamp": "2026-06-12T01:00:00Z",
            "message": {
                "usage": {
                    "input_tokens": 10,
                    "cache_creation_input_tokens": 2,
                    "cache_read_input_tokens": 7,
                    "output_tokens": 3,
                    "iterations": [
                        {
                            "input_tokens": 10,
                            "cache_creation_input_tokens": 2,
                            "cache_read_input_tokens": 7,
                            "output_tokens": 3,
                        }
                    ],
                }
            },
        }
    )

    assert stats.input_tokens == 10
    assert stats.cache_creation_tokens == 2
    assert stats.cache_read_tokens == 7
    assert stats.output_tokens == 3


def test_scan_usage_dir_sums_today_tokens(tmp_path, monkeypatch) -> None:
    session_file = tmp_path / "session.jsonl"
    session_file.write_text(
        json.dumps(
            {
                "timestamp": "2026-06-12T01:00:00Z",
                "message": {
                    "usage": {
                        "input_tokens": 10,
                        "output_tokens": 3,
                    }
                },
            }
        ),
        encoding="utf-8",
    )

    class FixedDateTime:
        @staticmethod
        def now():
            from datetime import datetime

            return datetime.fromisoformat("2026-06-12T12:00:00+00:00")

    import codex_watch_agent.scanner as scanner_module

    monkeypatch.setattr(scanner_module, "_now_local", FixedDateTime.now)

    result = scan_usage_dir(tmp_path)

    assert result.today.input_tokens == 10
    assert result.today.output_tokens == 3
    assert sum(bucket.total_tokens for bucket in result.hourly) == 13
