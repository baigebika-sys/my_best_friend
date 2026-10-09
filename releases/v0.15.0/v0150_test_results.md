# v0.15.0 测试结果与证据

自动检查、模拟验证、真实模型、实际游戏分开记录。

- 现行Python71项通过，含严格来源／目的地／多目标／修改协议4项；有旧版本全目录提示词逐字测试不代表现行协议，历史失败说明保留在r4报告，不宣称全历史测试都通过。
- 全部模组Lua通过Lua5.4语法检查；没有DST Lua5.1引擎。正式modmain注册回调模拟测试通过：悬浮操作、服务器距离与小花归属、重复赋予、解除、原容器／皮肤引用不变，客户端netvar名字和标签契约。此项没有测试真实网络复制或预测动画。
- 新仓库／规划模拟：四类容器赋予／解除／组件保存重载，普通箱拒绝，真实转移接口契约、仓库材料制作与存回、盐盒／冰箱／箱分类、满箱替代、部分存放／交付、玩家满地面回退，争用预留／暂停释放／玩家取走／取消授权，中间材料递归、原料保护、一个目标阻碍而另一个完成、追加／删除／暂停恢复，超过一分钟有效推进，均通过。
- 实际 supplied official OnUpgrade 函数分支在模拟对象中执行，箱与龙鳞箱授权及内容保持；视觉函数替换为空，不称原版完整动画或保存引擎实测。引用文件与哈希见 tests/v0150_official_upgrade_sources.json。
- 官方未列入本指示的六个非白名单物品：backpack、armorslurper、razor、goldenpitchfork、footballhat、multitool_axe_pickaxe，以本批真实确认配方构造模拟Builder检查，全部完成制作与交付。选样与原配方证据见 tests/v0150_official_recipe_cases.json。未新增这些物品执行分支；标准配方可用不等于原版每个特殊条件都已实测。
- 新自然语言7句通过正式本地HTTP解码和游戏聊天入口，覆盖“材料箱里有”“只用仓库”“存箱”“原料＋成品”“用途背景”“追加／删除”。响应由固定模拟模型提供；没有真实模型调用。
- 原语言入口28句、r3知识接续24句、r4语义检索88句与56未见知识样本边界、完整导入身份／引用／构建门槛、原工作／采集／工具／暂停取消／补状态／UI回归通过。知识抽样仍41个基本介绍、10个知识门槛缺口、5个同名待确认，未变成56项全面知识通过。

详细当前日志 tests/v0150_*.log；复现 developer_tools/run_v0150_checks.py、run_v0150_language_checks.py、run_foundation_checks.py、run_language_checks.py、run_lua_checks.py、run_knowledge_r3_checks.py、run_semantic_checks.py、run_official_checks.py。隔离解析依赖与现行Python模块列表见 developer_tools/云环境复现.md。

真实模型调用未运行，实际DST游戏验证未运行。实际网络同步、持久化引擎、世界寻路、官方Builder全部条件与模组联用不能由这些模拟保证。游戏验收步骤随包提供；未支持获取、制作和授权边界见能力说明。
