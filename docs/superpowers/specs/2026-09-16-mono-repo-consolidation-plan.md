# PacGate 单体仓库（Mono-Repo）整合方案

- **日期**: 2026-09-16
- **目标**: 将运行时平台仓库 `C:\pacgate-ai-pr` 整合进 `C:\Users\pacga\github-pr\pacgate-law`，形成单一的交付级 mono-stack
- **状态**: **待评审**（设计阶段，未执行任何迁移）
- **前置依赖**: ⚠️ 凭据泄露事件必须先处置（见 §6）

---

## 1. 目标与范围

### 1.1 明确的目标

`pacgate-law` 成为**唯一交付仓库**，包含：

| 组成 | 当前所在 | 说明 |
|---|---|---|
| 平台后端（Rust） | `pacgate-ai-pr/pacgate-ai` | 16 crates + 4 wasm-crates |
| 部署编排 | `pacgate-ai-pr/deploy` | 6 个 compose 项目、client-bundle、qm-pacgate |
| 平台适配层 | `pacgate-ai-pr/pacgate-adapters` | |
| 业务资产 | `pacgate-ai-pr/scope-assets` | |
| 补丁 | `pacgate-ai-pr/patches` | |
| 文档 | `pacgate-ai-pr/docs` + `pacgate-law/docs` | |
| Agent 工作区 | `pacgate-law/deer-flow` | deer-flow fork（branch `pacgate-layer`） |
| 运行时清单 | `pacgate-law/runtime` | 本次新建 |

### 1.2 明确不在范围内

- **不迁移**：`pacgate-ai/target`（4,475 MB Rust 构建产物）、
  `deploy/client-bundle/data`（1,916 MB 客户端对话/DB）。
  二者均为可再生或客户端数据，且已被 gitignore。占源仓库体积 **91%**。
- **不迁移**：`deploy/deer-flow-src`（deer-flow 源码检出，31 MB，可再生）
- **不改写**：4 个兄弟仓库（`odysseus`/`hermes-agent`/`ironclawai-survey`/`dockhand-dash`）

### 1.3 交付物定义

单一仓库，`git clone` 一次即得到可构建、可部署、可交付的完整栈。

---

## 2. 现状基线（实测）

### 2.1 两端状态

| 维度 | `pacgate-ai-pr`（源） | `pacgate-law`（目标） |
|---|---|---|
| 提交数 | **158** | **0**（有 `.git`，无提交） |
| remote | `origin`=JZKK720, `fork`=pacgate-ai | **无** |
| 当前分支 | `feat/agent-capability-enablement` | `main` |
| HEAD | `151a383` (2026-09-13) | *无* |
| 跟踪文件 | **515** | 部分已 `git add`，未提交 |
| 跟踪体积 | **23.8 MB** | — |
| `.git` 体积 | 67.1 MB | — |
| 磁盘总体积 | ~7 GB（含构建产物） | ~1.8 GB（含嵌套克隆） |

### 2.2 目标路径命名空间冲突（关键）

对比两端顶层路径，存在 **4 处冲突**：

| 路径 | `pacgate-ai-pr` | `pacgate-law` | 冲突性质 |
|---|---|---|---|
| **`pacgate-ai/`** | 真实 Rust workspace（crates/、wasm-crates/、Cargo.toml、migrations/） | **submodule**（`JZKK720/pacgate-ai`）内含 assets/ + declare-only Cargo.toml | 🔴 **同名异物 —— 最硬冲突** |
| **`docs/`** | 19 个条目（handbook、报告、plans、qa…） | `docs/superpowers/` | 🟡 目录重叠，**文件名不重叠** |
| **`.gitignore`** | Rust/Docker/临时文件规则 | 凭据规则（但规则写错了位置） | 🟡 需合并语义 |
| **`.github/`** | 11 个文件（workflow） | 无 |  无冲突，可直接并入 |

> `docs/superpowers/` 已逐文件核对：两侧**文件名不重叠**
> （源：`plans/2026-08-28-*`、`specs/2026-08-28-*`；目标：`specs/2026-09-16-*`），
> 可安全合并为同一目录树。

### 2.3 嵌套仓库情况

| 仓库 | 位置 | `.git` | 自身分支/PR |
|---|---|---|---|
| `deer-flow` | `pacgate-law/deer-flow` | ✅ 有 | `pacgate-layer`，**192 ahead / 6 behind** `origin/main`，有开放 PR |
| `pacgate-ai`（submodule） | `pacgate-law/pacgate-ai` | ✅ 有 | `main` @ `0f7db15` |
| `pacgate-ai`（Rust） | `pacgate-ai-pr/pacgate-ai` | ❌ 无（属父仓库） | — |
| `deer-flow-src` | `pacgate-ai-pr/deploy/deer-flow-src` | ✅ 有 | 上游克隆，可再生 |

**含义**：若 `pacgate-law` 要成为有提交的仓库，两个嵌套仓库的 `.git` 必须
**转为正式 submodule** 或**移除**。直接 `git add` 会得到
`mode 160000` gitlink —— 即当前 `pacgate-ai` 的破损状态（gitlink `f712ec2`
与实际 `0f7db15` 不一致）。

### 2.4 两仓库无共同历史

```
pacgate-ai-pr commits sampled: 158
deer-flow commits sampled   : 400
shared commits              : 0
```

`pacgate-law` 更是零提交。因此这是**三个互不相干的谱系**归并，
不存在"简单 merge"——必须选择导入策略（§5）。

---

## 3. 目标架构

```
pacgate-law/                          ← 唯一交付仓库（mono-stack）
│
├── AGENTS.md                          ← 更新：记录新拓扑
├── README.md                          ← 新增：交付入口
├── .gitignore                         ← 合并两端规则（含凭据修复，见 §6）
├── .gitmodules                        ← 声明 deer-flow（及 pacgate-ai，若保留）
│
├── pacgate-ai/                        ← 【决策 D1】Rust workspace
├── deer-flow/                         ← 【决策 D2】deer-flow fork
├── pacgate-ai-assets/                 ← 【决策 D3】资产树（原 submodule 内容）
│
├── deploy/                            ← 从源并入（compose、client-bundle、qm-pacgate）
├── pacgate-adapters/                  ← 从源并入
├── scope-assets/                      ← 从源并入
├── patches/                           ← 从源并入
├── auth-gate/                         ← 从源并入
├── nginx/                             ← 从源并入
├── scripts/                           ← 从源并入（注意与源内 scripts 合并）
├── plans/                             ← 从源并入
├── compose.yaml                       ← 从源并入
├── runtime/                           ← 保留（交付级运行时可复现清单）
├── docs/                              ← 两端合并
│   ├── superpowers/                   ← 合并（文件名不重叠，已核对）
│   ├── handbooks/                     ← 源
│   └── ...                            ← 源
└── .github/                           ← 从源并入（workflow）
```

### 3.1 三个必须决策的冲突

**D1 — `pacgate-ai/` 归谁？**

| 方案 | 做法 | 优点 | 缺点 |
|---|---|---|---|
| **D1-a（推荐）** | Rust workspace 占 `pacgate-ai/`；submodule 内容移到 `pacgate-ai-assets/` | 名称语义正确（"pacgate-ai" 就是产品本体）；与镜像名 `ghcr.io/pacgate-ai/*` 一致 | 需改 submodule 路径 |
| D1-b | submodule 保留 `pacgate-ai/`；Rust 移到 `pacgate-rust/` 或 `crates/` | 不动 submodule | 名称误导；与 `Cargo.toml` 里的 repo URL 不符 |
| D1-c | 移除 submodule，改用源内 vendored 资产 | 消除嵌套仓库 | vendored 仅 59 文件 vs submodule 262，**内容不全**；且源内副本含凭据 |

> **推荐 D1-a**。理由：`Cargo.toml` 声明
> `repository = "https://github.com/pacgate-ai/pacgate-ai"`，且全部镜像名为
> `ghcr.io/pacgate-ai/*`，"pacgate-ai" 在产品语义上**就是**那个 Rust 平台。
> 文档资产用 `-assets` 后缀区分更清晰。
>
> ⚠️ 但 vendored 资产树（59 文件）**含全部 4 个凭据文件**，而 submodule（262 文件）
> 的 `.gitignore` **正确忽略了它们**。所以"用哪份资产"这个选择有安全含义 ——
> 见 §6。

**D2 — `deer-flow/` 怎么处理？**

| 方案 | 做法 | 优点 | 缺点 |
|---|---|---|---|
| **D2-a（推荐）** | 转为正式 git submodule，指向 `pacgate-ai/deer-flow`（branch `pacgate-layer`） | 保留 PR 与历史；上游 `bytedance/deer-flow` 可继续同步；`git submodule update --init` 一把到位 | 需网络；开发者需 `--recursive` |
| D2-b | 移除 `.git`，源码整体纳入主仓库 | 真正"单体"，无 submodule 复杂度 | **丢失 192 提交与开放 PR**；无法再同步上游；仓库膨胀 ~1.7 GB |
| D2-c | 保持现状（裸嵌套目录，不纳入 git） | 不动 | 交付不完整 —— clone 后没有 agent 工作区；且当前 gitlink 已破损 |

> **推荐 D2-a**。deer-flow 是上游 fork 且有活跃 PR，转 submodule 能同时满足
> "交付完整"与"保留上游能力"。

**D3 — 资产树用哪一份？**

| 方案 | 优点 | 缺点 |
|---|---|---|
| **D3-a（推荐）** | 以 **submodule**（262 文件，`.gitignore` 正确）为准，忽略 vendored 副本 | 内容更全；凭据已被正确忽略；单一来源 |
| D3-b | 以源内 vendored（59 文件）为准 | 内容不全；**含 4 个未忽略的凭据文件** |

> **推荐 D3-a**，并**删除**源内的 vendored 副本 `pacgate-ai/pacgate-ai-assets/`，
> 彻底消除重复与凭据来源。

---

## 4. 迁移策略选择

### 4.1 三种导入方式

**方式 1 — `git subtree add`（保留历史）**

```bash
git subtree add --prefix=. https://github.com/pacgate-ai/pacgate-ai-pr.git main
```
- ✅ 保留 158 提交的 `git log --follow` 历史
- ✅ 单一仓库，无 submodule
- ❌ **会把 4 个凭据文件的历史一并导入**（历史无法靠后续删除清除）
- ❌ 前缀设为根目录时行为微妙，易出错

**方式 2 — squash 导入（新起点）**

```bash
# 把源工作树复制到目标，作为"初始提交"
git -C C:\pacgate-ai-pr archive --format=tar HEAD | tar -x -C <target>
```
- ✅ **不导入任何历史提交** → 天然规避凭据历史污染
- ✅ 从零建立干净的单体仓库（目标本就是零提交，非常契合）
- ❌ 丢失 158 提交的历史与 `git blame`
- ❌ 需要保留源仓库作为历史查询副本（可只读保留）

**方式 3 — filter-repo 净化后导入**

```bash
git filter-repo --path-glob '**/OPERATOR.md' --path-glob '**/MCP*/*' --invert-paths
git subtree add ...
```
- ✅ 历史与安全兼得
- ❌ 复杂度最高；需重写源历史并强制推送；会打断开发者现有克隆

### 4.2 推荐

> **推荐方式 2（squash 导入）**，理由：
>
> 1. **目标仓库零提交** —— 天然适合作为新起点，无历史包袱。
> 2. **凭据问题无从规避地简化** —— 不从历史导入，就不存在"历史里躺着一份公网
>    可读的密码"。这是最强的安全论据。
> 3. **交付物件是"可构建的栈"，不是"提交谱系"** —— 客户端拿到的是代码树，
>    `git blame` 对交付价值有限。
> 4. **源仓库保持只读保留**，历史仍可查（`C:\pacgate-ai-pr` 不删）。
>
> 若你认为 158 提交的历史对审计/追责有价值，则改用方式 3，但需接受重写源历史
> 与开发者重新克隆的代价。

---

## 5. 执行计划（分阶段）

> 每阶段均可独立验证、可回滚。**阶段 0 是硬前置。**

### 阶段 0 — 凭据处置（**必须先完成**）

| 步骤 | 动作 | 验收 |
|---|---|---|
| 0.1 | 轮换 PacGate GitHub 账号密码 + 吊销重签全部 PAT | 人工确认 |
| 0.2 | 轮换法律数据库统一密码（元典/北大法宝/企查查） | 人工确认 |
| 0.3 | 轮换境外法律数据库凭据 | 人工确认 |
| 0.4 | 在 `pacgate-ai-pr/.gitignore` 补规则（**根因修复**） | `git check-ignore -v <path>` 返回规则 |
| 0.5 | 重跑 `runtime/AUTHORITATIVE-credential-check.ps1` | 4 个文件转为 not-tracked（历史除外） |

**为什么必须最先做**：整合会把 `pacgate-ai-pr` 的文件与历史带进新仓库。若先整合、
后轮换，则期间新仓库同样持有有效凭据；若新仓库被公开，等于二次泄露。

⚠️ **注意**：`pacgate-ai-pr` 的 4 个凭据文件中，有 3 个是**中文路径**且此前被
编码缺陷漏报（见事件文档 §2.6）。凡涉及中文路径的检查，**必须**使用字节级脚本
（`AUTHORITATIVE-credential-check.ps1`），不得用字符串比较。

### 阶段 1 — 准备工作（不改变任何既有仓库）

1. **冻结写入**：确认无人正在 `pacgate-ai-pr` 上开发（当前 HEAD 在
   `feat/agent-capability-enablement`，确认是否为进行中分支）。
2. **建快照**：为两个源仓库各做一次 `.git` 备份（`pacgate-ai-pr` 仅 67 MB）。
3. **记录基线**：`git -C C:\pacgate-ai-pr rev-parse HEAD` → 写入
   `docs/pacgate/MONO-REPO-ORIGIN.md`，永久记录"本次归并自哪个提交"。
4. **决定 D1/D2/D3**（§3.1）。

### 阶段 2 — 清理目标仓库

`pacgate-law` 当前有**破损的 submodule 状态**，必须先修好再整合：

1. 处理 gitlink 破损：`.gitmodules` 记 `f712ec2`，实际 `0f7db15`。
2. 若按 **D3-a** 保留 submodule：修正 `.gitmodules` 的 `url` 与路径，
   并 `git submodule update --init` 使指针一致。
3. 若按 **D1-a**：将 submodule 路径由 `pacgate-ai` 改为 `pacgate-ai-assets`。
4. 清除临时文件：`containers.txt`、`mcp_verify.txt`、`mcp_final_verify.txt`、
   `verify_mcp.txt`（散落的验证输出，进 `runtime/` 或删除）。

### 阶段 3 — 首次提交（建立基线）

在**执行任何整合之前**，先把目标仓库现有内容提交为"初始状态"：

```bash
cd C:\Users\pacga\github-pr\pacgate-law
git add -A
git commit -m "chore: initial commit of pacgate-law docs/scope wrapper

Baseline before importing the runtime platform from pacgate-ai-pr.
Records the pre-merge state so the import is a reviewable, revertable diff."
```

**收益**：整合将成为**一个可 review、可 revert 的 diff**，而不是"一切都变了"。
这是本方案最重要的工程保障。

### 阶段 4 — 导入平台内容

按 **方式 2（squash）**：

1. 从源导出**仅跟踪文件**（这是关键 —— 绝不能 `cp -r` 整个目录）：

   ```powershell
   # 只导出 git 跟踪的内容（23.8 MB），不碰 target/ 与 data/
   git -C C:\pacgate-ai-pr archive --format=tar HEAD -o C:\tmp\pacgate-src.tar
   ```
2. 解包到目标根目录。
3. **在 `git add` 之前**清点：
   - 确认 `pacgate-ai/target/` 未出现（应被 archive 天然排除）
   - 确认 `deploy/client-bundle/data/` 未出现
   - 确认 4 个凭据文件**已删除或仍未跟踪**
4. 合并 `.gitignore`（两端规则取并集，含阶段 0.4 的凭据规则）。
5. 合并 `docs/`（文件不重叠，直接并入）。
6. 提交（见阶段 5）。

⚠️ **不要用 `git checkout origin/main -- <dir>` 整目录覆盖** —— 会覆盖目标端
已被修改的文件。逐个文件处理。

### 阶段 5 — 用 git 提交承载导入

```bash
git add -A
git commit -m "feat(mono): import pacgate-ai-pr runtime platform

Imported from pacgate-ai-pr @ <源 HEAD SHA> (see docs/pacgate/MONO-REPO-ORIGIN.md).
Squashed import: upstream history is intentionally not carried over, so that
credential-bearing commits do not enter this repository's history.

Contents: pacgate-ai (Rust workspace), deploy/ (6 compose projects),
pacgate-adapters/, scope-assets/, patches/, auth-gate/, nginx/, docs/.
Excluded: pacgate-ai/target/ (build artifacts), deploy/client-bundle/data/
(client data) -- both regenerable or client-owned."
```

### 阶段 6 — 处理嵌套仓库

1. **deer-flow（D2-a）**：转为正式 submodule
   ```bash
   git submodule add -b pacgate-layer https://github.com/pacgate-ai/deer-flow.git deer-flow
   ```
   或若目录已存在，先移开再 add，避免"已存在"报错。
2. 更新 `.gitmodules`，记录 branch。
3. 验证：`git submodule status` 无 `-` 前缀（`-` 表示未初始化）。

### 阶段 7 — 验证

| 检查 | 命令 | 期望 |
|---|---|---|
| 跟踪文件数 | `git ls-files \| wc -l` | ≈ 515 + 目标原有 |
| 体积 | `git count-objects -vH` | 与 23.8 MB 量级相符，**远小于 7 GB** |
| 无构建产物 | `git ls-files \| grep -c 'pacgate-ai/target/'` | 0 |
| 无客户端数据 | `git ls-files \| grep -c 'client-bundle/data/'` | 0 |
| 无凭据文件 | `runtime/AUTHORITATIVE-credential-check.ps1` | 4 文件 **not tracked** |
| 无凭据明文 | `runtime/check-authored-files-for-leaks.ps1` | PASS |
| submodule 一致 | `git submodule status` | 前缀为空 |
| 可构建 | 见 §7 | 通过 |
| **历史无凭据** | `git log --all -S '<凭据标记>'` | **0 命中**（squash 的核心收益） |

### 阶段 8 — 收尾

1. 更新 `AGENTS.md`：新拓扑、新路径、草案/权威说明。
2. 新增 `README.md`：交付入口（如何 clone、build、deploy）。
3. 保留 `C:\pacgate-ai-pr` 为**只读历史副本**，在 README 注明。
4. 通知开发者：新仓库位置、clone 方式（`--recursive`）、旧仓库只读。

---

## 6. 凭据处置（硬前置，独立于整合）

**事实**（字节级复核后）：

| # | 文件（同一子树） | 内容 | 公网可读 | 引入提交 |
|---|---|---|---|---|
| 1 | `.../pacgate-ai-remote-handbook/OPERATOR.md` | GitHub 账号凭据 ×10 | ✅ 200 | `01a4644` |
| 2 | `.../MCP授权/法律数据库MCP.md` | 统一登录名+密码 | ✅ 200 | — |
| 3 | `.../MCP授权/境外法律数据库和网站.md` | 境外库账号 | ✅ 200 | — |
| 4 | `.../MCP授权/百宸AI系统资源接入清单V2.docx` | 接入清单 | ✅ 200 | — |

**根因**：`pacgate-ai-pr/.gitignore` 无相应规则；正确规则只存在于
**submodule** 的 `.gitignore` 中。即**规则写在了错误的仓库里**。

**对整合方案的影响**：

- 若采用**方式 2（squash）**：这 4 个文件的历史**不会**进入新仓库 → 新仓库自然干净。
  这是推荐方式 2 的**主要理由**。
- 若采用**方式 1/3**：必须先用 `filter-repo` 清除，否则新仓库历史同样含凭据。
- **无论哪种方式**，阶段 0 的**凭据轮换都不可省略** ——
  `pacgate-ai-pr` 的历史已公网可读，删除与改历史都无法回收。

**额外**：源内 vendored 资产树 `pacgate-ai/pacgate-ai-assets/`（59 文件）
**包含全部 4 个凭据文件**且未被忽略。按 **D3-a** 应**整体删除**该副本。

---

## 7. 构建与部署验证（整合后）

整合的验收标准不是"文件都在"，而是"能构建、能起服务"：

1. **Rust 构建**：`cargo build --workspace`（在 `pacgate-ai/` 下）
2. **镜像构建**：`deploy/build-images.ps1 -Tag <测试标签>`（**不 push**）
3. **compose 校验**：`docker compose -f deploy/client-bundle/compose.bundle.yaml config`
   —— 验证路径引用在新目录结构下仍可解析
4. **运行时对比**：重跑 `runtime/capture-runtime.ps1`，与整合前清单比对
5. **冒烟**：按 `deploy/SETUP-AND-OPERATIONS.md` 起最小栈

> ⚠️ **最大风险点**：`compose.bundle.yaml` 中的**相对路径与 bind mount**。
> 当前工作目录为 `C:\pacgate-ai-pr\deploy\client-bundle`，容器 bind-mount
> 该目录下的路径。整合后绝对路径变化，**必须逐个核对**。建议整合后先
> `docker compose config` 全量检查，再考虑起容器。

---

## 8. 风险登记

| # | 风险 | 概率 | 影响 | 缓解 |
|---|---|---|---|---|
| R1 | 凭据被带进新仓库 | 中 | **高** | 阶段 0 先行；采用 squash 导入 |
| R2 | compose bind-mount 路径失效 | **高** | **高** | §7.3 `config` 校验；逐文件核对 |
| R3 | 误把 `target/`（4.5 GB）纳入 | 中 | 中 | 只用 `git archive`，禁 `cp -r` |
| R4 | 误把客户端数据 `data/`（1.9 GB）纳入 | 中 | **高** | 同上 + gitignore 复核 |
| R5 | submodule 再次破损 | 中 | 中 | 阶段 2 先修好；阶段 7 验证 `submodule status` |
| R6 | 丢失 deer-flow 的 192 提交与 PR | 中 | 中 | 采用 D2-a（submodule）而非 D2-b |
| R7 | 开发者仍向旧仓库提交 | 中 | 中 | 阶段 8 更新 AGENTS.md 并通知 |
| R8 | 中文路径检查再次假阴性 | **高** | **高** | **强制**使用字节级脚本；见事件文档 §2.6 |
| R9 | 整合期间源仓库有新提交 | 低 | 中 | 阶段 1 冻结写入并记录基线 SHA |
| R10 | `docs/scripts` 同名不同内容 | 低 | 低 | 逐文件 diff，不整目录覆盖 |

---

## 9. 回滚

每一阶段都可回滚：

- **阶段 3 之前**：目标仓库无提交，`git reset` 即可。
- **阶段 3 之后**：阶段 3 的初始提交是稳定基线。
  整合出问题 → `git reset --hard <阶段3 SHA>`。
- **源仓库**：全程不修改，仅读取。`C:\pacgate-ai-pr` 保持原样。
- **快照**：阶段 1.2 的 `.git` 备份可完整还原。

> 因为整合被承载为**独立提交**（阶段 5），回滚是 `git reset` 一次操作。

---

## 10. 待决策事项

| 编号 | 决策 | 推荐 | 影响面 |
|---|---|---|---|
| **D1** | `pacgate-ai/` 归 Rust workspace 还是 submodule | **D1-a**（Rust 占名，资产改 `pacgate-ai-assets/`） | 全仓库路径 |
| **D2** | `deer-flow/` 转 submodule 还是内联 | **D2-a**（submodule，保留 PR/上游） | 交付完整性 |
| **D3** | 资产树用 submodule 还是源内 vendored | **D3-a**（submodule，删 vendored） | 安全性 |
| **D4** | 导入方式：squash / subtree / filter-repo | **方式 2 squash**（规避历史凭据） | 历史保留 |
| **D5** | 目标仓库是否公开 | 建议**私有**（客户法律数据+模型配置） | 安全 |
| **D6** | `C:\pacgate-ai-pr` 是否保留为只读副本 | **保留**（历史查询用） | 可追溯性 |

---

## 11. 本方案明确不做的事

1. ❌ 不删除或改写 `C:\pacgate-ai-pr` 的任何内容
2. ❌ 不强制推送任何远程
3. ❌ 不轮换凭据（需所有者操作）
4. ❌ 不修改任何 compose 文件中的镜像引用
5.  不重启/停止/重建任何运行中的容器（当前 25 个）
6.  不触碰 4 个兄弟仓库

---

## 12. 参考

- 凭据事件详情：`docs/superpowers/specs/2026-09-16-credential-exposure-incident.md`
- 运行时清单：`runtime/RUNTIME-INVENTORY.md`、`runtime/README.md`
- 字节级凭据检查：`runtime/AUTHORITATIVE-credential-check.ps1`
- 现有集成说明：`DEER-FLOW-INTEGRATION.md`
- 部署手册：`C:\pacgate-ai-pr\deploy\SETUP-AND-OPERATIONS.md`、
  `C:\pacgate-ai-pr\deploy\AIPC-DEPLOYMENT-HANDBOOK.md`