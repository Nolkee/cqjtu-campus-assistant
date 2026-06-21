# 校园助手重构目标计划书

本文档面向当前两个本地项目：

- App 仓库：`G:\app`
- 现有后端仓库：`G:\schedule`

写作目标是把聊天截图里的重构要求落成一份可执行、可验收、可分阶段推进的计划书。这里的重点不是“把现有功能重写一遍”，而是重新定义产品形态和工程边界：项目最终必须同时交付两个产品形态。第一个是面向普通用户的 Android 纯前端 App，第二个是面向技术用户、多端访问和网页访问场景的自部署服务版。这里的“可选”只表示普通用户可以不启用自部署服务，不表示项目可以不做第二形态。

---

## 1. 对聊天截图中核心意思的理解

### 1.1 “安卓纯前端”不是普通网页前端

截图里说的“只做前端”“安卓纯前端”，不是指做一个没有能力的静态界面，也不是指把 Flutter 当成简单 UI 壳。

它的准确含义是：

1. 默认给普通用户使用的版本不依赖作者提供的服务器。
2. App 自己直接请求学校系统或学校相关接口。
3. 登录态、cookie、ticket、token、会话恢复全部保存在用户手机本地。
4. 学校返回的 JSON、HTML 或其他数据结构由手机端本地解析。
5. 课表、成绩、考试、电费、校园卡、请假等数据的缓存和展示都在本地完成。
6. 课前提醒、小组件、后台刷新、余额提醒等系统能力由 Android 端承担主要责任。
7. 服务器不再作为普通 App 使用路径中的必需中转层。

因此，“安卓纯前端”更准确的名字应该是：

```text
Android Local-Only Client
```

也就是“本地直连学校系统的 Android 客户端”。

### 1.2 为什么要这样改

截图中的质疑主要有几层：

1. 如果后端没有真正存储核心数据，也不做账号体系，只是带着 token 去学校系统中转请求，那么后端价值不高。
2. 如果每次都是 App -> 作者服务器 -> 学校系统 -> 作者服务器 -> App，会增加延迟和故障点。
3. 如果项目承诺不收集数据、不存储数据，那么让所有 token 和校验材料都留在手机本地反而更一致。
4. 手机本身可以发起请求、保存 token、解析 JSON/HTML，没有必要为了“中转”引入公共服务器。
5. 真正需要服务器的是技术用户的自部署、多端访问、网页访问、自动化任务，而不是普通用户使用 App 的主路径。

所以本次重构的方向应当是：

```text
普通用户：Android App 本地直连，零公共服务器依赖。
技术用户/多端用户：项目必须交付自部署服务版，由用户自己承担服务器和网络环境。
```

### 1.3 “后端”在新架构中的地位变化

现有 `G:\schedule` 后端不是简单删除，而是改变定位。

旧定位：

```text
App 必须通过后端访问学校系统。
```

新定位：

```text
后端是必须交付的第二产品形态：自部署适配器、网页查询服务和 HTTP API 服务。
普通 Android App 默认不需要它，但项目规划中必须完整建设它。
```

这意味着：

1. App 不能把 `G:\schedule` 当成必需依赖。
2. App 仍可保留“自定义后端地址”能力。
3. `G:\schedule` 必须继续演进为 self-host server。
4. Web 端由于浏览器 CORS、cookie、跨站限制等问题，通常仍需要自部署后端辅助。
5. 项目方不提供公共服务器，避免运营、合规、安全和隐私压力。

重要区分：

```text
用户使用路径：自部署服务对普通用户是可选的。
项目交付目标：自部署服务版是必须完成的第二产品形态。
```

---

## 2. 重构总目标

### 2.1 第一目标：Android 纯前端默认版

默认发布给普通用户的 App 应满足：

1. 安装 APK 后即可使用。
2. 不需要配置服务器地址。
3. 不向作者服务器上传账号、密码、ticket、cookie、token 或业务数据。
4. 所有敏感凭据只保存在手机本地安全存储中。
5. App 直接与学校系统交互。
6. 学校返回的数据在手机端解析并缓存。
7. Android 原生能力优先保证后台任务、小组件、通知、开机恢复等功能。

### 2.2 第二目标：自部署服务版

这是必须完成的第二产品形态，面向有技术能力的用户、多端访问用户、网页访问用户和自动化集成场景。它不是普通用户使用 App 的前置条件，但它是本项目重构后的正式交付物。

自部署服务版应满足：

1. 用户可以自己部署 `G:\schedule` 演进后的后端。
2. 用户可以通过网页、脚本、HTTP 客户端或 App 自定义后端地址查询数据。
3. 自部署后端不由项目方运营。
4. 自部署后端应提供 Docker、配置模板、健康检查和 API 文档。
5. Web Console 是自部署服务版的正式组成部分。
6. Web Console 只对接自部署后端，不承诺浏览器直接访问学校系统。
7. App 可以在设置中切换到自部署后端模式，用于多端一致或服务器代理访问。
8. 自部署服务版必须有清晰的部署、升级、备份、安全和故障排查文档。

### 2.3 第三目标：工程边界清晰

重构后应形成稳定边界：

```text
UI 层：Flutter 页面、交互、状态展示
业务层：课程、成绩、考试、电费、校园卡、请假等用例
数据源层：本地直连学校系统 / 自部署后端
平台层：Android 通知、小组件、后台任务、安全存储、WebView
核心层：纯模型、时间计算、课表算法、解析结果结构
```

页面层不能直接关心：

1. sessionId 怎么创建。
2. ticket 怎么恢复。
3. cookie 怎么注入。
4. token 什么时候过期。
5. 学校 HTML 怎么解析。
6. 是直连学校系统还是通过自部署后端。

这些都应该被数据源和会话层封装。

---

## 3. 当前项目现状判断

### 3.1 `G:\app` 当前形态

当前 App 是 Flutter monorepo，已经有较好的基础：

```text
G:\app
├─ apps\campus_app
├─ packages\core
├─ packages\data
├─ packages\platform
├─ melos.yaml
└─ pubspec.yaml
```

已有优势：

1. 已经是 monorepo，适合继续拆包。
2. 已经有 `core` 存放模型和纯逻辑。
3. 已经有 `data` 存放后端接口封装。
4. 已经有 `platform` 存放通知、后台、小组件、凭据等平台服务。
5. 已经使用 Riverpod，不需要强行换状态管理。
6. 已经有 Android 原生 Kotlin 小组件、提醒、系统集成代码。

主要问题：

1. App 目前仍以 `ApiService` 调用后端为主。
2. `apps\campus_app\lib\utils\providers.dart` 文件过大，承载了过多会话、数据源、业务状态和 provider 逻辑。
3. 前台请求和后台任务中有重复的后端请求逻辑。
4. 业务数据源没有清晰区分“本地直连学校系统”和“自部署后端”。
5. 平台能力和业务请求边界还不够稳定。
6. Android 原生能力虽然存在，但还没有成为架构上的第一优先级。

### 3.2 `G:\schedule` 当前形态

当前后端是 Spring Boot/Maven 项目：

```text
G:\schedule
├─ pom.xml
├─ API文档.md
├─ 前端接入-sessionId改造说明.md
├─ src\main\java\com\axu\schedule
│  ├─ controller
│  ├─ service
│  ├─ model
│  ├─ config
│  └─ utils
└─ src\main\resources
```

已有能力：

1. 认证和会话隔离。
2. 课表、成绩、考试接口。
3. 电费、校园卡接口。
4. 请假相关接口。
5. Todo 相关接口。
6. 缓存配置。
7. API 文档和 sessionId 改造说明。

主要问题：

1. 对普通 App 来说，它不应再是强依赖。
2. 如果只做请求中转，会带来隐私、延迟、运营责任和故障点。
3. 自部署体验需要进一步规范化。
4. API 契约需要稳定，方便 App、自部署 Web Console、脚本和 HTTP 客户端接入。
5. 部署文档、配置模板、容器化、健康检查还应强化。

---

## 4. 最终产品形态

### 4.1 形态 A：Android Local-Only App

这是默认形态，也是最优先目标。

用户路径：

```text
用户安装 APK
-> 输入学号/密码或通过 WebView 登录
-> App 本地保存凭据、cookie、ticket、token
-> App 直接请求学校系统
-> App 本地解析返回数据
-> App 本地缓存
-> Flutter 展示数据
-> Android 原生负责提醒、小组件、后台刷新
```

此形态下不需要：

1. 作者提供服务器。
2. 公共 API 网关。
3. 账号体系。
4. 云端数据库。
5. 服务端存储用户 token。

此形态下需要：

1. 强本地安全存储。
2. 稳定的学校系统请求封装。
3. 稳定的 HTML/JSON 解析器。
4. 缓存和过期策略。
5. 本地错误分类。
6. Android 后台任务控制。
7. 对验证码、登录过期、学校系统变更的降级处理。

### 4.2 形态 B：Self-Hosted Server Mode

这是必须交付的第二产品形态。它对普通 App 用户不是必需路径，但对整个项目不是附属品，也不是以后有空再说的实验功能。

用户路径：

```text
技术用户部署后端
-> 配置学校系统访问相关参数
-> App 或 Web Console 填写自部署地址
-> 客户端请求自部署后端
-> 自部署后端请求学校系统
-> 自部署后端解析数据
-> 客户端展示数据
```

适用场景：

1. 用户希望多端访问。
2. 用户希望网页查询。
3. 用户希望在自己的服务器上做定时任务。
4. 用户希望用脚本或 HTTP API 集成。
5. 浏览器端受 CORS 或 cookie 限制，无法直接访问学校系统。
6. 用户希望把学校系统适配、解析、缓存和自动刷新放到自己的服务器上。
7. 用户希望手机 App 只作为展示端，后端由自己的服务器统一处理。

不适用场景：

1. 普通用户下载安装即用。
2. 项目方提供公共服务。
3. 服务端集中保存全体用户数据。

必须交付的组成部分：

1. Spring Boot 自部署后端。
2. Web Console。
3. OpenAPI 或等价 API 文档。
4. Docker/Docker Compose 部署方案。
5. App 自定义后端接入模式。
6. 自部署安全和隐私说明。

### 4.3 明确排除：Mock / Demo Mode

本轮重构不再把 Mock 或 Demo 作为第三产品形态，也不再用 Mock 数据作为验收路径。

约束：

1. 产品运行模式只保留 `localAndroid` 和 `selfHosted`。
2. 测试不得通过 Mock、Fake、Stub、Demo 数据源伪造学校业务数据。
3. 课表、成绩、考试、校园卡、电费等学校请求链路优先复用旧项目已跑通的真实请求逻辑。
4. 需要外部学校系统时，使用真实账号和本地 `.env.local` 注入的真实参数验证。
5. 如果真实验证遇到验证码、账号密码错误、宿舍参数缺失或需要用户手动授权，必须明确说明缺少什么，等待补齐后继续。
6. 纯模型、时间计算、解析函数等不依赖外部学校系统的单元测试可以继续保留，但不能包装成 Mock 数据源测试。

---

## 5. 架构原则

### 5.1 不大爆炸重写

重构必须保留现有可用路径。

每个阶段都应满足：

1. 原功能可运行。
2. 有回滚方案。
3. 有可验证结果。
4. 可以独立合并。

### 5.2 双产品形态并行，默认路径不同

项目必须同时建设两个正式形态：

```text
Android Local-Only App
Self-Hosted Server Mode
```

它们的区别不是“做不做”，而是“用户默认走哪条路径”。

普通用户默认配置：

```dart
CampusRuntimeMode.localAndroid
```

技术用户可显式切换：

```dart
CampusRuntimeMode.remoteBackend
```

因此原则是：

1. Android 纯前端版是普通用户默认路径。
2. 自部署服务版是项目必须交付的第二路径。
3. 两个形态共享模型、接口契约、错误分类和测试资产。
4. 两个形态不能互相阻塞：Android App 不应因自部署后端未启动而不可用，自部署 Web Console 也不应依赖 Android App 页面状态。
5. 后端模式必须显式开启，避免普通用户误以为需要服务器。

### 5.3 保持 Riverpod，不切 BLoC

当前项目已使用 Riverpod。重构应继续使用 Riverpod：

1. 避免引入不必要迁移成本。
2. 保持现有 provider 生态。
3. 通过拆文件、拆 feature、拆 repository 改善结构。

不建议为了“Clean Architecture”强行改成 BLoC。

### 5.4 Android 原生能力优先

以下能力应优先考虑 Android 原生或 Android 强约束设计：

1. 小组件。
2. 通知。
3. 课前提醒。
4. 后台刷新。
5. 开机恢复。
6. 厂商后台权限引导。
7. App 更新安装。
8. WebView 登录态提取。

Flutter 仍作为 UI 和跨层协调中心，但不能让系统级能力完全依赖页面生命周期。

### 5.5 数据源可替换

所有业务功能都应通过统一接口访问数据。

示意：

```dart
abstract class CampusDataSource {
  Future<ScheduleResult> getSchedule(...);
  Future<GradeResult> getGrades(...);
  Future<List<Exam>> getExams(...);
  Future<String> getElectricityBalance(...);
  Future<String> getCampusCardBalance(...);
}
```

实现可以有：

```text
DirectSchoolDataSource      # Android 本地直连学校系统
SelfHostedBackendDataSource # 用户自部署后端
```

页面和业务 provider 不应该关心当前使用哪一个。

### 5.6 敏感信息本地化

默认 Android 纯前端形态下：

1. 学号、密码、cookie、ticket、token 只存在手机本地。
2. 使用 Android Keystore / flutter_secure_storage。
3. 日志中不得打印密码、完整 cookie、完整 token。
4. 崩溃日志不得上传敏感字段。
5. 导出调试信息时必须脱敏。

---

## 6. 目标目录结构建议

短期可以保留现有 monorepo，不强制一次性移动所有文件。

中长期建议演进为：

```text
G:\app
├─ apps
│  └─ campus_app
│     ├─ lib
│     │  ├─ app
│     │  ├─ features
│     │  ├─ routing
│     │  ├─ theme
│     │  └─ main.dart
│     └─ android
│
├─ packages
│  ├─ core
│  │  ├─ lib\models
│  │  ├─ lib\utils
│  │  └─ test
│  │
│  ├─ campus_client
│  │  ├─ lib\src\contracts
│  │  ├─ lib\src\direct_school
│  │  ├─ lib\src\self_hosted
│  │  └─ test
│  │
│  ├─ campus_session
│  │  ├─ lib\src\stores
│  │  ├─ lib\src\recovery
│  │  ├─ lib\src\artifacts
│  │  └─ test
│  │
│  ├─ campus_platform
│  │  ├─ lib\services
│  │  ├─ lib\src
│  │  └─ test
│  │
└─ docs
   ├─ target.md
   ├─ architecture.md
   ├─ local-android-mode.md
   ├─ self-hosting.md
   └─ api-contract.md
```

如果暂时不新增太多包，也可以先在现有 `packages\data` 中建立子目录：

```text
packages\data\lib\src
├─ contracts
├─ direct_school
└─ self_hosted
```

等稳定后再拆成 `campus_client` 包。

---

## 7. 关键抽象设计

### 7.1 运行模式

建议定义统一运行模式：

```dart
enum CampusRuntimeMode {
  localAndroid,
  selfHosted,
}
```

含义：

| 模式 | 面向对象 | 是否需要服务器 | 数据来源 |
| --- | --- | --- | --- |
| `localAndroid` | 普通用户 | 不需要 | App 直接请求学校系统 |
| `selfHosted` | 技术用户 | 需要用户自部署 | 自部署后端 |

### 7.2 数据源接口

现有 `CampusBackend` 可以演进为更中性的接口名。

当前名字 `CampusBackend` 容易暗示“必须有后端”。建议改为：

```dart
abstract class CampusGateway
```

或：

```dart
abstract class CampusDataSource
```

职责：

1. 提供统一业务数据接口。
2. 屏蔽直连学校系统、自部署后端的差异。
3. 统一异常类型。
4. 统一响应结构。

建议保留兼容层：

```text
CampusBackend -> deprecated alias -> CampusGateway
```

避免一次性修改全项目。

### 7.3 会话和登录材料

应把这些概念明确分开：

```text
Credential        # 用户输入的学号/密码
LoginArtifact     # ticket/cookie/token 等登录产物
SchoolSession     # 学校系统会话
SelfHostSession   # 自部署后端 sessionId
RecoverySnapshot  # 恢复状态和失败原因
```

默认本地直连模式下，不应依赖后端 `sessionId`。

`sessionId` 只属于自部署后端模式：

```text
localAndroid: 使用学校系统 cookie/ticket/token
selfHosted: 使用 self-host server sessionId
```

### 7.4 统一异常模型

建议定义：

```dart
sealed class CampusFailure implements Exception
```

分类：

1. `AuthInvalidFailure`：账号密码错误或 ticket 无效。
2. `SessionExpiredFailure`：学校会话过期。
3. `CaptchaRequiredFailure`：需要验证码或安全验证。
4. `NetworkFailure`：网络异常。
5. `SchoolSystemChangedFailure`：页面结构或接口结构变化。
6. `RateLimitedFailure`：访问频率受限。
7. `DormNotConfiguredFailure`：宿舍参数未配置。
8. `UnsupportedModeFailure`：当前模式不支持该能力。

UI 只处理这些业务异常，不直接处理 Dio、OkHttp、HTML 解析异常。

---

## 8. Android 纯前端数据流设计

### 8.1 前台查询数据流

```text
Flutter Page
-> Riverpod Feature Provider
-> Feature Repository
-> CampusGateway
-> DirectSchoolDataSource
-> SchoolAuthSession
-> School HTTP/WebView/Native bridge
-> Parser
-> Domain Model
-> Local Cache
-> UI
```

关键点：

1. 页面不直接发请求。
2. 页面不解析学校返回内容。
3. 页面不保存 token。
4. 数据源负责判断是否需要重新登录或恢复会话。
5. 解析结果先转换为 `core` 模型，再给 UI。

### 8.2 后台刷新数据流

短期可保持现有 Flutter Workmanager，降低迁移风险。

短期：

```text
Android WorkManager
-> Flutter background callback
-> CampusGateway
-> DirectSchoolDataSource or SelfHostedDataSource
-> Update notification/widget/cache
```

中长期：

```text
Kotlin WorkManager
-> Android secure storage / shared contract
-> School request worker
-> Minimal parser or shared result adapter
-> Notification
-> Widget update
-> Cache snapshot
```

迁移原则：

1. 不要一开始就把所有后台逻辑搬到 Kotlin。
2. 先让本地直连模式稳定跑通。
3. 再把最依赖系统稳定性的能力迁移到原生：
   - 课前提醒。
   - 小组件刷新。
   - 余额低提醒。
   - 开机恢复。

### 8.3 小组件数据流

目标：

```text
业务数据 -> 稳定 Widget Snapshot -> Android 原生渲染
```

不得让 Android 小组件依赖 Flutter 页面状态。

建议：

1. `core` 或 `platform` 定义稳定的 Widget Snapshot。
2. App 前台刷新后写入 snapshot。
3. 后台任务刷新后写入 snapshot。
4. Kotlin 小组件只读取 snapshot 并渲染。
5. snapshot schema 需要版本号。

---

## 9. 自部署后端设计

### 9.1 后端新定位

`G:\schedule` 应演进为：

```text
Self-hosted Campus Adapter Server
```

它的目标不是服务所有 App 用户，也不是由项目方运营公共服务器，而是作为第二产品形态交付给技术用户。它必须能独立部署、独立运行、独立升级，并能为 Web Console、脚本、HTTP 客户端和 App 自定义后端模式提供稳定服务。

新定位可以概括为：

```text
面向普通用户：不是 App 的必需依赖。
面向技术用户：是必须交付的正式产品形态。
面向项目工程：是与 Android Local-Only App 并行维护的适配服务。
```

### 9.2 后端保留能力

应保留：

1. Spring Boot 服务。
2. 课表、成绩、考试、电费、校园卡、请假接口。
3. sessionId 隔离。
4. 缓存。
5. API 文档。
6. Todo 或任务能力。

### 9.3 后端需要新增或强化

1. Dockerfile。
2. Docker Compose。
3. `.env.example`。
4. `application.example.yml`。
5. 健康检查接口。
6. OpenAPI 或更严格 API 文档。
7. 统一响应结构。
8. 统一错误码。
9. 请求日志脱敏。
10. 部署说明。
11. 安全说明。
12. 自部署免责声明。

### 9.4 API 版本策略

现有接口类似：

```text
/api/getSchedule
/api/getGrades
/api/getExams
/api/elec/balance
```

建议逐步引入 v1 API：

```text
/api/v1/auth/session
/api/v1/schedule
/api/v1/grades
/api/v1/exams
/api/v1/electricity/balance
/api/v1/campus-card/balance
/api/v1/leave/applications
```

旧接口保留兼容，不马上删除。

### 9.5 Web Console 的边界

Web Console 应只对接自部署后端。

原因：

1. 浏览器直接访问学校系统可能受 CORS 限制。
2. 浏览器 cookie 策略更复杂。
3. 浏览器中保存账号密码和跨域 token 风险更高。
4. 技术用户既然选择网页查询，就应该部署自己的服务。

---

## 10. 功能模块重构计划

### 10.1 Auth 登录模块

当前问题：

1. 登录材料分散在 `CredentialService`、`SessionService`、`SessionManager`、WebView bootstrapper、后端 sessionId 中。
2. 本地直连模式和自部署后端模式边界不清。

目标：

```text
features/auth
packages/campus_session
```

任务：

1. 定义 `CredentialStore`。
2. 定义 `LoginArtifactStore`。
3. 区分学校系统登录态和自部署后端 sessionId。
4. WebView 登录只负责获取学校系统材料。
5. 自部署登录只负责和 self-host server 建立会话。
6. UI 只展示登录状态和必要的重新验证入口。

验收标准：

1. localAndroid 模式下不调用 `/api/auth/createSession`。
2. selfHosted 模式下才调用自部署后端 session 接口。
3. 账号密码不出现在普通 debug 日志中。
4. 登录过期能给出明确提示。

### 10.2 课表模块

目标：

1. localAndroid 模式下 App 直接获取课表。
2. 解析逻辑在客户端本地完成。
3. 课程模型继续使用 `core\models\course.dart`。
4. 课表缓存支持按学期区分。
5. 小组件和提醒消费同一份规范化课程数据。

任务：

1. 梳理现有后端 `SpiderService` 中课表解析逻辑。
2. 将可复用解析规则迁移到 Dart 或 Kotlin。
3. 建立 sanitized fixture 测试。
4. 在 `DirectSchoolDataSource.getSchedule` 中实现直连。
5. 保留 `SelfHostedDataSource.getSchedule` 兼容后端。
6. 改造 `scheduleProvider`，让它只依赖 repository。

验收标准：

1. 不启动 `G:\schedule` 也能在 Android 真机查询课表。
2. selfHosted 模式仍可通过后端查询。
3. 课程提醒和小组件使用同一份真实结果。

### 10.3 成绩模块

目标：

1. 成绩查询本地直连。
2. 成绩 summary 和列表结构稳定。
3. 学期参数统一。

任务：

1. 从后端 `GradeService` 提取解析规则。
2. 定义 `GradeResult`。
3. 解析器增加边界测试：
   - 无成绩。
   - 绩点字段缺失。
   - 排名字段缺失。
   - 学校页面结构变化。
4. UI 只消费 provider 返回结果。

验收标准：

1. 本地直连能查询成绩。
2. 后端模式结果和本地模式转换后的模型一致。
3. 错误能归类为认证失败、网络失败或结构变化。

### 10.4 考试模块

目标：

1. 考试安排本地直连。
2. 考试可继续生成课表中的考试课程。
3. 可继续生成本地 todo 候选。

任务：

1. 迁移 `ExamService` 解析规则。
2. 保持 `Exam` 模型稳定。
3. 把 exam-to-course 逻辑从超大 provider 中移出。
4. 为考试时间解析增加单元测试。

验收标准：

1. 考试安排查询可脱离后端。
2. 考试课程能正确合并进课表。
3. 日期、周次、节次转换有测试覆盖。

### 10.5 电费模块

目标：

1. 宿舍参数本地保存。
2. 电费查询本地直连。
3. 余额提醒由 Android 后台稳定触发。

任务：

1. 梳理 `ElectricityService` 请求和解析逻辑。
2. 统一 `DormRoom` 参数映射。
3. `electricityProvider` 改为 feature repository。
4. 后台任务不再硬编码后端 API。
5. 通知阈值和冷却时间继续本地保存。

验收标准：

1. 不启动后端也能查询电费。
2. 宿舍未配置时给出明确错误。
3. 后台余额提醒不依赖 Flutter 页面打开。

### 10.6 校园卡模块

目标：

1. 校园卡余额本地直连。
2. 校园卡付款码 token 本地获取和缓存。
3. 支付宝充值链接逻辑清晰。

任务：

1. 拆出 campus card repository。
2. 定义 token 过期策略。
3. 区分余额、付款码、充值三个用例。
4. 日志中不得输出完整 token。

验收标准：

1. 本地直连能获取余额。
2. 付款码可正常刷新。
3. token 失效时能引导重新验证。

### 10.7 请假模块

目标：

1. 请假相关 zoveToken 本地保存。
2. 请假列表本地直连或通过 WebView 材料恢复。
3. 自部署后端模式保留同等能力。

任务：

1. 明确 zoveToken 来源。
2. 把 `SilentZoveTokenBootstrapper` 的职责缩小为“登录材料刷新器”。
3. 将请假接口包装进 `LeaveRepository`。
4. 区分 token 过期、未登录、安全验证。

验收标准：

1. localAndroid 模式下不需要后端中转请假查询。
2. token 缺失时能自动或手动引导刷新。
3. 不在 UI 层直接处理 cookie/token。

### 10.8 Todo 模块

当前后端已有 Todo 服务，但 Android 纯前端模式下，Todo 不应强依赖后端。

目标：

1. 普通 App 的 Todo 先本地化。
2. 考试、课程提醒可生成本地任务。
3. selfHosted 模式可以选择同步到自部署后端。

任务：

1. 定义 `TodoRepository`。
2. localAndroid 使用本地存储。
3. selfHosted 使用后端同步。
4. 增加冲突策略。

验收标准：

1. 默认 App 没有后端也能使用 todo。
2. selfHosted 用户可以启用同步。

---

## 11. 分阶段实施计划

### 阶段 0：冻结目标和建立安全线

目的：

先保护现有行为，避免边改边丢功能。

任务：

1. 保存本计划书。
2. 为当前主要功能建立功能清单。
3. 建立重构分支。
4. 明确默认模式目标为 `localAndroid`。
5. 暂时保留现有后端调用路径。
6. 不先大规模移动 UI 文件。

交付物：

1. `target.md`
2. `docs/current-behavior.md`
3. `docs/refactor-checklist.md`

退出标准：

1. 目标和非目标清楚。
2. 当前主要功能有列表。
3. 后续阶段可以逐步改，不需要推倒重写。

### 阶段 1：抽象数据源边界

目的：

先让 App 从“直接依赖后端”变成“依赖 CampusGateway 接口”。

任务：

1. 重命名或包装 `CampusBackend` 为 `CampusGateway`。
2. 定义 `CampusRuntimeMode`。
3. 建立两种实现：
   - `SelfHostedCampusGateway`
   - `DirectSchoolCampusGateway` 占位
4. 页面 provider 只依赖 gateway。
5. `ApiService` 移入 self-hosted 实现中。

退出标准：

1. 当前功能仍通过 selfHosted/legacy 后端跑通。
2. localAndroid 模式可以先返回明确的未实现错误。
3. UI 层没有直接依赖 `ApiService`。

### 阶段 2：拆分超大 Provider

目的：

降低重构风险，让每个业务模块独立演进。

任务：

将 `apps\campus_app\lib\utils\providers.dart` 拆分为：

```text
features\auth\auth_providers.dart
features\schedule\schedule_providers.dart
features\grades\grades_providers.dart
features\exams\exams_providers.dart
features\electricity\electricity_providers.dart
features\campus_card\campus_card_providers.dart
features\leave\leave_providers.dart
features\settings\settings_providers.dart
```

同时把纯函数移出：

```text
packages\core\lib\schedule
packages\core\lib\exam
packages\core\lib\time
```

退出标准：

1. provider 文件不再超大。
2. 每个 feature 可独立测试。
3. 页面 import 更清晰。
4. 行为不变。

### 阶段 3：实现本地直连学校系统

目的：

逐步替代后端中转。

优先顺序：

1. 课表。
2. 成绩。
3. 考试。
4. 电费。
5. 校园卡余额。
6. 付款码。
7. 请假。
8. 充值类操作。

原因：

1. 课表是核心功能。
2. 成绩和考试相对低频。
3. 电费和校园卡涉及提醒，需要稳定后再接后台。
4. 付款码和请假 token 更敏感，应放后面。
5. 充值类操作要谨慎，必须单独确认。

任务：

1. 以 `G:\schedule` 的 service 逻辑作为参考。
2. 在 App 端实现 DirectSchool client。
3. 建立解析器测试。
4. 每完成一个模块，就让该模块 localAndroid 模式可用。
5. 保留 selfHosted 模式作为回滚。

退出标准：

1. 不启动 `G:\schedule`，Android 真机可使用核心查询功能。
2. 至少课表、成绩、考试完成直连。
3. 错误提示可读。
4. 后端模式仍可切换。

### 阶段 4：Android 原生后台能力强化

目的：

让小组件、提醒、后台刷新真正独立于 Flutter 页面生命周期。

任务：

1. 梳理当前 Kotlin 小组件和提醒代码。
2. 定义稳定 snapshot。
3. 统一前台和后台写入 snapshot 的方式。
4. 课前提醒注册逻辑从 UI 中剥离。
5. 后台余额提醒增加本地直连支持。
6. 对厂商后台限制增加明确降级策略。

退出标准：

1. App 关闭后，小组件仍能读取最后 snapshot。
2. App 重启后，提醒可恢复。
3. 后台刷新失败不会破坏前台缓存。
4. 用户可以清楚知道哪些权限影响后台能力。

### 阶段 5：自部署后端产品化

目的：

把 `G:\schedule` 从“开发后端”整理为“必须交付的第二产品形态”。它不再只是 App 的历史中转层，而是自部署版的服务核心。

任务：

1. 增加 Dockerfile。
2. 增加 docker-compose。
3. 增加配置模板。
4. 增加 health endpoint。
5. 整理 API 文档。
6. 增加部署说明。
7. 明确隐私和安全边界。
8. 旧接口保留，新接口逐步 v1 化。

退出标准：

1. 新用户可以按文档部署。
2. App 可以配置自部署地址。
3. Web Console 可以请求自部署服务。
4. 后端日志不泄露敏感信息。
5. 自部署服务版拥有独立发布说明。
6. 自部署服务版可以脱离 Android App 独立验收。

### 阶段 6：Web Console

目的：

完成第二产品形态的前端入口，满足技术用户“部署后网页查看”和“任意设备浏览器访问”的需求。

原则：

1. Web Console 不替代 Android App。
2. Web Console 只对接自部署后端。
3. Web Console 不承诺浏览器直连学校系统。
4. Web Console 是自部署服务版的必交付组成部分，不是可有可无的演示页。
5. Web Console 应以实用查询为主，不做营销页，不做复杂后台系统。

功能优先级：

1. 配置后端地址。
2. 登录/会话建立。
3. 查看课表。
4. 查看成绩。
5. 查看考试。
6. 查看电费。
7. 查看校园卡余额。
8. 查看请假状态。

退出标准：

1. 技术用户部署后能通过网页查询。
2. API 错误展示清楚。
3. 不影响 Android 纯前端默认路径。
4. Web Console 可以作为自部署服务版的验收入口。
5. Web Console 至少覆盖课表、成绩、考试、电费、校园卡余额这些核心查询。

---

## 12. 测试策略

### 12.1 Characterization Tests

在大改前记录当前行为。

应覆盖：

1. `Course.fromJson/toJson`
2. `Grade.fromJson`
3. `Exam.fromJson`
4. 学期周次计算。
5. 考试转课程。
6. 课前提醒时间计算。
7. Widget snapshot 生成。
8. API 返回结构解析。

### 12.2 Parser Fixture Tests

本地直连会引入 HTML/JSON 解析器，必须有 fixture 测试。

要求：

1. fixture 必须脱敏。
2. 不提交真实账号、姓名、token、cookie。
3. 每个学校系统页面至少保留一个成功样本和一个异常样本。
4. 页面结构变化时先补 fixture，再改解析器。

### 12.3 Flutter Tests

覆盖：

1. provider 状态流。
2. 错误状态展示。
3. 空数据状态。
4. localAndroid/selfHosted 模式切换。

### 12.4 Android Tests

覆盖：

1. 小组件 snapshot 渲染。
2. 后台任务调度。
3. 通知渠道创建。
4. 开机恢复。
5. MethodChannel 参数兼容。

### 12.5 后端 Tests

覆盖：

1. sessionId 绑定。
2. API 错误码。
3. Controller 集成测试。
4. 缓存行为。
5. 自部署配置加载。

---

## 13. 安全和隐私要求

### 13.1 默认 App 的承诺

默认 Android 纯前端版应能明确承诺：

1. 不提供公共服务器。
2. 不上传用户账号密码到作者服务器。
3. 不上传学校 token 到作者服务器。
4. 不收集课表、成绩、电费、校园卡等个人数据。
5. 所有敏感数据只保存在用户手机本地。

### 13.2 本地存储要求

1. 账号密码：安全存储。
2. cookie/ticket/token：安全存储。
3. 课表缓存：普通本地缓存即可，但不应导出。
4. 错误日志：脱敏。
5. 调试开关：release 默认关闭敏感日志。

### 13.3 自部署说明

自部署版必须说明：

1. 数据由用户自己的服务器处理。
2. 项目方不接触用户数据。
3. 用户应自行保护服务器。
4. 不建议暴露到公网，除非有 HTTPS、鉴权和访问控制。
5. Docker 部署只是降低部署门槛，不代表安全托管。

### 13.4 不应做的事

1. 不内置作者公共后端地址。
2. 不偷偷上传诊断日志中的敏感字段。
3. 不在 Git 中提交真实 cookie/token。
4. 不把自部署服务包装成官方云服务。
5. 不在没有测试的情况下迁移充值、付款码等敏感功能。

---

## 14. 风险清单和缓解策略

| 风险 | 影响 | 缓解策略 |
| --- | --- | --- |
| 学校系统页面结构变化 | 解析失败 | fixture 测试、错误分类、快速修复解析器 |
| 登录需要验证码 | 自动登录失败 | 明确 `CaptchaRequiredFailure`，引导 WebView 手动验证 |
| Android 后台限制 | 提醒不稳定 | 原生 WorkManager、权限引导、降级说明 |
| Dart 和 Kotlin 逻辑重复 | 维护成本增加 | 先复用 Dart，稳定后只把关键后台逻辑迁移原生 |
| Web 端无法直连学校系统 | 网页不可用 | Web Console 只支持 selfHosted |
| 敏感日志泄露 | 隐私风险 | 日志脱敏、release 关闭敏感日志 |
| 本地直连请求太频繁 | 账号或 IP 受限 | TTL 缓存、冷却时间、指数退避 |
| 后端接口旧兼容 | 维护成本 | v1 API 逐步引入，旧接口延迟废弃 |
| 重构范围过大 | 项目失控 | 分阶段，每阶段可回滚 |
| 切换默认模式过早 | 用户功能损坏 | selfHosted/legacy 路径保留到 direct 模式稳定 |

---

## 15. 回滚策略

### 15.1 数据源级回滚

每个功能迁移本地直连时，都保留：

```text
DirectSchoolDataSource
SelfHostedBackendDataSource
```

如果本地直连失败，可以切回 selfHosted。

### 15.2 功能级回滚

不要一次性把所有模块切到 direct。

建议每个模块单独 feature flag：

```text
direct_schedule_enabled
direct_grades_enabled
direct_exams_enabled
direct_electricity_enabled
direct_card_enabled
direct_leave_enabled
```

### 15.3 发布级回滚

1. 每个版本只迁移少量核心功能。
2. 保留上一稳定 APK。
3. 自部署后端接口不随 App 版本强绑定。
4. 数据缓存 schema 升级要可降级或可清空。

---

## 16. 验收标准

### 16.1 Android 纯前端版验收

必须满足：

1. 未启动 `G:\schedule` 后端时，Android 真机可以完成核心功能。
2. App 默认不要求填写服务器地址。
3. 登录材料只保存在本地。
4. 课表、成绩、考试至少可本地直连查询。
5. 电费、校园卡、请假按计划逐步本地直连。
6. 小组件可以展示缓存数据。
7. 后台提醒不依赖页面打开。
8. 日志不输出敏感信息。

### 16.2 自部署服务版验收

必须满足：

1. 后端可独立部署。
2. 提供 Docker 或等价部署方案。
3. 提供配置模板。
4. 提供 API 文档。
5. App 可以选择自部署后端模式。
6. Web Console 可以连接自部署服务。
7. 项目说明明确“不提供公共服务器”。
8. 自部署服务版可以作为独立产品被安装、启动、访问和升级。
9. Web Console 至少能完成核心查询闭环，而不是只有接口调试能力。
10. 后端 API 可以被脚本或任意 HTTP 客户端调用。
11. 自部署服务版有单独的故障排查文档。
12. 自部署服务版的安全边界、敏感数据存储位置和公网暴露风险说明清楚。

### 16.3 工程质量验收

必须满足：

1. `providers.dart` 不再承担所有业务逻辑。
2. 数据源边界清晰。
3. 平台能力边界清晰。
4. 核心算法有单元测试。
5. 解析器有 fixture 测试。
6. 后端模式和本地直连模式可以独立测试。
7. 主要功能有清晰错误分类。

---

## 17. 不建议做的事情

1. 不建议直接删除 `G:\schedule`。
2. 不建议立刻把所有后端 Java 逻辑硬翻译成 Dart。
3. 不建议先重写 UI。
4. 不建议切 BLoC。
5. 不建议上微服务。
6. 不建议在 Android 本地直连和自部署 API 契约稳定前先做 Web Console；但 Web Console 是第二产品形态的必交付组成部分。
7. 不建议一开始就迁移付款码和充值功能。
8. 不建议让 Android 后台任务直接依赖 Flutter 页面状态。
9. 不建议把 selfHosted 模式做成普通 App 用户的默认模式；但必须把 selfHosted 模式做成完整、可验收的第二产品形态。
10. 不建议继续把后端称为普通用户必需组件。

---

## 18. 推荐技能组合

执行这个重构时，适合使用以下 skill 组合：

1. `legacy-modernizer`
   - 负责增量重构路线、风险清单、回滚策略。
2. `architecture-designer`
   - 负责最终系统架构和关键 ADR。
3. `api-designer`
   - 负责 self-hosted API 契约和版本策略。
4. `flutter-expert`
   - 负责 Flutter/Riverpod 侧拆分和实现。
5. `spring-boot-engineer`
   - 负责自部署后端整理。
6. `test-master`
   - 负责测试安全网。

本项目不优先使用：

1. BLoC 强制型 skill，因为当前已是 Riverpod。
2. Microservices 架构 skill，因为当前目标不是拆微服务。

---

## 19. 推荐工作顺序总表

这里的顺序不是说第二产品形态不重要，而是为了降低风险：先建立共享抽象和核心数据契约，再让 Android Local-Only 与 Self-Hosted 两条主线并行推进。

| 阶段 | 名称 | 主线 | 优先级 | 是否改功能 | 主要产出 |
| --- | --- | --- | --- | --- | --- |
| 0 | 冻结目标 | 共享基础 | P0 | 否 | `target.md`、行为清单 |
| 1 | 数据源抽象 | 共享基础 | P0 | 小 | `CampusGateway`、运行模式 |
| 2 | Provider 拆分 | Android 主线 A | P0 | 否 | feature providers |
| 3 | API 契约整理 | Self-Hosted 主线 B | P0 | 小 | v1 API 草案、错误码、响应结构 |
| 4 | 课表本地直连 | Android 主线 A | P0 | 是 | direct schedule |
| 5 | 自部署后端产品化基础 | Self-Hosted 主线 B | P0 | 是 | Docker、配置模板、health、部署文档 |
| 6 | 成绩/考试本地直连 | Android 主线 A | P1 | 是 | direct grades/exams |
| 7 | Web Console 核心查询版 | Self-Hosted 主线 B | P1 | 是 | schedule/grades/exams web |
| 8 | 电费/校园卡本地直连 | Android 主线 A | P1 | 是 | direct balance/card |
| 9 | Android 后台强化 | Android 主线 A | P1 | 是 | native widget/notification |
| 10 | Web Console 完整查询版 | Self-Hosted 主线 B | P1 | 是 | electricity/card/leave web |
| 11 | 请假和 token 刷新 | 双主线 | P2 | 是 | direct leave + self-host leave |
| 12 | 发布和文档闭环 | 双主线 | P2 | 是 | Android 使用文档、自部署手册、故障排查 |

---

## 20. 一句话目标

本次重构的最终目标不是“把 App 改成有两个后端版本”，而是：

```text
项目同时交付两个正式产品形态：
一是默认给普通用户使用的 Android 本地直连客户端，不依赖作者服务器；
二是给技术用户、多端访问和网页访问使用的自部署服务版，包含后端、API、部署文档和 Web Console；
Flutter、Android 原生、数据源、会话、安全存储、自部署后端和 Web Console 都有清晰边界。
```
