"""Public conversation text/context, independent of backend diagnostics."""
import re

def public_dialogue(text):
    # Strip only recognizable backend notices, not normal numbers/game answers.
    parts=re.findall(r'[^。！？\n]+[。！？]?|\n',text)
    kept=[]
    for part in parts:
        if re.search(r'任务指令完成|task\s+completed|processing_ms|rtt_ms|elapsed_ms|任务[Ii][Dd]|指令完成.*(?:用时|耗时)',part,re.I):
            continue
        kept.append(part)
    reply=''.join(kept).strip()
    reply=re.sub(r'[，,；;]?\s*(?:用时|耗时)\s*[:：]?\s*\d+(?:\.\d+)?\s*(?:ms|毫秒)', '',reply,flags=re.I).strip()
    return reply if reply.strip('。！？，,；; ') else '我在呢。'

def conversation_state(state):
    if not isinstance(state,dict):return {}
    result=dict(state)
    work=state.get('work')
    if isinstance(work,dict):
        def clean(value):
            if isinstance(value,dict):
                return {key:clean(item) for key,item in value.items() if key not in {'task_id','serial','attempt','step_index','audit','dependencies','time','last_plan_result','last_internal_summary'}}
            if isinstance(value,list):return [clean(item) for item in value]
            return value
        result['work']=clean(work)
    return result
