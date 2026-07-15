from modules.risk_scoring import calculate_security_score, highest_risk


def test_score_perfect_when_no_risks() -> None:
    assert calculate_security_score([]) == 100
    assert calculate_security_score(["low", "low"]) == 94  # 100 - 3*2


def test_score_high_penalty() -> None:
    assert calculate_security_score(["high"]) == 75        # 100 - 25
    assert calculate_security_score(["high", "high"]) == 50
    assert calculate_security_score(["high"] * 4) == 0     # 100 - 25*4 = 0
    assert calculate_security_score(["high"] * 10) == 0    # capped at 4


def test_score_mixed_levels() -> None:
    assert calculate_security_score(["high", "medium"]) == 63       # 100 - 25 - 12
    assert calculate_security_score(["high", "medium", "low"]) == 60
    assert calculate_security_score(["medium", "low"]) == 85        # 100 - 12 - 3


def test_score_capped_repetition() -> None:
    # Each level capped at 4 repetitions
    assert calculate_security_score(["medium"] * 6) == 52           # 100 - 12*4


def test_score_edge_cases() -> None:
    assert calculate_security_score(["low"]) == 97
    assert calculate_security_score(["medium"]) == 88
    assert calculate_security_score(["high", "medium"] * 3) == 0    # capped over 100


def test_highest_risk_empty() -> None:
    assert highest_risk([]) == "low"


def test_highest_risk_order() -> None:
    assert highest_risk(["low", "medium", "high"]) == "high"
    assert highest_risk(["low", "medium"]) == "medium"
    assert highest_risk(["low", "low"]) == "low"


def test_highest_risk_with_highest_last() -> None:
    assert highest_risk(["low", "low", "high", "medium"]) == "high"
