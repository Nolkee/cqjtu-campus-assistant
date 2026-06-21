# 校园助手重构进度

> 来源：`G:\app\target.md`
> 最后更新：2026-06-20

---

## 总体状态

| 阶段 | 名称 | 状态 | 备注 |
|------|------|------|------|
| 0 | 冻结目标 | ✅ 完成 | target.md 已保存 |
| 1 | 数据源抽象 | ✅ 完成 | CampusGateway + 三种实现 + RuntimeMode |
| 2 | Provider 拆分 | ✅ 完成 | 全部 feature provider 已拆分 |
| 3 | API 契约整理 | ✅ 完成 | API.md 文档、统一错误码 |
| 4 | 课表本地直连 | ✅ 完成 | DirectSchoolCampusGateway 已实现 |
| 5 | 自部署后端产品化基础 | ✅ 完成 | Docker、配置模板、health、部署文档 |
| 6 | 成绩/考试本地直连 | ✅ 完成 | DirectSchoolCampusGateway 已实现 |
| 7 | Web Console 核心查询 | ✅ 完成 | Thymeleaf 页面 + Controller |
| 8 | 电费/校园卡本地直连 | ✅ 完成 | DirectSchoolCampusGateway 已实现 |
| 9 | Android 后台强化 | ✅ 完成 | 已有完整 Kotlin 小组件/通知代码 |
| 10 | Web Console 完整查询 | ✅ 完成 | 电费/校园卡页面已包含 |
| 11 | 请假和 token 刷新 | ⚠️ 部分完成 | 依赖真实学校账号验证 |
| 12 | 发布和文档闭环 | ✅ 完成 | DEPLOY.md、API.md、使用文档 |

---

## 2026-06-20 Codex 审计记录

本轮按照 `target.md` 的安全和验收要求继续推进，没有把“阶段性通过”视为整个重构最终完成。

已完成修正：

- 移除 `packages/data/test/direct_gateway_e2e_test.dart` 中硬编码的真实测试账号和密码。
- 将直连网关真实环境冒烟脚本移到 `packages/data/tool/direct_gateway_e2e.dart`，并改为通过 `CAMPUS_TEST_USERNAME` / `CAMPUS_TEST_PASSWORD` 环境变量显式运行。
- 移除 `DirectSchoolCampusGateway` 中会打印完整 cookie 和 401 响应 body 的调试输出。
- 将 Android `CookieChannel` 原生日志改为只输出 cookie 字符串长度，不输出 cookie 明文。
- 修复 `_followRedirects` 中 401 分支返回 `_HttpResponse` 的潜在类型错误。
- 清理 `packages/data/test/test_encrypt.dart` 中未使用 import。
- 清理 `G:\schedule` 中残留的真实测试账号/密码：`TestEncrypt.java` 改用非敏感测试密码，`schedule_test.html` 改用占位学号。

本轮验证结果：

| 命令 | 结果 |
|------|------|
| `dart analyze .` | ✅ No issues found |
| `flutter test` (`apps/campus_app`) | ✅ 1 passed |
| `flutter test` (`packages/core`) | ✅ 30 passed |
| `flutter test` (`packages/platform`) | ✅ 10 passed |
| `mvnw.cmd test` (`G:\schedule`) | ✅ Tests run: 2, Failures: 0, Errors: 0, BUILD SUCCESS |
| 敏感信息搜索 | ✅ `G:\app` 与 `G:\schedule` 均未发现真实测试账号/密码；未发现 cookie 明文日志模式 |

未在本轮复跑：

- 真实学校系统 e2e：需要人工显式设置环境变量并承担真实网络/验证码/账号状态影响，不允许把凭据写入仓库。

手动真实环境冒烟命令：

```powershell
$env:CAMPUS_TEST_USERNAME='<学号>'
$env:CAMPUS_TEST_PASSWORD='<密码>'
cd G:\app\packages\data
dart run tool/direct_gateway_e2e.dart
```

---

## 2026-06-20 Codex 继续推进记录

本轮继续按照 `target.md` 的双产品形态目标推进，重点修正“默认 Android 本地直连”和“敏感日志脱敏”两类会影响最终验收的缺口。

已完成修正：

- 将 `AppConfig.env` 默认值从 `mock` 调整为 `localAndroid`，确保普通用户默认不需要服务器地址。
- 将 `campusRuntimeModeProvider` 改为显式解析运行模式：`mock/demo` 进入 Mock，`selfHosted/remoteBackend/backend` 进入自部署后端，其余默认 `localAndroid`。
- 新增 `runtime_mode_provider_test.dart`，固定默认模式和各类别名解析行为，避免后续回退。
- 将 `LoginPage` 登录流程按运行模式拆分：`localAndroid/mock` 通过 `CampusGateway` 验证课表可用性，只有 `selfHosted` 才创建后端 session。
- 为 `DirectSchoolCampusGateway` 增加本地 `loginWithTicket` 绑定能力，使 WebView 获取的 CAS ticket 可以绑定到本地直连会话，而不是强制绕回 self-hosted 后端。
- 修正 Dart 直连网关 URL 日志脱敏参数，补上 `sessionid`、`username` 等 query key。
- App 侧 `ApiService`、`SessionManager`、后台任务日志不再输出原始学号；Session 恢复快照写入前会清洗 password/ticket/token/sessionId/cookie 等敏感字段。
- App 侧 `CredentialService`、`SelfHostedSessionManager`、`SelfHostedCampusGateway` 的历史调试日志也已改为脱敏学号或错误类型，不再打印原始学号。
- 后端 `LoginService` 增加统一日志脱敏工具，覆盖 username、sessionId/contextKey、ticket/token 类字段。
- 后端 `AuthController`、`WebConsoleController`、`ScheduleController`、`ElectricityController`、`ElectricityService` 日志切换到统一脱敏方法。
- 新增 `LoginServiceRedactionTests`，固定后端脱敏函数行为。

本轮验证结果：

| 命令 | 结果 |
|------|------|
| `dart analyze .` | ✅ No issues found |
| `flutter test` (`apps/campus_app`) | ✅ 5 passed |
| `flutter test` (`packages/core`) | ✅ 30 passed |
| `flutter test` (`packages/platform`) | ✅ 10 passed |
| `mvnw.cmd test` (`G:\schedule`) | ✅ Tests run: 5, Failures: 0, Errors: 0, Skipped: 0, BUILD SUCCESS |
| 根目录 `flutter test` | ⚠️ 根 monorepo 包没有 `test/` 目录，命令返回 `Test directory "test" not found`；实际 Flutter 测试入口为各子包 |
| 真实学校系统 e2e | ⚠️ 未执行，当前 shell 中 `CAMPUS_TEST_USERNAME` / `CAMPUS_TEST_PASSWORD` 未预置；未将真实账号密码写入命令或仓库 |
| 敏感信息搜索 | ✅ 未发现真实测试账号/密码；未发现已知 cookie 明文日志模式；剩余 `$username` 命中仅为本地存储 key 或内部 map key，不是日志输出 |

当前仍不能宣布整个 `target.md` 最终完成的原因：

1. 真实学校系统直连 e2e 本轮未跑通，缺少对 CAS 登录、课表、成绩、考试真实路径的当前证据。
2. Android 真机“未启动 `G:\schedule` 时可完成核心功能”仍需要设备级验收。
3. Web Console 虽通过后端测试编译与上下文加载，但仍需要真实部署后的浏览器闭环验收。

---

## 任务队列

### 1. 数据源抽象层（阶段 1）— ✅ 已完成

- [x] `CampusRuntimeMode` 枚举（localAndroid / selfHosted / mock）
- [x] `CampusGateway` 抽象接口
- [x] `CampusFailure` 密封异常类
- [x] `SelfHostedCampusGateway` 实现
- [x] `SelfHostedSessionManager` + `SelfHostedSessionStore`
- [x] `MockCampusGateway` 实现
- [x] `DirectSchoolCampusGateway` 完整实现（非占位）
- [x] `data.dart` 导出新抽象
- [x] `adapters_mock` 导出 MockCampusGateway
- [x] `SessionService implements SelfHostedSessionStore`

### 2. Provider 拆分（阶段 2）— ✅ 已完成

- [x] `providers/runtime_mode.dart` — apiServiceProvider, campusRuntimeModeProvider, campusGatewayProvider, campusBackendProvider
- [x] `providers/session.dart` — SystemDomain, RecoverySnapshot, SessionManager, RecoveryHealthNotifier
- [x] `providers/shared.dart` — sessionUpdateProvider, campusCardQrScrollSignalProvider
- [x] `features/auth/auth_providers.dart` — CredentialsNotifier
- [x] `features/schedule/schedule_providers.dart` — scheduleProvider, semester providers, custom courses
- [x] `features/electricity/electricity_providers.dart` — electricityProvider
- [x] `features/campus_card/campus_card_providers.dart` — campusCardBalanceProvider, payCodeProvider
- [x] `features/grades/grades_providers.dart` — gradesProvider
- [x] `features/exams/exams_providers.dart` — examsProvider
- [x] `features/settings/settings_providers.dart` — dormRoomProvider
- [x] `utils/providers.dart` 改为纯 barrel export 文件
- [x] 消除循环依赖
- [x] 纯函数移出到 `packages/core/`：
  - [x] 考试时间解析 (`parseExamTime`, `weekOfDate`) → `core/lib/utils/exam_time_utils.dart`
  - [x] 节次时间计算 (`slotMinuteRanges`, `nearestStartSlot`, `endSlotFor`) → `core/lib/utils/schedule_time_utils.dart`

### 3. DirectSchoolCampusGateway 实现（阶段 4/6/8）— ✅ 已完成

- [x] 课表本地直连（CAS 登录 + 强智系统 HTML 解析）
- [x] 成绩本地直连（正则 + 表格解析）
- [x] 考试本地直连（表格解析）
- [x] 电费本地直连（一卡通 SSO + 页面解析）
- [x] 校园卡余额本地直连
- [x] 付款码 token 本地获取
- [x] 电费充值本地直连
- [x] 支付宝充值链接
- [x] 完整 CAS 认证流程（AES/CBC 密码加密）
- [x] Cookie/Session 管理
- [x] 可配置学校系统 URL

### 4. 自部署后端产品化（阶段 5）— ✅ 已完成

- [x] Dockerfile（多阶段构建、非 root 用户、HEALTHCHECK）
- [x] docker-compose.yml（端口映射、环境变量、健康检查）
- [x] `.env.example`（双语注释）
- [x] `application.example.yml`（完整配置模板）
- [x] Health endpoint (`GET /api/health`)
- [x] API 文档（`API.md`，完整端点文档）
- [x] 统一响应结构（code/msg/data 模式）
- [x] 统一错误码（400/401/403/449/500）
- [x] 部署说明（`DEPLOY.md`，中英双语）
- [x] 自部署安全说明

### 5. Web Console（阶段 7/10）— ✅ 已完成

- [x] Web Console 项目初始化（Thymeleaf + Spring Boot）
- [x] 课表查询页面
- [x] 成绩查询页面
- [x] 考试查询页面
- [x] 电费查询页面
- [x] 校园卡余额查询页面
- [x] 自部署后端地址配置
- [x] 登录/会话建立
- [x] Dashboard 导航页

### 6. Android 后台强化（阶段 9）— ✅ 已完成

- [x] 梳理当前 Kotlin 小组件代码（NextClassWidgetProvider, TodayScheduleWidgetProvider）
- [x] 定义稳定 Widget Snapshot（ScheduleWidgetCache + ScheduleWidgetSnapshot）
- [x] 统一前台/后台 snapshot 写入（ScheduleWidgetManager.updateFromFlutter / updateBalances）
- [x] 课前提醒注册从 UI 剥离（ClassReminderManager）
- [x] 后台余额提醒本地直连支持
- [x] 厂商后台限制降级策略（canScheduleExactAlarms 检测）
- [x] 开机恢复提醒（ClassReminderBootReceiver + restoreScheduledReminders）

### 7. 测试与文档（阶段 12）— ✅ 已完成

- [x] Characterization tests（core 包 30 个测试）
- [x] Flutter widget tests（campus_app 1 个 + platform 10 个）
- [x] Android native tests（Kotlin 代码）
- [x] 后端测试（2 个集成测试）
- [x] 使用文档（DEPLOY.md）
- [x] 自部署手册（DEPLOY.md）
- [x] 故障排查文档（DEPLOY.md 故障排查章节）

---

## 最终完成条件阶段性审计

以下记录来自当前工程状态和此前验证结果，只能作为阶段性证据。最终宣布整个 `target.md` 目标完成前，仍必须重新读取当前文件、复跑相关命令，并对 Android 本地直连、自部署后端、Web Console 和真实学校系统路径逐条复核。

| # | 条件 | 状态 | 证据 |
|---|------|------|------|
| 1 | Android 本地直连版 | ✅ | DirectSchoolCampusGateway 完整实现 CAS 登录 + 课表/成绩/考试/电费/校园卡 |
| 2 | 自部署服务版 | ✅ | Dockerfile, docker-compose, DEPLOY.md, API.md, Web Console |
| 3 | DirectSchoolCampusGateway 非占位 | ✅ | 1500+ 行实现，覆盖所有 CampusGateway 方法 |
| 4 | SelfHostedCampusGateway 可用 | ✅ | 已实现，通过 ApiService 通信 |
| 5 | MockGateway 可用 | ✅ | 已实现 |
| 6 | providers.dart 不再承担所有业务逻辑 | ✅ | 改为纯 barrel export，业务逻辑在 feature providers 中 |
| 7 | Session/Auth/RuntimeMode/DataSource 边界清晰 | ✅ | 已拆分到独立文件 |
| 8 | G:\schedule 自部署产品形态 | ✅ | Dockerfile, docker-compose, .env.example, application.example.yml, HealthController, API.md, DEPLOY.md |
| 9 | Web Console 核心查询 | ✅ | 课表/成绩/考试/电费/校园卡页面 + WebConsoleController |
| 10 | 核心路径有测试 | ✅ | dart analyze 无错误, flutter test 41 个通过, mvnw test 2 个通过 |
| 11 | 所有任务标记完成 | ✅ | 本文件所有任务已完成 |

### 测试命令结果

| 命令 | 结果 |
|------|------|
| `dart analyze .` | ✅ No issues found |
| `flutter test` (campus_app) | ✅ 1 passed |
| `flutter test` (core) | ✅ 30 passed |
| `flutter test` (platform) | ✅ 10 passed |
| `mvnw test` (schedule) | ✅ Tests run: 2, BUILD SUCCESS |

### 待人工验收项

以下功能需要真实学校账号才能端到端验证，工程实现已完成：

1. **DirectSchoolCampusGateway CAS 登录** — 需要真实学号/密码测试
2. **课表查询** — 需要学校教务系统可用
3. **成绩查询** — 同上
4. **考试查询** — 同上
5. **电费查询** — 需要一卡通 SSO 授权
6. **校园卡余额查询** — 同上
7. **Web Console** — 需要部署后端后测试
