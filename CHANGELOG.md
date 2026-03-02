# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [0.1.0] - 2025-03-02

### Added
- 课程表：教务账号登录后拉取课表，周历可视化，多学期切换，按周导航
- 课前 15 分钟本地推送提醒
- 电费监控：寝室余额查询、自定义预警阈值、WorkManager 后台轮询（白天 / 夜间降频）
- 校园卡：余额查询、消费二维码（动态 Token）、跳转支付宝充值
- 成绩：历史学期查询，GPA / 均分 / 排名汇总
- 考试安排：时间 / 考场 / 座位号 / 准考证号
- Riverpod 分层状态管理，统一 AsyncValue 错误处理
- monorepo（melos）：core / data / platform / adapters_mock 分层
- Mock 模式：无需账号一键体验
- GitHub Actions CI：analyze + format
- 单元测试：Course / DormRoom / Grade / Exam 模型 + 轮询策略