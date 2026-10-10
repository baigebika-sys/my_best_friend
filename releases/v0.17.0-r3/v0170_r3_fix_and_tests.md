# v0.17.0-r3 料理交付与超时残留修复

基线：完整v0.17.0-r2，保留r2的执行占位和归属清理修复。本轮只修改交付路由、动作有效性及清理引用，不新增烹饪玩法、设施、调度或其他动作。两端统一版本0.17.0-r3。

## 游戏日志确认的事实

本次上传server_log.txt中任务119526-2：03:13 harvest verified=true，asparagussoup库存0→1；随后give提交至玩家118803，无give Perform；03:33确有超时并进入交付受阻。03:51后的119526-3/4仍被YBF_COOK_TASK挡住；04:11忙碌预算到期。该日志提供了“实际已做好并入包、交付没有执行、旧缓冲持续阻塞”的游戏证据，不是AcceptGift拒绝。

日志格式和超时文案匹配r1执行链，没有r2的time、动作身份、inflight_set和清理前后字段；日志本身没有足以核定安装包版本的版本行。不能凭本地最新版目录假定游戏已运行那一份源码，也不能据这些旧字段认定r2动作清理的实例路径。

## 已确认的残留根因

官方756039 EntityScript:GetBufferedAction()返回：实体bufferedaction优先，否则回退到locomotor.bufferedaction。它不是“只读实体缓冲”的接口。

旧代码ClearBufferedAction仅清实体引用；Work:StopAction随后调用locomotor:Stop，而原版Stop明确保留locomotor.bufferedaction。因此“清过实体但GetBufferedAction仍显示YBF_COOK_TASK”可以是同一个locomotor残留一直没清掉，并不需要发生重新挂回。ActionBusy读取这个回退结果，遂把失效烹饪动作当成其他工作；新任务被拦在调度前，超时后也未得到执行机会。这一接口语义和清理缺口由官方函数及针对性复现确认，与日志表现吻合。

旧日志没有实例编号或分开的两套引用，不能进一步证实某次原动作确曾清空后再挂回。新日志能够区分：cleanup_after仍持有同一实例是未清净；以后又出现已记录cleanup_done的实例，会输出retired_action_reappeared。

## 交付根因的证据边界与修改

旧日志未记录give提交后的玩家距离、locomotor目的地、寻路状态及状态图动作实例。因此不能确定历史give是被旧状态退出/默认行为停掉、路径未到达，还是动作处理未启动；不能归因于尚未进入的AcceptGift。

已确认的代码差异是：普通物品交付走YBF_GIVE→原版give，料理原来走YBF_COOK_TASK→doshortaction。r3让料理直接复用已用过的YBF_GIVE注册、原版give动画与locomotor路径。Work:PerformGive仅对带ybf_cook归属的动作转到烹饪实际数量核验；普通物品原流程不变。不绕过距离、授权、玩家接收或真实AcceptGift，不直接隔空移物。

原版give只有giving标签，没有busy/working。r3将giving纳入烹饪完成后的动画退出检查，保证成功回调后仍保留执行占位，直到给予动画退出；否则又可能在原状态退出前交出执行权。此为官方时间线核验后的生命周期修复，不能把这一差异单独冒称为历史日志已证实的唯一交付触发原因。

## 改动位置

- my_best_friend/scripts/ybf_cooking_executor.lua：give选择ACTIONS.YBF_GIVE；完成占位检查包含giving；BufferedAction.validfn验证当前hub、动作身份、task attempt、暂停/取消/受阻和持有人，使退休尝试不能再通过原版TestForStart。
- 失效处理先提升attempt、清inflight，收集本任务的实体/locomotor/状态图/最后动作引用，再按归属清理。调用原版SetBufferedAction(nil)、Stop和Clear，清动作、目的地、到达回调等；清理前后重新读取，避免同步失败回调安装其他有效动作后误停它。
- 清理状态图原动作与本模组归属标记；不可中断状态不强制跳idle。不同任务动作或补给pending不被无条件停止。
- Reconcile检查实体、locomotor和SG引用，回收失效本任务尝试，包括旧尝试被再次挂回的情况。
- components/ybf_work.lua：PerformGive的烹饪动作路由，保留已有非料理交付实现。
- 模组/外部程序版本标识同步；外部理解和协议无功能扩展。

## 进度和保护

交付受阻保留done/carry/product及实际汤，释放占位、锅和预留。恢复先处理carry，只有已有料理交付完成后才核对完成数量，不重复找食材、开锅或收取。取消只停止任务后续操作，保留实物；不会退还已消耗材料或增加成品。

单动作期限仍20游戏秒，未延长。若真实路径无法到达，报告受阻并释放动作；不会虚报完成。多个料理仍遵守现有锅占用和食材限制；本轮没有扩展同一锅的调度策略。测试中的第二、第三项是在首项交付受阻后分别安排，验证旧动作不会阻塞它们，不宣称同一锅可以并行烹饪。

## 日志

instance编号区分实际动作对象；task+attempt标明所有权。记录submitted/deadline/当前游戏time、目标GUID与距离、entity_buffer（直接读实体字段）、effective_buffer（官方getter含回退）、loco_buffer/target/dest、移动状态、SG原动作和模组归属标记、giving/doing/busy。

关键阶段：inflight_set、push_return、perform、actual_result、callback、inflight_clear、owned_action_cleanup_before/after、callback_ignored、retired_action_reappeared、action_timeout。监测日志至少相隔2秒，不因距离持续变化逐帧刷屏；相同摘要通常10秒才重复。实际提交/结果及清理立即记录，不含密钥。

## 验证

- 56项料理与任务Lua检查通过；包括本轮近处玩家、需要走近的玩家、途中移动的玩家：执行官方give的第13帧Perform和动画结束事件，核对双方库存减少/增加各一份。
- 交付超时测试保留第一份汤，清实体/locomotor/目的地/SG标记；旧动作IsValid=false；故意重新挂回同一旧实例后仍回收。随后第二、第三项分别完成；恢复第一项只交付原汤，锅batch及原料数量不增加消耗。取消已收取料理保留一份实物。
- 执行官方GetBufferedAction原函数，验证实体为空仍报告locomotor缓冲；保留r2官方Stop/SetBufferedAction和doshortaction测试。
- 新增自然句“做一份芦笋汤给我”经过真实HTTP服务/生产解码与游戏聊天入口，再到生产YBF_GIVE路由和库存核验。模型响应模拟，非真实模型调用。
- 82项相关Python检查通过；原有基础46项、建筑48项、Lua语法26项及旧语言回归通过。各runner内嵌PASS不混作统一总数。
- 引擎、路径和玩家移动是模拟；官方动作与状态图片段实际运行。未运行修复后的真实DST闭环，不用模拟替代游戏证据。当前唯一游戏证据就是本次日志：收取成功，交付失败。

## 最少游戏验收

1. 同时替换模组和外部程序、保留密钥，重启双方。核实版本0.17.0-r3。附近空锅、授权冰箱内有可行材料；先站近，说“做一份芦笋汤给我”。核实玩家实际入包1份，朋友对应减少1份。
2. 再在合理任务范围内站远一些，让朋友必须走近；途中移动一次。观察YBF_GIVE同一instance进入give→perform→actual_result，交付后动画正常结束。
3. 再次制作，收取后制造无法到达的交付路径。20游戏秒受阻后，日志cleanup_after应无该旧instance的实体、locomotor和SG引用/目的地。锅和已取食物不消失。
4. 保持首项受阻，分别安排第二、第三项料理，确认实际完成。解除阻碍，按第一项编号恢复：只交付库存中的汤，不再烹饪；最后数量与锅批次准确。
5. 如出现“清后又挂回”，保留cleanup_before/after到retired_action_reappeared区段。若尚未进入Perform，保留push_return/flight_monitor中的距离、目的地和SG。只有新增真实游戏的双边数量变化才能确认r3交付通过。

完整包无密钥、无完整玩家日志。来源核查摘要在knowledge/v0170_r3_execution_evidence.json；本轮模拟记录在tests/v0170_r3_*.log。旧版本说明保留，本文件为本轮有效说明。
