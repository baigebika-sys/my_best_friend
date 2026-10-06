name = "我最好的朋友 / My best friend"
description = "v0.12.1 修复正常闲聊、自然汇报及砍挖异步异常保护；保留目标工作与有界依赖补齐；保留聊天、补状态、跟随和等待。"
author = "My best friend"
version = "0.12.1"
api_version = 10
dst_compatible = true
dont_starve_compatible = false
reign_of_giants_compatible = false
shipwrecked_compatible = false
hamlet_compatible = false
client_only_mod = false
all_clients_require_mod = true
server_filter_tags = { "My best friend" }

configuration_options={
 {name="pickup_radius",label="附近工作半径（旧设置至少32）",options={{description="32（默认）",data=32},{description="40",data=40},{description="48",data=48},{description="64",data=64}},default=32},
 {name="pickup_timeout",label="工作任务时间上限（秒）",options={{description="30",data=30},{description="60（默认）",data=60},{description="120",data=120}},default=60},

 {name="hunger_trigger",label="饥饿需求触发",options={{description="20%",data=0.2},{description="30%",data=0.3},{description="40%",data=0.4},{description="50%",data=0.5},{description="60%",data=0.6},{description="70%",data=0.7},{description="75%",data=0.75}},default=0.4},
 {name="hunger_target",label="饥饿恢复目标",options={{description="50%",data=0.5},{description="60%",data=0.6},{description="70%",data=0.7},{description="75%",data=0.75},{description="80%",data=0.8},{description="90%",data=0.9},{description="95%",data=0.95}},default=0.8},
 {name="health_trigger",label="生命需求触发",options={{description="20%",data=0.2},{description="30%",data=0.3},{description="40%",data=0.4},{description="50%",data=0.5},{description="60%",data=0.6},{description="70%",data=0.7},{description="75%",data=0.75},{description="80%",data=0.8}},default=0.7},
 {name="health_target",label="生命恢复目标",options={{description="75%",data=0.75},{description="80%",data=0.8},{description="90%",data=0.9},{description="95%",data=0.95}},default=0.9},
 {name="sanity_trigger",label="精神需求触发",options={{description="20%",data=0.2},{description="30%",data=0.3},{description="40%",data=0.4},{description="50%",data=0.5},{description="60%",data=0.6},{description="70%",data=0.7}},default=0.4},
 {name="sanity_target",label="精神恢复目标",options={{description="50%",data=0.5},{description="60%",data=0.6},{description="70%",data=0.7},{description="75%",data=0.75},{description="80%",data=0.8},{description="90%",data=0.9},{description="95%",data=0.95}},default=0.75},
 {name="help_cooldown",label="求助最小间隔（秒）",options={{description="30",data=30},{description="60",data=60},{description="120",data=120}},default=60},
}
