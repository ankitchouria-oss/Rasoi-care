import app as app_module


def test_bounded_default_dict_evicts_oldest_past_max_size():
    d = app_module._BoundedDefaultDict(lambda: 0, max_size=3)
    d["a"]
    d["b"]
    d["c"]
    assert list(d.keys()) == ["a", "b", "c"]
    d["d"]  # over capacity — must evict "a", the least-recently-touched
    assert list(d.keys()) == ["b", "c", "d"]


def test_bounded_default_dict_touch_marks_recently_used():
    d = app_module._BoundedDefaultDict(lambda: 0, max_size=3)
    d["a"]
    d["b"]
    d["c"]
    d["a"]  # touching "a" again should protect it from the next eviction
    d["d"]
    assert "a" in d
    assert "b" not in d


def test_request_body_over_max_content_length_returns_413_json(client):
    # A route with no auth decorator ahead of it, so the oversized body is
    # actually reached rather than short-circuited by an earlier 401.
    huge_body = b"x" * (17 * 1024 * 1024)
    resp = client.post(
        "/api/auth/register",
        data=huge_body,
        content_type="application/json",
    )
    assert resp.status_code == 413
    assert resp.get_json()["error"]
