# Pacgate-ai 客户交付包（Client Delivery Package）

> 面向律师事务所客户的技术交付文档集
> 版本 0.1.3 — 2026-09-04

本交付包包含 Pacgate-ai 系统的**客户可见文档**（PDF）与**运行时部署包**。请按读者分发：

---

## 一、文档（`docs/`）— 按读者分发

| 文档 | 读者 | 用途 |
|---|---|---|
| **USER-MANUAL-ZH.pdf** | 律师、助理、合伙人 | 终端用户使用手册（中文） |
| **USER-MANUAL.pdf** | 律师、助理、合伙人 | 终端用户使用手册（英文） |
| **AIPC-DEPLOYMENT-HANDBOOK-ZH.pdf** | 客户 IT / 部署工程师 | 双 AIPC 部署手册（中文） |
| **AIPC-DEPLOYMENT-HANDBOOK.pdf** | 客户 IT / 部署工程师 | 双 AIPC 部署手册（英文） |
| **deer-flow-openviking-pacgate-handbook.zh.pdf** | 客户技术团队 | deer-flow + OpenViking + pacgate 网关集成原理 |
| **qm-openviking-pacgate-handbook.zh.pdf** | 客户技术团队 | qm + OpenViking + pacgate 网关/RAG 集成原理 |

> **说明**：`USER-MANUAL` 与 `AIPC-DEPLOYMENT-HANDBOOK` 提供中英双语；两份集成手册目前仅中文版。

---

## 二、运行时部署包（`client-bundle/`）— 机器要跑起来需要什么

`client-bundle/` 是**运行时包**（配置、脚本、镜像引用），与文档分开但一起交付：

```
client-bundle/
├── compose.prod.yaml          ← pacgate-api + deer-flow + nginx + Postgres 的 Docker Compose
├── install.ps1                ← 一键 Windows 安装脚本
├── setup-qm.ps1               ← qm 启动脚本
├── .env.example               ← 客户填写数据库密码 + JWT 密钥 + OpenViking 密钥
├── deer-flow-config.yaml      ← deer-flow 多模型配置
├── deer-flow-extensions-config.json ← MCP 服务器注册（法律数据库 + OpenViking）
├── ollama-models.txt          ← 需要预先拉取的模型
├── nginx/default.conf         ← 运行时 nginx 路由
├── openviking/                ← OpenViking 配置
├── workflows/                 ← 15 个 YAML 文件，220 个工作流模板
└── personas/                  ← 20 个执业领域 + 10 个 SOUL 角色参考
```

> **⚠️ 注意**：`client-bundle/` 内的 `.env`、`deer-flow-extensions-config.json`（含 API 密钥）、
> `data/`（运行时租户数据）**不**随交付包分发，也不提交到仓库。客户需自行填写 `.env.example`。

---

## 三、交付结构

```
client-delivery/
├── README.md                  ← 本索引
├── docs/                      ← 客户文档（PDF）
│   ├── USER-MANUAL-ZH.pdf
│   ├── USER-MANUAL.pdf
│   ├── AIPC-DEPLOYMENT-HANDBOOK-ZH.pdf
│   ├── AIPC-DEPLOYMENT-HANDBOOK.pdf
│   ├── deer-flow-openviking-pacgate-handbook.zh.pdf
│   └── qm-openviking-pacgate-handbook.zh.pdf
└── client-bundle/             ← 运行时部署包（见上）
```

---

## 四、快速开始（客户 IT）

1. 安装 Docker Desktop 与 Ollama（`ollama signin`）
2. 克隆仓库：`git clone https://github.com/JZKK720/pacgate-ai-pr.git`
3. 进入 `deploy/client-bundle/`，复制 `.env.example` 为 `.env` 并填写
4. 运行 `.\install.ps1`
5. 打开浏览器：`http://localhost:8081`（检索）/ `http://localhost:8182`（协作）

完整分步安装见 `docs/AIPC-DEPLOYMENT-HANDBOOK-ZH.pdf`。

---

> 本交付包由 pacgate-ai 部署文档与运行环境自动整理生成。版本 0.1.3 — 2026-09-04。
