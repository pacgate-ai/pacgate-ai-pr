# 仓库整合与运行时锁定 — 设计方案

- **日期**: 2026-09-16
- **状态**: 待评审（设计阶段，未实施）
- **触发问题**: "there are two identical repo locally, can we merge everything from `C:\pacgate-ai-pr` into this repo, and also pin and support our entire docker containers and runtime stacks?"

---

## 1. 结论先行

**前提不成立，因此"合并两个仓库"这个动作不应该做。** 但问题背后的真实痛点是真的，且需要解决。

经实测：

1. 两个 `pacgate-ai` 目录 **不是同一个仓库的副本**，而是同名但完全不同的东西（见 §2）。
2. `pacgate-law` **实际上还不是一个仓库** —— 零提交、无 remote（见 §3）。
3. 用户所说的"我们全部的 docker 容器"，**大部分不在两个仓库里**，而在 6 个同级目录中（见 §4）。

因此本方案把问题重新表述为两个可独立交付的目标：

- **目标 A（治理）**: 消除"哪个目录是权威"的歧义。
- **目标 B（运行时）**: 把实际运行的 25 个容器固化成可复现的清单。

**本阶段仅实施目标 B 中零风险的部分**（清单与生成脚本），目标 A 只出方案不出手，因为涉及嵌套 git 仓库改写，属不可逆操作，且与本仓库 `AGENTS.md` 明示的红线冲突。

---

## 2. 实测证据：两个 `pacgate-ai` 不是同一个东西

| 维度 | `C:\pacgate-ai-pr\pacgate-ai` | `c:\Users\pacga\github-pr\pacgate-law\pacgate-ai` |
|---|---|---|
| 实质 | **真实的 Rust workspace** | `JZKK720/pacgate-ai` 的嵌套 git clone |
| 顶层内容 | `crates/` `migrations/` `wasm-crates/` `workflows/` `target/` `Cargo.lock` | `assets/` `pacgate-ai/` `AGENTS.md` `DEER-FLOW-INTEGRATION.md` |
| 版本 | `0.1.9` | `0.1.0` |
| 体积 | 4,520 MB | 85 MB |
| `Cargo.toml` | 2,337 bytes | 2,498 bytes |

两者的 `Cargo.toml` 虽然 workspace 成员列表相同（都是 scaffolded 16 个 crate），但**版本号不同、依赖声明不同、文件长度不同**。它们不是副本，是"一个名字两个实体"。

> 这正是本仓库 `AGENTS.md` 已经警告过的误区来源。`AGENTS.md` 说"不要为 scaffolded 的 Cargo workspace 写 Rust 源码"，指的是第二个（`pacgate-law\pacgate-ai\pacgate-ai\Cargo.toml` 这个 declare-only 版本）。

## 3. 实测证据：`pacgate-law` 还不是仓库

```
git log       → fatal: your current branch 'main' does not have any commits yet
git remote -v → (空)
git ls-files -s pacgate-ai  → 160000 f712ec2c... pacgate-ai     ← submodule gitlink
submodule 实际 HEAD         → 0f7db15
```

- 执行过 `git init`，少量文件已 `git add` 进暂存区，但**从未提交**，也**没有 remote**。
- `.gitmodules` 声明了一个 submodule：`https://github.com/JZKK720/pacgate-ai.git`。
- gitlink 指向 `f712ec2`，而工作区实际停在 `0f7db15` —— **指针对不上，submodule 处于 dirty + diverged 状态**。

`AGENTS.md` 对此有明文约束：

> **Do NOT** create a GitHub repo for `pacgate-law`. Treat `pacgate-ai-pr` as the single source of truth.

## 4. 实测证据：容器分散在 6 个项目里

`docker compose ls` + compose 标签实测结果：

| Compose 项目 | 容器数 | compose 文件位置 | 是否在本次讨论的两个仓库内 |
|---|---|---|---|
| `pacgate-ai-bundle` | 7 | `C:\pacgate-ai-pr\deploy\client-bundle\compose.bundle.yaml` | ✅ 在 `pacgate-ai-pr` |
| `qm-pacgate` | 7 | `C:\pacgate-ai-pr\deploy\qm-pacgate\compose.qm.yaml` | ✅ 在 `pacgate-ai-pr` |
| `odysseus` | 4 | `C:\Users\pacga\github-pr\odysseus\docker-compose.yml` |  外部目录 |
| `hermes-agent` | 3 | `C:\Users\pacga\github-pr\hermes-agent\docker-compose.upstream.yml` | ❌ 外部目录 |
| `ironclawai-survey` | 1 | `C:\Users\pacga\github-pr\ironclawai-survey\docker-compose.yml` |  外部目录 |
| `dockhand` | 1 | `C:\Users\pacga\github-pr\dockhand-dash\docker-compose.yaml` | ❌ 外部目录 |
| *（未托管）* | 2 | 无 compose 标签，裸 `docker run` |  无来源 |

**25 个容器中只有 14 个可追溯到 `pacgate-ai-pr`。** 其余 11 个属于独立的上游 clone 目录。所以"把 `pacgate-ai-pr` 合并进来"**并不能**实现"锁定全部容器"——那 11 个容器根本不在 `pacgate-ai-pr` 里。

---

## 5. 目标 B 的现状：可复现性缺口

`runtime/capture-runtime.ps1` 的实测输出（25 个容器）：

**未托管容器（2）** —— 无 compose 项目，无法通过 compose 重建：

- `cloudflare` → `cloudflare/cloudflared:latest`
- `open-webui` → `ghcr.io/open-webui/open-webui:main`

**浮动镜像引用（9）** —— 未按 digest 锁定，未来 `pull` 会静默换代码：

| 容器 | 项目 | 镜像引用 | 浮动原因 |
|---|---|---|---|
| `cloudflare` | (未托管) | `cloudflare/cloudflared:latest` | 移动标签 `:latest` |
| `open-webui` | (未托管) | `ghcr.io/open-webui/open-webui:main` | 移动标签 `:main` |
| `dockhand` | dockhand | `fnsys/dockhand:latest` | 移动标签 `:latest` |
| `hermes-gateway` | hermes-agent | `ghcr.io/jzkk720/hermes-agent:latest` | 移动标签 `:latest` |
| `hermes-web` | hermes-agent | `ghcr.io/jzkk720/hermes-agent:latest` | 移动标签 `:latest` |
| `ironclawai-survey` | ironclawai-survey | `ironclawai-survey-ironclawai-survey` | 无标签（隐式 `:latest`） |
| `odysseus-chromadb-1` | odysseus | `docker.io/chromadb/chroma:latest` | 移动标签 `:latest` |
| `odysseus-ntfy-1` | odysseus | `docker.io/binwiederhier/ntfy` | 无标签（隐式 `:latest`） |
| `odysseus-odysseus-1` | odysseus | `ghcr.io/jzkk720/odysseus:main` | 移动标签 `:main` |

**已经锁定得好的部分**（值得保留的做法）：

- `qm-pacgate` 的 5 个镜像全部按 `@sha256:` 锁定。
- `openviking` 在 `compose.bundle.yaml` 中按 `@sha256:` 锁定。
- PacGate 自己的 4 个镜像使用明确的语义化版本标签（`0.1.9` / `0.1.10` / `0.1.11`）。

**一个需要人工确认的隐患**：本机存在**两个** `deer-flow-frontend-pacgate` 版本——运行中的容器用的是 `0.1.11`，而 `compose.bundle.yaml` 里写的是 `0.1.11`（一致 ✅），但 `0.1.10` 与 `0.1.9` 仍在本地镜像库中，且 `deer-flow-pacgate` 运行的是 `0.1.10`。版本组合为 `deer-flow-pacgate:0.1.10` + `deer-flow-frontend-pacgate:0.1.11`，**跨版本混用**，需要确认这是有意的。

---

## 6. 三个方案

### 方案 A — 合并进 `pacgate-ai-pr`，让 `pacgate-law` 退役

把 `pacgate-law` 的文档资产并入 `pacgate-ai-pr`，删掉 `pacgate-law`。

- ✅ 单一权威源，消除歧义
- ❌ **技术上不可行**：`pacgate-law` 的 `pacgate-ai` 是一个 85MB 的独立 git clone，含独立历史；`pacgate-ai-pr` 里已有一个同名但内容完全不同的 `pacgate-ai/`（Rust workspace）。合并会产生**路径与语义双重冲突**。
- ❌ 与本仓库 `AGENTS.md` 明文红线直接冲突。
- ❌ 涉及改写嵌套 git 仓库，不可逆。
- **判定：否决。**

### 方案 B — `pacgate-law` 作为本地伞形工作区（umbrella）

保持 `pacgate-law` 为 local-only，把 6 个同级目录作为并列项目纳入一个 workspace 定义，并修正其 git 状态（提交 / 明确 submodule 指针）。

- ✅ 解决"东西在哪"的问题，不动任何上游仓库
- ✅ 符合 `AGENTS.md` 的 local-only 定位
- ️ 需要修复 submodule 指针错位（gitlink `f712ec2` vs 实际 `0f7db15`）
- ⚠️ `.gitmodules` 指向 `JZKK720/pacgate-ai.git`，而本机只有 `pacgate-ai/*` 的推送权限，clone 会失败
- **判定：可行，但需先修 submodule 状态。建议作为下一阶段。**

### 方案 C — 只做运行时锁定（本次采用）

不合并任何仓库。产出一份权威的运行时清单 + 可重复执行的生成脚本。

- ✅ **零风险**：不碰 git，不碰容器
- ✅ 立即产生价值：9 个浮动引用 + 2 个未托管容器被显式记录
- ✅ 可重复：任何时候重跑即得当前状态
- ❌ 不解决"权威目录"的歧义（留给方案 B）
- **判定：采用。本次已实施。**

---

## 7. 本次交付物

| 文件 | 作用 |
|---|---|
| `runtime/capture-runtime.ps1` | 生成器：枚举容器 → 解析 compose 归属 → 记录 digest → 标记浮动/未托管 |
| `runtime/runtime-inventory.json` | 机器可读的完整清单（25 容器，含 digest、端口、网络、重启策略） |
| `runtime/RUNTIME-INVENTORY.md` | 人可读清单，按 compose 项目分组，含风险小节 |
| `runtime/README.md` | 使用说明与已知风险 |
| `docs/superpowers/specs/2026-09-16-repo-consolidation-and-runtime-pinning-design.md` | 本设计文档 |

**设计要点**：脚本刻意区分两个常被混淆的概念——

- `refPinned`：镜像引用本身是否指明不可变字节（只有 `@sha256:` 才算）。决定"将来 pull 会不会变"。
- `digest`：当前容器**实际**运行的字节。始终记录，因此即使引用是浮动的，运行状态仍可事后恢复。

初版脚本把这两者混为一谈（因为本地总能解析出 digest，导致浮动引用被误标为 "pinned"），已修正。

---

## 8. 显式记录：未做的事

为保证本方案可被安全评审，明确列出**未执行**的动作：

1. ❌ 未创建 / 未推送任何 GitHub 仓库。
2. ❌ 未在 `pacgate-law` 中 `git commit`（仍为零提交）。
3. ❌ 未修改 `.gitmodules` 或修复 submodule 指针。
4. ❌ 未改动任何 compose 文件中的镜像引用（9 个浮动引用**仍保持原样**）。
5.  未重启 / 停止 / 重建任何容器。
6.  未触碰 `C:\pacgate-ai-pr` 的任何文件。

**为什么不动那 9 个浮动引用**：把 `:latest` 改成 `@sha256:...` 会改变部署行为，且在 `ironclawai-survey`（本地 build）等场景下无 digest 可锁。这属于需要你决策的变更，不应由我在无人确认时执行。

---

## 9. 后续步骤（按优先级）

1. **确认 `deer-flow` 跨版本组合是否有意**：`deer-flow-pacgate:0.1.10` + `deer-flow-frontend-pacgate:0.1.11`。
2. **决定 9 个浮动引用的处理方式** —— 三选一：按 digest 锁定 / 换成语义化版本 / 明确接受浮动。
3. **治理那 2 个未托管容器**：`cloudflare` 与 `open-webui` 建议补成 compose 服务，纳入某个项目。
4. **执行方案 B**：修复 `pacgate-law` 的 submodule 指针错位，建立伞形 workspace。
5. 考虑把本地 4 个 PacGate 镜像（含旧版 `0.1.9` / `0.1.10`）做一次清理，避免误用旧版。

---

## 10. 安全校验（已通过）

按 `AGENTS.md` 要求，推送前必须确认两个凭据文件被 gitignore。实测（在 submodule 内部执行）：

```
assets/智库资料收集/智库资料收集/MCP授权/法律数据库MCP.md  → IGNORED ✅
assets/pacgate-ai-remote-handbook/OPERATOR.md               → IGNORED ✅
```

两个文件**在磁盘上存在**但均被正确忽略，凭据门禁正常。本次未提交任何内容，故无泄露风险。