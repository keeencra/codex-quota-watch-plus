# DeepSeek API 账户余额

手机首页的「账户余额 → DeepSeek」、手表总览下方的 DeepSeek 卡片，以及手机桌面小号／中号小组件均可显示账户余额。点开可查看各币种的总余额、充值余额、赠送余额、API 可用状态与采集时间。手表仍保留原来的三页滑动结构。

数据来自 [DeepSeek 官方 GET /user/balance](https://api-docs.deepseek.com/api/get-user-balance/)。这是开放平台 API 账户余额；人民币和美元分别显示，不兑换或相加，不是 Codex 订阅额度。

## 界面展示

以下为本项目余额详情组件在隔离的 iPhone／Watch 模拟器宿主中渲染的截图，使用虚构余额演示；不是个人账户数据，也不代表真机验收。

| 手机余额详情 | 手表余额详情（可滚动） |
| --- | --- |
| <img src="assets/gallery/v3.0.0/iphone-balance-pro-ok.jpg" width="250" alt="手机 DeepSeek 双币种余额详情，虚构演示数据"> | <img src="assets/gallery/v3.0.0/watch-balance-pro-ok.jpg" width="220" alt="手表 DeepSeek 余额详情首屏，虚构演示数据"> |

### 手机小组件

下图为小号、中号两套布局，使用实际小组件视图在模拟器宿主内按固定尺寸渲染，非桌面截图；余额为虚构演示数据。

<img src="assets/gallery/v3.0.0/iphone-widgets-pro-ok.jpg" width="360" alt="v3.0.0：已配置与未配置 DeepSeek 的小号、中号组件演示">

小组件自动按配置选择独立维护的布局：

- **未配置 DeepSeek／旧版快照没有该字段**：Codex 专用布局，保留原有百分比、进度条、重置时间，中号保留今日 token 用量图；不会显示空白 DeepSeek 区域。
- **已配置 DeepSeek**：显示 Codex＋DeepSeek；小号将留白分布在各内容区之间，保留 Codex 进度条。
- **已配置但零余额或查询失败**：继续使用双余额布局，显示真实零值或错误状态，不因临时失败切换版式。

## 在 Mac 配置

创建自己的 [DeepSeek API Key](https://platform.deepseek.com/api_keys)，在项目目录运行：

```bash
python3 scripts/configure-deepseek.py
```

按提示粘贴密钥并回车，输入不显示字符。密钥保存为本用户的 `~/Library/Application Support/CodexQuotaWatch/deepseek-api-key`，权限为 `600`，不写入仓库、手机、手表或小组件。也支持 Mac 服务环境变量 `DEEPSEEK_API_KEY`，该变量优先于文件；不要将真实值提交到 GitHub。

更新 Mac 后端并重启额度服务，再使用自己的签名更新 iPhone／Watch App。已有配对与 HTTPS 地址无需重新配置。配置或更换文件后，在手机首页点刷新；无需重启服务即可读取新密钥。

## 刷新与异常

- 余额随原 `/watch` 认证快照刷新、缓存及同步；支持手机转发和手表通过已配置 HTTPS 直接访问。
- Mac 仅向固定官方地址发送密钥，不跟随重定向。查询有超时限制，失败不影响 Codex 额度返回。
- 金额使用十进制字符串传递，保留精度；币种分行显示。小组件只去除末尾无意义的零，不四舍五入或换算。
- 未配置、密钥失效、网络错误均明确提示，不当作零余额。全链路离线时可能显示上次快照，详情页显示原余额采集时间；“上次采集”不代表实时扣费结果。
- 老版 Mac 不含余额字段时提示更新服务；新版客户端能继续读取原 Codex 数据。旧版客户端可忽略新增字段。
- 不增加模型调用或充值操作，不向 Bark／ntfy 推送余额或密钥。手机桌面小号／中号小组件也显示各币种总余额，沿用小组件后台及手动刷新；小号保留额度百分比及分段进度条，中号保留额度与今日 Tokens。
