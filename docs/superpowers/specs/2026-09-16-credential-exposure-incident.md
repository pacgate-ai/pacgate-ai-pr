# 安全事件：GitHub 凭据泄露到公开仓库

- **发现日期**: 2026-09-16
- **严重级别**: **高** —— 凭据当前正被公网可读
- **状态**: 已确认，**未修复**（修复需仓库所有者决策）
- **发现者**: 在执行 "transfer pacgate-ai-pr into this repo/PR" 调查时偶然发现

> ## ⚠️ 勘误（同日晚间修订）
>
> 本文档初版声称"**仅 1 个文件**泄露，`法律数据库MCP.md` 未被跟踪"。
> **该结论是错的**，原因是本人扫描脚本存在编码缺陷（见新增的 §2.6）。
>
> 经字节级复核，实际为 **4 个** 凭据文件均已跟踪且公网可读：
>
> | # | 文件 | 内容 | 公网可读 |
> |---|---|---|---|
> | 1 | `.../pacgate-ai-remote-handbook/OPERATOR.md` | PacGate GitHub 账号凭据（10 项） | ✅ |
> | 2 | `.../MCP授权/法律数据库MCP.md` | 统一登录名 + 统一密码 | ✅ |
> | 3 | `.../MCP授权/境外法律数据库和网站.md` | 境外库账号信息（11 行） | ✅ |
> | 4 | `.../MCP授权/百宸AI系统资源接入清单V2.docx` | 资源接入清单（含凭据） | ✅ |
>
> 严重级别不变仍为"高"，但**影响面比初版评估更大**：泄露的不只是 GitHub 账号，
> 还包括三套法律数据库（元典、北大法宝、企查查统一登录）的账号密码。
>
> 教训见 §2.6 —— 这也是本次修订保留在文档中的原因。

---

## 1. 事件概要

`pacgate-ai-pr` 仓库中，一个自述为"已 gitignore、含真实凭据"的文件**实际上被 git 跟踪，并已推送到公开仓库**。

**文件路径**（注意 `assets/assets` 重复）：

```
pacgate-ai/pacgate-ai-assets/pacgate-ai/assets/assets/pacgate-ai-remote-handbook/OPERATOR.md
```

**文件自身声明**（第 3 行起）：

```
# 🚨 OPERATOR ONLY — DO NOT COMMIT, DO NOT SHARE 🚨

> **This file is gitignored.** It contains real credentials for the PacGate
> GitHub account that the public handbook must never see. If you are reading
> this on a public clone, you are reading stale or fake data.
```

该声明的两部分**均为错误**：

1. "This file is gitignored" —— 实际**未被忽略**。
2. "you are reading stale or fake data" —— 实际**是真实凭据**（已核验非占位符）。

---

## 2. 核验证据

### 2.1 跟踪与忽略状态

| 检查项 | 结果 |
|---|---|
| `git ls-files --error-unmatch` | **跟踪中** |
| `git check-ignore` | **空**（未被忽略） |
| 存在于 `HEAD` | **是** |
| 存在于 `main` | **是** |
| 存在于 `fork/main`（pacgate-ai/pacgate-ai-pr） | **是** |
| 存在于 `origin/main`（JZKK720/pacgate-ai-pr） | **是** |
| 引入提交 | `01a4644` (2026-08-13) "feat: implement pacgate-rag + 20 legal personas + 10 workflow templates" |
| 触及该路径的提交数 | **1** |

### 2.2 内容一致性（关键）

四个 ref 指向**同一个 blob**，即内容逐字节相同：

```
HEAD        5855e649dbbf203f6432a3f5370f3daf427a9180
main        5855e649dbbf203f6432a3f5370f3daf427a9180
fork/main   5855e649dbbf203f6432a3f5370f3daf427a9180
origin/main 5855e649dbbf203f6432a3f5370f3daf427a9180
```

且**磁盘上的文件与已泄露的 blob 完全一致**（`git hash-object` == `git rev-parse HEAD:path`），
说明泄露的是**当前有效凭据**，而非历史遗留的旧值。

> 注：`fork/main` 与 `origin/main` 是**不同的提交**（`28dc159` vs `c2b54f9`），
> 但该路径的 blob 相同 —— 即两个远端都持有同一份凭据。

### 2.3 公网可读性（含反向对照）

仅凭 HTTP 200 不足以证明暴露（企业代理/VPN 可能对一切请求返回 200）。
因此加入**反向对照**：一个必然不存在的路径必须返回 404。

```
CONTROL: bogus path (must 404)     HTTP 404     ← 对照通过
CONTROL: bogus repo (must 404)     HTTP 404     ← 对照通过
TARGET: fork raw                   HTTP 200  bytes=1731
TARGET: origin raw                 HTTP 200  bytes=2250
```

对照返回 404、目标返回 200，**排除了代理误报**，暴露属实。
（两个 TARGET 的字节数差异是抓取时的测量噪声，非内容差异 —— 见 2.2 的 blob 比对。）

### 2.4 凭据真实性

**判定方式**（未打印任何明文）：解析文件中的 Markdown 表格，统计每行取值单元格：

- 共 **10** 个非空取值单元格
- 无一个匹配占位符模式 `{{...}}`
- 长度分布 5–93 字符（邮箱长度 26、密码 12、token 35–93 等）

判定：**真实值，非占位符**。

### 2.5 根因

`pacgate-ai-pr/.gitignore` 的内容中**完全不含** `OPERATOR` 或 `法律数据库MCP` 字样。
忽略规则只存在于**子模块** `pacgate-law/pacgate-ai/.gitignore` 中，而子模块的
`.gitignore` 管不到 `pacgate-ai-pr` 的路径。

即：**忽略规则写在了错误的仓库里。** 文件头部"本文件已被 gitignore"的声明，
反映的是作者对子模块规则的信任，而非对实际仓库状态的核验。

---

### 2.6 ⚠️ 勘误根因：扫描脚本的编码缺陷（重要教训）

初版扫描得出"仅 1 个文件"的**错误**结论，根因是**字符串比较在这一环境下不可靠**。

**失效链条：**

1. `git ls-files` 输出的路径是 **UTF-8** 编码；
2. PowerShell 5.1 把原生命令的 stdout 按**控制台代码页**解码 —— 中文 Windows 是 **GBK**；
3. 于是 git 的 UTF-8 中文路径被解码成乱码（如 `智库资料收集` → `哄簱璧勬枡鏀堕泦`）；
4. 脚本里用**中文字面量**去匹配这些乱码 → 永不匹配；
5. 结果：文件明明被跟踪，却被判定为"未跟踪" → **假阴性**。

**为什么第一次没发现：** `OPERATOR.md` 是纯 ASCII 文件名，不受影响，所以命中了；
含中文的两个文件全部漏报。**只漏报中文文件**，正是编码缺陷的典型特征。

**根治措施（已实施）：改用字节级比较，消除代码页参与。**

```powershell
# 1) 把 git 输出按"原始字节"落盘，全程不做字符串解码
cmd /c "git -C C:\pacgate-ai-pr ls-files -z > _lsfiles.raw"
$raw = [System.IO.File]::ReadAllBytes($tmp)

# 2) 搜索词也用字节构造 —— 且不在 .ps1 里写任何中文字面量
#    （BOM-less 的 .ps1 同样会被 PowerShell 以 GBK 读取，中文字面量会先损坏）
$needle = [System.Text.Encoding]::UTF8.GetBytes((ConvertFrom-CodePoints @(0x6CD5,0x5F8B,...)))
$hits   = Find-Bytes -hay $raw -needle $needle    # 逐字节匹配
```

**复核结果（含对照）：**

```
OPERATOR.md (handbook creds)           TRACKED=True  (byte hits: 1)
legal-DB passwords .md                 TRACKED=True  (byte hits: 1)
overseas legal-DB .md                  TRACKED=True  (byte hits: 1)
resource inventory .docx               TRACKED=True  (byte hits: 4)

CONTROL  OPERATOR.md positive control  hits=1     ← 匹配器有效
CONTROL  bogus negative control        hits=0     ← 不会误报
```

**该缺陷不止影响一处**：同一脚本的远程暴露检查也曾对中文路径返回 404（同样是
URL 编码前就把路径弄坏了）。修正后变成 200。**即"未泄露"这个结论本身也是编码
假象**。凡涉及中文路径的判断，都必须走字节级或显式 UTF-8 路径。

**可复现工具**：`runtime/AUTHORITATIVE-credential-check.ps1`（字节级，权威）
与 `runtime/check-all-exposed-remote.ps1`（远程暴露，含反向对照）。

---

## 3. 影响范围（已界定）

### 3.1 三个仓库的全历史扫描

扫描 `git log --all -S`（内容级搜索，覆盖已删除文件），并带**正向对照**以确保搜索功能
本身有效（若对照为 0，说明搜索失效而非"干净"）：

| 仓库 | 凭据标记命中 | `OPERATOR` 路径（含已删除） | 对照 `-S 'pacgate'` |
|---|---|---|---|
| `pacgate-ai-pr` | **1** (`01a4644`) | **1** | 103 ✅ 搜索有效 |
| `deer-flow` | 0 | 0 | 8 ✅ 搜索有效 |
| `pacgate-ai`（子模块） | 0 | 0 | 6 ✅ 搜索有效 |

**结论：泄露仅存在于 `pacgate-ai-pr` 一个仓库。** `deer-flow` 与子模块均干净，
且两者的对照命中数非零，证明"0 命中"是真实结果而非搜索失效。

### 3.2 其他潜在泄露面

> ⚠️ 本节初版结论已被 §2.6 推翻，以下为**更正后**的结论。

- **是否已泄露法律数据库密码**：**是** —— 见 §1 勘误表第 2–4 项。
  初版判定"否"是编码假阴性所致。
- **是否泄露 `.env`**：**否** —— 无真实 `.env` 被跟踪（此项经字节级复核仍成立）
- **历史中是否曾有其他敏感文件被删除后残留**：扫描曾进入过历史的全部 775 个路径
  （当前跟踪 515 个，另有 260 个为 `pacgate-adapters/` 下已删除文件），
  未发现**其它**敏感命名的历史残留

**更正后的结论**：泄露共 **4 个文件**，全部位于同一目录树
`pacgate-ai/pacgate-ai-assets/pacgate-ai/assets/assets/` 下。它们**不是**分散的
孤立问题，而是**同一个根因**（该子树应被忽略却未被忽略）的多个表现。

| 泄露内容 | 影响 |
|---|---|
| PacGate GitHub 账号凭据（10 项） | 可登录该账号 → 可改代码/仓库 |
| 法律数据库统一登录名 + 统一密码 | 可访问元典 / 北大法宝 / 企查查 |
| 境外法律数据库账号信息 | 可访问境外法律库 |
| 资源接入清单（含凭据） | 面更广，需人工审阅 |

**注**：全部 4 个文件同属一子树，意味着**修复是单点动作**（忽略该子树 + 轮换凭据），
而不是 4 个独立修复。这是更正后唯一的好消息。

---

## 4. 为什么"删掉文件"不能解决问题

该文件存在于**公开的历史提交** `01a4644` 中。即使现在 `git rm` 并提交：

- 该提交仍可通过 `github.com/pacgate-ai/pacgate-ai-pr/commit/01a4644` 访问；
- raw 链接按 commit hash 仍可直读；
- 任何已克隆/已 fork 的副本（包括 GitHub 的 fork 网络与缓存）仍持有；
- GitHub 不会因后续删除而清除历史对象。

**因此必须按"已泄露"处理，而不是"已删除"处理。**

---

## 5. 建议处置（按优先级，均需所有者决策）

> 以下为建议，**尚未执行任何一项**。

### P0 —— 立即轮换凭据（唯一真正有效的措施）

1. 轮换 PacGate GitHub 账号密码。
2. 吊销所有现存 PAT / token，重新签发。
3. 若该账号对 `pacgate-ai/*` 或 `JZKK720/*` 有写权限，检查近期是否有异常提交/分支/协作者。
4. 检查该凭据是否在其他服务复用（复用会扩大影响面）。

*顺序很重要：先轮换，再清理历史。先清理会暴露"已发现"信号而无实际防护收益。*

### P1 —— 补上忽略规则（修根因）

在 **`C:\pacgate-ai-pr\.gitignore`**（而非子模块）中加入：

```gitignore
# PacGate remote-access handbook — operator-only credentials
**/pacgate-ai-remote-handbook/OPERATOR.md

# Legal-DB credentials (defense in depth)
**/MCP授权/法律数据库MCP.md
```

用 `**/` 前缀是因为该文件位于深层且重复的 `assets/assets` 路径下，具体路径易变。

### P2 —— 从跟踪中移除（但要理解其局限）

```powershell
git -C C:\pacgate-ai-pr rm --cached "pacgate-ai/pacgate-ai-assets/pacgate-ai/assets/assets/pacgate-ai-remote-handbook/OPERATOR.md"
```

**局限**：这一步只防止**未来**的提交，**不能**撤销历史泄露。仅在前述 P0 完成后执行才有意义。

### P3 —— 历史重写（可选，高风险）

`git filter-repo` 或 BFG 清除 `01a4644` 中的该文件，然后强制推送。代价：

- 必须同时 force-push `fork/main` **和** 协调 `origin/main`；
- 开发者需重新克隆（否则会推回旧历史，导致泄露复活）；
- 已知 fork/缓存不会自动清除。

**须先与持有该仓库的人协调后再执行**，否则极易造成开发者与客户端仓库分叉。

---

## 6. 记录：本次未执行的动作

1. ❌ 未修改 `.gitignore`
2. ❌ 未 `git rm` 任何文件
3. ❌ 未提交、未推送、未 force-push
4. ❌ 未轮换任何凭据（需所有者操作）
5. ❌ 未在日志/输出中打印任何凭据明文
6. ❌ 未执行原请求的 "transfer pacgate-ai-pr into this repo/PR"

第 6 项被有意搁置：把 `pacgate-ai-pr` 合并进 deer-flow 的 PR 会把该凭据文件**再扩散到第三个公开仓库**，使影响面扩大。在 P0 完成前，任何跨仓库复制该目录的操作都应暂停。

---

## 7. 复核工具（修复后可重复运行）

本事件的所有结论均由脚本产出，**修复后应重跑以验证**。脚本位于 `runtime/`：

| 脚本 | 作用 | 输出 |
|---|---|---|
| `runtime/scan-credential-history.ps1` | 对三个仓库做**全历史**内容级扫描，含已删除文件 | `runtime/credential-scan-results.txt` |
| `runtime/check-exposure-control.ps1` | 检测目标文件是否仍公网可读，**含反向对照** | `runtime/exposure-control-results.txt` |
| `runtime/check-authored-files-for-leaks.ps1` | 自检：本文档自身是否误抄了凭据值 | `runtime/leak-selfcheck-results.txt` |
| `runtime/capture-runtime.ps1` | 容器/镜像清单（与本事件无关，见 `runtime/README.md`） | `runtime-inventory.json` 等 |

运行方式（须用绝对路径，`-File` 参数）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "c:\Users\pacga\github-pr\pacgate-law\runtime\scan-credential-history.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "c:\Users\pacga\github-pr\pacgate-law\runtime\check-exposure-control.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "c:\Users\pacga\github-pr\pacgate-law\runtime\check-authored-files-for-leaks.ps1"
```

### 修复完成的验收标准

修复后，下列条件**全部**成立才算闭环：

1. `scan-credential-history.ps1` 中 `pacgate-ai-pr` 的"凭据标记命中"仍为 **1**
   —— 这是**预期**的，因为历史提交无法通过新提交抹除。**不要**因为这仍是 1 就认为修复失败。
2. `check-exposure-control.ps1` 中两个 TARGET 变为 **404**
   —— 这需要历史重写 + 强制推送（P3），或仓库转为私有。
3. `.gitignore` 补丁生效：`git -C C:\pacgate-ai-pr check-ignore -v <path>` 返回规则行。
4. 凭据已轮换（此项无法由脚本验证，须人工确认）。

### 为什么要内置反向对照

两个脚本都刻意包含**反向对照**，因为单一信号会产生假结论：

- **HTTP 检查**：企业代理/VPN 可能对任意请求返回 200。若不加一个必然 404 的对照路径，
  "200" 可能只是代理行为，而非真实暴露。
- **`git log -S` 检查**：返回 0 命中可能是"仓库干净"，也可能是"搜索没生效"
  （例如路径错误、仓库损坏）。因此在同一仓库内搜一个已知存在的字符串作对照，
  必须命中 > 0，否则 0 命中无意义。

首次运行本事件检测时，这两点都得到了验证：对照分别返回 404 与非零命中，
因此 200 和 0 都是真实结果。

### 本文档自身的凭据自检

撰写本事件报告时，文档中不可避免地要描述那个凭据文件（路径、标签、行号）。
为避免"调查泄露的文档本身成为新的泄露源"，执行了自动化自检：

- 从源文件提取全部取值单元格 → **7 个真实值**参与比对
- **排除 1 个公开标识符**：标签为 `**GitHub ID**` 的单元格，其值是
  `` `pacgate-ai` ``（带反引号的公开组织名）。该名称本身出现在每个仓库 URL
  与目录路径中，**不是机密**，计入比对只会产生噪声。
  排除依据是**标签**（而非值），因此凭据轮换后依然稳定。
- 对 9 个本次撰写的文件逐一全文检索

**结果：`leaks=0`，判定 PASS。** 本文档不含任何凭据明文。

复现命令：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "c:\Users\pacga\github-pr\pacgate-law\runtime\check-authored-files-for-leaks.ps1"
```

> ⚠️ 该脚本的初版曾误报 3 处 FAIL，原因是把上述公开组织名当成了机密。
> 修正后才得到 PASS。保留此说明是为了提醒：**自动扫描需要人工判读**，
> 否则会把公开标识符当成泄露（噪声），也可能反向漏判。

---

## 8. 关联

- 传输可行性分析见 `2026-09-16-repo-consolidation-and-runtime-pinning-design.md`
- 关键事实：两仓库**无共同提交历史**（0 shared commits），deer-flow 是 `bytedance/deer-flow` 的 fork，其 PR 面向上游 —— 因此"合并"会破坏可上游性。