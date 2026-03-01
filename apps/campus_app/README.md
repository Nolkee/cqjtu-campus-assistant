# CQJTU Campus Assistant

重庆交通大学（CQJTU）校园生活助手，基于 **Flutter + Riverpod** 开发（当前以 Android 为主）。

## Features

### 课程表
- 教务账号登录后拉取课表
- 周历可视化展示：多学期切换、按周导航
- 课前 15 分钟提醒（本地通知）

### 电费监控
- 寝室电量查询与充值
- 自定义余额预警阈值，余额不足推送通知
- 后台轮询：白天高频 / 夜间降频（WorkManager）

### 校园卡
- 校园卡余额查询
- 消费二维码（动态 Token）
- 跳转支付宝充值

### 成绩与考试
- 历史学期成绩查询：GPA / 均分 / 排名汇总
- 当前与历史考试安排：时间 / 考场 / 座位号 / 准考证号

## Highlights
- Riverpod 分层状态管理，统一异步状态（AsyncValue）与错误处理
- WorkManager 后台任务：定时轮询 + 夜间降频 + 通知冷却，降低打扰与耗电
- 本地通知封装：课前提醒、阈值提醒，适配 Android 权限与通知渠道配置
- 学期推算与周次计算结果持久化：重启 App 不丢失

## Getting Started

### 环境
- Flutter stable
- Android Studio / VS Code

### 运行（开发）
```bash
flutter pub get
flutter run
```

## Backend Configuration (Optional)

本项目支持通过 `--dart-define` 配置后端地址：

```
flutter run --dart-define=ENV=prod --dart-define=BASE_URL=http://127.0.0.1:8080
```

打包 release：

```
flutter build apk --release --dart-define=ENV=prod --dart-define=BASE_URL=http://127.0.0.1:8080
```

## Compliance & Security

- 不收集、不上传用户账号密码
- Token 等敏感信息仅本地存储
- 如学校提供官方 API，优先使用官方接口
- 本项目仅供学习交流，使用者需自行遵守学校相关规定

## Roadmap

-  monorepo + melos：core/data/platform/adapters 分层
-  Mock 模式一键体验（无账号可运行）
-  单元测试：学期推算 / 提醒时间 / 轮询策略
-  CI：analyze + test + format

## License

Apache-2.0