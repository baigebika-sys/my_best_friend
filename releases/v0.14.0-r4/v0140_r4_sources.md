# v0.14.0-r4 来源、版本与复现

目标用户提供的 DST 构建756039；不是对当前所有平台最新版本的声明。沿用已校验 scripts 三个分装包、version.txt 和 chinese_s.po，没有重复索取文件。4030个Lua字节、完整清单、分装SHA256／CRC已核对；原大ZIP的CRC来自用户运行的分装工具报告，未在此独立打开原大ZIP。PO有87681上下文、2881正式名称、580图鉴说明，SHA256见 input_validation.json；PO无独立构建印记，根据同批文件及实际键关联。

确认依据：本批游戏 prefab 构造与公共函数、TUNING、实际组件接口、AllRecipes对应脚本、图鉴数据及匹配中文说明、行为树、房间生成表、实际 cooking 注册表与可静态结构化的菜品测试条件。每条事实保留源路径、行号、SHA256、版本、确定程度、规则与适用范围，附加依据在 additional_evidence。无新增外部百科记忆补全；未经核验代码保持候选。运行时 APP_VERSION 不匹配时不使用静态确认事实。

集中适配仍在 reviewed_adapters_756039.json／reviewed_concepts_756039.json，沿用r3已核验特殊用途和条件；新增长主要来自通用 scoped_ast_v1，而非添加抽样对象专用条目。指南针导航由装备标签与 HUD 实现契约绑定，猪人计数由注册回调的受限AST契约提取，阶段关联保留源码生成证据，不把额外分支当普通连续阶段。

开发复现（Python3.10+）：在隔离目录安装 developer_tools/requirements-static.txt；保留代理和CA设置。标准身份／配方导入器仍使用Python标准库，AST二次提取依赖固定 luaparser4.0.0，游戏模组和后台不安装该解析库。

```bash
python -m pip install --target /tmp/ybf-static-parser -r developer_tools/requirements-static.txt
python developer_tools/import_dst_knowledge.py --source <含scripts的目录> --version-file <version.txt> --localization <chinese_s.po> --adapters knowledge/reviewed_adapters_756039.json --output /tmp/ybf-base
PYTHONPATH=/tmp/ybf-static-parser:developer_tools python developer_tools/enrich_mechanisms.py --knowledge /tmp/ybf-base/official_knowledge.json --source <含scripts的目录> --output /tmp/ybf-r4 --workers 4
```

生成 JSON 审计文件与 ybf_official_*.lua／ybf_knowledge_semantic_data.lua；Lua放入模组scripts，JSON放入knowledge，不需将原官方脚本分发给玩家。当前安装依赖位于 /workspace/setup-runtime/static-parser；同等流程的本地测试日志随包附带。基本门槛和来源概率分组已纳入生成器。

实时库存、位置、耐久、新鲜度始终读取游戏，不用静态百科替代。未执行Lua回调、批量生成实体、修改世界或安装游戏来探测知识。底层知识与角色扮演披露分离。
