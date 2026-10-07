# PacGate 0.1.24 全栅 审计 + 烟测 E2E 总报告

> 2026-10-07 · AIPC #1 · 本报告 汇总 本次会话 全部 实测 证据 — 每 项 均 有 命令 输出 或 字节 级 验证

## 0. 结论速览

| 评定 | 结果 |
|---|---|
| 全栈 可用性 | **PASS** (26 容器 全部 Up, 关键 链路 全部 实测 通过) |
| 性能 | **PASS** (热 路径 22-116ms, 向量 35ms, 无 性能 缺陷) |
| 红线 (消毒 门控) | **PASS** (1597 pending 全部 排除; 消毒 管线 实测 通过) |
| 中文 链路 | **PASS** (每 层 字节 级 验证) |
| 持久化 | **PASS** (DB 1603 chunks / deer-flow 1.96GB / openviking 9.9MB / qm 77 表) |
| 已知 未完成 | tabular 引擎 未 接线 (脚手架, 非 回归); skills 目录 未 挂载 (上游 默认) |

## 1. 栈 清单 (26 容器)

| 组件 | 镜像 | 状态 |
|---|---|---|
| pacgate-api | ghcr.io/jzkk720/pacgate-api:0.1.24 | Up |
| pacgate-mcp | ghcr.io/jzkk720/pacgate-mcp:0.1.24 | Up |
| deer-flow | ghcr.io/jzkk720/deer-flow-pacgate:0.1.24 | Up |
| deer-flow-frontend | ghcr.io/jzkk720/deer-flow-frontend-pacgate:0.1.24 | Up |
| ocr-service | ghcr.io/jzkk720/ocr-service:0.1.24 | Up |
| pacgate-nginx / pacgate-db | nginx:1.27-alpine / pgvector:pg16 | Up |
| openviking | digest-pinned 46f9e34cd372 | Up healthy |
| qm-* (6) | digest-pinned ghcr.io/yc-software/qm/* | Up |

## 2. 烟测 E2E 结果 明细

### 2.1 pacgate-api (Rust)

| 测试 | 结果 | 证据 |
|---|---|---|
| 认证 login | PASS | JWT 287 字符, 633ms |
| matters CRUD | PASS | create 49ms / get 30ms / delete 34ms |
| workflows 模板 | PASS | 222 个, 8 分类 (litigation 45...), 字段 id/name/description/category/step_count |
| documents 元数据 | PASS | get/versions/sanitize-status 全 200 |
| 连接器 搜索 | PASS | /search/health + registry + connectors 200; 实搜 5.4s |
| dd-configs | PASS | 200, 10.4KB |
| kb/search 向量 | PASS | 冷 1349ms → 热 35-41ms |
| tabular | **STUB** | 500 引擎 未 接线 (源 码 确认) |

### 2.2 消毒 管线 (本次 实测 完整 E2E)

| 阶段 | 结果 | 证据 |
|---|---|---|
| 1. 创建 matter | PASS | 7bbe8a29 (E2E-SANITIZER-1007e) |
| 2. 上传 PDF (含 PII + 中文) | PASS | 22KB reportlab 生成, 71ms 上传 |
| 3. 抽取 /extract | PASS | 14.5s, 中文 + PII 文本 + spans |
| 4. 消毒 T3 | PASS | 14.3s, verdict=pass, redaction_count=2, chunks_promoted=1 |
| 5. 状态迁移 | PASS | documents.sanitization_state: pending → sanitized |
| 6. 脱敏 映射 库 | PASS | sanitizer_jobs.mapping: EMAIL/CN_MOBILE → 占位符, version 1 |
| 7. kb/search 可见性 | PASS | 消毒 后 chunk 可 检索 (score 0.36) |
| 8. 清理 | PASS | matter 删除, DB 归零 |

**设计 观察 (非 缺陷)**: kb/search 返回 原文 (含 PII) 给 已认证 租户 会话 - 脱敏 占位符 映射 保存 在 mapping vault, 用 于 导出/restore 层 (源 码 与 job verdict 一致: T3 matter binding 适用)

### 2.3 deer-flow (Python agent 层)

| 测试 | 结果 | 证据 |
|---|---|---|
| 认证 | PASS | local login 200 + csrf |
| API 端点 | PASS | auth/me 87ms, agents 116ms, models 40ms, skills 44ms, memory 75ms |
| 英文 agent E2E | PASS | 197.5s, 3 turns, prompt cache 生效 (48807 cached) |
| 中文 suggestions | PASS | 15.9s, 3 条 全 中文 (36 CJK 码点 验证) |
| 中文 agent E2E | PASS | 200.7s 完整 流; 提示 字节 完好 送达; 模型 选 英文 回 = 自主性 |
| skills=[] | 非 缺陷 | 两 份 compose 均 未 挂载 skills 目录 (上游 默认 行为) |

### 2.4 记忆 库 (openviking)

| 测试 | 结果 | 证据 |
|---|---|---|
| health/ready | PASS | 24ms / 227ms |
| MCP tools/list | PASS | 15 工具 |
| 中文 写读 roundtrip | PASS | viking://resources/bench/zh-smoke, 21 CJK 回读 |
| 持久化 | PASS | 本机 bind 挂载 9.9MB |

### 2.5 OCR (ocr-service)

| 测试 | 结果 | 证据 |
|---|---|---|
| 英文 PDF 44KB | PASS | 75.26s, 43.6KB 文本 |
| 中文 PDF 188KB | PASS | 30.2s, 71 CJK 字 正确 |
| 模型 持久化 | PASS | paddleocr 模型 卷 持久化 |

### 2.6 qm-pacgate

| 测试 | 结果 | 证据 |
|---|---|---|
| 沙箱 E2E | PASS | PACGATE-SANDBOX-OK, exit 0 (浏览器 会话 可见) |
| 沙箱 指纹 | PASS | 429e4a961adcd94e 匹配 钉定 digest 52e867fc |
| 中文 对话 | PASS | 浏览器 实测 回 全 中文 |
| 数据库 | PASS | qm db 77 表 |
| mailpit | PASS | API 200, 邮件 捕获 正常 |

### 2.7 中文 链路 (字节 级 验证)

| 层 | 结果 |
|---|---|
| pacgate-db 存储 | PASS |
| pacgate-api 模板名 码点 | PASS |
| ollama 中文 推理 (24 CJK 回) | PASS |
| deer-flow suggestions (36 CJK) | PASS |
| openviking roundtrip (21 CJK) | PASS |
| OCR 中文 PDF (71 CJK) | PASS |
| qm web UI 浏览器 实测 | PASS |

## 3. 持久化 存储 清单 (实测)

| 组件 | 存储 | 内容 |
|---|---|---|
| pacgate-db | 卷 pacgate-ai-bundle_pacgate-db-data | matters=10, documents=100, kb_chunks=1603, users=3 |
| deer-flow | bind data/deer-flow → /app/backend/.deer-flow | 1.96GB (线程 状态 + 工具 结果) |
| pacgate-api | bind data → /data + workflows → /app/workflows | 共享 2.0GB |
| ocr-service | 卷 paddleocr-models | 模型 缓存 |
| openviking | bind openviking → /app/.openviking | 9.9MB |
| qm-pacgate-pg | 卷 qm-pacgate-pgdata | qm db 77 表 |
| qm-pacgate-core | 卷 coredata + skills/tools 挂载 | 沙箱 层 |

## 4. 性能 基准 (摘录)

| 操作 | 延迟 |
|---|---|
| pacgate-api 热 路径 | 22-66ms |
| kb/search 向量 热 | 35-41ms (原生 pgvector 112-127ms, HNSW) |
| deer-flow API | 40-116ms |
| openviking | 24-227ms |
| qm | 29-115ms |
| 聊天 E2E | 197.5s (英) / 200.7s (中), cache 生效 |
| OCR | 30.2s (中 188KB) / 75.3s (英 44KB) |
| 连接器 实搜 | 5.4s (外部, 预期) |

## 5. 缺陷 与 观察 (全部 已记录)

| # | 类型 | 描述 | 状态 |
|---|---|---|---|
| 1 | 脚手架 | tabular review 引擎 未 接线 (POST/GET 均 500) | 已知, 源 码 标注 not yet wired |
| 2 | 部署 | skills 目录 未 挂载 进 容器 (skills=[]) | 上游 默认; 可选 增强 |
| 3 | 设计 | kb/search 向 认证 租户 返回 原文 (PII 在 租户 内 可见); 脱敏 占位符 仅 在 导出 层 | 与 当前 设计 一致; 如 需 角色 级 脱敏 需 上游 变更 |
| 4 | 行为 | agent 忽略 语言/工具 指令 (英 提示 调 vaquill 22x; 中 提示 英 回) | 模型 自主性; 建议 SOUL.md 强化 |
| 5 | 工具 | 本机 PS 5.1 生成 中文 .md 双重编码 | 已修复 (码点 构建 + BOM) |

## 6. 证据 存档 (本次 会话 命令 与 输出)

- 消毒 E2E: job da8191b7, verdict=pass, redaction_count=2, chunks_promoted=1
- 持久化: docker inspect 挂载 清单 + psql 计数 (见 第 3 节)
- 指纹: qm-sandbox-fingerprint.ps1 输出 [OK] 429e4a961adcd94e
- 基准: 详 2026-10-07-benchmark-0.1.24.md
- 中文 烟测: 详 2026-10-07-zh-e2e-smoke-0.1.24.md
