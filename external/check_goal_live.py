"""One REAL provider request through production bridge decoding.
Not a game/chat UI test. Reads existing local key; never prints it.
Run: python check_goal_live.py [--message "我想要一个石砖"]
"""
import argparse,json,os,time,uuid
from pathlib import Path
from bridge import BridgeServer,PROTOCOL

def main():
    parser=argparse.ArgumentParser(description='真实模型目标解析检查；不执行游戏动作，不等同聊天入口/游戏内验收')
    parser.add_argument('--message',default='我想要一个石砖')
    args=parser.parse_args()
    keyfile=Path(__file__).with_name('api_key.txt')
    key=(keyfile.read_text(encoding='utf-8-sig').strip() if keyfile.exists() else '') or os.environ.get('DEEPSEEK_API_KEY','').strip()
    if not key or key.startswith('在这里'):
        print('NOT RUN: 没有本地已配置的密钥；未发出真实模型请求。无需提供或上传密钥。')
        return 2
    server=BridgeServer(('127.0.0.1',0));server.ai=True;server.api_key=key
    request_id='live-goal-'+uuid.uuid4().hex
    try:
        server.submit(dict(protocol=PROTOCOL,request_id=request_id,friend_id='live-probe',friend_name='朋友',message=args.message,
                           conversation_id=request_id,game_state={'inventory':{'items':[]},'work':{'version':'0.12.1','radius':32,'capabilities':['goal','bounded_dependencies'],'recipes':['axe','pickaxe','cutstone','boards','rope','torch']}}))
        for _ in range(450):
            result=server.lookup(request_id,server.instance_id)[1]
            if result['state']!='pending':break
            time.sleep(.1)
        safe={k:result[k] for k in ('state','action','item','quantity','error','diagnostic') if k in result}
        print('REAL PROVIDER RESULT (不是游戏入口/游戏执行验证):')
        print(json.dumps(safe,ensure_ascii=False,indent=2))
        return 0 if result.get('state')=='done' else 1
    finally:server.server_close()

if __name__=='__main__':raise SystemExit(main())
