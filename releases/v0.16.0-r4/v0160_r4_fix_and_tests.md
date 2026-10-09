# v0.16.0-r4 服务器掉线修复

## 已证实的原因

本次server_log第1293行，00:03:11：
`../mods/my_best_friend/modmain.lua:248: attempt to call global 'pcall' (a nil value)`。
异常栈经原版networkclientrpc.lua:1743 HandleRPCQueue / TheNet:CallRPC进入点位接收器；参数raw含完整的点位JSON。说明客户端已经成功把点位送到服务器，服务器在JSON解码前崩溃。client_log随后记录Connection lost / ID_CONNECTION_LOST，与服务器中断一致。白色虚影不消失是等待回执的新流程；服务器崩溃后自然无法回执。无需额外上传文件。

源码依据是已提供756039 scripts/mods.lua的CreateEnvironment：模组沙箱显式提供type、print、pairs等，但不提供pcall，也不自动回退到_G。GLOBAL指向真实全局表，那里才有pcall。r3新增的两处裸pcall因此错误；第一处直接崩溃，第二处同样是后续隐患。这个错误由本次实现引入，不能归因于模型、玩家操作或安装错误。

## 修复及测试纠正

两处改为G.pcall，其中G=GLOBAL：一处用于解码，另一处用于执行位置提交保护。不改变坐标、权限、原版材料/预制规则或其他游戏动作；r3回执、取消、重试去重仍保留。

原test_game_adapter直接dofile(modmain)，执行在完整_G里，因此没有暴露pcall缺失。现在测试用不继承全局的白名单沙箱加载正式modmain，并明确assert沙箱pcall==nil。旧调用在该环境重现与用户日志相同的nil pcall异常；修复后再通过注册的实际RPC接收器测试解码、真实Control.Submit、工作恢复和回执。坏参数、权限拒绝、重复nonce、超时、发送失败与退出点选也回归。

这是对特定已复现崩溃的源码修复，并非仅加异常吞掉保护。详细结果tests/v0160_r4_*.log。现行Python76项、Lua语法及受限沙箱接口、建筑逻辑模拟、14句自然语言入口、基础工作回归通过。

验证限制：Lua测试库为5.4，DST引擎未运行；实体、网络、寻路/状态图依然是替身。用户日志提供了原版CallRPC确实收到JSON的现场证据，但本地不声称已执行实际TheNet或游戏放置。旧建筑模拟直接移动朋友到点位，不能作为真实寻路成功证明。没有新增真实模型调用或游戏实测；本轮只确认已定位崩溃的代码被纠正。

## 安装与最少复验

客户端与服务器模组使用同一r4完整包；后台也同步更新以便版本一致，保留自己的api_key.txt。重启后台与服务器，重新进入存档，不能只热替换已缓存modmain。

先取消旧任务，确保朋友或授权友谊箱已有材料，再说“在这里建一个科学机器”，点击合法空地并让开：
1. 确认不再掉线。
2. 查看是否出现“位置已确认”，服务器日志是否出现[YBF POINT] phase=received及accepted/rejected。
3. accepted之后观察实际准备、移动与建筑实体；只有实体出现才算施工通过。若停在后续阶段，保留该次日志，无需反复发送继续。
4. 再试一次右键/Esc退出点选和“取消任务”。

本包不含用户原始日志、玩家身份或密钥。其他0.16建筑支持限制沿用r3，未新增蓝图、战斗、拆除、耕种或主动行为。
