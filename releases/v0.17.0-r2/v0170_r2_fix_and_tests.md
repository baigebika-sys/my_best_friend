# v0.17.0-r2：烹饪执行链修复

基线 v0.17.0-r1。官方源码构建756039。本轮没有新增料理、玩法或调度功能，没有重写已有工作系统。

## 真实日志能够确认什么

server_log.txt 00:03:06–00:03:07：任务119811-2求解 meatballs；monstermeat 取材确实成功，朋友0→1、冰箱20→19；紧接着提交 load 至锅119776，没有后续 Perform 或实际数量变化。
00:03:18仍记录 inflight=true。00:03:45的新任务119811-3以及00:04:15的新任务119811-4均显示自己的 inflight=nil，但有 YBF_COOK_TASK 缓冲、idle/funnyidle状态、无busy/working、无补给pending、无旧制作inflight。

注意：旧 scheduler 的 inflight=false/nil 是“当前任务是否持有 inflight”的布尔表达式，并没有输出全局动作实例。新任务日志的 inflight=nil符合全局为空；但旧记录没有清除路径，所以不能证明由哪个调用清除了119811-2的 inflight。
客户端日志没有提供这个服务器动作的执行/清除栈；外部程序截图中的最初两次模型格式错误早于有效料理任务，不是本次 load 停止的根因。未授权冰箱不属于缺陷。

## 确认并修改的执行链缺陷

1. ybf_cooking_executor.lua 的成功回调原来立即清除 hub.inflight。官方 SGwilson 的 doshortaction 在第6帧先移除 busy、再执行动作，而状态要到第10帧才退出，仍带 doing。原忙碌检查没有 checking doing；于是回调成功后过早释放执行占位，下一动作可能在旧状态退出前安排。友谊朋友脑在该空档也会失去 WorkBusy 保护，进入 StandStill（可停止 locomotor）。这是已核实的生命周期缺陷，不是配方问题。
2. 官方 locomotor:Stop() 明确不清 bufferedaction，注释保留了 SetBufferedAction(nil)。原 Invalidate 调用 Work:StopAction，清的是实体缓冲区，随后 Stop locomotor；其自己的动作缓冲和执行器所有权可能脱节。失效动作随即被通用 ActionBusy 当作有效工作，影响后续任务。
3. r1没有在调度入口根据动作所属任务与attempt核对两套缓冲区，也没有记录所有 inflight 清除、忽略回调的路径，导致无法还原这次“全局inflight消失、动作仍残留”的来源。

这些是源码和针对性复现确认的缺陷。原日志不能独立证明119811-2的load具体被哪个旧状态/调用停止或清除；不把上述风险路径冒称为完整游戏调用栈。

## 改动位置与实际行为

- `my_best_friend/scripts/ybf_cooking_executor.lua`：成功/失败回调先标记 finished，保留执行占位至原版 doing/busy/working退出且至少一个0.25秒调度间隔经过，再释放并提交下一动作。取材成功到下一槽放料之间不会因回调瞬间释放占位而交给默认脑行为。
- 新增统一 ClearFlight：所有生产代码中的清除都记录理由；submit记录唯一 task+attempt、提交时间与截止时间；不会直接覆盖已有执行占位。
- Invalidate先提升attempt、清除占位，再按动作身份清实体和locomotor缓冲。调用原版 SetBufferedAction(nil)使其失效回调得到正常处理；旧回调因令牌不匹配只能记录 callback_ignored，不能再改进度。
- CleanAction只处理带本朋友hub标记的烹饪动作。存在其他有效缓冲动作或补给pending时，不停止其locomotor；不可中断状态不强制转idle。
- Reconcile在调度入口回收本hub的无占位、旧attempt、已取消/受阻/暂停动作，包括只有locomotor保存残留的情况。不会将其无限当作其他工作。
- `ybf_task_hub.lua`：先做缓冲归属核对，再做等待/超时与正常调度；超时仍20游戏秒，并沿统一受阻入口清资源、报告阶段。不会借延长时间掩盖问题。
- `components/ybf_work.lua`：实体移除清理也通过带原因的统一失效入口。其他材料、建筑和工作执行器不变。
- 模组及外部程序均标记0.17.0-r2；外部程序仅版本标识更新，解析能力不扩大。

实际已取材料、已放锅材料、已开锅批次、已收取与交付数量均保留。恢复重新核对真实库存及锅状态，不退还已消耗材料、不复制物品、不自动重复开锅。

## 为什么旧超时/持续忙碌日志没有出现

r1源码如果在游戏时间到达 deadline 时仍持有原 inflight，应先输出 action_timeout；现有日志没有它，也没有 inflight 清除理由。因此不能声称“20秒已经触发，只是没通知”，也不能确认某个取消调用清了它。

原日志方括号时间是日志经过时间；任务期限使用原版 GetTime（TheSim:GetTick()*ticktime），暂停时不推进。原记录未同时输出 GetTime、deadline和busy_since，无法判断该期限是否达到，也不能拿墙钟经过时间直接替代游戏计时。这是证据缺口，并非已确认游戏暂停就是原因。

r2每条动作链日志都含当前游戏time；inflight_set/push_return/flight_monitor/callback/inflight_clear/owned_action_cleanup/action_timeout/callback_ignored输出所属task+attempt、步骤、submitted、deadline、全局占位、实体缓冲、locomotor缓冲、dest、移动和更新标志、SG状态及doing/busy；busy_monitor额外给出起点和期限。相同状态有限间隔记录，状态变化立即记录，不逐帧刷新、不记录密钥。以此精确区分：未到期限、所有权被清、动画未退出、寻路停止、旧回调被忽略。

## 验收证据与边界

- 82项相关Python测试通过。
- 52项料理与任务Lua检查通过，其中新增6项r2检查：
  1. 运行官方756039 `doshortaction`原始onenter、第6帧时间线、ontimeout及onexit。meatballs完成4次withdraw、4次load、1次start、原版Stewer等待、1次harvest、1次give；逐步断言旧状态未退出前不提交新动作。
  2. locomotor-only失效残留被归属检查回收，后续料理继续。
  3. 首动作超时后实体/locomotor缓冲与占位全部释放，独立新料理完成。
  4. 他人有效动作/补给pending不被旧动作清理中断。
  5. 成功取到一份材料后取消，新任务复用该份材料，完成一份成品，无重复取材/产出。
  6. 运行官方实际Stop/SetBufferedAction函数，复现Stop保留缓冲，再验证取消能清除，后续料理完成。
- r1同步失败、长期忙碌、取消及材料保留回归保留。原22种自然输入及“任务终止”仍通过真实HTTP服务/解码或本地游戏聊天入口；提供者响应模拟。
- 基础工作46项、建筑48项、Lua语法26项以及旧语言回归通过；不将嵌入测试的PASS累计值混为一个总测试数。
- 官方SG和locomotor函数确实执行，但引擎、寻路、场景及玩家实体仍模拟。没有真实模型调用或本轮真实DST游戏闭环证据。用户提供的真实证据只证明r1成功withdraw、之后停在load提交；不能把r2模拟完成写成游戏完成。

## 最少游戏复测

1. 同时替换模组和外部程序，保留密钥，重启服务器和外部程序。保留附近空锅和友谊冰箱，准备1份怪物肉、3份冰；可用食材避免额外竞争组合。说“用现有食材做一份肉丸给我”。
2. 核实实际库存、4槽放料、真实锅加工、真实收取及交付数量。日志应对每个动作有同一 task+attempt 的 submit/push_return→perform/actual_result→callback→inflight_clear(native_action_settled)。不以说话、开锅动画或模拟结果代替入包/交付证据。
3. 第一份材料取出后“任务终止”，再安排相同或其他独立任务；核实材料保留、旧回调不增加计数、新任务可继续。
4. 制造一次路径阻塞或在动作中途移除目标：确认有限期限内报告受阻，出现明确清除原因。再安排“给我一根树枝”验证独立工作不受残留阻塞。
5. 若仍停止，提供同一请求从 inflight_set 到停滞的服务器日志；需包含 time/submitted/deadline、两套缓冲及 stategraph。只有看到实际4槽放料、开锅、收取与交付，才算本轮游戏闭环通过。

本包未含密钥或完整玩家日志。日志核查摘要与源码依据保存在本文件，模拟原始输出在tests/v0170_r2_*.log。旧说明保留，本文件为本轮说明。
