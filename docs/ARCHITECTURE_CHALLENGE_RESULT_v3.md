# Architecture Challenge Response — v3.0

> Reviewer: Principal Architect (AI)
> Date: 2026-07-25
> Input: Architecture Challenge v3.0 — Product, Domain & Architecture Validation
> Approach: First Principles

---

## 7. Product Validation

### 7.1 這個產品真正解決的是什麼問題？

**消除「每個 Linux distro 的 PXE boot 參數都不同且文檔分散」所帶來的重複人工研究成本。**

### 7.2 這是真正存在的問題嗎？Vitamin or Painkiller？

**Painkiller — 但只對特定族群。**

對每週都在 PXE boot 不同 ISO 的人（lab technician, homelab heavy user, MSP）：這是 painkiller。每次新 ISO 都要 Google + trial-and-error kernel args = 真實痛苦。

對一年 PXE boot 一兩次的人：這是 vitamin。手動寫一次 iPXE entry 然後 copy-paste 就夠了。

**結論：** 產品值得存在，但 TAM (Total Addressable Market) 小。這不是問題 — 開源 infrastructure tool 不需要大 TAM。它需要的是：高痛感的小眾群體 + 極低的 adoption friction。

### 7.3 目前有哪些產品已經解決這個問題？它們真正缺少的是什麼？

| 產品 | 解決了什麼 | 缺少什麼 |
|------|-----------|----------|
| iVentoy | Drop ISO → PXE boot（最接近） | Closed-source；注入證書；不透明；不可審計 |
| netboot.xyz | 統一 boot menu，upstream fetch | 不處理本地 ISO；不做 extraction；需要手動寫 custom menu |
| OpenPXE | Drop ISO → auto detect → PXE boot | 極新；private repo；license 未知；bus factor=1 |
| MAAS | Full lifecycle provisioning | 太重；需要 PostgreSQL；不適合 homelab |
| Cobbler | PXE + kickstart automation | 過時；Python 2 遺留；配置複雜 |
| Foreman | Enterprise provisioning | Enterprise 級複雜度；需要 PostgreSQL + Redis |

**它們共同缺少的：**

一個 open-source、lightweight、community-maintained 的 **ISO → boot parameters** 映射層。

iVentoy 有這個能力但 closed-source 且不可信。netboot.xyz 有社區但不做本地 ISO。OpenPXE 最接近但生態不明。

**Gap 確認存在。**

### 7.4 如果今天沒有 NetBoot Catalog，使用者會如何完成工作？

```
1. 下載 ISO
2. Google "<distro name> PXE boot kernel parameters"
3. 找到 3-5 篇 blog posts / wiki pages（部分過期）
4. 試 mount ISO，自己找 kernel / initrd 路徑
5. 猜測 boot args（trial and error）
6. 手動寫 iPXE menu entry
7. 測試 boot（失敗 → 回到步驟 2）
8. 成功後 copy-paste 保留備用
9. 下次換新 ISO → 重複步驟 1-8
```

每個新 distro/version 大約花費 15-60 分鐘。如果是不常見的 distro（VyOS, Alpine, Arch）可能花數小時。

### 7.5 如果 NetBoot Catalog 成功，Workflow 將如何改變？

```
1. 下載 ISO
2. nbc import <iso>   (或 drop 到 watch folder)
3. 自動完成，可以 boot
```

步驟 2-8 被消除。每個新 ISO 的時間從 15-60 分鐘 → 30 秒。

### 7.6 真正不可替代的價值（Moat）是什麼？

**社區維護的 Adapter Library — 一份覆蓋主流 Linux distros 的、版本化的、經過驗證的 "ISO structure → boot parameters" 知識庫。**

這份知識庫：
- Machine-readable（不是 wiki text）
- Version-controlled（git tracked）
- Community-maintained（PR model）
- Continuously validated（CI with real ISOs）
- Portable（不綁定任何特定 PXE tool）

工具可以被重寫。Docker image 可以被替代。但一份準確的、持續維護的映射資料庫 — 需要年和社區 effort 累積。

**這才是 moat。Tool 是 delivery vehicle。Adapter library 是真正的 product。**

---

## 8. Domain Validation

### 8.1 真正的 Domain 是什麼？

**ISO Structure Normalization。**

不是 "NetBoot"。不是 "PXE"。不是 "Catalog Management"。

Core domain = 理解一個 Linux ISO 的內部結構，提取必要的 boot components，並產出正確的 boot parameters。

這是一個 **knowledge-intensive transformation** domain：

```
Input:  opaque ISO file (binary blob)
Output: structured boot recipe (kernel path + initrd path + rootfs path + boot args)
```

### 8.2 真正的 Domain Object 是什麼？

**Boot Recipe。**

不是 "Catalog Entry"。不是 "Asset"。不是 "Boot Profile"。

一個 Boot Recipe 包含：

```yaml
distro: ubuntu
version: "24.04"
arch: amd64
kernel: vmlinuz              # extracted file
initrd: initrd               # extracted file
rootfs: filesystem.squashfs  # extracted file
rootfs_type: squashfs
boot_args: "boot=casper netboot=url url={{rootfs_url}}"
variants:
  - name: safe_graphics
    boot_args: "boot=casper nomodeset netboot=url url={{rootfs_url}}"
```

這就是 domain object。其餘的（adapter、runtime、UI、API）都是 supporting infrastructure。

### 8.3 哪些只是 Implementation Detail？

| 被當作 Domain 的東西 | 實際是什麼 |
|---------------------|-----------|
| Catalog Engine | Implementation — 執行 transformation 的工具 |
| Runtime / Backend | Infrastructure — delivery mechanism |
| Adapter | Knowledge Encoding — domain knowledge 的載體 |
| YAML format | Serialization choice |
| REST API | Interface choice |
| Docker | Deployment choice |
| iPXE menu generation | Output formatting |

**唯一真正屬於 Domain 的：** Adapter 裡面的 knowledge（detection rules + extraction paths + boot args）。

### 8.4 目前 Product Boundary 是否正確？

**基本正確，但上界模糊。**

下界清晰：Boot 完成後不管。正確。

上界問題：
- ISO 從哪來？（使用者責任 — 需要明確寫出）
- 是否支援 URL import？（scope decision — 建議 v1 不做）
- 是否支援 ISO auto-update？（scope decision — 建議永遠不做）

**修正後的 boundary：**

```
Input boundary:  Local ISO file on filesystem
Output boundary: Boot assets served via HTTP + correct iPXE menu entry
```

### 8.5 目前是否存在錯誤的抽象？

**是。兩個：**

**錯誤抽象 1：Runtime as Domain Concept**

Runtime（dnsmasq + nginx + iPXE）被提升到與 Catalog Engine 同等地位。但它沒有 domain knowledge。它只是 "serve files via HTTP + generate iPXE config"。不值得獨立 module。

**錯誤抽象 2：Backend Interface / Runtime Interface**

將 "native vs netboot.xyz vs OpenPXE" 抽象為 interface，暗示它們有共同行為。實際上它們是完全不同的 deployment topology，不是可互換的 implementation。

正確的 model：output format（generate iPXE menu vs generate netboot.xyz custom menu）— 這是 template 差異，不是 interface 差異。

---

## 9. Architecture Validation

### 9.1 目前最大的五個 Architecture Risk

**Risk 1: Adapter Rot（最大風險）**

Linux distros 改 boot structure 時 adapter 會 break。沒有 automated test = 無法知道何時 broken。社區 contribute 後無人維護 = 半年後 stale。

**Risk 2: ProxyDHCP Compatibility（使用者痛苦）**

不是所有 network environment 都支援 proxyDHCP。Consumer router、managed switch、corporate firewall 可能 block 或 ignore。Debug 極難。使用者會認為是你的 bug。

**Risk 3: 部署複雜度 vs 預期的「簡單」**

Promise = "simple like iVentoy"。但 iVentoy 是 single binary + Web UI。你的方案 = Docker + dnsmasq + nginx + iPXE + process manager + Web UI。如果部署不是真正 one-command，promise 就 broken。

**Risk 4: ISO extraction 需要 privileged operations**

`mount -o loop` 需要 root 或 CAP_SYS_ADMIN。Docker container 需要 `--privileged` 或 `--cap-add`。這與 "simple deployment" 衝突。某些 container runtime（rootless Podman）直接不支援。

**Risk 5: Scope creep via community requests**

"Can I boot Windows?" "Can I add per-host config?" "Can I auto-download ISO?" 每個看起來合理的 feature request 都會推動 project 遠離核心。

### 9.2 哪些設計屬於 Premature Abstraction？

| 抽象 | 為什麼過早 |
|------|-----------|
| Runtime Interface | 你只有一個 runtime (native)；第二個未驗證過 |
| Backend switching in UI | 90% 使用者只會用一個 backend，永遠不切換 |
| Plugin Registry | 你的 "plugins" 就是幾個 YAML files |
| Worker Queue | Import 是 sequential IO task，不需要 queue |
| Boot Profile entity | 只是 boot_args string list |

### 9.3 哪些地方反而抽象不足？

| 缺失 | 為什麼需要 |
|------|-----------|
| Adapter Schema Versioning | 沒有 version = 無法 migrate |
| Output Format Templating | iPXE menu generation 應該是 template，不是 hardcoded |
| Extraction Validation | 目前沒有 "verify extraction result" 的 concept |
| Error Taxonomy | Import 失敗的原因有很多種（unsupported distro, corrupted ISO, missing files），需要結構化 error |
| Adapter Testing Contract | 沒有定義 "什麼算一個正確的 adapter" |

### 9.4 Dependency Direction

目前隱含的 dependency：

```
Web UI → API → Catalog Engine → Adapter Library
                     ↓
               File System (catalog storage)
                     ↓
              Output Generator → iPXE menu / netboot.xyz menu
                     ↓
              Runtime (dnsmasq + nginx) [optional, deployment concern]
```

**我建議的 dependency direction：**

```
┌─────────────────────────────────────────────────────┐
│  Adapter Library (YAML definitions)                 │  ← Core Knowledge (most stable)
│  - detection rules                                  │
│  - extraction paths                                 │
│  - boot args templates                              │
└──────────────────────┬──────────────────────────────┘
                       │ consumed by
                       ▼
┌─────────────────────────────────────────────────────┐
│  nbc (CLI tool)                                     │  ← Core Engine
│  - import: mount + detect + extract + validate      │
│  - generate: read catalog → render output template  │
│  - list / delete / export                           │
└──────────────────────┬──────────────────────────────┘
                       │ invoked by
                       ▼
┌─────────────────────────────────────────────────────┐
│  nbc-server (optional appliance)                    │  ← Deployment Packaging
│  - file watcher (inotifywait)                       │
│  - HTTP API                                         │
│  - Web UI                                           │
│  - dnsmasq + nginx (embedded runtime)               │
│  - process supervisor (s6-overlay)                  │
└─────────────────────────────────────────────────────┘
```

**Key insight：** Adapter Library 是最穩定的層（changes only when distros change）。CLI tool 是中間層。Server/UI 是最不穩定的層（UX 經常改）。Dependency 應該從不穩定指向穩定。

### 9.5 哪些 Component 應該刪除？

| 刪除 | 原因 |
|------|------|
| Runtime Manager | 不需要 — 用 process supervisor (s6) 代替 |
| Runtime Interface | 不需要 — output format template 代替 |
| Backend switching UI | 不需要 — deployment decision, not runtime decision |
| Plugin Registry | 不需要 — file system directory scan 代替 |
| Worker Queue | 不需要 — sequential process + status file 代替 |

### 9.6 哪些 Component 應該新增？

| 新增 | 原因 |
|------|------|
| Adapter Schema (versioned) | 讓 adapter format 可以 evolve |
| Adapter Validator | 驗證 YAML 是否 well-formed + complete |
| Output Template Engine | iPXE menu, netboot.xyz menu 都是 template rendering |
| Extraction Verifier | Extract 後檢查 files 是否存在且 valid |
| ISO Mount Abstraction | 處理 privileged mount vs bsdtar extraction（fallback） |

---

## 10. MVP Validation

假設：一位 Developer，六個月。

### 10.1 哪些功能必須保留？

| # | 功能 | 理由 |
|---|------|------|
| 1 | CLI import (mount + detect + extract) | 核心價值 |
| 2 | 3 個 adapter (Ubuntu, Debian, VyOS) | 最小可用 proof |
| 3 | iPXE menu generation | 最常見 output format |
| 4 | Dockerfile (native runtime) | One-command deployment |
| 5 | File watcher (auto-import) | iVentoy-like UX |

### 10.2 哪些功能必須刪除（from MVP）？

| # | 功能 | 理由 |
|---|------|------|
| 1 | Web UI | CLI + auto-import 已夠用；UI 開發成本高 |
| 2 | netboot.xyz integration | 等 native 穩定後再做 |
| 3 | REST API | 沒有 UI 就不需要 API |
| 4 | Backend switching | MVP 只有 native |
| 5 | ARM64 support | x86_64 first |

### 10.3 哪些決策應該延後？

| 決策 | 延後到何時 |
|------|-----------|
| UI framework 選擇 | 有 3+ 使用者要求時 |
| 第二個 output format | 有人實際要 netboot.xyz integration 時 |
| Adapter script escape hatch | 遇到 YAML 搞不定的 distro 時 |
| API authentication | 有人要求 remote access 時 |
| Multi-arch (同一 entry 多 arch) | 有人提 ISO 包含多 arch 時 |

---

## 11. Long-term Sustainability

### 11.1 真正最難維護的是什麼？

**Adapter Library 的持續準確性。**

每次 distro release 可能改 boot structure。你需要：
- 知道改了什麼（monitoring upstream releases）
- 更新 adapter YAML
- 驗證更新後仍然正確

這不是一次性工作。這是永久的 operational commitment。

### 11.2 最大的 Technical Debt 會是什麼？

**未經驗證的 adapters。**

情境：社區 contribute 了一個 Fedora adapter。PR 被 merge。三個月後 Fedora 40 release，改了 boot structure。沒有 CI 去 detect breakage。使用者 import Fedora 40 ISO → 失敗 → 開 issue → 你才知道壞了。

這會成為所有 open source adapter/plugin 系統的共同問題。唯一解法是 automated testing with real ISOs。

### 11.3 最大的 Community Risk 是什麼？

**Adapter contribution without ownership。**

Someone contributes adapter → merges → disappears → adapter rots → users blame project。

需要：
- Adapter ownership model（每個 adapter 有 maintainer）
- Staleness detection（6 months without test = marked "unverified"）
- Clear adapter lifecycle（active → unverified → deprecated → removed）

### 11.4 哪些地方需要自動化測試？

| 測試類型 | 覆蓋什麼 |
|---------|----------|
| Adapter validation test | YAML schema correctness |
| Integration test (per adapter) | Download ISO → import → verify extraction → verify boot args |
| Output generation test | Catalog entries → iPXE menu → validate syntax |
| Regression test | 確保新 adapter 不 break 舊的 |

**Integration test 是最重要也最難的。** 需要 CI 環境能 download + mount ISO。考慮用 mini ISO 或 mock ISO structure 做 unit test，real ISO 做 nightly integration。

### 11.5 哪些地方需要 Compatibility Matrix？

| Dimension | 例子 |
|-----------|------|
| Distro × Version × Adapter | Ubuntu 22.04 ✓, 24.04 ✓, 24.10 ? |
| Boot Mode × Firmware | UEFI ✓, Legacy BIOS ✓, Secure Boot ? |
| Network Environment | ProxyDHCP ✓, Full DHCP ?, VLAN ? |
| Container Runtime | Docker ✓, Podman ?, LXC ? |
| Host OS | Debian ✓, Ubuntu ✓, Alpine ? |

---

## 12. Redesign Challenge

完全忘記目前設計。從 first principles 重建。

### 核心 insight

問題的本質是：**知識缺失 + 重複勞動。**

使用者缺少的是一份「告訴我這個 ISO 怎麼 PXE boot」的 knowledge base。工具只是 apply 這份 knowledge 的方式。

### 最小有效設計

```
┌───────────────────────────────────────────┐
│  netboot-catalog/                         │
│                                           │
│  adapters/                                │
│    ubuntu.yaml                            │
│    debian.yaml                            │
│    vyos.yaml                              │
│    ...                                    │
│                                           │
│  nbc (single binary or shell script)      │
│    nbc import <iso>                       │
│    nbc generate                           │
│    nbc list                               │
│    nbc validate                           │
│                                           │
│  catalog/           (generated output)    │
│    ubuntu-2404/                           │
│      recipe.yaml                          │
│      vmlinuz                              │
│      initrd                               │
│      rootfs.squashfs                      │
│                                           │
│  output/            (generated config)    │
│    menu.ipxe                              │
│                                           │
│  Dockerfile         (optional appliance)  │
└───────────────────────────────────────────┘
```

**That's it.** 整個 project 可以是：

1. 一個 directory of YAML adapter files（knowledge base）
2. 一個 CLI tool（applies knowledge to ISOs）
3. 一個 Dockerfile（convenience packaging with dnsmasq + nginx）

不需要：
- Runtime Manager
- Backend Interface
- Plugin Registry
- Domain Events
- REST API (v1)
- Web UI (v1)
- Worker Queue

### 為什麼這就夠了

因為 90% 的使用者只需要：

```bash
# 部署
docker run -d --network host -v /my/isos:/import ghcr.io/xxx/netboot-catalog

# 使用
# 把 ISO 放入 /my/isos/ → 自動可以 PXE boot
```

Container 內部做的事：
1. `inotifywait` watch import folder
2. `nbc import` when new ISO detected
3. `nbc generate` produce iPXE menu
4. dnsmasq + nginx serve everything

**使用者不需要知道任何東西。** 不需要看 UI。不需要用 API。不需要理解 adapter。Drop ISO → boot。

UI 和 API 是 Phase 2 — 當有人真正需要「管理大量 entries」時才加。

---

## 13. Decision

### 13.1 是否批准開始開發？

**YES.**

理由：
- Problem 真實存在
- Gap 確認（no open-source tool does ISO normalization well）
- Scope 合理（不是另一個 Foreman）
- 一人可以在 6 個月內交付 MVP
- 失敗成本低（worst case = 一份有用的 adapter YAML library）

### 13.2 開始前必須修改的三件事

**1. 砍掉 Runtime Manager / Backend switching。**

MVP = native only。Container 裡跑 dnsmasq + nginx。沒有 switching，沒有 interface。如果使用者想 feed netboot.xyz，用 `nbc generate --format netbootxyz` 手動或 cron。

**2. 先交付 adapter library + CLI，再包裝 Docker。**

開發順序：adapters → CLI → Docker。不是反過來。因為 adapter library 獨立有價值（即使沒有 Docker appliance）。

**3. 定義 adapter testing strategy from day one。**

不是「以後再做 CI」。第一個 adapter 就要有 test。至少：
- 用 `mkisofs` 做一個 mock Ubuntu ISO structure
- `nbc import mock.iso` → verify output files exist
- `nbc generate` → verify iPXE syntax valid

不需要真實 4GB ISO。Mock structure 夠了。

---

## 14. Consensus Extraction

### Confirmed（可以立即定案）

| # | Decision |
|---|----------|
| 1 | Product 值得存在 — gap confirmed |
| 2 | Core value = adapter library (knowledge base) |
| 3 | Adapter 用 YAML declarative + script escape hatch |
| 4 | No database — file system is the database |
| 5 | Product boundary: local ISO → boot assets served via HTTP |
| 6 | Boot 後不管 — responsibility ends at boot |
| 7 | Domain object = Boot Recipe (not "Catalog Entry", not "Asset") |
| 8 | MVP = CLI + 3 adapters + Docker appliance (native only) |
| 9 | No Web UI in v1 |
| 10 | Adapter schema needs version field from day one |

### Controversial（合理分歧存在）

| # | Issue | Position A | Position B |
|---|-------|-----------|-----------|
| 1 | Engine language | Shell（人人識改） | Go（better HTTP + process management） |
| 2 | ISO mount method | `mount -o loop`（needs privileges） | `bsdtar` extraction（no mount needed） |
| 3 | Runtime bundling | 包含 dnsmasq + nginx in Docker | 獨立 — 使用者自己跑 PXE |
| 4 | Backend switching | 永遠只做 native | Future: UI toggle |
| 5 | Naming | "NetBoot Catalog" | 其他名（nbc 太 generic） |

### Requires Prototype

| # | Question | Prototype Method |
|---|----------|-----------------|
| 1 | YAML adapter 能否覆蓋 top 10 distros? | 寫 10 個 adapter YAML → 手動驗證 |
| 2 | `bsdtar` 能否取代 `mount` for extraction? | 測試 5 個 ISO → 比較結果 |
| 3 | ProxyDHCP 在 common homelab routers 的 success rate? | 測試 3 種 router (UniFi, pfSense, consumer) |
| 4 | Docker --privileged 是否可以避免? | 嘗試 `bsdtar` + `--cap-add` 組合 |

### Requires User Validation

| # | Assumption | Validation Method |
|---|-----------|-------------------|
| 1 | 使用者接受 CLI-only MVP (no Web UI) | Reddit/Discord poll in r/homelab |
| 2 | 使用者願意只用 Docker 部署 | 同上 |
| 3 | 3 個 adapter (Ubuntu, Debian, VyOS) 夠 MVP | 問 target users 他們最常 PXE boot 什麼 |
| 4 | "Drop ISO → auto boot" 的 UX 足夠 | 找 3 個 beta tester 觀察 |

---

## 15. Final Challenge

> 如果目標不是設計 NetBoot Catalog，而是讓它根本不需要存在，會怎樣解決同一個問題？

### Alternative A：擴充 netboot.xyz

為 netboot.xyz 加一個 "local ISO import" plugin。

```
成本：Medium（需要理解 netboot.xyz codebase，寫 Ansible role）
複雜度：Medium（受制於 netboot.xyz 的 architecture decisions）
可維護性：High（由 netboot.xyz maintainers 維護）
長期價值：High — 如果 merge 進主線，所有使用者受惠
```

**問題：** netboot.xyz maintainers 可能不接受（scope 不符合他們的 vision — 他們 focus 在 upstream fetching 而非 local ISO）。而且你無法控制 merge timeline。

### Alternative B：為 iPXE 建立 community adapter registry

不做任何 tool。只維護一個 Git repo：

```
ipxe-adapters/
  ubuntu/
    24.04.yaml
    22.04.yaml
  debian/
    12.yaml
  vyos/
    rolling.yaml
```

使用者自己用 `yq` + shell 去 apply。

```
成本：Very Low
複雜度：Minimal
可維護性：High（just YAML files in a repo）
長期價值：Medium — 有用但 friction 高（使用者要自己寫 extraction logic）
```

**問題：** 沒有 automation = friction 高。大部分使用者不會用。但作為 data source 獨立有價值。

### Alternative C：Contribute adapters to OpenPXE

如果 OpenPXE 真正成為 open source：contribute adapter definitions 進去。

```
成本：Low（只需要寫 adapter config）
複雜度：Low（利用現有 platform）
可維護性：Depends on OpenPXE project health
長期價值：High if OpenPXE survives, zero if it dies
```

**問題：** 依賴第三方 project（bus factor = 1, license unknown）。不可控。

### Alternative D：NetBoot Catalog as proposed

```
成本：Medium-High（6 months one person）
複雜度：Medium
可維護性：Medium（adapter maintenance is ongoing）
長期價值：Highest — own the knowledge base + tool + community
```

### 比較

| | A (extend netboot.xyz) | B (YAML repo only) | C (feed OpenPXE) | D (NetBoot Catalog) |
|---|---|---|---|---|
| 控制權 | Low | High | Low | High |
| 成本 | Medium | Low | Low | Medium-High |
| Adoption friction | Low (existing users) | High | Low | Medium |
| Long-term value | Medium | Medium | Risky | High |
| Community building | Piggyback | Hard | Piggyback | Own |

### 結論

**Alternative B (YAML repo) 是你的 Phase 0。**

即使你決定不做 CLI tool 或 Docker appliance，一份 community-maintained adapter YAML library 獨立有價值。

**Alternative D (full NetBoot Catalog) 是 justified** — 因為 automation layer 的 value add 顯著降低 friction。但前提是先確保 adapter library 質量高。

**實際建議：從 B 開始（pure YAML repo），加上 minimal CLI tool (Phase 1)，最後才包裝 Docker (Phase 2)。** 這樣即使 project 只走到 Phase 1 就停了，社區仍然有一份有用的 adapter knowledge base。

---

*Review complete. Document prepared for cross-AI debate.*
