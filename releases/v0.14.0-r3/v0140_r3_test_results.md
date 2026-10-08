# v0.14.0-r3 测试结果

本地检查使用实际导入的 756039 静态知识、生产模块、Lua 5.4 解析器和模拟游戏对象。没有真实模型调用，也没有 DST 游戏实测。未找到本轮可读取的 server_log.txt，根因来自源码及用户提供的代表性原句，不声称已复现日志每次失败。

- 56 项 Python 测试通过：版本／来源／知识结构、静态导入和提取、分装验证、桥接决策、历史回传、聊天、目标和配置。
- 24 个不同中文原句：经真实本地 HTTP 桥接和生产模型响应解码，再送入生产聊天入口、知识／工作系统；提供商响应为预设 fixture，世界为模拟。另在聊天入口复测跨玩家指代、服务不可用反馈及诊断开关。不是只手工调用 Retrieve，也不是自然模型理解能力实测。
- 实际 3067 条静态详细记录加载、版本闸门和引用检查通过；普通／烧灼／错字／多对象、食物／容器／生物查询、树枝采集与取消通过。
- 原有 28 个语言／目标／控制样例、本地基础工作与聊天回归通过，覆盖暂停恢复、取消失效动作、补状态、交付和保留聊天。没有以动作数量代替知识验收。
- 模组全量 Lua 语法和 UI／聊天模拟集成通过；当前没有 DST Lua 5.1 引擎，不能把 Lua 5.4 通过写成游戏验证。
- 结果回传 5 项 HTTP 检查：实际回答记忆、GET 不提前记忆、重复幂等、请求／朋友／玩家隔离、重启与冲突拒绝、密钥文本脱敏。普通两轮查询为 2 次预设提供商响应，回传不新增模型调用。

花瓣代表性验收在模拟中使用当前官方 Pickable 组件参考文件，它与输入 scripts/components/pickable.lua 完全一致；断言实际入包和交付。fixture 数量为 1，实际模型应沿用模糊小量默认 3，需要真实自然入口游戏验收数量和动作。

详细输出见 tests/v0140_r3_*.log。复现：运行 developer_tools/run_knowledge_r3_checks.py、run_official_checks.py、run_language_checks.py、run_foundation_checks.py、run_lua_checks.py；Python 用 PYTHONPATH=external:tests python -m unittest test_knowledge_schema test_official_import test_official_enrichment test_repack_scripts test_result_memory test_bridge test_chat_ai test_goal_ai test_language_schema test_config。需要系统 liblua5.4.so.0，本地工具不进入游戏执行。

真实游戏待验收清单见改动说明；全面百科还需覆盖审计与逐项机制核验，不能计作完成。
