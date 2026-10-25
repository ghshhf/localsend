# LocalSend Fork 整体代码审查（2026-10-26）

> 审查对象：`D:/code/localsend`，HEAD `002e896`，`main` 单分支，与 origin 零差异，工作区干净。
> 上一轮审查：`docs/CODE_REVIEW-PRP-2026-09-22.md`（P0-1/2/3/4/5、P1-6/7/8/10 声称已修）。
> 本轮方法：不重读上游代码，聚焦 fork 自有面（PRP + 中继 + 原生插件 + 服务端路由 + Manifest）。
> 本机无 flutter/dart 工具链，**未在本机复现 `flutter analyze` / `flutter test`**，编译与测试结论一律引 CI，不由本报告背书。

---

## 一、盘点

### 1.1 仓库事实

| 项 | 值 |
|---|---|
| HEAD | `002e896` feat(prp): 远程中继桥接 |
| 提交总数 | **4**（`git rev-list --count HEAD`）→ 历史是重建的，无法 blame 追责 |
| 手写 Dart | 42,804 行（排除 `app/lib/gen/` 与 `frb_generated*`） |
| Rust | 25,660 行（含 `frb_generated`） |
| Rust 服务端 | axum，**仅一条路由** `/v1/ws`（`server/src/main.rs:31-32`） |
| CI | 4 job：format / test / rust / packaging；含 `flutter analyze` + `flutter test` |

### 1.2 fork 自有面清单（本次实际覆盖）

| 文件 | 行数 | 说明 |
|---|---|---|
| `app/lib/provider/network/prp_provider.dart` | 434 | PRP 状态机 + 8 个 Action |
| `app/lib/util/transport/transport_interface.dart` | 181 | 传输抽象 + `invokeChannel` 超时包装 |
| `app/lib/util/transport/transport_manager.dart` | 231 | 传输调度 |
| `app/lib/util/transport/wifi_hotspot_transport.dart` | 256 | WiFi 热点 Dart 侧 |
| `app/lib/util/transport/usb_tethering_transport.dart` | 260 | USB 共享 Dart 侧 |
| `app/lib/util/transport/local_network_transport.dart` | 81 | stub |
| `app/lib/pages/tabs/hotspot_relay_page.dart` | 650 | PRP UI |
| `HotspotRelayPlugin.kt` | 573 | WiFi 热点原生侧 |
| `UsbTetheringPlugin.kt` | — | USB 原生侧 |
| `MainActivity.kt` | — | 插件生命周期 |
| `AndroidManifest.xml` | — | 权限面 |

### 1.3 上一轮 P0/P1 的复核结果（逐条核过代码，不是看文档）

| 旧项 | 结论 | 证据 |
|---|---|---|
| P0-1 init 死代码 | ✅ 已修 | `prp_provider.dart:141-156` 真写回 state |
| P0-2 EventChannel | ✅ 已修 | `_ensureNativeEvents()` 双端都有 |
| P0-3 result 丢失 | ⚠️ 部分 | 有 BUSY 守卫，但双 reply 风险仍在（见 P1-9） |
| P0-4 状态机破洞 | ✅ 部分修 | 失败回 idle ✅；`transferring` 已删 ✅；但清字段失效（见 P1-6） |
| P0-5 切换用 stop | ✅ 已修 | `_teardown()` 同时 stop+disconnect |
| P1-6 超时包装 | ✅ 已修 | `invokeChannel` 45s |
| P1-7 dispose 后写流 | ✅ 已修 | `_disposed` 守卫 |
| P1-8 MainActivity 清理 | ✅ 已修 | `cleanUpFlutterEngine` 调两个 dispose |
| P1-10 UI 响应式 | ✅ 已修 | `availableTransports` 入 state |
| P2-12 stub 进列表 | ✅ 已修 | `isAvailable => false` |

**判断**：9-22 那轮是真修了，不是文档注水。

---

## 二、缺口

### P0 — 阻断性

**P0-1 远程中继没有服务端实现**
`prp_provider.dart:371` POST `$relayUrl/api/prp/register`、`:386` POST `$relayUrl/api/prp/message`。
`grep -rn "prp" server/src` — **零命中**。仓库唯一服务端只有 `/v1/ws`（`server/src/main.rs:31-32`），是 signaling server，与中继协议无关。
无协议文档、无 mock、无集成测试。→ 该链路在任何环境下都不可能成功。

**P0-2 `ConnectToRelayAction` 全仓零调用**
`grep -rn "ConnectToRelayAction" app/lib` 只命中定义处（`:350`）。
UI 无入口：`hotspot_relay_page.dart` 全文无 relay 按钮，`settings_tab.dart:525-530` 只推 `PrpPage`。
测试无覆盖：`prp_provider_test.dart` 11 条全是 state/enum/copyWith，无一条触达 Action 行为。
`PrpState` 的 `relayUrl/relayDeviceId/relayInstruction/relayLastEcho` 四个字段（`:56-65`）同样无任何 UI 消费。
→ 最新提交的 120 行是死代码。

**P0-3 断开 PRP 后整个进程挂死在无网热点上**
`HotspotRelayPlugin.kt:348` `cm.bindProcessToNetwork(network)` 把进程绑定到无 internet 的热点网络。
`disconnectWifi`（`:409-421`）与 `stopHotspot`（`:238-260`）**都没有** `bindProcessToNetwork(null)`。
→ 后果：用户断开 PRP 后，LocalSend 自身的 HTTP 收发、版本检查全部走一条死路，直到进程重启。
这条不是 PRP 内部问题，它会污染主功能，优先级高于其他所有项。

### P1 — 健壮性

**P1-4 `_relayPost` 无超时、无重试**
`prp_provider.dart:401-423`：`HttpClient()` 未设 `connectionTimeout`，`postUrl` / `close` 均无 `.timeout()`。
公网不可达时 UI 停在 connecting 直到系统默认超时（可达数分钟）。
ROADMAP P01（失败自动回退）/ P02（指数退避 3 次）：`grep -rn "retry|backoff|exponential"` 在 PRP 全部代码中**零命中**。

**P1-5 中继走明文且不校验 scheme**
同函数用 `Uri.parse(url)`，接受 `http://`，无白名单。上报的 `self_check` 含 mode / transport / 可用传输列表 / device_id（`:361-367`）。

**P1-6 `copyWith` 传 null 清不掉字段（同一文件两套语义）**
`copyWith` 语义是 `x ?? this.x`（`:106-108`），传 null = 不改。
但 `StopHostAction`（`:225-227`）与 `DisconnectPeerAction`（`:292-294`）都传 `null` 期望清空 networkName/networkPassword/ipAddress。
`:112-113` 的注释自己写明「传 null 表示不改」——作者知道这个坑，但同一文件里两处照样踩。
→ 停止主机后旧 SSID / 密码仍留在 state，UI 继续展示。

**P1-7 中继连接成功不置 mode**
`ConnectToRelayAction` 成功分支（`:391-398`）只改 `state`，`mode` 保持 idle。
而 `PrpState.isActive => mode != PrpMode.idle`（`:83`）。→ 连上中继后 `isActive` 仍为 false。

**P1-8 `start()` 忽略 `isRunning`**
`wifi_hotspot_transport.dart:79` 读出 `isRunning` 后**从未使用**；`:77-90` 只要拿到非 null map 就 `_setState(connected)` + `return true`。
原生返回 `isRunning:false` 时 Dart 侧假成功。

**P1-9 原生 result 可能 reply 两次 → IllegalStateException**
`HotspotRelayPlugin.kt:173-221`：`onStarted` / `onStopped` / `onFailed` 三个回调各自 `pendingStartResult = null`，但**用的都是闭包捕获的 `result`**。
若 `onFailed` 先到把 `pendingStartResult` 置 null 并 reply，随后 `onStarted` 又触发，第二次 `result.success()` 抛 "Reply already submitted" → 崩溃。
正确写法：`pendingStartResult?.let { pendingStartResult = null; it.success(info) }`。

**P1-10 `requestNetwork` 无超时，callback 会累积**
`HotspotRelayPlugin.kt:363` `cm.requestNetwork(request, callback)` 没有 timeout 参数。
失败路径只靠 Dart 侧 45s channel 超时兜底；悬挂的 callback 不释放，Android 每 app 上限约 100 个，反复重试后 `requestNetwork` 直接抛异常。

**P1-11 `TransportManager.init()` 的 6 个 listen 不保存 subscription**
`transport_manager.dart:59, 62, 69, 72, 79, 82`。`dispose()`（`:221-230`）只关 controller，不 cancel 源订阅。
`_initialized` 在 dispose 后置 false（`:229`），再 init 会**重复订阅** → 事件重复 + 泄漏。

**P1-12 `PrpService` 不覆写 dispose**
`_transportManager` 是 final 字段（`:133`），`TransportManager.dispose()` 全仓**无调用者**。传输层资源只能靠进程回收。

**P1-13 UI 无 pending 守卫**
`hotspot_relay_page.dart:163-171` 的 Start host 按钮在 connecting 态仍可点；`_buildActionButton`（`:629-649`）没有 disabled 逻辑。
原生有 BUSY 守卫，但第二次 dispatch 会把 Dart 状态打成 error，即使第一次其实成功了。

**P1-14 `_setError` 不清 `_transportInfo`**
`wifi_hotspot_transport.dart:249-255`、`usb_tethering_transport.dart:253-259`：失败后残留上一次的连接信息，`activeInfo` 会返回过期数据。

### P2 — 打磨

| # | 项 | 位置 |
|---|---|---|
| 15 | `startHotspotAndroid13` 纯转发到 `startLocalOnlyHotspot`，无 13+ 专属逻辑，`@RequiresApi(TIRAMISU)` 有误导 | `HotspotRelayPlugin.kt:228-233` |
| 16 | `wifi_state` 广播在 Android 10+ 需平台签名，普通 app 收不到，该监听实际无效 | `HotspotRelayPlugin.kt:508-533` |
| 17 | `disconnectWifi` 双重 unregister（`_unregister` 已把 callback 置 null），死代码 | `HotspotRelayPlugin.kt:411` vs `:415-418` |
| 18 | stub 的 `isAvailable` 每次打 warning，而 `availableTransports` getter 每次调用都遍历 → 日志噪音 | `local_network_transport.dart:37-40` |
| 19 | CI format job `rm -rf lib/gen` 但 gen 已入库，test job 不删 —— 生成物入库且处理不一致 | `.github/workflows/ci.yml` + `app/lib/gen/` |
| 20 | ROADMAP 10 月里程碑是「蓝牙发现」，代码全在 PRP 中继上 | `ROADMAP.md` |

### 安全面单列

| 项 | 判断 |
|---|---|
| TLS 证书体系 | 标准做法，未见削弱：自签证书 + fingerprint pinning（`packages/core/src/crypto/cert.rs`），`with_custom_certificate_verifier` 用于校验对端自签证书（`http/client/mod.rs:214`），不是关闭校验。**无问题** |
| `app/lib` 明文 HTTP | 零命中（除 `_relayPost` 的动态 URL） |
| `REQUEST_INSTALL_PACKAGES` | 真实使用于 `app/lib/util/native/open_file.dart:17`，为打开 APK 请求安装权限，属上游既有行为。**但 Google Play 会以此拒审**，若要走商店需按政策移除 |
| `QUERY_ALL_PACKAGES` | 同属上游既有，Play 需声明用途 |
| MethodChannel 校验 | 无，但为 app 进程内通道，不构成外部攻击面 |

---

## 三、结论

### 3.1 整体判断

PRP 骨架的质量在线：接口抽象、状态机设计、条件导入、channel 超时包装、原生→Dart 事件回传都在，9-22 那轮 P0/P1 逐条核实是真修。

问题集中在新的一公里：远程中继那 120 行，是照着**一个仓库里不存在的服务**写的协议客户端，而且没有任何入口、没有测试、状态字段没有消费者。它不是「待完成」，是「孤岛」。

真正需要立刻处理的反而不是中继，而是 P0-3：`bindProcessToNetwork` 不解绑，断 PRP 会连坐主功能。这是唯一一条会伤害非 PRP 用户的缺陷。

### 3.2 优先级

| 序 | 项 | 理由 | 成本 |
|---|---|---|---|
| 1 | P0-3 解绑进程网络 | 唯一污染主功能的缺陷 | ~5 行 |
| 2 | P0-1/P0-2 二选一：落地服务端端点，或撤掉 120 行 | 死代码留着的成本是持续的认知负担 | 撤除 5 分钟 / 落地以天计 |
| 3 | P1-6 `copyWith` 清字段 | 用户能直接看到错误 SSID | ~10 行 |
| 4 | P1-13 + P1-8 假成功与连点 | 一起修，都是「明明失败但显示成功」 | ~20 行 |
| 5 | P1-4 超时 + 退避 | ROADMAP P01/P02 的欠账 | ~40 行 |
| 6 | P1-9 / P1-10 / P1-11 / P1-12 | 崩溃与泄漏面 | ~30 行 |

### 3.3 本报告不能下的结论

- **代码能否编译 / 测试是否通过**：本机 `which flutter`、`which dart` 均为空，未复现。只能引 CI 结论，不由本报告背书。
- **P0-1 的外部中继服务是否真实存在**：仓库内无凭据。若确实有一台公网服务提供 `/api/prp/register`，则 P0-1 降级为「协议未入库 + 无契约测试」，P0-2（无入口）仍然成立。
- **`UsbTetheringPlugin.kt` 未逐行读**（本轮只覆盖其 Dart 侧与事件通道约定），USB 原生实现存在未审风险。

---

## 四、修复记录（2026-10-26 同日）

改动未提交 git。7 个文件，+316 / −80。

### 已修 12 项

| # | 原缺口 | 改了什么 | 位置 |
|---|---|---|---|
| 1 | P0-3 断 PRP 连坐主功能 | 新增 `unbindProcessNetwork()`（`bindProcessToNetwork(null)`，API 23+ 护栏），在 `stopHotspot` / `disconnectWifi` / `onLost` / `dispose` 四处调用 | `HotspotRelayPlugin.kt` |
| 2 | P1-9 原生 result 双 reply | 三个回调统一 `val pending = pendingStartResult; pendingStartResult = null; pending?.xxx()`；取不到 pending 时（start 已被放弃）直接 close 孤立 reservation，不留后台热点 | `HotspotRelayPlugin.kt` `onStarted/onStopped/onFailed` |
| 3 | P1-9 同类（client 侧） | `connectToWifiAndroid10` 的 callback 加 `replied` 幂等守卫 + `replyOnce` | `HotspotRelayPlugin.kt` |
| 4 | P1-10 `requestNetwork` 无超时 | API 26+ 传 `REQUEST_NETWORK_TIMEOUT_MS = 30_000` | `HotspotRelayPlugin.kt` |
| 5 | 附带的真 bug | `onLost` 原本只打日志；改为解绑进程网络 + `notifyEvent("hotspotStopped")` | `HotspotRelayPlugin.kt` |
| 6 | 附带的真 bug | `setWpa2Passphrase` 对空/超长密码抛异常 → 前置校验，空密码走 `setIsEnhancedOpen(true)`，非法长度返回 `INVALID_PASSWORD` | `HotspotRelayPlugin.kt` `connectToWifiAndroid10` |
| 7 | P2-15 死分层 | 删除纯转发的 `startHotspotAndroid13`，`startLocalOnlyHotspot` 去掉未使用的 `result` 参数 | `HotspotRelayPlugin.kt` |
| 8 | P2-17 死代码 | 删掉 `disconnectWifi` 里第二次 unregister（前一行已置 null） | `HotspotRelayPlugin.kt` |
| 9 | P1-6 `copyWith` 清不掉字段 | 新增 `clearNetwork` 开关，与 `clearError`/`clearRelay` 同构；`StopHostAction`、`DisconnectPeerAction` 改用它 | `prp_provider.dart:99-119, 240, 306` |
| 10 | P1-4 中继无超时 | `connectionTimeout` + `postUrl`/`close`/`join` 三处 `.timeout(10s)`，`on TimeoutException` 单独记日志 | `prp_provider.dart:427-465` |
| 11 | P1-5 中继不校验 scheme | `Uri.tryParse` + 仅放行 http/https，http 走明文时打警告 | `prp_provider.dart:434-441` |
| 12 | P1-7 中继成功不置 mode | 成功分支补 `mode: PrpMode.client`；`DisconnectRelayAction` 补 `mode: PrpMode.idle` | `prp_provider.dart:415, 475` |
| 13 | 附带 | `device_id` 为空直接报错，不再拿空 id 继续发消息 | `prp_provider.dart:397-405` |
| 14 | P1-8 假成功 | `start()` 检查 `isRunning`，false 时 `_setError` 并返回 false | `wifi_hotspot_transport.dart:79-87` |
| 15 | P1-14 错误残留连接信息 | `_setError` 里清 `_transportInfo` | `wifi_/usb_tethering_transport.dart` |
| 16 | P1-11 subscription 泄漏 | `_subscriptions` 保存 6 个 listen，`dispose` 里先 cancel 再关 controller；`_disposed` 防重复 dispose | `transport_manager.dart:25-31, 62-107, 238-258` |
| 17 | P1-12 传输层从不 dispose | `PrpService` 覆写 `dispose()`，`catchError` 兜住异步异常（否则无 binding 单测会红） | `prp_provider.dart:169-182` |
| 18 | P1-13 UI 无 pending 守卫 | starting 态禁用 Start host 按钮 | `hotspot_relay_page.dart:129-132, 172` |
| 19 | 测试空白 | 新增 3 条回归测试：`clearNetwork` 能清、不清时保持、`clearRelay` 能清 | `prp_provider_test.dart:50-101` |
| 20 | P0-1 中继服务端不存在 | 在 `server` 侧补齐两个端点 + 5 条测试（见 4.1） | `prp_controller.rs`（新）、`state.rs`、`main.rs` |
| 21 | P0-2 `ConnectToRelayAction` 无入口 | 客户端标签页新增「公共中继」卡片：地址输入 + 连接/断开 + 显示 device_id/指令/回声 | `hotspot_relay_page.dart:412-505` |
| 22 | 会话句柄回传失败仍报 connected | `msg == null \|\| ok != true` 时进 error，不再假成功 | `prp_provider.dart:412-420` |

### 4.1 中继协议（实现后即契约）

| 端点 | 请求 | 响应 |
|---|---|---|
| `POST /api/prp/register` | `{alias, self_check}` | `{ok, device_id, instruction, lease_secs}` |
| `POST /api/prp/message` | `{device_id, content}` | `{ok, relay_says, messages}` |

约束（都写在 `prp_controller.rs` 顶部常量里）：

- 设备上限 **2048**，超了答 503（公网无鉴权端点，不能无限增长）
- 租约 **600s**，无流量即回收；回收走注册请求里的 `retain`，不另起后台任务
- 单次负载上限 **8 KiB**；alias 截断到 **64** 字符，空则回落 `LocalSend`
- `device_id` 必须是合法 UUID，否则 400；未注册/已过期答 404

relay 只做 rendezvous：不排队、不主动连接、不解释 `self_check` 内容，只存最新一份。

### 未修，及原因

| 项 | 原因 |
|---|---|
| P1-4 的退避重试 | 需要重试策略参数（次数/间隔/可取消）。当前是「单次 10s 超时 + 明确报错」，比凭空写一套退避更可控 |
| P2-16 `wifi_state` 广播失效 | 需换 API（`WifiManager.isWifiApEnabled` 反射在 28+ 也被封），属重写 |
| P2-18 stub 日志噪音 | 改 `availableTransports` 缓存策略会牵动 UI 响应式，收益低 |
| P2-19 gen 入库 | 涉及 CI 与仓库结构，单独处理 |

### 本轮验证边界（必须如实标注）

本机无 `flutter` / `dart`，**未跑 `flutter analyze` / `flutter test` / `dart format`**。已做的静态核对只有三项：

1. **括号计数**：7 个文件 `{}`/`()`/`[]` 净差均与 HEAD 一致（`prp_provider.dart` 的 `()` 净差 −3 在 HEAD 上同样存在，属原有，非本轮引入）。
2. **行宽**：新增行长全部 ≤ 150 —— 阈值取自 `app/analysis_options.yaml` 的 `formatter.page_width: 150`，不是默认 80。多行调用均带尾逗号，配合 `trailing_commas: preserve` 不会被格式化器压回单行。
3. **残留引用**：`startHotspotAndroid13`、`networkName: null` 等旧写法全仓零命中。

**真正的编译与测试结论仍需 CI 给出。** 本轮改动没有触及上游代码路径，风险集中在 `HotspotRelayPlugin.kt` 的 API level 分支、`PrpService.dispose()` 的单元测试副作用，以及新增的 `prp_controller.rs`（CI 的 `cargo test --package server` 会跑它自带的 5 条测试）。

> 本机尝试过装 Flutter 3.41.9 做本地验证（`git clone --depth 1 --branch 3.41.9`），2 分 46 秒只拉到 13MB，判定不可行后放弃并删除临时目录。因此「本机能编」这句话在这台机器上无法成立，验证权交给 CI —— 这也解释了为什么本轮先提交推送再改：CI 的四个 job（format / test / rust / packaging）就是验收。
