# v0.10.0 新增测试参考

这些文件是原版游戏脚本的公开源码副本／未修改片段，用于开发侧模拟，不安装到 mods 中。获取日期：2026-10-06。

- bufferedaction.lua：https://github.com/vietnd69/dst-scripts/blob/main/bufferedaction.lua
- actions_work.lua：actions.lua 中 DoToolWork、CHOP、MINE、PICK、GIVETOPLAYER、BUILD 原版函数片段：https://github.com/vietnd69/dst-scripts/blob/main/actions.lua
- tool.lua：https://github.com/vietnd69/dst-scripts/blob/main/components/tool.lua
- finiteuses.lua：https://github.com/vietnd69/dst-scripts/blob/main/components/finiteuses.lua

另核对了同一源码镜像的 components/builder.lua、inventory.lua、pickable.lua、workable.lua、trader.lua、lootdropper.lua，prefabs/rocks.lua、evergreens.lua、deciduoustrees.lua 与 stategraphs/SGwilson.lua。它是源码镜像，不是本地已安装游戏版本的证明。

My Mate 与 GrimWorld 来自用户附件，仅学习组件判定、工具装备、动作结束等待、释放任务和有限失败处理；未整体移植其模组逻辑。
