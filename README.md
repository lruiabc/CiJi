# 词笺（CiJi）

面向 Mac 的英语单词库应用「词笺」，目标可上架 Mac App Store。当前完成 **功能 1：单词库 + 分组 + 发音**。

## 功能（已实现）

- **单条添加**：输入英文 → 查询音标与中文 → 试听发音 → **可多选分组** → 入库
- **多分组**：同一单词可同时属于多个分组；词库中已有该词时，保存会追加所选分组
- **原型还原**：无论输入 `running` / `went` / `apples` 等，查询结果与入库均使用原型（`run` / `go` / `apple`）
- **音标 (IPA/DJ)**：优先 Free Dictionary IPA，失败则用 Datamuse 发音转 DJ 音标（如 `/ɪnˈtenʃənəl/`）
- **批量导入**：每行一个单词，自动查词；默认/逐词多选分组，并可 **一键批量改组**；已有词追加分组
- **分组管理**：新建 / 重命名 / 删除；每组可设容量；列表中可「加入 / 仅保留 / 移出 / 清空」分组
- **发音按钮**：列表、添加预览、批量预览均可点击喇叭听读音（有道发音，失败回退系统朗读；支持美音/英音）
- **短语支持**：可添加 / 导入多词短语（如 `look forward to`）
- **严格中文判分**：练习须写出完整义项；只写片段（如「使」对「使尴尬」）不算对
- **亮色界面**：浅色纸感 + 青绿点缀为主
- **输入顺序**：词库按用户添加/导入顺序保存与展示，不会被自动重排
- **词库复用**：已有词条再次添加/导入时，直接使用已有音标与中文，不再联网查询
- **有道词典**：公开网页接口，用户无需申请密钥；失败可回退本地示例

## 品牌

- 中文名：**词笺**（读作「词 · 笺」）
- 含义：把单词记在笺纸上，安静地积累词库
- 工程 Target 仍为 `CiJi`，Bundle ID 保持 `app.ciji.mac`

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

查词使用 **有道词典公开网页接口**（与 Gloss 等同类 App 同思路，用户无需 API Key）；音标单独拉取：

- 中文 / 发音：有道 `dict.youdao.com/jsonapi` + `dictvoice`（免费网页接口）
- 音标：优先 [Free Dictionary API](https://dictionaryapi.dev/) 的 IPA；失败则 [Datamuse](https://www.datamuse.com/api/) CMU 发音转 **DJ 音标**
- 网络失败时可在设置中开启「本地示例释义」
- 发音优先有道 dictvoice，失败则回退到系统朗读（AVSpeech）

> 说明：使用有道公开词典接口，开箱即用、无需付费；接口非官方文档保证，若变更可回退本地示例。上架审核时请在隐私说明中写明会联网访问有道词典。


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
2. 日志前缀为 `[词笺/…]`，批量导入、查词、分组写入都会打印
3. 也可在 macOS「控制台」App 中过滤子系统 `app.ciji.mac`

## 近期变更（功能 1）

1. **查词改为有道公开词典接口**（无需 API Key；失败可回退本地示例）
2. **发音改为有道 dictvoice**，失败时回退系统朗读
3. **音标显示**：IPA/DJ（Free Dictionary + Datamuse），不再使用 Google 拼读转写
4. **原型还原**：不规则变化表 + 后缀规则；预览与数据库均存原型
5. **批量导入**：最多 3 路并发、可停止、请求超时约 12 秒；按原型去重
6. **多分组**：`Word` ↔ `WordGroup` 多对多；添加/批量导入支持多选与批量改组
7. **中文可编辑**：词库列表支持行内修改与弹窗编辑中文释义
8. **分组练习**：左右布局；顺序/乱序；每页多词；任一义项正确即得分；可选实时校验（不必先提交）

## 项目结构

```
CiJi/
├── CiJi.xcodeproj
├── CiJi/
│   ├── CiJiApp.swift
│   ├── Models/          # Word、WordGroup、GroupSelection（多对多分组）
│   ├── Services/        # Google 查词、IPA 音标、原型还原、发音、设置、日志
│   └── Views/           # 主界面、添加、批量导入、设置
└── CiJiTests/           # Google 响应解析等单元测试
```

## 功能 2（已实现）：分组练习

- **每页题数可手动输入**，默认等于当前练习范围（分组）的单词总数
- **错题统计**：每轮结束记录答错词数，并累计每个单词的答错次数（词库「错次」列）

- 工具栏「练习」或侧栏分组右键「练习此组」
- 可选 **顺序 / 乱序**，并设置每页同时出示的单词数
- **左右布局**：左侧英文（可听发音），右侧输入中文释义
- **实时校验（可选）**：设置页与答题工具栏可开关；开启后输入即可对照对错，不必先提交；关闭则提交后再显示
- 一词多义时写出 **任一义项** 即可；提交本页后写入成绩并看完整对照
- 结束后显示正确率与错题回顾

## 许可证

私有项目；按你的发布需要自行补充。

## 上架 Mac App Store（美国 · 免费）

工程已准备为 **Version 1.0.0 / Build 7**。云端无法替你上传，请在自己的 Mac 上完成：

### A. Xcode 打包上传
1. `git pull` 后打开 `CiJi/CiJi.xcodeproj`
2. Target **CiJi** → **General** → **App Icons**：确认是 **AppIcon**（`Assets.xcassets/AppIcon.appiconset`，其中 `icon_1024.png` = 1024×1024，对应 512pt @2x）
3. Target **CiJi** → **Signing & Capabilities**
   - 勾选 Automatically manage signing
   - **Team** 选你的 Apple Developer 账号
4. 确认 Capabilities：App Sandbox、Outgoing Connections（Client）
5. **Product → Clean Build Folder**，再 **Product → Archive**（不要用旧 Archive；请上传 Build 7（勿再用已拒的旧构建））
6. 上传前可本机校验图标（把路径换成你的 `.app`）：

```bash
bash CiJi/scripts/verify-app-icon.sh "/path/to/CiJi.app"
```

应看到 `OK: App Store 512 / 512@2x icons are present.`  
Archive 包内也应有 `Contents/Resources/AppIcon.icns`（由 Xcode 从 Asset Catalog 生成，勿再手动拷贝手写 `.icns`）。
7. Organizer → **Distribute App** → **App Store Connect** → **Upload**

### B. App Store Connect 创建应用
1. [App Store Connect](https://appstoreconnect.apple.com) → 我的 App → **+**
2. 平台：**macOS**
3. 名称：可用 `CiJian` / `词笺`（以当时可用名为准）
4. 主要语言：**English (U.S.)**
5. Bundle ID：选 `app.ciji.mac`
6. SKU：例如 `cijian-mac-001`

### C. 定价与销售范围（按你的要求）
1. **定价**：Free（免费）
2. **销售范围**：只勾选 **United States**（不要选其他国家/地区）

### D. 上架资料（最少）
- Mac 截图（建议 1280×800 或 App Store 要求尺寸）
- 英文简介（面向美国区展示；App 内仍可为中文界面，适合在美学习英语的中文用户）
- 分类：Education
- 隐私政策 URL（必填；写明会联网访问有道词典做查词/发音，词库存在本机）
- App 隐私问卷：不收集可识别身份信息；声明联网用途
- 选中刚上传的构建版本 → **提交审核**

### E. 审核备注建议（英文）
说明：免费英语单词本；查词/发音需网络访问 Youdao dictionary endpoints；无需登录；仅美国区免费分发。

