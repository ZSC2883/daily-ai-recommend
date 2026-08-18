# 每日 AI 推荐工具

每天定时自动联网搜索最新的开源 AI 插件 / 工具 / MCP / Claude 技能，桌面弹窗推荐，支持收藏和使用方法查看。

## 前置要求（缺一不可）

1. **Claude Code CLI 已安装并登录**
   - 安装：`npm install -g @anthropic-ai/claude-code`
   - 登录：命令行运行 `claude` 并按提示登录自己的 Claude 账号
   - 验证：命令行运行 `where claude` 能看到路径
2. **Node.js**
   - 安装：`winget install OpenJS.NodeJS.LTS`（或到 https://nodejs.org 下载 LTS 版安装包，双击安装）
   - 验证：新开一个终端运行 `node -v` 能看到版本号

> 推荐内容靠 Claude Code 联网搜索生成，所以必须先装好 Claude Code——用官方账号或国内免费模型都行，配置全流程见下一节。

## Claude Code + ccswitch 安装配置 & 国内模型免费调用全流程

Claude Code 只认 Anthropic 的接口。把接口地址改到国内厂商的「兼容接口」、钥匙换成国内厂商的 API Key，就能用**免费的国产大模型**驱动它，全程不需要 Claude 官方账号。

### 路线 A：官方账号（省心，但要订阅付费）

```bash
npm install -g @anthropic-ai/claude-code
claude    # 首次运行按提示登录 Claude 官方账号
```

### 路线 B：国内模型免费调用（推荐，全程免费）

以**智谱 GLM-4.5-Flash**（免费模型，官方支持 Claude Code）为例：

**第 1 步：安装 Claude Code**（需 Node.js ≥ 18）

```bash
npm install -g @anthropic-ai/claude-code
```

**第 2 步：申请免费 API Key**

1. 打开 https://open.bigmodel.cn ，手机号注册（需实名认证）
2. 右上角头像 → 「API Keys」→ 创建新 Key → **立即复制保存**（只显示一次）

**第 3 步：配置环境变量**（Windows PowerShell 执行，永久生效）

```powershell
[Environment]::SetEnvironmentVariable("ANTHROPIC_BASE_URL", "https://open.bigmodel.cn/api/anthropic", "User")
[Environment]::SetEnvironmentVariable("ANTHROPIC_AUTH_TOKEN", "你的智谱APIKey", "User")
```

配置完**新开一个终端**再往下走。

**第 4 步（推荐）：用 cc-switch 图形界面管理供应商**

手动改环境变量麻烦且一次只能配一家，cc-switch 一键切换、内置 50+ 供应商预设：

1. 到 https://github.com/farion1231/cc-switch/releases 下载 Windows 版，双击安装
2. 打开后选「智谱」，粘贴 API Key，点切换——环境变量自动写好
3. 以后想换 DeepSeek / Kimi / 硅基流动等，界面里点一下就行，Claude Code 无需重启

**第 5 步：验证**

```bash
claude -p "你好，报一下你的型号"
```

能正常回复就通了。**本工具额外依赖联网搜索**，再多验一条：

```bash
claude -p "联网搜一下今天的AI新闻" --allowedTools WebSearch
```

> ⚠️ 如果这条报错或返回空，说明你用的供应商不支持联网搜索（WebSearch），本工具会生成失败——换一家支持的供应商即可。

### 其他免费/低价国内供应商（政策随时会变，以官网为准）

| 供应商 | 免费情况 | 备注 |
|--------|---------|------|
| 智谱 GLM-4.5-Flash | 免费 | 本 README 示例，工具调用优化 |
| 硅基流动 SiliconFlow | 注册送额度，部分小模型免费 | 模型多 |
| 阿里云百炼（通义） | 新用户送额度 | Qwen 系列 |
| DeepSeek | 不免费但极便宜 | 效果好 |

## 部署步骤（3 步）

1. 解压本压缩包到任意目录（如 `D:\MyAITools\01-每日AI推荐`）
2. 双击 `install.bat`
3. 等待跑完（首次生成推荐约 1-2 分钟）

`install.bat` 会自动：检测环境 → 创建两个计划任务（每日定时弹窗 + 登录自启服务）→ 启动本地服务 → 首次生成。

## 使用

- **每天定时**自动弹窗推荐，不点「确定」不消失（当前设定时间见「常用维护」）
- **推荐过的、已收藏的都不再重复推荐**：生成时读 `历史.md` + 收藏清单做排除（提示词排除 + 链接兜底过滤），记录只留档不重推
- **每天固定展示 8 条**：让 AI 出 12 个候选，剔除重复后取前 8；同一天重新生成也保证 8 条全新
- **页面地址**：http://127.0.0.1:8765/
- **输出文件（不堆积）**：
  - `今日推荐.html` —— 唯一展示页面，每天覆盖更新
  - `历史.md` —— 每日记录归档，只保留最近 30 天
  - `收藏.md` —— 你的收藏（页面点 ⭐ 自动写入）
- **重新生成**：页面上点「✦ 重新生成」，或双击 `refresh.bat`

## 常用维护

| 想做什么 | 命令 |
|---------|------|
| 改推荐时间 | `schtasks /Change /TN "DailyAIRecommend" /ST HH:MM` |
| 删除整个工具 | 先删两个任务 `schtasks /Delete /TN "DailyAIRecommend" /F` 和 `schtasks /Delete /TN "DailyAIRecommendServer" /F`，再删整个文件夹 |
| 手动重新生成 | 双击 `refresh.bat` |
| 改历史保留天数 | 编辑 `daily-ai-recommend.ps1` 里 `Update-History` 中的 `30` |

## 文件说明

```
daily-ai-recommend.ps1   主生成脚本（联网搜索 + 归档历史 + 渲染单页）
server.js                本地服务（收藏读写 + 重新生成）
今日推荐.html             唯一展示页面（每日覆盖）
历史.md                  每日记录归档（保留 30 天）
收藏.md                  收藏清单（页面点 ⭐ 写入）
launcher.vbs             弹窗任务无黑窗启动器
server-launcher.vbs      服务无黑窗启动器
install.bat              一键部署脚本
refresh.bat              手动重新生成
```
