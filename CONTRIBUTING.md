# Contributing

感谢你有兴趣为本项目贡献！以下是参与方式。

## 开发环境

```bash
git clone https://github.com/AAAAxuuuuu/cqjtu-campus-assistant.git
cd cqjtu-campus-assistant
dart pub get
dart run melos bootstrap
```

运行（Mock 模式，无需账号）：

```bash
cd apps/campus_app
flutter run --dart-define=ENV=mock
```

## 提交 PR

1. Fork 本仓库，基于 `main` 创建新分支（如 `feat/xxx` 或 `fix/xxx`）
2. 改动代码，确保通过本地检查：
   ```bash
   dart format .
   cd apps/campus_app && flutter analyze
   cd ../../packages/core && dart test
   ```
3. 提交 commit，格式参考：`feat: 添加 xxx` / `fix: 修复 xxx` / `docs: 更新 README`
4. 发起 Pull Request，描述改动内容与测试方式

## 接入其他学校

本项目通过 `CampusBackend` 接口隔离了学校相关实现。如需接入其他学校：

1. 在 `packages/adapters/` 下新建一个包（参考 `adapters_mock` 的结构）
2. 实现 `CampusBackend` 接口的所有方法
3. 在 `apps/campus_app/lib/utils/providers.dart` 的 `campusBackendProvider` 里按 ENV 切换即可

## 注意事项

- 请勿在代码或 commit 中包含真实服务器地址、账号密码、Token 等敏感信息
- 敏感对接实现请放在私有 adapter 包中，不要提交到本仓库