# 0.1.24 全栅审计 (2026-10-07) · gstack + karpathy

> **v2 注**: v1 正 文 因 PS 5.1 双重编码 损坏, 已 于 同日 重写 (测量 数据 不受 影响)
> 中文 E2E 烟测 补充 报告: 2026-10-07-zh-e2e-smoke-0.1.24.md

## 审计 结果 (全部 PASS)

| 组件 | 结果 | 证据 |
|---|---|---|
| pacgate-api | PASS | 健康/认证/工作流/文档 全 通 |
| pacgate-mcp | PASS | 19 工具 tools/list OK |
| deer-flow | PASS | 认证/会话/运行 全 通 |
| deer-flow-frontend | PASS | :8090 200 |
| ocr-service | PASS | /extract 英文 75.3s / 中文 30.2s |
| openviking | PASS | 健康 + MCP + 中文 写读 roundtrip |
| pacgate-db | PASS | HNSW 索引 就位, 红线 门控 生效 |
| qm-pacgate | PASS | 沙箱 E2E + 中文 UI 渲染 |
| 向量库 | PASS | kb/search 热 35-41ms |
| 记忆 库 | PASS | /api/memory 75ms (nginx 修复) |

## 详细 数据

- 基准 测试: 2026-10-07-benchmark-0.1.24.md
- 中文 E2E: 2026-10-07-zh-e2e-smoke-0.1.24.md
- 已知 行为 特征: 首 turn 137s (48k 系统 提示 未 缓存), 连接器 实搜 5.4s, agent 指令 服从 度 低
