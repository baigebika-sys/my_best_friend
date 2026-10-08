# v0.14.0-r3 知识来源与版本

目标 DST 构建 756039，来自用户提供的 version.txt，不宣称这是所有平台当前最新版本。游戏运行时使用 APP_VERSION 精确校验；版本不符则不将静态事实作为当前确认知识。APP_VERSION 在本批 scripts 的官方界面及版本比较代码中被实际使用。

本轮来源：用户提供的完整 Lua 清单分装包、chinese_s.po；官方自动生成 scripts/screens/redux/scrapbookdata.lua；实际 scripts/recipes.lua、constants.lua，以及集中核验的花朵、浆果、园艺锄、温度工具代码。中文图鉴关联规则与实际 scrapbookscreen.lua 核对。PO 没有独立构建号，仅据用户同批文件声明与实际键映射绑定此版本，后续冲突优先核对实现。

输入完整性见 knowledge/input_validation.json 和 input_parts_manifest.json。完整事实与候选线索见 official_knowledge.json，缺口见 coverage.json。各条事实保留版本、来源、行号、SHA256 和确定程度。没有执行任意工厂/回调、批量生成实体或修改世界来探测知识；本轮没有用旧源码或模型记忆填补缺口。

可复现导入：先验证并将所有小 ZIP 解压到同一目录，保留 scripts/ 原路径；使用本包 developer_tools/import_dst_knowledge.py 的 --source 指向这个目录，--version-file 指向版本标记，--localization 指向中文 PO，--adapters 指向 knowledge/reviewed_adapters_756039.json，--output 指向新输出目录。随后将生成的 ybf_official_*.lua 复制到模组 scripts，并保留 JSON 审计文件。工具只依赖 Python 标准库（Python 3.9+）。

基础身份索引分片加载，详细条目按需加载。库存、耐久、新鲜度和位置不来自静态条目。底层知识独立于执行器及将来角色扮演披露层，不删除知识实现扮演。

本次新增检索主题 habitats、集中生物／设施／限制适配及科技概念。附加引用可在 additional_evidence 中追溯，主引用和附加引用均须匹配输入文件 SHA256。官方图鉴中文说明仅按原文可确认主题归入索引，不标记为完整行为模型。角色扮演披露层尚未新增。
