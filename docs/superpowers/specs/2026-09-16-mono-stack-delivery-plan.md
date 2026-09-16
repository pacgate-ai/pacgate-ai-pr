# PacGate 单体交付栈（Mono-Stack）整合与交付方案

- **日期**: 2026-09-16（替代同日早前的 `2026-09-16-mono-repo-consolidation-plan.md`）
- **目标**: 把运行时平台 `C:\pacgate-ai-pr` 整合进 `C:\Users\pacga\github-pr\pacgate-law`，
  使**单个文件夹即构成完整交付物**：规划 + 资产 + deer-flow + qm + pacgate MCP + api + 构建包。
- **状态**: **待评审**（未执行任何迁移）
- **硬前置**: ⚠️ 凭据轮换（见 §8）

---

## 0. 本版的关键修正

用户澄清了两点，本方案据此重写：

1. **`C:\pacgate-ai-pr` 不是可丢弃的克隆**，而是在一个**意外克隆**的仓库上持续积累的
   真实成果 —— 含 158 个提交、完整部署编排、以及当前**正在支撑全套本地容器栈**的配置。
   因此它是**权威运行时定义**，不能当作临时目录处理。
2. **交付要求是"整套"**：规划、资产、deer-flow、qm、pacgate MCP、api、构建包都要
   随这个 mono-folder 一起交付。

本版最重要的新增结论是 **§2 的三层交付模型**，以及 **§3 一个已在本机发生的真实故障**。

---

## 1. 目标仓库结构（建议）

```text
pacgate-law/                          ← 单一交付仓库（mono-stack）
│
├── README.md                          ← 交付入口：这是什么、怎么部署、怎么发版
├── AGENTS.md                          ← 更新：新拓扑
├── .gitignore                         ← 三层规则（见 §2）
├── .gitmodules                        ← deer-flow（+ 资产树，视 D3）
│
├── pacgate-ai/                        ← 【D1】Rust 平台（16 crates + 4 wasm-crates）
├── deer-flow/                         ← 【D2】agent 工作区（submodule, branch pacgate-layer）
├── pacgate-ai-assets/                 ← 【D3】法律业务资产（原 submodule 内容）
│
├── deploy/                            ← 部署编排（随源并入）
│   ├── client-bundle/                 ← 主 compose + 模板 + install.ps1
│   ├── qm-pacgate/                    ← qm 栈
│   ├── handbooks/                     ← 手册与 PDF 渲染
│   ├── client-delivery/               ← 客户交付包（PDF）
│   └── build-images.ps1               ← 镜像构建/推送
│
├── pacgate-adapters/                  ← 随源并入
├── scope-assets/                      ← 随源并入
├── patches/                           ← 随源并入
├── plans/                             ← 随源并入（规划）
├── auth-gate/  nginx/  scripts/       ← 随源并入
├── compose.yaml                       ← 随源并入
├── runtime/                           ← 保留：运行时清单 + 校验工具
└── docs/                              ← 两端合并（文件名不重叠，已逐文件核对）
```

> **关于是否重排目录**：本方案**不重排**，只并入。理由见 §3 —— 本机已经因为
> 目录名/项目名变化产生过一次"数据库像被清空"的故障；每一次重排都会放大该风险。
> 结构清晰度通过 README 与 AGENTS.md 描述解决，而不是靠移动文件。

---

## 2. 三层交付模型（本方案的核心概念）

"交付整套栈"之所以容易做错，是因为**三种东西的交付方式完全不同**。把它们混为一谈，
结果要么是 7 GB 的仓库，要么是缺件的交付。

| 层 | 内容 | 体积 | 交付方式 | 是否进 git |
|---|---|---|---|---|
| **T1 源码与配置** | 代码、compose、模板、文档、规划、资产、skills | **23.8 MB**（515 文件） | **git** | ✅ **是** |
| **T2 构建产物** | 4 个 PacGate 镜像 + qm 5 镜像 + openviking/pgvector/nginx | 数 GB | **GHCR 拉取**（`docker compose pull`） | ❌ 否 |
| **T3 运行时状态与交付包** | `client-bundle/data`（客户端对话/DB）、渲染出的 `.env`、`.zip` 交付包 | 1,915 MB | **per-machine 生成 / 单独分发** | ❌ 否 |

### 2.1 为什么 T2 不能进 git

镜像由 `.github/workflows/build-ghcr.yml` 构建并推送到 `ghcr.io/pacgate-ai/*`；
`install.ps1` 在客户端机器上执行 `docker compose -f compose.prod.yaml pull`。
**镜像的交付通道是 GHCR，不是 git。** 仓库的职责是"定义如何构建/拉取"，不是"承载字节"。

### 2.2 为什么 T3 绝对不能进 git

`deploy/client-bundle/data/` **1,915 MB / 244 文件 / 100% 被 gitignore**，其中：

| 文件 | 体积 | 性质 |
|---|---|---|
| `data/deer-flow/checkpoints.db` | **1,635 MB** | 实时会话检查点 |
| `data/deer-flow/checkpoints.db-wal` | 123 MB | WAL |
| `data/deer-flow/users/.../workspace/.fonts/*.otf` | 每份 15–16 MB | 线程内工作区 |
| `data/assets/智库资料收集/.../货拉拉...扫描件.pdf` | 37.7 MB | 尽调扫描件 |

这是**客户端数据 + 可再生的运行时状态**。它被忽略是**正确的设计**，必须保持。
把它纳入 git 既泄露客户数据，又会让仓库膨胀到不可用。

### 2.3 交付流程因此是"三通道"

```text
git clone（T1） → install.ps1 → docker compose pull（T2, GHCR） → 首次运行生成（T3）
```

**"交付整套栈"= 保证这三条通道都有定义、都被修订、都能在客户端机器上跑通** ——
而不是把三样东西塞进一个仓库。

---

## 3. ⚠️ 已在本机发生的真实故障：项目名与卷

这是本版最重要的发现，**独立于整合就已经存在**。

### 3.1 事实

同一目录 `deploy/client-bundle/` 下有两个 compose 文件，它们**声明相同的服务名与卷名**，
但产生**不同的 Compose 项目名**：

| 文件 | 是否有 `name:` | 推导项目名 | 结果卷名 |
|---|---|---|---|
| `compose.bundle.yaml` | ✅ `name: pacgate-ai-bundle` | `pacgate-ai-bundle` | `pacgate-ai-bundle_pacgate-db-data` |
| `compose.prod.yaml`（**install.ps1 使用**） | ❌ 无 | 取自**目录名** `client-bundle` | `client-bundle_pacgate-db-data` |

本机**同时存在两个该卷**：

```text
client-bundle_pacgate-db-data        created 2026-09-01   project=client-bundle      attached-to=(none)  ← 孤儿
pacgate-ai-bundle_pacgate-db-data    created 2026-09-02   project=pacgate-ai-bundle  attached-to=pacgate-db  ← 在用
```

两者都带 `com.docker.compose.volume=pacgate-db-data` 标签，但
`com.docker.compose.project` 不同（`client-bundle` vs `pacgate-ai-bundle`）。

### 3.2 机制

Docker Compose 的具名卷会被**项目名前缀化**。项目名变化 → 创建**新的空卷** →
应用连上空库 → **看起来像数据被清空**（旧数据其实还在另一个卷里）。

### 3.3 为什么与整合直接相关

1. **重命名或移动 `deploy/client-bundle/` 目录，就会产生第三代空卷。**
   这正是"把仓库搬进 mono-folder"最容易踩的坑。
2. **本机现在就有这个隐患**：`install.ps1` 走 `compose.prod.yaml`（无 `name:`），
   而当前在跑的栈走 `compose.bundle.yaml`（有 `name:`）。若现在跑 `install.ps1`，
   可能挂到**孤儿卷**上，于是"数据库是空的"。

### 3.4 处置（已取证，**本方案不动手**）

**已完成只读取证**（`runtime/VOLUME-INVESTIGATION-FINDINGS.md`），结论如下：

| | `pacgate-ai-bundle_...` | `client-bundle_...` |
|---|---|---|
| 体积 | **95.5 MB** | 46.6 MB |
| 最新 WAL 时间 | **2026-09-15 02:49** | 2026-09-02 05:04 |
| 最新 `base/` mtime | **2026-09-15 02:44** | 2026-09-01 07:37 |
| PGDATA uid | 999 | 70 |
| 挂载 | ✅ `pacgate-db`（在用） | ❌ 无 |

**判定**：

- **`pacgate-ai-bundle_` 是权威。** 在用、更大、最新写入为 **09-15（昨天）**。
- **`client-bundle_` 是第一代产物**，最后写入 **09-01**。**并非空库** ——
  含 46.6 MB 真实数据，**不得未审查即删除**。
- 两者 PGDATA uid 不同（70 vs 999），证明由**不同容器定义**初始化，
  与"两个 compose 文件"的判断一致。

**这坐实了"项目名变更已发生过一次"**：09-01 经 `compose.prod.yaml` 建卷；
09-02 经 `compose.bundle.yaml` **新建了第二个空卷**并开始写入。
旧数据没丢，但应用切到了新空库 —— 这正是"看起来像数据丢失"的成因。

**处置建议**：

1. ⚠️ **两个卷都不要删。** 孤儿卷含 46.6 MB 真实数据。
2. ⚠️ **不要重命名或移动 `deploy/client-bundle/`**，否则会产生第三代空卷。
3. **修复 `compose.prod.yaml`**：补 `name: pacgate-ai-bundle`，使其与
   `compose.bundle.yaml` 落到同一项目名 → 同一卷。
4. 修复前确认：是否存在**仅存于 09-01 代**的客户端数据。若有，
   以**只读源挂载**方式复制过去再切换。
5. 若确认 09-01 数据已废弃，**显式记录决策**后再
   `docker volume rm client-bundle_pacgate-db-data`，而非当作清理动作。

**验证命令**：

```powershell
docker compose -f deploy/client-bundle/compose.prod.yaml config | findstr name
# 期望与 compose.bundle.yaml 的 pacgate-ai-bundle 一致
```

---

## 4. 现状基线（实测）

### 4.1 两端状态

| 维度 | `pacgate-ai-pr`（源） | `pacgate-law`（目标） |
|---|---|---|
| 提交数 | **158** | **0**（有 `.git`，无提交） |
| remote | `origin`=JZKK720, `fork`=pacgate-ai | **无** |
| 当前分支 | `feat/agent-capability-enablement` | `main` |
| HEAD | `151a383` (2026-09-13) | *无* |
| 跟踪文件 | **515**（23.8 MB） | 部分已 `git add` |
| `.git` 体积 | 67.1 MB | — |
| 磁盘总体积 | **~7 GB**（含 T2/T3） | ~1.8 GB（含嵌套克隆） |

### 4.2 路径命名空间冲突（4 处）

| 路径 | `pacgate-ai-pr` | `pacgate-law` | 性质 |
|---|---|---|---|
| **`pacgate-ai/`** | 真实 Rust workspace | **submodule**（JZKK720/pacgate-ai） | 🔴 **同名异物** |
| **`docs/`** | 19 个条目 | `docs/superpowers/` | 🟡 目录重叠，**文件名不重叠**（已逐文件核对） |
| **`.gitignore`** | Rust/Docker 规则 | 凭据规则（写错了仓库） | 🟡 需合并语义 |
| **`.github/`** | 11 个 workflow | 无 |  直接并入 |

### 4.3 嵌套仓库

| 仓库 | 位置 | 分支/状态 |
|---|---|---|
| `deer-flow` | `pacgate-law/deer-flow` | `pacgate-layer`，**192 ahead / 6 behind**，有开放 PR |
| `pacgate-ai`（submodule） | `pacgate-law/pacgate-ai` | gitlink `f712ec2` vs 实际 `0f7db15` —— **已破损** |
| `deer-flow-src` | `pacgate-ai-pr/deploy/` | 574 文件 **100% 被忽略**，上游克隆，可再生（31 MB） |

**三端共同提交数：0** —— 无共同历史，只能"导入"，不能 merge。

### 4.4 资产树的两份副本

| | 源内 vendored | submodule |
|---|---|---|
| 路径 | `pacgate-ai-pr/pacgate-ai/pacgate-ai-assets/` | `pacgate-law/pacgate-ai/` |
| 文件数 | **59** | **262** |
| 体积 | 43.4 MB | 85.4 MB |
| `.gitignore` 是否覆盖凭据 | ❌ **否**（4 个凭据文件被跟踪） | ✅ **是**（已字节级验证） |

> **结论：submodule 那份更全且凭据已正确忽略。** 源内 vendored 副本应删除（见 D3）。

---

## 5. 迁移策略

### 5.1 三种导入方式

| 方式 | 做法 | 优 | 劣 |
|---|---|---|---|
| **1. subtree** | 保留 158 提交历史 | 历史完整 | **把 4 个凭据文件的历史一并带入** |
| **2. squash** | 仅当前树，作新起点 | **历史天然无凭据** | 丢 `git blame` |
| **3. filter-repo** | 净化历史后导入 | 二者兼得 | 最复杂；需改写源历史并强制推送 |

### 5.2 推荐：方式 2（squash）

理由：

1. **目标仓库零提交** —— 天然适合当新起点，无历史包袱。
2. **凭据无从规避地简化** —— 不导入历史，就不存在"历史里躺着公网可读的密码"。
3. **本次交付物是"可构建的栈"**，不是"提交谱系"；客户端拿到的是代码树。
4. **源仓库保持只读保留**，历史仍可查（`C:\pacgate-ai-pr` 不删）。

> 但 `pacgate-ai-pr` 是**意外克隆 + 持续积累**的仓库（§0.1），历史可能对追责有价值。
> 若你认为需要，改用方式 3，代价是改写源历史 + 开发者重新克隆。

### 5.3 导入纪律

**只导跟踪内容**：

```powershell
git -C C:\pacgate-ai-pr archive --format=tar HEAD -o C:\tmp\pacgate-src.tar
```

- ✅ 天然排除 `pacgate-ai/target`（4,475 MB）与 `client-bundle/data`（1,915 MB）
- ❌ **禁止** `cp -r` 整个目录 —— 会拖入 6.4 GB 的非交付内容

---

## 6. 执行计划

> 每阶段可独立验证、可回滚。**阶段 0 是硬前置。**

### 阶段 0 — 凭据处置（必须先做）

| # | 动作 | 验收 |
|---|---|---|
| 0.1 | 轮换 PacGate GitHub 账号密码，吊销重签全部 PAT | 人工确认 |
| 0.2 | 轮换法律数据库统一密码（元典/北大法宝/企查查） | 人工确认 |
| 0.3 | 轮换境外法律数据库凭据 | 人工确认 |
| 0.4 | 在 **`pacgate-ai-pr/.gitignore`** 补规则（根因修复） | `check-ignore -v` 返回规则 |
| 0.5 | 重跑 `runtime/AUTHORITATIVE-credential-check.ps1` | 4 文件转 not-tracked |

⚠️ 4 个凭据文件中 **3 个是中文路径**，此前被编码缺陷漏报。**必须用字节级脚本**检查。

### 阶段 1 — 卷与项目名前置修复（**本版新增，且必须先于搬迁**）

> 已完成只读取证（§3.4）：`pacgate-ai-bundle_` 权威（09-15 仍写入），
> `client-bundle_` 是第一代（09-01），**两者都含真实数据**。

1. 确认是否存在**仅存于 09-01 代**的客户端数据（对比两者的 `base/` 库数量与 WAL 时间）。
2. 给 `deploy/client-bundle/compose.prod.yaml` 补 `name: pacgate-ai-bundle`。
3. 记录修复前后的 `docker volume ls` 与 `docker ps` 输出到 `runtime/`。
4. 验证：`docker compose -f compose.prod.yaml config | findstr name` 与
   `compose.bundle.yaml` 一致。
5. 若 09-01 数据确认废弃 → **显式记录决策**后再删卷；否则保留并归档。

> 不做此步就搬迁目录，等于拿生产数据做赌注。

### 阶段 2 — 准备（不改动任何既有仓库）

1. **冻结写入**：确认无人正在 `pacgate-ai-pr` 上开发。
2. **备份 `.git`**（仅 67 MB）。
3. **记录基线**：`git rev-parse HEAD` → 写入 `docs/pacgate/MONO-STACK-ORIGIN.md`。
4. **决定 D1/D2/D3**（§9）。

### 阶段 3 — 清理目标仓库

1. 修复破损 submodule（gitlink `f712ec2` vs `0f7db15`）。
2. 按 D3 处理资产树（submodule 保留 / vendored 删除）。
3. 清理散落临时文件：`containers.txt`、`mcp_verify.txt`、`mcp_final_verify.txt`、
   `verify_mcp.txt`（并入 `runtime/` 或删除）。

### 阶段 4 — 首次提交（关键工程保障）

```bash
cd C:\Users\pacga\github-pr\pacgate-law
git add -A
git commit -m "chore: initial commit of pacgate-law mono-stack baseline

Pre-import baseline. Committing the existing state first so the platform
import lands as a single reviewable, revertable diff."
```

**收益**：整合变成一个**可 review、可 revert 的 diff**，而不是"一切都变了"。

### 阶段 5 — 导入平台内容

1. `git archive HEAD` 导出（T1，23.8 MB）并解包到目标根。
2. **在 `git add` 之前清点**：
   - 确认无 `pacgate-ai/target/`
   - 确认无 `client-bundle/data/`
   - 确认 4 个凭据文件**未出现**
3. 合并 `.gitignore`（两端并集 + 阶段 0.4 的凭据规则）。
4. 合并 `docs/`（文件名不重叠，直接并入）。
5. 提交（提交信息注明来源 SHA、squash 原因、排除项）。

### 阶段 6 — 处理嵌套仓库

- **deer-flow（D2-a）**：转为正式 submodule，`-b pacgate-layer`。
- 验证 `git submodule status` 无 `-` 前缀。

### 阶段 7 — 路径去耦（**本版新增**）

实测 **23 个文本文件**硬编码了 `C:\pacgate-ai-pr`：

| 文件 | 引用数 |
|---|---|
| `.vscode/tasks.json` | **602** |
| `deploy/AIPC-DEPLOYMENT-HANDBOOK(-ZH).md` | 各 20 |
| `deploy/AIPC2-HANDOFF-PROMPT(-v2).md` | 19 / 12 |
| `docs/plans/...`、`plans/007-*` | 6 / 6 / 3 |
| `deploy/build-images.ps1`、`build-frontend.ps1` | 各 2 |
| 其余（README、CONTINUE-FROM-OTHER-MACHINE、extract_pdfs.py 等） | 1–2 |

处置：**改用相对路径或环境变量**，或至少在 README 声明"本仓库路径以 `<repo-root>` 为基准"。
`.vscode/tasks.json`（602 处）建议整体重写为 `${workspaceFolder}` 相对形式。

### 阶段 8 — 交付通道验证（**本版新增，最重要**）

对三条通道分别验证，缺一不可：

| 通道 | 验证 | 期望 |
|---|---|---|
| **T1 git** | `git ls-files \| wc -l`；`git count-objects -vH` | ≈515+；量级 24 MB，**远小于 7 GB** |
| **T1 无凭据** | `runtime/AUTHORITATIVE-credential-check.ps1` | 4 文件 **not tracked** |
| **T1 无客户数据** | `git ls-files \| grep -c 'client-bundle/data/'` | 0 |
| **T1 无构建产物** | `git ls-files \| grep -c 'pacgate-ai/target/'` | 0 |
| **T1 历史无凭据** | `git log --all -S '<标记>'` | **0 命中**（squash 的核心收益） |
| **T2 compose 可解析** | `docker compose -f deploy/client-bundle/compose.bundle.yaml config` | 无错误 |
| **T2 卷名稳定** | 上述 `config` 输出的 `name:` / 卷前缀 | 与阶段 1 统一后一致 |
| **T2 镜像可构建** | `deploy/build-images.ps1 -Tag <测试>`（**不 push**） | 4 镜像构建成功 |
| **T3 交付包可生成** | 重跑手册渲染 + 打包脚本 | `client-delivery.zip` 等生成 |
| **运行时一致** | 重跑 `runtime/capture-runtime.ps1` | 与整合前清单比对一致 |

### 阶段 9 — 收尾

1. 更新 `AGENTS.md`：新拓扑 + 三层模型 + 卷风险。
2. 新增 `README.md`：交付入口（clone / build / deploy / 发版）。
3. 保留 `C:\pacgate-ai-pr` 为**只读历史副本**。
4. 通知开发者：新位置、`--recursive` clone、旧仓库只读。

---

## 7. 风险登记

| # | 风险 | 概率 | 影响 | 缓解 |
|---|---|---|---|---|
| **R1** | **项目名变化 → 空卷 → 看着像数据丢失** | **高（已发生）** | **高** | 阶段 1 先统一项目名；**不重命名 `client-bundle/`** |
| R2 | 凭据被带进新仓库 | 中 | **高** | 阶段 0 先行；squash 导入 |
| R3 | 误把 `target/`（4.5 GB）纳入 | 中 | 中 | 只用 `git archive` |
| R4 | 误把客户端数据（1.9 GB）纳入 | 中 | **高** | 同上 + gitignore 复核 |
| R5 | 硬编码路径失效（23 文件） | **高** | 中 | 阶段 7 去耦；`${workspaceFolder}` |
| R6 | submodule 再次破损 | 中 | 中 | 阶段 3 先修；阶段 8 验证 |
| R7 | 丢失 deer-flow 192 提交与 PR | 中 | 中 | D2-a（submodule），非内联 |
| R8 | 中文路径检查再次假阴性 | **高** | **高** | **强制**字节级脚本 |
| R9 | 离线客户端无法 pull GHCR | 中 | **高** | 见 §7.1 |
| R10 | 整合期间源仓库有新提交 | 低 | 中 | 冻结写入 + 记录基线 SHA |

### 7.1 R9 补充：离线交付缺口

`install.ps1` 依赖 `docker compose pull`（GHCR）。但这是**律所客户机**，
可能无外网。实测**未发现**任何 `docker save` / `docker load` / 离线包机制。

**建议新增** `deploy/package-offline.ps1`：

```powershell
# 生成可离线交付的镜像包（在联网机器执行）
docker save -o <out>/images.tar `
  ghcr.io/pacgate-ai/pacgate-api:<tag> `
  ghcr.io/pacgate-ai/pacgate-mcp:<tag> `
  ghcr.io/pacgate-ai/deer-flow-pacgate:<tag> `
  ghcr.io/pacgate-ai/deer-flow-frontend-pacgate:<tag> `
  ghcr.io/yc-software/qm/* ghcr.io/volcengine/openviking* pgvector/pgvector:pg16 nginx:1.27-alpine
```

并在 `install.ps1` 增加 `-Offline <tar>` 分支走 `docker load`。
**这属于 T2 通道的补齐**，是"交付整套栈"的必要部分。

---

## 8. 凭据处置（硬前置）

**4 个文件均被跟踪且公网可读**（字节级复核 + 反向对照）：

| # | 文件（同一子树） | 内容 |
|---|---|---|
| 1 | `.../pacgate-ai-remote-handbook/OPERATOR.md` | GitHub 账号凭据 ×10 |
| 2 | `.../MCP授权/法律数据库MCP.md` | 统一登录名 + 密码 |
| 3 | `.../MCP授权/境外法律数据库和网站.md` | 境外库账号 |
| 4 | `.../MCP授权/百宸AI系统资源接入清单V2.docx` | 接入清单 |

**根因**：`pacgate-ai-pr/.gitignore` 无相应规则；正确规则只在 **submodule** 的
`.gitignore` 里 —— **规则写在了错误的仓库**。

**与整合的关系**：

- **方式 2（squash）** → 这 4 个文件的历史**不进**新仓库，新仓库天然干净。
  这是推荐方式 2 的主要理由。
- **方式 1/3** → 必须先用 `filter-repo` 清除。
- **无论哪种**，阶段 0 的**轮换不可省略** —— 历史已公网可读，删除与改历史都无法回收。

**额外**：源内 vendored 资产树含全部 4 个凭据文件且未被忽略 → 按 D3 应整体删除。

---

## 9. 待决策事项

| # | 决策 | 推荐 | 影响面 |
|---|---|---|---|
| **D1** | `pacgate-ai/` 归 Rust workspace 还是 submodule | **D1-a**：Rust 占名；资产改 `pacgate-ai-assets/` | 全仓库路径 |
| **D2** | `deer-flow/` 转 submodule 还是内联 | **D2-a**：submodule（保留 192 提交 + PR + 上游同步） | 交付完整性 |
| **D3** | 资产树用哪份 | **D3-a**：用 submodule（262 文件，凭据已忽略）；删 vendored | 安全性 |
| **D4** | 导入方式 | **方式 2 squash** | 历史保留 |
| **D5** | 仓库可见性 | **私有** | 安全 |
| **D6** | 是否保留 `pacgate-ai-pr` 只读副本 | **保留** | 可追溯 |
| **D7** | 阶段 1 卷修复：09-01 代数据是否保留 | **已取证**：`pacgate-ai-bundle_` 权威（09-15 写入）；09-01 代含 46.6 MB 真实数据 —— **建议保留归档，确认废弃后再显式删除** | **数据安全** |
| **D8** | 是否新增离线交付通道（§7.1） | **建议新增**（未见任何 `docker save/load` 机制） | 客户端可部署性 |

---

## 10. 本方案明确不做的事

1. ❌ 不删除、移动或改写 `C:\pacgate-ai-pr`
2. ❌ **不删除任何 Docker 卷**（R1 相关，需人工确认）
3. ❌ 不重命名 `deploy/client-bundle/` 目录
4. ❌ 不强制推送任何远程
5. ❌ 不轮换凭据（需所有者操作）
6. ❌ 不修改任何 compose 的镜像引用
7. ❌ 不重启/停止/重建任何运行中的容器

---

## 11. 参考

- 凭据事件：`docs/superpowers/specs/2026-09-16-credential-exposure-incident.md`
- 运行时清单：`runtime/RUNTIME-INVENTORY.md`
- **卷取证结论：`runtime/VOLUME-INVESTIGATION-FINDINGS.md`**（含体积/WAL 时间对比）
- 卷/项目名证据：`runtime/volume-generations.txt`、`runtime/critical-verification.txt`、
  `runtime/volume-mtime.txt`、`runtime/volume-contents-investigation.txt`
- 路径耦合证据：`runtime/hardcoded-path-references.txt`
- 交付层证据：`runtime/delivery-mechanics.txt`、`runtime/client-bundle-breakdown.txt`
- 字节级凭据检查：`runtime/AUTHORITATIVE-credential-check.ps1`
- 既有集成说明：`DEER-FLOW-INTEGRATION.md`
- 部署手册：`C:\pacgate-ai-pr\deploy\SETUP-AND-OPERATIONS.md`、`AIPC-DEPLOYMENT-HANDBOOK.md`