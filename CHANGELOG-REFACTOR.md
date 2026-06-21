# 校园助手重构 — 改动说明

> 生成日期：2026-06-20
> 来源：`G:\app\target.md`
> 进度跟踪：`G:\app\docs\refactor-progress.md`

---

## 一、概述

本次重构的目标是将项目从"App 强依赖自部署后端"的架构，演进为**双产品形态并行**：

1. **Android Local-Only App** — 普通用户默认路径，App 直接请求学校系统，零公共服务器依赖
2. **Self-Hosted Server Mode** — 技术用户可自部署的后端服务版，包含 Web Console

重构范围覆盖 `target.md` 中定义的阶段 0–12，涉及 `G:\app`（Flutter monorepo）和 `G:\schedule`（Spring Boot 后端）两个仓库。

---

## 二、阶段 1：数据源抽象层

### 2.1 新增抽象接口

| 文件 | 说明 |
|------|------|
| `packages/data/lib/src/campus_gateway.dart` | `CampusGateway` 抽象接口，定义 `getSchedule`、`getGrades`、`getExams`、`getElecBalance`、`getCampusCardBalance`、`rechargeElec`、`getPayCodeToken`、`getCampusCardAlipayUrl` |
| `packages/data/lib/src/campus_runtime_mode.dart` | `CampusRuntimeMode` 枚举：`localAndroid` / `selfHosted` / `mock` |
| `packages/data/lib/src/campus_failure.dart` | `CampusFailure` 密封异常类：`AuthInvalidFailure`、`SessionExpiredFailure`、`CaptchaRequiredFailure`、`NetworkFailure`、`SchoolSystemChangedFailure`、`RateLimitedFailure`、`DormNotConfiguredFailure`、`UnsupportedModeFailure` |

### 2.2 三种数据源实现

| 实现 | 文件 | 状态 |
|------|------|------|
| **SelfHostedCampusGateway** | `packages/data/lib/src/self_hosted/self_hosted_campus_gateway.dart` | ✅ 可用，通过 ApiService 与自部署后端通信 |
| **SelfHostedSessionManager** | `packages/data/lib/src/self_hosted/self_hosted_session_manager.dart` | ✅ 可用，管理 sessionId 创建/缓存/恢复 |
| **SelfHostedSessionStore** | 同上文件，抽象接口 | ✅ `SessionService` 已实现此接口 |
| **MockCampusGateway** | `packages/adapters_mock/lib/src/mock_campus_gateway.dart` | ✅ 可用，返回 Mock 数据 |
| **DirectSchoolCampusGateway** | `packages/data/lib/src/direct_school/direct_school_campus_gateway.dart` | ⚠️ 工程路径完成，CAS 登录认证待修复 |

### 2.3 导出更新

| 文件 | 变更 |
|------|------|
| `packages/data/lib/data.dart` | 新增导出：`campus_runtime_mode`、`campus_failure`、`campus_gateway`、`self_hosted_campus_gateway`、`self_hosted_session_manager`、`direct_school_campus_gateway` |
| `packages/adapters_mock/lib/campus_adapters_mock.dart` | 新增导出：`mock_campus_gateway` |
| `packages/platform/pubspec.yaml` | 新增 `data` 包依赖 |

---

## 三、阶段 2：Provider 拆分

### 3.1 新建文件

| 文件 | 包含内容 |
|------|----------|
| `apps/campus_app/lib/providers/runtime_mode.dart` | `apiServiceProvider`、`campusRuntimeModeProvider`、`campusGatewayProvider`、`campusBackendProvider`（deprecated 适配器） |
| `apps/campus_app/lib/providers/session.dart` | `SystemDomain`、`RecoveryState`、`RecoveryFailureKind`、`RecoverySnapshot`、`ManualVerificationRequiredException`、`RecoveryHealthNotifier`、`SessionManager` |
| `apps/campus_app/lib/providers/shared.dart` | `sessionUpdateProvider`、`campusCardQrScrollSignalProvider` |
| `apps/campus_app/lib/features/auth/auth_providers.dart` | `CredentialsNotifier`、`credentialsProvider`、`ensureCredentialPassword` |
| `apps/campus_app/lib/features/schedule/schedule_providers.dart` | `scheduleProvider`、`semesterStartProvider`、`selectedScheduleSemesterProvider`、`customCoursesProvider`、`selectedWeekProvider`、`scheduleSundayFirstProvider`、`semesterTotalWeeksProvider` |
| `apps/campus_app/lib/features/electricity/electricity_providers.dart` | `electricityProvider`、`NoDormSetException` |
| `apps/campus_app/lib/features/campus_card/campus_card_providers.dart` | `campusCardBalanceProvider`、`payCodeProvider` |
| `apps/campus_app/lib/features/grades/grades_providers.dart` | `gradesProvider` |
| `apps/campus_app/lib/features/exams/exams_providers.dart` | `examsProvider` |
| `apps/campus_app/lib/features/settings/settings_providers.dart` | `dormRoomProvider` |

### 3.2 修改文件

| 文件 | 变更 |
|------|------|
| `apps/campus_app/lib/utils/providers.dart` | 从 1387 行缩减为纯 barrel export 文件，移除全部重复定义 |
| `apps/campus_app/lib/providers/runtime_mode.dart` | 移除 `import 'session.dart'`（消除循环依赖） |

### 3.3 纯函数提取到 core 包

| 文件 | 包含函数 |
|------|----------|
| `packages/core/lib/utils/exam_time_utils.dart` | `parseExamTime()`、`weekOfDate()` |
| `packages/core/lib/utils/schedule_time_utils.dart` | `slotMinuteRanges`、`nearestStartSlot()`、`endSlotFor()` |

---

## 四、阶段 3/4/6/8：DirectSchoolCampusGateway 实现

### 4.1 架构

```
DirectSchoolCampusGateway
├── SchoolSystemConfig      — 可配置的学校系统 URL
├── _SchoolHttpClient       — 手动 CookieJar + 手动重定向 HTTP 客户端
│   ├── ManualCookieJar     — 按域名隔离的 cookie 存储
│   └── _followRedirects()  — 手动跟随重定向（POST→GET 切换）
├── _CasAuthenticator       — CAS 统一认证登录
│   ├── login()             — 密码登录（AES/CBC/PKCS7 加密）
│   └── loginWithTicket()   — Ticket 登录（WebView SSO）
├── _CasPasswordEncryptor   — AES/CBC/PKCS7 密码加密
├── _ScheduleParser         — 强智系统课表 HTML 解析
├── _GradeParser            — 强智系统成绩 HTML 解析
├── _ExamParser             — 强智系统考试 HTML 解析
└── _EcardParser            — 一卡通系统页面解析
```

### 4.2 已实现功能

| 方法 | 状态 | 说明 |
|------|------|------|
| `getSchedule()` | ⚠️ | 登录认证待修复，解析器已实现 |
| `getGrades()` | ⚠️ | 同上 |
| `getExams()` | ⚠️ | 同上 |
| `getElecBalance()` | ⚠️ | 依赖登录认证 |
| `getCampusCardBalance()` | ⚠️ | 依赖登录认证 |
| `rechargeElec()` | ⚠️ | 依赖登录认证 |
| `getPayCodeToken()` | ⚠️ | 依赖登录认证 |
| `getCampusCardAlipayUrl()` | ⚠️ | 依赖登录认证 |

### 4.3 加密验证

Dart 的 AES/CBC/PKCS7 实现已通过固定测试向量验证，与 Java 的 `PasswordEncryptor` 输出完全一致。

### 4.4 当前卡点

CAS 登录认证在跨域重定向（`ids.cqjtu.edu.cn` → `jwgln.cqjtu.edu.cn`）时 cookie 传递失败。POST 登录返回 401，而非预期的 302 重定向。需要进一步调试密码加密或 cookie 处理。

---

## 五、阶段 5：自部署后端产品化

### 5.1 新增文件（G:\schedule）

| 文件 | 说明 |
|------|------|
| `Dockerfile` | 多阶段构建（Maven builder → JRE Alpine runtime），非 root 用户，HEALTHCHECK |
| `docker-compose.yml` | 端口映射、环境变量、健康检查、持久化卷 |
| `.env.example` | 所有可配置环境变量，中英双语注释 |
| `src/main/resources/application.example.yml` | 完整配置模板，敏感字段标记为 `CHANGE_ME` |
| `src/main/java/.../controller/HealthController.java` | `GET /api/health` 端点，返回 status/version/timestamp/uptime |
| `DEPLOY.md` | 部署文档（系统要求、快速开始、环境变量、安全、故障排查） |
| `API.md` | API 文档（所有端点、参数、响应示例、错误码） |

### 5.2 修改文件

| 文件 | 变更 |
|------|------|
| `pom.xml` | 新增 `spring-boot-starter-thymeleaf` 依赖 |

---

## 六、阶段 7/10：Web Console

### 6.1 新增文件（G:\schedule）

| 文件 | 说明 |
|------|------|
| `src/main/java/.../controller/WebConsoleController.java` | Web Console 控制器，处理登录/会话/页面路由 |
| `src/main/resources/templates/console/index.html` | 登录页 |
| `src/main/resources/templates/console/dashboard.html` | 导航仪表盘 |
| `src/main/resources/templates/console/schedule.html` | 课表查询页 |
| `src/main/resources/templates/console/grades.html` | 成绩查询页 |
| `src/main/resources/templates/console/exams.html` | 考试查询页 |
| `src/main/resources/templates/console/electricity.html` | 电费查询页 |
| `src/main/resources/templates/console/campus-card.html` | 校园卡余额查询页 |

### 6.2 技术栈

Spring Boot + Thymeleaf + Bootstrap 5（CDN），中文 UI。

---

## 七、阶段 9：Android 后台强化

### 7.1 已有代码（未修改）

| 文件 | 说明 |
|------|------|
| `android/.../ScheduleWidgetManager.kt` | 小组件管理（NextClass + TodaySchedule），含 snapshot 缓存、自动刷新调度 |
| `android/.../ClassReminderManager.kt` | 课前提醒管理（AlarmManager 精确调度、通知渠道、灵动岛适配） |
| `android/.../NextClassWidgetProvider.kt` | 下一节课小组件 |
| `android/.../TodayScheduleWidgetProvider.kt` | 今日课表小组件 |
| `android/.../ClassReminderReceiver.kt` | 提醒广播接收器 |
| `android/.../ClassReminderBootReceiver.kt` | 开机恢复提醒 |

Kotlin 代码已具备完整的 widget snapshot 机制、跨进程缓存、厂商限制降级策略（`canScheduleExactAlarms` 检测）、开机恢复能力。

---

## 八、测试与验证

### 8.1 测试命令结果

| 命令 | 最新结果 |
|------|----------|
| `dart analyze .` | ✅ No issues found（仅测试文件警告） |
| `flutter test` (campus_app) | ✅ 1 passed |
| `flutter test` (core) | ✅ 30 passed |
| `flutter test` (platform) | ✅ 10 passed |
| `mvnw test` (schedule) | ✅ Tests run: 2, BUILD SUCCESS |

### 8.2 端到端测试

| 测试 | 文件 | 结果 |
|------|------|------|
| 加密一致性 | `packages/data/test/test_encrypt.dart` | ✅ Dart == Java 输出完全一致 |
| 登录 + 课表查询 | `packages/data/test/direct_gateway_e2e_test.dart` | ❌ 登录认证失败（401） |

---

## 九、进度文件

| 文件 | 说明 |
|------|------|
| `docs/refactor-progress.md` | 完整任务队列、完成状态、最终条件审计 |
| `target.md` | 重构目标计划书（原始来源） |

---

## 十、未完成任务

### 10.1 DirectSchoolCampusGateway CAS 登录认证

**问题**：POST 登录返回 401，而非 302 重定向。可能原因：
1. 密码加密实现仍有细微差异
2. Cookie 未正确传递
3. 需要验证码

**当前方案**：手动 CookieJar + 手动重定向跟随已实现，但登录仍返回 401。

### 10.2 解析器真实数据验证

课表/成绩/考试解析器需要登录成功后用真实数据验证。

### 10.3 请假模块本地直连

`DirectSchoolCampusGateway` 未实现请假相关方法。

### 10.4 API v1 版本化

`G:\schedule` 的 API 尚未引入 v1 路径。

---

## 十一、文件变更总览

### G:\app 新增文件

```
apps/campus_app/lib/providers/runtime_mode.dart
apps/campus_app/lib/providers/session.dart
apps/campus_app/lib/providers/shared.dart
apps/campus_app/lib/features/auth/auth_providers.dart
apps/campus_app/lib/features/schedule/schedule_providers.dart
apps/campus_app/lib/features/electricity/electricity_providers.dart
apps/campus_app/lib/features/campus_card/campus_card_providers.dart
apps/campus_app/lib/features/grades/grades_providers.dart
apps/campus_app/lib/features/exams/exams_providers.dart
apps/campus_app/lib/features/settings/settings_providers.dart
packages/core/lib/utils/exam_time_utils.dart
packages/core/lib/utils/schedule_time_utils.dart
packages/data/lib/src/campus_gateway.dart
packages/data/lib/src/campus_failure.dart
packages/data/lib/src/campus_runtime_mode.dart
packages/data/lib/src/self_hosted/self_hosted_campus_gateway.dart
packages/data/lib/src/self_hosted/self_hosted_session_manager.dart
packages/data/lib/src/direct_school/direct_school_campus_gateway.dart
packages/adapters_mock/lib/src/mock_campus_gateway.dart
docs/refactor-progress.md
```

### G:\app 修改文件

```
apps/campus_app/lib/utils/providers.dart      # 从 1387 行 → barrel export
apps/campus_app/lib/pages/campus_card_page.dart  # campusBackendProvider → campusGatewayProvider
apps/campus_app/lib/pages/electricity_page.dart  # 同上
apps/campus_app/lib/pages/profile_page.dart      # 同上
apps/campus_app/lib/pages/schedule_page.dart     # 同上
packages/data/lib/data.dart                      # 新增导出
packages/adapters_mock/lib/campus_adapters_mock.dart  # 新增导出
packages/platform/lib/services/session_service.dart   # implements SelfHostedSessionStore
packages/platform/pubspec.yaml                       # 新增 data 依赖
packages/data/pubspec.yaml                           # 新增 http 依赖
```

### G:\schedule 新增文件

```
Dockerfile
docker-compose.yml
.env.example
src/main/resources/application.example.yml
src/main/java/.../controller/HealthController.java
src/main/java/.../controller/WebConsoleController.java
src/main/resources/templates/console/index.html
src/main/resources/templates/console/dashboard.html
src/main/resources/templates/console/schedule.html
src/main/resources/templates/console/grades.html
src/main/resources/templates/console/exams.html
src/main/resources/templates/console/electricity.html
src/main/resources/templates/console/campus-card.html
DEPLOY.md
API.md
```

### G:\schedule 修改文件

```
pom.xml  # 新增 spring-boot-starter-thymeleaf
```
