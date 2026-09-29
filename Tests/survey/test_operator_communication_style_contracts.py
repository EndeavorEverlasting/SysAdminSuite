from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
STYLE = ROOT / "docs" / "OPERATOR_COMMUNICATION_STYLE.md"
HANDOFF = ROOT / "docs" / "HH_KIOSK_DELIVERY_COORDINATION_HANDOFF.md"


def test_operator_style_contract_captures_confirmed_preferences() -> None:
    text = STYLE.read_text(encoding="utf-8")

    required = [
        "concise, direct, professional language",
        "Directive versus request",
        "Do not use em dashes",
        'Avoid the phrase "locked in"',
        "confirmed facts separated from open dependencies",
        "Plan to be onsite",
    ]

    for marker in required:
        assert marker in text, f"missing operator prose contract marker: {marker}"


def test_hh_handoff_uses_operator_style_contract() -> None:
    text = HANDOFF.read_text(encoding="utf-8")

    assert "docs/OPERATOR_COMMUNICATION_STYLE.md" in text
    assert "Internal team install directive template" in text
    assert "Plan to be onsite [DATE] for the install." in text
    assert "\u2014" not in text
    assert "locked in" not in text.lower()
