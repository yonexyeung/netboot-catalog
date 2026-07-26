# NetBoot Catalog — Multi-Perspective Review v2

> Date: 2026-07-25
> Method: 10 independent expert perspectives
> Input: ACD v2.0 + v3.0 + All Architecture Challenge Results

---

## Prompt 1: Devil's Advocate（反方）

**任務：證明這個產品不應該存在。**

---

### 論點 1：問題規模不足以支撐一個專案

「PXE boot 新 ISO 要 Google 15 分鐘」。

一個 homelab 使用者一年加多少個新 ISO？3-5 個。
每次 15-30 分鐘。一年總成本：1.5-2.5 小時。

你要花 6 個月建立一個工具，去省使用者每年 2 小時的手動工作。

**這不是 problem。這是 minor inconvenience。**

### 論點 2：iVentoy 已經完全解決這個問題

iVentoy Free Edition：
- Drop ISO → PXE boot ✓
- Auto detect distro ✓
- UEFI + Legacy BIOS ✓
- Web UI ✓
- Works out of the box ✓
- Zero configuration ✓

「但 iVentoy 是 closed source」— 99% 使用者不在乎。他們在乎「是否能用」。

「但 iVentoy 注入證書」— 只影響 Windows WinPE boot。Linux PXE boot 完全不受影響。沒有證據顯示 iVentoy 在 Linux boot chain 中注入任何東西。

「但我不信任 closed source」— 那你也不應該信任你 PXE boot 的 ISO（大部分使用者也不驗證 ISO hash）。Trust argument 是選擇性的。

### 論點 3：netboot.xyz + 30 分鐘手動配置 = 等效

netboot.xyz 已經有：
- 幾乎所有主流 distro 的 upstream boot support
- Self-hosted Docker image
- Custom menu 支援
- 活躍社區

如果使用者需要 local ISO boot，只需寫一個 custom iPXE entry。一次性工作。

**你的工具自動化的是一個「只需做一次」的動作。** 自動化的 ROI 在 frequency × effort。如果 frequency 低，ROI 不存在。

### 論點 4：這是 Engineering Hobby，不是 Product

所有「讓我用更好的方式做一件已經能做的事」的專案都有這個風險。

特徵：
- 解決的問題使用者已有 workaround ✓
- 目標使用者人數少 ✓
- 競品已存在且好用 ✓
- 主要動機是「我覺得應該有 open source 版本」✓

**「應該有」≠「需要有」。**

### 論點 5：沒有真正的競爭優勢

| 你宣稱的優勢 | 為什麼不成立 |
|-------------|-------------|
| Open source | 大部分使用者不 care |
| Adapter library | 只有 maintainer 維護才有價值 — bus factor=1 |
| Community | 你還沒有社區 |
| Extensible | iVentoy 不需要 extend — it just works |
| Auditable | 使用者不會 audit |

### 論點 6：五年維護不值得

五年維護成本：
- 每次 distro release → update adapter（~20 次/年）
- 每次 upstream tool change → fix integration
- 每次 Docker base image update → rebuild + test
- 每次使用者 report "boot 不到" → debug network issue（不是你的 bug）
- Community management（PRs, issues, discussions）

**所有這些都沒有收入。** 對一個 niche 工具，motivation 會在 1-2 年後消失。

### Devil's Advocate 最終判決

**建議停止專案。原因：**

1. Problem 太小（minor inconvenience, not real pain）
2. iVentoy 已解決（99% 使用者的需求）
3. 沒有 sustainable competitive advantage
4. 五年維護成本高於價值
5. 更好的做法：寫一篇 blog post 整理所有 distro 的 PXE boot params

---

### Devil's Advocate 自我承認的弱點

1. iVentoy 的 trust 問題在 2024 年爆發後確實產生了 demand signal
2. OpenPXE 的出現證明有人願意從零重建
3. 如果目標不是 "beat iVentoy" 而是 "provide auditable alternative for security-conscious users" — 那 niche 雖小但 real
4. Adapter library 作為 knowledge base 有獨立價值（即使 tool 消亡）

---

## Prompt 2: Product Manager（產品）

---

### 真正的 Problem

**Problem Statement：**
Linux Live ISO 的 PXE boot configuration 是分散的、undocumented 的、brittle 的知識。每個 distro 不同。每次 update 可能變。沒有 canonical source。

**Pain 的表現形式：**
- 花時間 research boot params
- Trial and error 直到成功
- Setup 完不敢動（怕壞）
- 不敢加新 ISO（怕搞亂現有 setup）

### Target User

**Primary:** Security-conscious homelab power user（在乎 open source + 頻繁換 ISO）

**Secondary:** MSP technician（需要快速 PXE boot 多種 tool ISO）

**Not target:** Casual user（一年 PXE boot 一次）、Enterprise（用 MAAS/Foreman）

### User Journey（Current）

```
Want to PXE boot a new ISO
  → Download ISO
  → Google "<distro> PXE boot parameters"
  → Find 3 blog posts (2 outdated, 1 partial)
  → Mount ISO locally to find kernel path
  → Guess boot args
  → Write iPXE entry manually
  → Test boot (fail)
  → Debug kernel panic / unable to find rootfs
  → Google more
  → Fix boot args
  → Test again (success)
  → 30-90 minutes elapsed
```

### User Journey（Future with NetBoot Catalog）

```
Want to PXE boot a new ISO
  → Drop ISO into import folder
  → System auto-detects and extracts
  → Boot menu updated
  → Test boot (success)
  → 30 seconds elapsed
```

### MVP 聚焦度

**必須有：**
- Import ISO (CLI or file drop)
- Auto detect distro
- Auto extract boot assets
- Generate iPXE menu
- Serve boot files (HTTP)
- Docker one-command deploy

**不需要（Scope Creep）：**
- Web UI（v1 不需要）
- REST API（沒有 UI 就不需要）
- Backend switching
- Windows support
- URL import / auto-download
- Per-host configuration
- Multi-user / RBAC
- Ansible playbook

### Differentiation

| vs | NetBoot Catalog 的差異 |
|----|----------------------|
| iVentoy | Open source, auditable, no binary injection |
| netboot.xyz | Local ISO support, auto-extraction, zero-config |
| Manual iPXE | Automation, community adapter library |
| MAAS/Cobbler | Lightweight, no DB, homelab-friendly |

### Product Positioning

> **「Drop ISO. Network Boot. Open Source.」**

不要叫 "Catalog Platform"。使用者不想要 platform。
他們想要：**放入 ISO → 可以 boot。**

### Painkiller or Vitamin?

**Painkiller for a niche audience.**

- 對 security-conscious + frequent ISO changer：Painkiller
- 對其他所有人：Vitamin（iVentoy 已夠好）

Product viable 但必須精準命中 primary persona。

---

## Prompt 3: Domain Expert（DDD）

---

### Ubiquitous Language

| Term | Definition |
|------|-----------|
| ISO | 原始輸入檔案（opaque binary blob） |
| Adapter | 描述如何從某 distro 的 ISO 中提取 boot assets 的知識 |
| Boot Recipe | 從 ISO 提取出的完整 boot 描述（kernel + initrd + rootfs + args） |
| Import | 將 ISO 轉化為 Boot Recipe 的 transformation process |
| Catalog | 所有 Boot Recipe 的集合 |
| Publish | 將 Boot Recipe 轉化為 PXE-servable 狀態 |

### Domain

**Domain：ISO Boot Knowledge Normalization**

核心問題域 = 理解不同 Linux ISO 的內部結構，並將其轉化為標準化的 boot recipe。

這是一個 **knowledge transformation domain** — 不是 CRUD domain，不是 workflow domain。

### Bounded Context

只有一個 Bounded Context：**Boot Recipe Production**。

不需要多個 context。系統太小。如果你把它切成多個 bounded context，你在製造 artificial complexity。

### Aggregate

**沒有 Aggregate。**

Aggregate 存在的理由是 protect transactional invariants across a cluster of objects。

這個系統：
- 沒有 concurrent writes
- 沒有 cross-entity invariants
- 沒有 transactional boundary
- 是 single-user admin tool

**結論：不需要 Aggregate pattern。**

### Entity

**Boot Recipe** 是唯一的 Entity（有 identity — 通過 distro + version + arch 唯一識別）。

其他全部是 Value Object 或 Infrastructure。

### Value Object

| Object | Why Value Object |
|--------|-----------------|
| Adapter definition | 無 identity，由 content 定義 |
| Boot args | 純值，immutable |
| File path | 純值 |
| Detection rule | 純值，可比較 |

### Domain Service

**ImportService** — orchestrates: mount ISO → match adapter → extract files → produce recipe

這是唯一的 domain service。其餘都是 infrastructure。

### Domain Event

**不需要 Domain Events。**

Domain Events 有價值 when：多個 bounded contexts react to same event。

這個系統只有一個 context，一條 pipeline，同步執行。Event = function call。不需要 event bus。

### 哪些只是 Infrastructure？

| 被誤認為 Domain 的 | 實際角色 |
|-------------------|---------|
| Runtime (dnsmasq, nginx, iPXE) | Infrastructure — file delivery |
| REST API | Interface adapter |
| Web UI | Interface adapter |
| Docker | Deployment concern |
| File system layout | Persistence mechanism |
| iPXE menu generation | Output formatting (presentation) |
| DHCP/TFTP | Network infrastructure |

### 哪些抽象根本不存在？

| 被命名但不存在的 Abstraction | 原因 |
|----------------------------|------|
| "Runtime Interface" | Runtime 不是可互換的 — 不同 runtime 有完全不同的 config model |
| "Backend" | 沒有共同行為 — native 和 netboot.xyz 只共享 "publish files" 概念 |
| "Catalog Entry vs Asset vs Boot Profile" 三層 | 不需要三層。Recipe = flat object |
| "Plugin Registry" | 沒有 plugin — 只有 data files (YAML adapters) |

---

## Prompt 4: Principal Architect（架構）

---

### Product Boundary 驗證

```
Input:  Local ISO file (user responsibility to obtain)
Output: Boot assets served via HTTP + iPXE menu entry
Ends:   Client begins kernel execution
```

**驗證結果：正確。不需要修改。**

### Architecture Boundary 驗證

應該只有三個 boundary：

```
1. Knowledge Boundary   — Adapter YAML files (static, version-controlled)
2. Engine Boundary      — nbc CLI tool (transformation logic)
3. Delivery Boundary    — Docker appliance (runtime infrastructure)
```

目前設計的問題：把 Delivery 提升到與 Engine 同等地位（"Runtime Manager"）。不應該。Delivery 是可替換的包裝。

### Dependency Direction

```
┌─────────────────────────────────────────────────┐
│ Knowledge Layer (Adapter YAML definitions)      │  MOST STABLE
│   - detection rules                             │  Changes: only when distro changes
│   - extraction paths                            │
│   - boot args templates                         │
└────────────────────┬────────────────────────────┘
                     │ consumed by
                     ▼
┌─────────────────────────────────────────────────┐
│ Engine Layer (nbc CLI)                          │  STABLE
│   - import: mount → detect → extract → validate│  Changes: with features
│   - generate: read catalog → render template    │
│   - list / delete / export / validate           │
└────────────────────┬────────────────────────────┘
                     │ packaged into
                     ▼
┌─────────────────────────────────────────────────┐
│ Delivery Layer (Docker appliance)               │  LEAST STABLE
│   - file watcher                                │  Changes: UX-driven
│   - process supervisor (s6-overlay)             │
│   - dnsmasq + nginx + iPXE                      │
│   - optional: Web UI / API                      │
└─────────────────────────────────────────────────┘
```

**Rule：下層永遠不 import 上層。Delivery depends on Engine depends on Knowledge。**

### Layer 定義

| Layer | Responsibility | Stability |
|-------|---------------|-----------|
| Knowledge | "What files to extract + what boot args to use" | Highest |
| Engine | "Execute the transformation + manage catalog" | High |
| Delivery | "Serve the result to PXE clients" | Low |

### Extensibility

**唯一需要 extensible 的地方：Adapter library。**

方式：新增 YAML file。沒有 code change。沒有 plugin interface。

其他所有地方不需要 extensibility：
- Output format：加一個 template file（rare）
- Runtime：不需要 swap（deployment decision）

### Maintainability (十年)

| Risk | Mitigation |
|------|-----------|
| Adapter schema evolution | Version field + backward-compatible reader |
| CLI API stability | Semver + changelog |
| Docker base image EOL | Periodic rebuild + multi-stage build |
| UI framework rot | Don't build UI until necessary; API-first |
| Dependency supply chain | Minimal deps; pin versions |

### Architecture Dependency Graph（重新設計）

```
                    ┌─────────┐
                    │  User   │
                    └────┬────┘
                         │
              ┌──────────┼──────────┐
              ▼          ▼          ▼
         ┌────────┐ ┌────────┐ ┌────────┐
         │  CLI   │ │Web API │ │  File  │
         │  (nbc) │ │(future)│ │Watcher │
         └───┬────┘ └───┬────┘ └───┬────┘
             │           │          │
             └───────────┼──────────┘
                         ▼
              ┌──────────────────────┐
              │    Import Engine     │
              │  (detect + extract)  │
              └──────────┬───────────┘
                         │ reads
                         ▼
              ┌──────────────────────┐
              │   Adapter Library    │
              │   (YAML files)       │
              └──────────────────────┘
                         │ writes
                         ▼
              ┌──────────────────────┐
              │   Catalog (fs dirs)  │
              │   recipe.yaml + files│
              └──────────┬───────────┘
                         │ read by
                         ▼
              ┌──────────────────────┐
              │  Output Generator    │
              │  (iPXE template)     │
              └──────────┬───────────┘
                         │ consumed by
                         ▼
              ┌──────────────────────┐
              │  dnsmasq + nginx     │
              │  (serve to clients)  │
              └──────────────────────┘
```

---

## Prompt 5: Platform Engineer（平台）

---

### Platform Potential 分析

**直接判斷：作為 tool，沒有 platform potential。作為 adapter library，有。**

### 無法擴展到企業的設計

| 設計 | 為什麼不能 scale |
|------|----------------|
| Single instance, no sync | Enterprise 有 multi-site |
| No RBAC | Enterprise 需要 access control |
| No audit trail | Compliance 需要 |
| ProxyDHCP only | Enterprise 需要 DHCP relay across VLAN |
| File-based storage | 無法 distribute |
| No API auth | 無法安全暴露 |

**這些都不是問題 — 因為 target 不是 enterprise。**

### 具有 Platform Potential 的設計

| 設計 | Platform Value |
|------|---------------|
| Adapter YAML schema | 可被任何 PXE tool 消費（MAAS, Foreman, custom tooling） |
| Boot Recipe format | 可成為跨工具的 interchange format |
| nbc CLI as library | 可被 embedded 在 larger automation pipeline |
| Detection rules | 可被 CI/CD 用來 validate boot compatibility |

### 真正的 Platform Play

如果 adapter YAML schema 成為 de facto standard：

```
NetBoot Catalog Adapter YAML
       │
       ├── consumed by: nbc (this project)
       ├── consumed by: MAAS plugin
       ├── consumed by: Foreman integration
       ├── consumed by: Enterprise internal tooling
       └── consumed by: CI/CD pipeline validation
```

**策略：先做好 tool（build adoption），再 publish schema as spec（build ecosystem）。**

### Multi-site / HA

不需要。

如果使用者有多個 site：每個 site 跑一個 instance。Adapter library 通過 git repo 同步。Catalog 通過 rsync 或 shared storage 同步。不需要 built-in replication。

### API First

**v1 不需要 API。** CLI + file system = 足夠。

v2 如果加 Web UI 則需要 API。但 API 應該只是 CLI 的 HTTP wrapper：

```
POST /api/import  →  nbc import
GET  /api/catalog →  nbc list --json
```

---

## Prompt 6: Security Architect（安全）

---

### Trust Boundary Map

```
┌─ TRUSTED ─────────────────────────────────────────┐
│  nbc binary (from official release)               │
│  Adapter YAML (from official repository)          │
│  Generated catalog (output of trusted tool)       │
│  Docker image (built from official source)        │
└───────────────────────────────────────────────────┘

┌─ UNTRUSTED ───────────────────────────────────────┐
│  ISO files (any source, user-provided)            │
│  Community-contributed adapters (until reviewed)   │
│  Network (PXE/DHCP/TFTP/HTTP — inherently clear)  │
│  Script hooks in adapters (if enabled)            │
└───────────────────────────────────────────────────┘

┌─ TRUST BOUNDARY (critical crossing points) ───────┐
│  1. ISO → mount/extract (untrusted data enters)   │
│  2. Adapter YAML → engine execution               │
│  3. HTTP served files → PXE client boot           │
└───────────────────────────────────────────────────┘
```

### Threat Model

| # | Threat | Impact | Likelihood | Risk |
|---|--------|--------|-----------|------|
| 1 | Malicious ISO with path traversal in filenames | Host compromise | Medium | HIGH |
| 2 | Malicious ISO with symlink to sensitive file | Data exfil | Medium | HIGH |
| 3 | Zip bomb equivalent (huge file in ISO) | Disk exhaustion / DoS | Low | MEDIUM |
| 4 | MITM on HTTP boot (replace kernel) | Client compromise | Medium (LAN) | MEDIUM |
| 5 | Rogue DHCP response | Boot redirection | Low (LAN) | MEDIUM |
| 6 | Malicious adapter script hook | Host compromise | Low (requires merge) | MEDIUM |
| 7 | Unauthenticated API (if exposed remotely) | Unauthorized import | Low (default localhost) | LOW |

### 最大安全風險

**#1：ISO extraction path traversal。**

ISO 是 untrusted input。Extraction 是最危險的 trust boundary crossing。

If using `mount -o loop` + `cp`：relatively safe（OS handles filesystem）。
If using `bsdtar` / `7z`：must validate output paths explicitly。

**Mitigation（必須 implement）：**
```
1. Extract to temp directory (isolated)
2. Validate all extracted paths — reject .. / absolute / symlinks
3. Only copy expected files (kernel, initrd, rootfs) — ignore everything else
4. Set max file size limit
5. Atomic move to catalog (temp → final) only after validation
```

### 最危險信任邊界

**ISO file → system file system。** 這是唯一一個 untrusted data 進入 trusted space 的 crossing point。所有安全 effort 應集中在這裡。

### 最容易被攻擊位置

**如果 Web UI/API 暴露在 network 且無 auth：** 任何人可以 trigger import of a malicious ISO。

**Mitigation：** Default listen on `127.0.0.1` only。Remote access requires explicit opt-in + auth。

### Supply Chain

- Minimal：工具本身 dependency 少（如果用 shell = zero external deps）
- Docker base image：pin digest，不用 `:latest`
- Adapter YAML：no dependencies（pure data）
- iPXE binaries：from official ipxe.org builds or self-compiled

---

## Prompt 7: DevOps / SRE（營運）

---

### Deployment

**目標：一行命令。**

```bash
docker run -d --network host --cap-add NET_ADMIN \
  -v /srv/import:/import \
  -v /srv/catalog:/catalog \
  ghcr.io/xxx/netboot-catalog:latest
```

**已知 constraints：**
- `--network host` 必須（DHCP + TFTP 需要 specific ports）
- `--cap-add NET_ADMIN` 必須（dnsmasq raw socket）
- Rootless container 不可能（至少 v1）
- 需要 document clearly

### Upgrade

```bash
docker pull ghcr.io/xxx/netboot-catalog:latest
docker stop nbc && docker rm nbc
docker run ... (same command, same volumes)
```

Catalog data persisted in volume → upgrade = replace container only。

**Risk：** Schema migration。如果新版改了 recipe.yaml format 或 adapter YAML format → 需要 migration script。

**Mitigation：** Semver。Major bump = breaking。Provide `nbc migrate` command。

### Rollback

```bash
docker run ... ghcr.io/xxx/netboot-catalog:v1.2.3  # pin to previous version
```

File-based = no database migration to reverse。Volume 是 forward-compatible 就行。

### Backup & Restore

```bash
# Backup (whole catalog)
tar czf nbc-backup.tar.gz /srv/catalog/ /srv/config/

# Restore
tar xzf nbc-backup.tar.gz -C /

# Or: re-import from ISOs (everything rebuildable)
for iso in /backup/*.iso; do nbc import "$iso"; done
```

**"Everything Rebuildable" 原則是真正的運維優勢。** Backup 可以只保留 ISO + config。

### Disaster Recovery

RTO: minutes（re-deploy container + re-import ISOs）
RPO: zero data loss（catalog = deterministic output from ISOs）

**Best-case scenario for DR。** 因為 catalog 可以 regenerate from source ISOs。

### Observability

**Minimum viable（v1）：**

| Signal | Implementation |
|--------|---------------|
| Logs | Structured JSON to stdout (Docker default) |
| Health | `/health` endpoint or healthcheck script |
| Status | `nbc status` command (list entries + state) |

**Nice-to-have（v2）：**

| Signal | Implementation |
|--------|---------------|
| Metrics | Prometheus `/metrics` (import count, catalog size, uptime) |
| Boot tracking | nginx access log (which entries are being booted) |

**不需要：** Tracing。系統太簡單，沒有 distributed calls。

### Day-2 Operations

| Operation | Frequency | Effort |
|-----------|-----------|--------|
| Add new ISO | Weekly | Zero (drop file) |
| Update adapter | Per distro release | Edit YAML + test |
| Disk cleanup | Monthly | `nbc delete` old entries |
| Check health | Continuous | Automated health check |
| Debug "can't boot" | As reported | Check logs + network |

### 五年後是否仍容易維護？

**YES — 如果：**
1. 保持 file-based（no database to upgrade/migrate）
2. Adapter schema 有 version（可以 evolve）
3. Docker image stays minimal（few deps to patch）
4. 不加複雜 UI framework（biggest rot risk）

**NO — 如果：**
1. 加了 database
2. 加了 complex UI framework
3. 加了 runtime switching logic
4. Adapter library 沒有 automated testing

---

## Prompt 8: Open Source Maintainer（開源）

---

### Contributor Experience

**Adapter contribution = 極佳 contributor experience。**

- Barrier to entry：寫一個 YAML file（不需要會寫 code）
- Scope：每個 PR 是一個獨立的、small-scope adapter
- Motivation：使用者想用自己的 distro → 自然的 contribution 動機
- Review：YAML 容易 review（不像 code 有 hidden side effects）

**Core engine contribution = 較高 barrier。**

- 需要理解 engine 架構
- 需要寫 tests
- 需要 maintain backward compatibility

### API Stability

| Surface | Stability Promise |
|---------|-------------------|
| Adapter YAML schema | HIGH — 改 schema = break all community adapters |
| CLI commands/flags | MEDIUM — semver, deprecation warning before removal |
| Catalog directory layout | MEDIUM — other tools may depend on it |
| REST API (if added) | LOW initially — stabilize at v1.0 |
| Docker env vars | MEDIUM — changing means re-deployment |

**Most critical：Adapter YAML schema。** 一旦有 community adapters，schema 幾乎不能 break。

### Versioning Strategy

```
Adapter YAML:    adapter_version: "1" (in each file)
CLI tool:        Semver (v0.x = unstable, v1.x = stable API)
Docker image:    Semver tag + :latest
Catalog format:  catalog_version: "1" (in recipe.yaml)
```

### Community Governance

**建議 model：Benevolent Dictator + Adapter Maintainers**

- Core tool：main maintainer makes all decisions
- Adapter library：each adapter has an owner (can be community member)
- Decision process：RFC for breaking changes only

### 哪些應開放社群維護？

| Component | Governance |
|-----------|-----------|
| Adapter Library | **Community** — each adapter has an owner |
| Output Templates | **Community** — iPXE, GRUB, etc. formats |
| Documentation | **Community** — especially per-distro guides |
| Example configs | **Community** |

### 哪些必須由 Core Team 維護？

| Component | Governance |
|-----------|-----------|
| CLI engine | **Core** — breaking change affects all |
| Adapter schema | **Core** — it's the contract |
| Docker image / build | **Core** — release quality |
| CI/CD pipeline | **Core** — trustworthiness |
| Security patches | **Core** — response time matters |

### Documentation Cost

| Doc Type | Priority | Cost |
|----------|----------|------|
| Quick start (README) | Critical | Low (one-time) |
| Adapter writing guide | Critical | Low (one-time) |
| Troubleshooting PXE issues | High | Medium (ongoing) |
| Architecture docs | Low | Low (one-time) |
| API reference | Low (no API in v1) | N/A |

### Long-term Maintenance Cost

主要 cost driver：
1. **Adapter freshness** — ongoing, community can share load
2. **Docker base image updates** — periodic, low effort
3. **Issue triage** — "can't boot" issues that are network problems, not software bugs
4. **Schema evolution** — rare but high-impact

---

## Prompt 9: Research Reviewer（Evidence）

---

### 所有結論的 Evidence Classification

#### Confirmed（有充分證據）

| # | Claim | Evidence |
|---|-------|----------|
| 1 | iVentoy 是 closed source | Verified — GitHub repo only contains partial code |
| 2 | iVentoy 被發現注入證書/驅動 | Verified — multiple community reports (2024), garybowers/iventoy_docker README |
| 3 | netboot.xyz 不做 local ISO extraction | Verified — official docs confirm upstream-only model |
| 4 | 不同 distro 有不同 boot parameters | Verified — well-documented across multiple sources |
| 5 | OpenPXE 存在且宣稱做 ISO introspection | Verified — openpxe.com content fetched |
| 6 | iPXE 是 GPL open source | Verified — ipxe.org |
| 7 | Docker + dnsmasq 需要 NET_ADMIN / host network | Verified — technical requirement |

#### Likely（合理推論，缺乏驗證）

| # | Claim | Missing Evidence |
|---|-------|-----------------|
| 1 | YAML adapter 能覆蓋 80% distros | 未用真實 ISO 驗證 — 只是 architectural assumption |
| 2 | `bsdtar` 可以替代 `mount -o loop` | 未 benchmark — 部分 ISO 的 squashfs 可能不被 bsdtar 正確 handle |
| 3 | Homelab 使用者在乎 open source vs closed source | Survey data 缺失 — 只有 anecdotal Reddit posts |
| 4 | ProxyDHCP 在大部分 homelab 環境可用 | 未測試 common routers (UniFi, pfSense, consumer) |
| 5 | 12 週足夠完成 MVP | 未做 effort estimation with actual task breakdown |

#### Hypothesis（純假設）

| # | Claim | Why Hypothesis |
|---|-------|---------------|
| 1 | Adapter library 會吸引社區貢獻 | 沒有 precedent data — project 不存在 |
| 2 | 使用者會從 iVentoy switch 到本專案 | 沒有 user interview data |
| 3 | Adapter YAML schema 可以成為 de facto standard | 沒有 adoption signal |
| 4 | 五年後 adapter rot 是最大風險 | 合理推論但無法證明 |
| 5 | CLI-only MVP 足以獲得 early adopters | 未驗證 — 可能需要 GUI |

#### Requires Prototype

| # | Question | Prototype Method |
|---|----------|-----------------|
| 1 | YAML adapter 能否正確偵測 + extract top 5 distros? | 寫 5 個 adapter → test with real ISOs |
| 2 | `bsdtar` vs `mount` for ISO extraction | 測試 5 個 ISO → compare results |
| 3 | ProxyDHCP 在 3 種 router 的成功率 | 實際測試 UniFi / pfSense / TP-Link |
| 4 | End-to-end: drop ISO → PXE boot 成功 | Full integration test |
| 5 | Docker image size 是否可接受 | Build image → measure |

#### Requires User Interview

| # | Assumption | Question to Ask |
|---|-----------|-----------------|
| 1 | 使用者在乎 iVentoy trust 問題 | "你知道 iVentoy 的證書注入問題嗎？在乎嗎？" |
| 2 | CLI-only MVP 可接受 | "如果沒有 Web UI，你會用嗎？" |
| 3 | 使用者願意只用 Docker 部署 | "你會用 Docker 跑 PXE server 嗎？" |
| 4 | 使用者最常 PXE boot 哪些 distro | "列出你過去一年 PXE boot 過的所有 ISO" |
| 5 | Frequency of adding new ISOs | "你多久加一次新的 PXE boot ISO？" |

#### Requires Benchmark

| # | Question | Benchmark Method |
|---|----------|-----------------|
| 1 | Import speed (ISO → ready to boot) | 計時：mount + detect + extract + generate |
| 2 | Boot latency (PXE request → kernel loaded) | 計時：DHCP → TFTP → HTTP → kernel exec |
| 3 | Disk usage per entry | 量測 5 個 distro 的 extracted size |

---

## Prompt 10: Consensus Reviewer（共識整理）

---

### Consensus（所有 Reviewer 同意）

| # | Decision | Confidence |
|---|----------|-----------|
| 1 | Problem is real but niche | High |
| 2 | Core value = adapter library (knowledge base), not the tool | High |
| 3 | Product boundary correct: ISO → boot assets served → client boots | High |
| 4 | Boot 後不管 — out of scope | High |
| 5 | No database — file system is storage | High |
| 6 | No DDD patterns needed (no Aggregate, no Domain Events) | High |
| 7 | Runtime / Backend switching = over-engineering for v1 | High |
| 8 | ISO content = untrusted input, must validate extraction | High |
| 9 | Adapter YAML schema needs version field from day one | High |
| 10 | Web UI is NOT required for MVP | High |
| 11 | Docker appliance needs `--network host` + `--cap-add NET_ADMIN` | High |
| 12 | Five-year risk = adapter rot (not architecture) | High |
| 13 | CLI + adapters + Docker = correct MVP scope | High |
| 14 | Adapter contribution = best community engagement path | High |

### Major Disagreement

| # | Topic | Position A | Position B | Implication |
|---|-------|-----------|-----------|-------------|
| 1 | Should project exist? | Yes — gap is real, trust issue is real | No — problem too small, iVentoy works | Requires user validation |
| 2 | Engine language | Shell (zero deps, everyone reads) | Go (better HTTP, process mgmt, single binary) | Requires prototype |
| 3 | Is audience big enough to sustain? | Yes — iVentoy trust crisis creates demand | No — niche × niche × niche | Requires adoption metrics post-launch |
| 4 | Adapter repo location | Separate repo (reusable by others) | Same repo (simpler maintenance) | Can defer — start same repo, split later if demand |
| 5 | `mount` vs `bsdtar` for extraction | `mount` (precise, OS-handled) | `bsdtar` (no privileges needed) | Requires benchmark |

### High Risk（優先處理）

| # | Risk | Why Priority | Mitigation |
|---|------|-------------|-----------|
| 1 | ISO extraction security (path traversal) | Untrusted input → host compromise | Validate all extracted paths; extract to temp; atomic move |
| 2 | ProxyDHCP compatibility | Users can't boot → blame project | Test on 3 common routers; document limitations clearly |
| 3 | Adapter rot (stale after distro update) | Silent breakage → user frustration | Automated testing with mock ISOs; staleness marking |
| 4 | Privileged container requirement | Blocks rootless / some hosting | Explore bsdtar fallback; document clearly |

### Prototype Required

| # | What to Prototype | Success Criteria | Effort |
|---|-------------------|------------------|--------|
| 1 | End-to-end: Ubuntu ISO → PXE boot | Client boots successfully | 1-2 days |
| 2 | YAML adapter covers 5 distros (Ubuntu, Debian, VyOS, Fedora, Alpine) | All detected + extracted correctly | 2-3 days |
| 3 | bsdtar vs mount extraction comparison | Same output, no privileges needed | 1 day |
| 4 | ProxyDHCP with UniFi / pfSense / consumer router | Boot succeeds on all 3 | 1-2 days |
| 5 | Docker image build + deploy flow | One command → serving boot menu | 1 day |

### User Validation Required

| # | Hypothesis | Validation Method |
|---|-----------|-------------------|
| 1 | iVentoy trust issue drives switching | r/homelab poll or discussion post |
| 2 | CLI-only MVP is acceptable | Ask 5 target users |
| 3 | Docker deployment is acceptable for PXE | Ask 5 target users |
| 4 | Top 5 distros cover 80% of use cases | Survey: "what do you PXE boot?" |

---

### Final Recommendation

#### 是否批准開始開發？

## **YES — with conditions.**

---

#### 開始前最重要三項修改：

**1. 做一個 2-day prototype first（不是 6 個月開發）。**

Before writing any production code：
```
Day 1: Write Ubuntu adapter YAML + shell script that imports one ISO + generates iPXE menu
Day 2: Run dnsmasq + nginx in Docker + PXE boot a VM successfully
```

如果這個 prototype 失敗 → 不繼續。
如果成功 → proceed to production implementation。

**2. 砍掉所有 non-essential scope。**

刪除（不是 defer — 刪除 from mental model）：
- Runtime Manager
- Backend switching
- Web UI
- REST API
- Plugin Registry
- Domain Events
- Worker Queue

v1 = `nbc import` + `nbc generate` + Docker appliance。全部。

**3. Adapter testing strategy from day one。**

第一個 adapter 就要有 test：
- Mock ISO structure（用 `mkisofs` 建立）
- Run `nbc import` → verify output files
- Run `nbc generate` → verify iPXE syntax

不需要真實 4GB ISO。Mock structure 足夠做 unit/integration test。

---

#### 如果以上三個 condition 都滿足，推薦開發順序：

```
Week 1:     2-day prototype (validate end-to-end feasibility)
Week 2-3:   Define adapter YAML schema + write 3 adapters + test framework
Week 4-5:   Build nbc CLI (import, generate, list, validate)
Week 6-7:   Docker image (dnsmasq + nginx + iPXE + file watcher)
Week 8:     Integration testing + documentation
Week 9-10:  Additional adapters (Fedora, Alpine, Arch, Kali)
Week 11-12: Proxmox helper script + release + community launch
```

---

*10-perspective review complete. Document prepared for final decision.*
