import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
SNAPSHOT_SCHEMA = ROOT / "schemas" / "snapshot.schema.json"
SNAPSHOT_EXAMPLE = ROOT / "docs" / "examples" / "snapshot-response.json"
SENSITIVE_KEYS = {"source_path", "path", "raw_path", "token", "authorization", "cookie", "api_key"}


def _walk_keys(value: Any) -> set[str]:
    keys: set[str] = set()
    if isinstance(value, dict):
        for key, child in value.items():
            keys.add(str(key))
            keys.update(_walk_keys(child))
    elif isinstance(value, list):
        for child in value:
            keys.update(_walk_keys(child))
    return keys


def test_snapshot_schema_file_documents_v1_contract() -> None:
    schema = json.loads(SNAPSHOT_SCHEMA.read_text(encoding="utf-8"))

    assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
    assert schema["$id"].endswith("/schemas/snapshot.schema.json")
    assert schema["required"] == [
        "schema_version",
        "updated_at",
        "stale",
        "providers",
    ]
    assert sorted(schema["properties"]["providers"]["properties"]) == ["codex"]
    assert "sessionSummary" not in schema["$defs"]


def test_snapshot_example_matches_public_contract_shape() -> None:
    example = json.loads(SNAPSHOT_EXAMPLE.read_text(encoding="utf-8"))

    assert example["schema_version"] == "v1"
    assert sorted(example["providers"]) == ["codex"]
    assert example["providers"]["codex"]["hourly"][0]["total_tokens"] == 123456
    assert not (_walk_keys(example) & SENSITIVE_KEYS)
