---
name: event-debugger
description: 查询和调试视觉小说事件数据。Use when users need to (1) 查看事件列表/详情, (2) 追溯事件前置条件链, (3) 查找无条件/低门槛可触发事件, (4) 检查 flag/pool/quest 依赖关系, (5) 校验 JSON 引用完整性, (6) 编辑事件脚本/前置条件/效果, (7) 排查"为什么事件没触发", (8) 生成事件依赖图, (9) 填充剧情/补全事件脚本内容, (10) 查找缺少脚本或脚本行数不足的事件。
---

# Event Debugger

事件数据调试 CLI，位于 `tools/event_debugger.py`，数据目录默认 `assets/data/`。

**调用方式**: `python3 tools/event_debugger.py <command> [args]`（在 `/workspace` 下执行）

## 剧情填充工作流（核心场景）

批量填充/补全事件脚本的典型流程：

### Step 1: 定位缺脚本的事件

```bash
python3 -c "
import json, pathlib
for f in sorted(pathlib.Path('assets/data/events').glob('*.json')):
    payload = json.loads(f.read_text('utf-8'))
    for r in (payload if isinstance(payload, list) else [payload]):
        if not isinstance(r, dict) or 'id' not in r: continue
        lines = r.get('script',{}).get('lines',[])
        n = len(lines)
        if n == 0:
            tag = 'EMPTY'
        elif n <= 3:
            tag = 'SPARSE'
        else:
            continue
        print(f'[{tag:6s}] {r[\"id\"]:50s} | {r.get(\"type\",\"?\"):15s} | {r.get(\"phase\",\"?\"):12s} | {r.get(\"locationId\",\"?\"):25s} | {r.get(\"name\")}')
"
```

可加 `--chapter` 等过滤（自行在脚本中加 `if r.get('chapterId') \!= 'chapter_02': continue`）。

### Step 2: 查看事件上下文

```bash
python3 tools/event_debugger.py show <event_id>
```

关注：`participants`（谁参与）、`phase/location`（场景）、`event_prereqs`（前面发生了什么）、`next_events`（后续衔接）、`notes`（策划备注）、`scene_defaults`（演出环境）。

### Step 3: 查看前后事件的脚本（理解剧情衔接）

```bash
# 看前置事件的脚本结尾
python3 tools/event_debugger.py show <prereq_event_id>
# 看后续事件的脚本开头
python3 tools/event_debugger.py show <next_event_id>
```

### Step 4: 写入脚本行

```bash
# 添加 stage cue（背景+立绘，推荐作为第一行）
python3 tools/event_debugger.py edit line-add-json <event_id> \
  '{"type":"stage","cues":[{"op":"background_change","backgroundId":"<bg_id>","transition":"fade"},{"op":"portrait_show","characterId":"<char_id>","slot":"left","expressionId":"soft_smile","effectId":"fade_in"}]}' --at 1

# 添加旁白
python3 tools/event_debugger.py edit line-add <event_id> "旁白文本" --type narration

# 添加对白
python3 tools/event_debugger.py edit line-add <event_id> "台词文本" \
  --type dialogue --speaker-id <char_id> --slot left --expression-id soft_smile

# 在指定位置插入
python3 tools/event_debugger.py edit line-add <event_id> "台词" \
  --type dialogue --speaker-id youkichi --slot center --expression-id bright_smile --at 3
```

### Step 5: 验证

```bash
python3 tools/event_debugger.py validate --strict
```

### 表情/槽位/效果速查

| 表情 expressionId | 语义 |
|---|---|
| neutral, soft_smile, bright_smile | 平静/微笑/开朗 |
| troubled, serious, surprised | 困扰/严肃/惊讶 |
| embarrassed, sad, angry | 尴尬/悲伤/愤怒 |
| tired, wary, thinking, shadowed | 疲惫/警惕/思考/阴沉 |

| 槽位 slot | 布局 |
|---|---|
| left, right | vn_two_side 标准双人 |
| left, center, right | vn_three_way 三人 |

| 效果 effectId | 用途 |
|---|---|
| fade_in/fade_out | 立绘渐入/渐出 |
| slide_in_left/right | 滑入 |
| shake, hop, flash | 强调（震动/跳动/闪白） |
| focus, unfocus, dim | 聚焦/弱化/变暗 |

## 查询命令

### 列出事件

```bash
python3 tools/event_debugger.py list events
python3 tools/event_debugger.py list events --phase night
python3 tools/event_debugger.py list events --pool ch2_night_pool
python3 tools/event_debugger.py list events --type main_story
python3 tools/event_debugger.py list events --location library
python3 tools/event_debugger.py list events --contains 柚吉
```

### 列出其他类型

```bash
python3 tools/event_debugger.py list quests
python3 tools/event_debugger.py list locations
python3 tools/event_debugger.py list pools
python3 tools/event_debugger.py list flags
```

### 查看详情 / 追溯 / 排查

```bash
python3 tools/event_debugger.py show <id>
python3 tools/event_debugger.py trace <event_id> --max-depth 4
python3 tools/event_debugger.py why-not <event_id>
python3 tools/event_debugger.py flag <flag_name>
python3 tools/event_debugger.py graph <event_id> --max-depth 4
python3 tools/event_debugger.py validate --strict
```

## 编辑命令

所有编辑命令支持 `--dry-run` 预览。

```bash
# 脚本行（行号从 1 开始）
python3 tools/event_debugger.py edit line-set <event_id> <n> "文本" --type dialogue --speaker-id <id> --slot left --expression-id soft_smile
python3 tools/event_debugger.py edit line-add <event_id> "文本" --type dialogue --speaker-id <id> --at 3
python3 tools/event_debugger.py edit line-set-json <event_id> <n> '<json>'
python3 tools/event_debugger.py edit line-add-json <event_id> '<json>' --at 1
python3 tools/event_debugger.py edit line-del <event_id> <n>

# 前置条件 / 效果
python3 tools/event_debugger.py edit precondition-add <event_id> '{"type":"flag_set","flag":"xxx"}'
python3 tools/event_debugger.py edit precondition-del <event_id> <index>
python3 tools/event_debugger.py edit effect-add <event_id> '{"type":"flag_set","flag":"xxx"}'
python3 tools/event_debugger.py edit effect-del <event_id> <index>

# Flag 重命名
python3 tools/event_debugger.py edit flag-rename old_flag new_flag

# 记录 CRUD
python3 tools/event_debugger.py edit create-record events data/events/file.json '<json>'
python3 tools/event_debugger.py edit delete-record <record_id>
```

## 其他常见场景

### 找低门槛可触发事件（用于测试）

```bash
python3 -c "
import json, pathlib
for f in sorted(pathlib.Path('assets/data/events').glob('*.json')):
    payload = json.loads(f.read_text('utf-8'))
    for r in (payload if isinstance(payload, list) else [payload]):
        if not isinstance(r, dict) or 'id' not in r: continue
        p = r.get('preconditions', [])
        types = [c.get('type') for c in p if isinstance(c, dict)]
        if not p or all(t == 'chapter_started' for t in types):
            print(f'{r[\"id\"]:50s} | preconds={len(p)} | lines={len(r.get(\"script\",{}).get(\"lines\",[]))} | {r.get(\"name\")}')
"
```
