# CQJTU Hub

重庆交通大学校园助手，当前主打 Android 端使用体验。  
仓库采用 Flutter monorepo 结构，默认运行模式为学校系统直连，兼容可选的 self-hosted 后端接入方式。

![CI](https://github.com/AAAAxuuuuu/cqjtu-campus-assistant/actions/workflows/ci.yml/badge.svg)

## Current Release

- App version: `1.0.0`
- Flutter package version: `1.0.0+16`
- Current branch baseline: `main`

## What It Does

### 教务与学业

- 课表查询与多学期切换
- 周次导航、学期周数设置、周日起始日切换
- 成绩查询、成绩明细、GPA / 均分 / 排名汇总
- 考试安排查询，支持考试时间、考场、座位和准考证展示
- 培养计划查询
- 学业情况卡片与学业情况页，联动培养计划数据展示学分进度

### 校园生活

- 宿舍电费余额查询与充值
- 校园卡余额查询
- 动态付款码与支付宝充值跳转
- 请假申请 WebView 入口

### 在线系统

- 邮箱服务入口
- 课程评价入口
- 通用校园服务 WebView，支持统一认证页面自动填充

### Android 后台能力

- 课前提醒
- Android 桌面小组件
- 电费 / 校园卡余额阈值提醒
- WorkManager 后台检查与通知冷却

## Runtime Modes

### `localAndroid`（默认）

App 直接访问学校系统完成课表、成绩、考试、电费、校园卡等数据获取。  
这是普通用户的默认路径，不依赖公共后端。

### `selfHosted`

App 可切换到自部署后端模式：

```bash
flutter run --dart-define=ENV=selfHosted --dart-define=BASE_URL=http://127.0.0.1:8080
```

说明：
当前仓库只包含 Flutter App 和共享 packages。  
self-hosted 后端服务不在这个仓库里。

## Repository Layout

```text
apps/
  campus_app/      Flutter Android app

packages/
  core/            纯模型、时间计算、业务工具
  data/            数据网关、直连学校系统、自部署接入
  platform/        凭据存储、后台任务、通知、小组件支持
```

## Development

### Prerequisites

- Flutter stable
- Dart SDK matching Flutter
- Android Studio or VS Code

### Bootstrap

在仓库根目录执行：

```bash
dart pub get
dart run melos bootstrap
```

### Run

```bash
cd apps/campus_app
flutter run
```

### Build Release APK

```bash
cd apps/campus_app
flutter build apk --release
```

### Analyze

```bash
dart format --set-exit-if-changed .
cd apps/campus_app && flutter analyze --no-fatal-infos
cd ../../packages/core && dart analyze
cd ../data && dart analyze
cd ../platform && dart analyze
```

## Project Notes

- 当前 UI 和数据结构已经从早期集中式 provider 迁移到按功能拆分的 feature providers
- 数据层已抽象为统一 `CampusGateway`
- 服务页已整合学业情况、培养计划、成绩、考试、电费、请假、邮箱和课程评价入口
- 会话恢复、缓存复用和后台刷新逻辑已经独立到 `session` / shared cache 体系

## Security

- 账号密码使用本地安全存储
- 不依赖公共服务器即可运行默认能力
- 敏感会话信息仅保存在本地设备

## Compliance

本项目仅供学习与个人使用。  
使用者需要自行遵守学校系统使用规范与相关规定。

## License

Apache-2.0
