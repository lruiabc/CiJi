# 词记（CiJi）

面向 Mac 的英语单词库应用，目标可上架 Mac App Store。当前完成 **功能 1：单词库 + 分组 + 发音**。

## 功能（已实现）

- **单条添加**：输入英文 → 查询音标与中文 → 试听发音 → 选择分组 → 入库
- **批量导入**：每行一个单词，自动查词；可统一或按词指定分组
- **分组管理**：新建 / 重命名 / 删除；每组可设容量；单词可随时改组
- **发音按钮**：列表、添加预览、批量预览均可点击喇叭听读音（Google TTS，失败回退系统朗读；支持美音/英音）
- **Google 免费翻译**：无需 API Key；网络失败时可回退本地示例释义

## 环境要求

- macOS 14.0+
- Xcode 15.4+（建议最新稳定版）
- 网络访问（查词与在线发音）

> 本仓库在 Linux 云环境中维护源码；请在 **Mac + Xcode** 上编译运行。

## 打开与运行

1. **务必打开工程文件**（不是单个 `.swift`）：双击 `CiJi/CiJi.xcodeproj`，或用 Xcode → File → Open…
2. 看 Xcode **顶部工具栏**中间：
   - 左侧 scheme 选 **CiJi**（不要选 CiJiTests）
   - 右侧运行目标选 **My Mac**（本机 Mac）
3. 菜单 **Product → Run**，或点工具栏 ▶ 按钮，或 `⌘R`
4. 若 ▶ 是灰色 / `⌘R` 没反应：先点一下左侧蓝色工程图标，确认已打开的是 `.xcodeproj` 而不是 lone 源码文件
5. 本地调试一般**不需要** Apple Developer 账号；若 Signing 报错，在 Target → Signing & Capabilities 里可先不选 Team（工程已用 ad-hoc 签名 `-`）

### 词典数据来源

查词使用 **Google Translate 免费接口**（无需 API Key）：

- 主接口：`clients5.google.com/translate_a/single`（`dict-chrome-ex`）
- 回退：`clients5.google.com/translate_a/t`
- 网络失败时可在设置中开启「本地示例释义」
- 发音优先 Google TTS，失败则回退到系统朗读（AVSpeech）

> 注意：这是非官方免费接口，可能限流或变更；正式上架 App Store 前建议换成 Google Cloud Translation 官方 API。


## 使用提示

| 操作 | 说明 |
|------|------|
| 添加单词 | 工具栏「添加单词」或 `⌘N` |
| 批量导入 | 「批量导入」或 `⇧⌘N`，每行一词 |
| 听发音 | 点击行首 / 预览区的喇叭按钮 |
| 改组 | 选中单词 →「移动到组」，或右键菜单 |
| 新建分组 | 侧栏底部「新建分组」 |

## 查看运行日志

云端环境**看不到**你本机 Mac 的实时日志。请在 Xcode 查看：

1. 运行 App 后打开 **View → Debug Area → Activate Console**（或 `⇧⌘C`）
2. 日志前缀为 `[词记/…]`，批量导入、查词、分组写入都会打印
3. 也可在 macOS「控制台」App 中过滤子系统 `app.ciji.mac`

## 近期变更（功能 1）

1. **查词改为 Google Translate 免费接口**（无需 API Key；失败可回退本地示例）
2. **发音改为 Google TTS**，失败时回退系统朗读
3. **批量导入**：最多 3 路并发、可停止、请求超时约 12 秒
4. **分组选择**：使用 `GroupChoice`，避免 macOS 上 `UUID?` Picker 匹配失败

## 项目结构

```
CiJi/
├── CiJi.xcodeproj
├── CiJi/
│   ├── CiJiApp.swift
│   ├── Models/          # Word、WordGroup、GroupChoice（SwiftData）
│   ├── Services/        # Google 查词、发音、设置、日志
│   └── Views/           # 主界面、添加、批量导入、设置
└── CiJiTests/           # Google 响应解析等单元测试
```

## 下一步（功能 2）

按组抽出单词，用户手动输入中文，系统校验对错——帮助记忆。功能 1 的词库与分组是功能 2 的数据基础。

## 许可证

私有项目；按你的发布需要自行补充。
