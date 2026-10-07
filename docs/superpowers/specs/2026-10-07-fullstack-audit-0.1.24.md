# 0.1.24 鍏ㄦ爤瀹¤鎶ュ憡 (2026-10-07) 鈥?gstack + karpathy 鍑嗗垯

## 鎬讳綋鍒ゅ畾: 鉁?PASS 鈥?鍏ㄦ爤 E2E 宸ヤ綔姝ｅ父

## 1. 瀹瑰櫒鑸伴槦 (16 涓?pacgate 鐩稿叧瀹瑰櫒)
- 5 涓钩鍙伴暅鍍忓叏閮?0.1.24 (pacgate-api, pacgate-mcp, deer-flow, deer-flow-frontend, ocr-service)
- 0 閲嶅惎 (鏃犲穿婧冨惊鐜?; openviking healthy (v0.4.16); qm 7 瀹瑰櫒姝ｅ父
- compose.prod.yaml: name 閽夊瓙 + 0.1.24 閽夊瓙 + mem_limit 4g + 娉ㄥ唽闂?鍏ㄩ儴灏变綅 (宸叉彁浜?79af77e)

## 2. 鏈嶅姟鍋ュ悍
| 绔偣 | 鐘舵€?|
|---|---|
| pacgate-api /pacgate/health | 200 |
| deer-flow frontend :8090 | 200 |
| nginx :8089 root | 200 |
| openviking :1933 | 200 (healthy) |
| qm web-ui :8182 / admin :8183 | 200 |
| qm portal :8181 | 401 (auth gate, 姝ｇ‘) |
| pacgate-api /version | 401 (auth gate, 姝ｇ‘) |

## 3. 鏁版嵁灞?(persistent data lane)
- pacgate-db: 1 tenant / 3 users / 10 matters / 100 documents / 1603 kb_chunks / 340 spans / 7 sanitizer jobs
- pgvector 鎵╁睍 OK; 鍏ㄩ儴 1603 chunks 鏈?768 缁?embedding (涓?ollama nomic-embed-text 涓€鑷?
- content_tsv 鍏ㄩ儴濉厖 (鍏抽敭璇嶉€氶亾鍙敤)

## 4. vectorDB / RAG 妫€绱?鈥?鉁?宸ヤ綔姝ｅ父 (绾㈢嚎鏈哄埗鐢熸晥)
- **鍙戠幇**: 瀵?1597-chunk 鐨勫ぇ matter 鎼滅储杩斿洖 0 缁撴灉 鈥?鏍瑰洜鏄?*鍑€鍖栭棬** (sanitization gate):
  AND c.sanitization_state IN ('sanitized','never') 鈥?1597 chunks 鏄?'pending',鍙湁 6 涓?'sanitized'
- **杩欐槸绾㈢嚎姝ｇ‘鐢熸晥**: 鏈噣鍖栧唴瀹逛笉鍙绱€傚鍚?sanitized chunks 鐨?matter 鎼滅储杩斿洖 2 缁撴灉 (score 0.25)
- SQL 鍙岄€氶亾 (pgvector 璇箟 + tsvector 鍏抽敭璇? 鎵嬪伐楠岃瘉鍧囧伐浣? tenant/matter 瑙ｆ瀽姝ｇ‘
- /api/search (娉曞緥鏁版嵁搴撹繛鎺ュ櫒) 杩斿洖 eur-lex 绛?9 涓繛鎺ュ櫒缁撴灉

## 5. OCR 鈥?鉁?PASS
- test-ocr-extraction: paddleocr 寮曟搸, span 鍧愭爣姝ｇ‘ (page=1 x=13 y=31 w=124 h=12, 韬唤璇佸彿璇嗗埆)

## 6. Sanitizer + Matters 宸ヤ綔娴?鈥?鉁?PASS
- test-sanitization-gate: 鍏ㄩ儴鏂█閫氳繃 (documents.matter_id == kb_chunks.matter_id)
- test-legal-journey: 17/17 (鍏ㄩ€氶亾)
- test-sanitizer-e2e-local: PASS (upload -> sanitize -> gate -> admin restore -> ledger + audit 琛?

## 7. openviking 璁板繂搴?鈥?鉁?PASS
- write (remember) -> 鎸佷箙鍖?-> read 鍏ㄩ摼璺獙璇? 浠婃棩 (2026/10/07) 宸叉湁鐪熷疄鎻愬彇鐨勮蹇嗘枃浠?
- vault 鏍戝惈鐪熷疄鏁版嵁: pacgate_workflows_intro.md (18.6KB), patent-disclosure-skill 鏂囨。, 鑱斿姩楠岃瘉璁板繂
- 璇箟绱㈠紩寮傛婊炲悗 (by design); MCP 宸ュ叿闈? find/search/read/list/tree/remember/write/edit/forget/grep/glob 绛?15 涓?

## 8. 绾挎潫 (harnesses)
- deer-flow: 137 MCP 宸ュ叿缂撳瓨鍔犺浇, 鎸佷箙 MCP session pool 鍒涘缓, 30 杩炴帴鍣ㄩ厤缃湪浣?
- pacgate-mcp: 19 宸ュ叿 (kb_search, ocr_document/batch, sanitize_document/text, verify_sanitized, read/write_memory, workflows, connectors) 鈥?initialize 200 瀹瑰櫒鐩磋繛
- qm: core 鍋ュ悍, 娌欑绾挎潫瀹屾暣 (SANDBOX_BACKEND=local + LOCAL_SANDBOX_IMAGE + docker CLI 28.5.2 + socket)
- 娌欑 E2E (鏈細璇濇棭鍓?: spawn -> exec -> teardown 鍏ㄧ敓鍛藉懆鏈熼€氳繃

## 9. 宸茬煡浜嬮」 (闈為樆濉?
- 鑱婂ぉ閾捐矾: 鍔熻兘姝ｅ父浣嗘湰鍦?12B 妯″瀷鍦?137 宸ュ叿/48k token 鎻愮ず涓嬭緝鎱?(鏃㈡湁琛屼负)
- /api/memory 鍓嶇浠ｇ悊缂洪櫡: 宸茬敤 nginx location 淇 (commit a6b6626), 涓婃父 PR 鍊欓€夊凡澶?
- bootstrap admin 瑙掕壊鏁版嵁缂哄彛: 宸?SQL 淇 (system_role='admin'), 鍊煎緱涓婃父鎶ュ憡
- 1597 chunks 澶勪簬 'pending' 鍑€鍖栫姸鎬? 灞炴甯歌繍钀ョ姸鎬?(闇€鎸夐渶鍑€鍖?, 闈炵己闄?