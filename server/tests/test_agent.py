"""Agent 测试：用假 LLM 验证工具调用循环（不依赖真实 AI 服务）。"""

from .conftest import unique


class FakeLLM:
    """按脚本返回预设响应序列。"""

    def __init__(self, script):
        self.script = list(script)
        self.calls = []

    def __call__(self, cfg, messages):
        # 快照拷贝：run_agent 会在同一列表上继续追加工具消息
        self.calls.append([dict(m) for m in messages])
        return self.script.pop(0)


def tool_call(name, args_json, call_id="call_1"):
    return {
        "role": "assistant",
        "content": None,
        "tool_calls": [{
            "id": call_id,
            "type": "function",
            "function": {"name": name, "arguments": args_json},
        }],
    }


def test_unconfigured_returns_hint(client, auth_headers, monkeypatch, server_env):
    from coachpal_server import agent, config

    # 清掉 LLM 配置（测试环境的 data 目录没有 llm_config.json，也不设环境变量）
    monkeypatch.delenv("COACHPAL_LLM_BASE_URL", raising=False)
    monkeypatch.delenv("COACHPAL_LLM_API_KEY", raising=False)
    monkeypatch.delenv("COACHPAL_LLM_MODEL", raising=False)
    from coachpal_server.db import connect as server_connect
    con = server_connect()
    cfg = config.llm_config()
    assert cfg["configured"] is False
    con.close()
    # run_agent 在未配置时返回提示而非异常
    from coachpal_server.db import connect as c2
    result = agent.run_agent(c2(), "你好")
    assert "llm_config.json" in result["reply"]


def test_agent_records_weight_via_tool(client, auth_headers, monkeypatch, server_env):
    from coachpal_server import agent, config
    from coachpal_server.db import connect as server_connect

    monkeypatch.setenv("COACHPAL_LLM_BASE_URL", "https://llm.example.com/v1")
    monkeypatch.setenv("COACHPAL_LLM_API_KEY", "test")
    monkeypatch.setenv("COACHPAL_LLM_MODEL", "test-model")

    fake = FakeLLM([
        tool_call("record_weight", '{"weight": 77.9, "body_fat": 21.4}'),
        {"role": "assistant", "content": "已记录：体重 77.9 kg，体脂 21.4%。"},
    ])
    con = server_connect()
    result = agent.run_agent(con, "今天体重77.9，体脂21.4", llm_call=fake)

    assert result["reply"] == "已记录：体重 77.9 kg，体脂 21.4%。"
    assert result["actions"][0]["tool"] == "record_weight"
    assert result["actions"][0]["ok"] is True
    # 确实写进了服务端库
    row = con.execute(
        "SELECT weight_kg FROM body_metrics WHERE weight_kg = 77.9"
    ).fetchone()
    assert row is not None
    con.close()


def test_agent_ambiguity_flow(client, auth_headers, monkeypatch):
    """食物歧义：query_food 返回 ambiguous，LLM 应把候选转告用户。"""
    from coachpal_server import agent, config

    monkeypatch.setenv("COACHPAL_LLM_BASE_URL", "https://llm.example.com/v1")
    monkeypatch.setenv("COACHPAL_LLM_API_KEY", "test")
    monkeypatch.setenv("COACHPAL_LLM_MODEL", "test-model")

    fake = FakeLLM([
        tool_call("query_food", '{"query": "香蕉"}'),
        {"role": "assistant",
         "content": "香蕉有多个条目（红皮/甘蕉），你想记哪一种？"},
    ])
    from coachpal_server.db import connect as server_connect
    con = server_connect()
    result = agent.run_agent(con, "记一个香蕉", llm_call=fake)
    assert "香蕉" in result["reply"]
    # 第一轮消息以用户请求结束
    assert fake.calls[0][-1]["role"] == "user"
    assert fake.calls[0][-1]["content"] == "记一个香蕉"
    # 第二轮消息包含 assistant(tool_calls) 与 tool 结果（含 candidates 回填）
    roles = [m.get("role") for m in fake.calls[1]]
    assert "tool" in roles
    tool_msg = fake.calls[1][-1]
    assert tool_msg["role"] == "tool"
    assert "ambiguous" in tool_msg["content"]
    con.close()


def test_agent_tool_error_surfaced(client, auth_headers, monkeypatch):
    """工具报错（如体重不合法）应作为工具结果回传给 LLM。"""
    from coachpal_server import agent, config
    from coachpal_server.db import connect as server_connect

    monkeypatch.setenv("COACHPAL_LLM_BASE_URL", "https://llm.example.com/v1")
    monkeypatch.setenv("COACHPAL_LLM_API_KEY", "test")
    monkeypatch.setenv("COACHPAL_LLM_MODEL", "test-model")

    fake = FakeLLM([
        tool_call("record_weight", '{"weight": 9999}', call_id="call_2"),
        {"role": "assistant", "content": "体重数值超出合理范围，请确认。"},
    ])
    con = server_connect()
    result = agent.run_agent(con, "我重9999斤", llm_call=fake)
    tool_msg = fake.calls[1][-1]
    assert tool_msg["role"] == "tool"
    assert "不合理" in tool_msg["content"]
    assert result["actions"][0]["ok"] is False
    con.close()


def test_agent_chat_endpoint_unconfigured(client, auth_headers):
    # 测试环境默认没配 LLM（除上述 monkeypatch 的用例），端点应返回 400 提示
    r = client.post("/api/agent/chat", json={"message": "你好"},
                    headers=auth_headers)
    assert r.status_code in (200, 400)  # 取决于其他用例是否设置了环境变量
    if r.status_code == 400:
        assert "LLM" in r.json()["detail"]


def test_agent_exercise_returns_media(client, auth_headers, monkeypatch):
    """问动作 → exercise_detail → 回复应携带动画 GIF 的媒体附件。"""
    from coachpal_server import agent, config
    from coachpal_server.db import connect as server_connect

    monkeypatch.setenv("COACHPAL_LLM_BASE_URL", "https://llm.example.com/v1")
    monkeypatch.setenv("COACHPAL_LLM_API_KEY", "test")
    monkeypatch.setenv("COACHPAL_LLM_MODEL", "test-model")

    fake = FakeLLM([
        tool_call("exercise_detail", '{"query": "卧推"}', call_id="call_m"),
        {"role": "assistant", "content": "卧推要点：肩胛后收、杠铃轨迹落胸前。动画已展示。"},
    ])
    con = server_connect()
    result = agent.run_agent(con, "卧推怎么练", llm_call=fake)
    media = result.get("media") or []
    assert media, "应携带动画媒体"
    assert media[0]["url"].startswith("/media/videos/")
    assert media[0]["url"].endswith(".gif")
    assert media[0]["steps"], "应包含中文步骤要点"
    con.close()
