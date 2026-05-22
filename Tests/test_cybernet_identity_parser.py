import csv
import importlib.util
import json
from pathlib import Path


def load_parser_module():
    repo_root = Path(__file__).resolve().parents[1]
    module_path = repo_root / "tools" / "Parse-CybernetIdentityArtifact.py"
    spec = importlib.util.spec_from_file_location("cybernet_identity_parser", module_path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def test_opr338_identity_artifact_keeps_ping_separate(tmp_path):
    parser = load_parser_module()
    repo_root = Path(__file__).resolve().parents[1]
    xml_path = repo_root / "Tests" / "fixtures" / "cybernet_identity_opr338_sample.xml"
    ping_path = repo_root / "Tests" / "fixtures" / "cybernet_ping_opr338_transient.json"

    ping_evidence = parser._load_ping_evidence(ping_path)
    records = parser.parse_artifact(xml_path, "enterprise", ping_evidence)

    assert len(records) == 1
    record = records[0]
    assert record.HostAddress == "10.10.10.338"
    assert record.HostIdentity == "OPR338"
    assert record.IdentityArtifactStatus == "IdentityArtifactPresent"
    assert record.CmdPingStatus == "FailedThenSucceeded"
    assert record.PingAttemptCount == "2"
    assert record.Classification == "INCONCLUSIVE_TRANSIENT_REACHABILITY"
    assert "initially failed cmd ping" in record.Notes


def test_cli_writes_csv_json_and_deploy_axis_html(tmp_path):
    parser = load_parser_module()
    repo_root = Path(__file__).resolve().parents[1]
    xml_path = repo_root / "Tests" / "fixtures" / "cybernet_identity_opr338_sample.xml"
    ping_path = repo_root / "Tests" / "fixtures" / "cybernet_ping_opr338_transient.json"
    out_csv = tmp_path / "out.csv"
    out_json = tmp_path / "out.json"
    out_html = tmp_path / "out.html"

    rc = parser.main([
        "--input", str(xml_path),
        "--ping-evidence", str(ping_path),
        "--network-posture", "enterprise",
        "--out-csv", str(out_csv),
        "--out-json", str(out_json),
        "--out-html", str(out_html),
    ])

    assert rc == 0
    assert out_csv.exists()
    assert out_json.exists()
    assert out_html.exists()

    with out_csv.open(newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    assert rows[0]["HostIdentity"] == "OPR338"
    assert rows[0]["CmdPingStatus"] == "FailedThenSucceeded"
    assert rows[0]["Classification"] == "INCONCLUSIVE_TRANSIENT_REACHABILITY"

    data = json.loads(out_json.read_text(encoding="utf-8"))
    assert data[0]["HostAddress"] == "10.10.10.338"

    html = out_html.read_text(encoding="utf-8")
    assert "Deploy Axis / Cybernet Identity" in html
    assert "Artifact Intelligence Dashboard" in html
    assert "Classification Mix" in html
    assert "Ping Evidence" in html
    assert "Identity artifact evidence and cmd ping evidence are separate signals" in html
