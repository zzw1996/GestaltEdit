# 下一步功能候选（v1.6 提案）

> 基线：`main@cf586f8`（v1.5 全部落地）。候选来源：仓库内 `docs/FEATURE-IDEAS.zh-CN.md` 的未完成项、GestaltX v1.0.1 README、Nugget README、上游 GestaltEdit README 的功能对照，以及各项目 issue 里反复出现的用户诉求。
> 原则：只收「本机改 MobileGestalt.plist 能实现」或「纯应用层能力」的项；跨域改 SpringBoard prefs / daemons / PosterBoard 的一律单列，不进预设列表。

---

## 1. 与外部工具的功能差（截至本次调研）

| 能力 | Nugget | GestaltX | 本 app | 差距性质 |
|---|---|---|---|---|
| 区域码 + 销售区域分离、多地区预设 | 有（US/区域限制） | **有（US/CN/HK/TW/JP/UK 双维度）** | 只有 US AI + 只读面板 | **真差距** |
| 整份 plist 本地导入导出 | 无（走电脑） | 有 | 仅备份导入/分享 | 真差距（小） |
| Date 值类型编辑 | 无 | 有 | 无（7 类型） | 真差距（小） |
| 写入历史/操作日志页 | 无 | 有（exploit 阶段日志） | 只有诊断 + 最后错误 | 真差距 |
| 预设搜索 / 收藏 / 适用性过滤 | GUI 分类 | 分类 | 分类（29 项，无搜索） | 中等 |
| Shortcuts / URL Scheme / App Intents | 无 | 无 | 无 | 空白位 |
| 多语言 | 21 种 | 7 种 | 2 种（en/zh-Hans） | 差距 |
| 机型伪装（身份字符串） | 有 | 有 | **有（本批新增）** | 已追平（不含 DeviceClass） |
| 逐键 diff / 选择性恢复 / 撤销 | 无 | 有 | **有** | 已追平 |
| 实验键分组 + 验证记录 | 无 | 有（新键表） | **有（本批新增）** | 已领先 |

结论：**MG 预设层面已经没有缺口，剩下的可加项集中在「区域语义」「编辑完备性」「可观测性与自动化」「本地化/合规」四块。**

---

## 2. 第一批（建议做，低风险、收益直接）

### N1. 区域设置器（RegionCode + 销售区域分离）

- **依据**：GestaltX README「Presets：Independent region-code options、sales-region options」明确把两个维度拆开：Region Code 决定 `RegionCode`，Sales Region 决定销售后缀；并支持 US / 中国 / 香港 / 台湾 / 日本 / 英国。Nugget 的「Disable Region Restrictions」用的是 `h63QSdBCiT="US"` + `zHeENZu="LL/A"`。
- **本 app 现状**：只有「Siri AI（US 区域）」一条路径，区域面板只读。
- **设计**：
  - 面板给两个独立 Picker：`RegionCode`（`h63QSdBCiT`）与 `RegionInfo`（`zHeENZu`，形如 `LL/A`）。
  - 常用组合：US `LL / LL/A`、中国 `CH / CH/A`、香港 `ZP / ZP/A`、台湾 `TA / TA/A`、日本 `J / J/A`、英国 `B / B/A`。
  - 允许只改其一（例如只关快门声只改 RegionCode，保留原销售区域）。
  - 写入走现有预览 + 备份 + 校验链路；首次读取时把原始区域值快照下来，提供「还原原始区域」。
- **风险**：区域与机型绑定（监管型号 `97JDvER…` 是否需要同步）语义未统一，需按 `docs/FEATURE-IDEAS.zh-CN.md` §4.2 先做一次真机实测再定默认组合；否则会出现「区域改了但功能没变」。
- **工作量**：面板 + 快照 + 预设表，约半天。

### N2. 预设搜索 / 收藏 / 适用性过滤

- **依据**：`docs/FEATURE-IDEAS.zh-CN.md` §3.2 L 明确列出；29 项预设已经超过一屏可扫的范围。
- **设计**：
  - Tools 顶部搜索框（按标题/说明/键名匹配）。
  - 星标收藏置顶，存 UserDefaults。
  - 适用性过滤：AOD 类在非 OLED 机型标「本机可能不适用」、相机控制在非 iPhone 16 系列标灰、iPadOS 模式在 iPad 上标「已是 iPad」。依据现有的 `AIRegionProfile` 机型表 + 修订后营销名推导，不新增外部数据。
  - 只做提示与排序，不隐藏（避免用户以为功能丢了）。
- **风险**：机型推断可能误判（改过机型伪装后），需以真实 `0+nc…` 为准并在 UI 注明。
- **工作量**：约半天。

### N3. 写入历史 / 操作日志页

- **依据**：GestaltX README「Logs & respring：Actual exploit-stage logs and manual NeoSpring respring」；本 app 只有诊断页 + `lastError`。
- **设计**：
  - 每次写入记录：时间、来源（预设/字段/恢复/身份/伪装）、改动键数、备份文件名、结果（成功/校验失败已回滚/写失败）、耗时。
  - 保留最近 50 条，存 JSON；页面可查看、按结果筛选、一键分享。
  - 与现有 `BackupChange` 打通，点某条可跳到对应备份。
- **风险**：无写入风险；注意日志不落敏感内容（当前只记键名与结果）。
- **工作量**：约一天。

### N4. 整份 plist 导入 / 导出（当前编辑对象）

- **依据**：GestaltX「local plist import/export」。
- **设计**：
  - Fields 工具栏加「导出当前文件」（分享 `.plist`）与「从文件载入到编辑器」（不直接写入系统，先载入到内存供预览）。
  - 载入时校验顶层类型与 `CacheExtra` 存在、大小上限（沿用备份导入的 8MB 限制）。
  - 与「恢复备份」区分：恢复是写系统，载入只是编辑内存。
- **风险**：用户可能误以为载入即生效，需明确文案 + 「未写入」徽标。
- **工作量**：约半天。

---

## 3. 第二批（中等收益，需要设计取舍）

### N5. 字段编辑器支持 Date / 无损容器编辑

- **依据**：GestaltX 支持 Date 类型；`docs/FEATURE-IDEAS.zh-CN.md` §2.2 #17 指出当前数组/字典用 JSON 往返，遇到 `Data`/`Date` 会失败或破坏。
- **设计**：
  - 值类型增加 `.date`（DatePicker 编辑）。
  - 容器（array/dict）改由 **XML plist 文本**编辑与校验，而不是 JSON；解析失败给出行列提示。
  - 未知类型（UID 等）只读展示，不参与写入。
- **风险**：XML 编辑框对普通用户偏硬核，需保留「只读 + 复制」模式；解析器需严格，避免写入半成品。
- **工作量**：1–2 天。

### N6. Shortcuts / URL Scheme / App Intents

- **依据**：`docs/FEATURE-IDEAS.zh-CN.md` §3.2 O。
- **设计**：
  - `gestaltedit://apply?preset=<id>`、`gestaltedit://backup`、`gestaltedit://restore-latest`、`gestaltedit://diagnostics`
  - App Intents：应用自定义预设、备份当前、导出诊断报告。
  - 所有 Intent 复用 ViewModel 的 `requestWrite` 链路（含预览确认策略：Intent 场景下改为「必须参数确认风险」或直接拒绝高风险项）。
- **风险**：自动化绕过确认是这条功能的主要风险。建议：**Intent 只允许低风险预设 + 自动备份**，高风险（iPadOS 模式、内部安装、身份伪装、区域）仍要求前台确认。
- **工作量**：2–3 天。

### N7. 本地化扩展：繁体中文 + 日语

- **依据**：GestaltX 支持 zh-Hant-TW / zh-Hant-HK / vi / ru / fa；本 app 只有 en + zh-Hans。
- **设计**：优先 `zh-Hant`（台湾用词与大陆差异需人工校对，不能简体转繁体直出）与 `ja`。同步补 accessibilityLabel 与格式化字符串。
- **风险**：低；主要是人工校对成本。
- **工作量**：每种语言约半天（不含审校）。

### N8. 关于页 / 开源许可 / 版本一致性

- **依据**：`docs/FEATURE-IDEAS.zh-CN.md` §2.3 #33（LICENSE 与 README 表述不一致、需附 `worse_query` GPL 声明）；#11（`MARKETING_VERSION` 与 release 不一致）。
- **设计**：About 页列出致谢（Nugget / worse_query / NeoSpring / GestaltX）与许可证；版本号由 tag 注入或构建脚本写入，设置页显示真实版本 + build。
- **风险**：无功能风险，属合规与可维护性。
- **工作量**：半天。

---

## 4. 第三批（能力扩展，须先解决前置问题）

### N9. 机型伪装 DeviceClass 联动（iPad ↔ iPhone 类别）

- **现状**：本 app 只改身份字符串（产品型号/监管型号/营销名），主板与 CPU 为可选同步；**不改 DeviceClass**。
- **依据**：Nugget 的 SpoofModel 列表包含 iPad 目标，并配合 DeviceClass 才真正切换布局；本 app 已有 iPadOS 模式走 CacheData 精确偏移的另一条路径。
- **风险**：极高。改 DeviceClass 等于把 iPhone 变成「iPhone 跑 iPad 布局」，与现有 iPadOS 模式路径冲突，可能双写导致 SpringBoard 崩溃。
- **建议**：**不做**，或在 iPadOS 模式内部作为高级选项并强制互斥。需要真机验证计划（至少 2 机型 × 2 系统版本）后再议。

### N10. 扩展 AI 解锁到 eligibility 文件

- **依据**：Nugget 的 AI Enabler 实际要改 `/var/db/eligibilityd/eligibility.plist` 等；`docs/FEATURE-IDEAS.zh-CN.md` §3.3 明确这超出当前 MG 定位。
- **判断**：不建议纳入。可作为独立「偏好文件编辑器」立项，涉及新的文件域与合规风险。

### N11. SpringBoard / 状态栏 / PosterBoard 定制

- **依据**：Nugget 的功能大半在这些域（状态栏文字、锁屏脚注、壁纸动画、daemon 管理）。
- **判断**：与「最小、可回退的 MG 编辑器」定位冲突，且 iOS 27 上 Nugget 自述「很可能导致数据丢失」。**不做**。

### N12. CacheData 结构化补丁 UI（布尔选项通用化）

- **依据**：Nugget `MobileGestaltCacheDataTweak` 用固定 slice 偏移；本 app 的 iPadOS 模式已用元数据精确偏移。
- **判断**：可做「只读解析 + 已知补丁列表」，不做任意偏移编辑。优先级低，等 iPadOS 26.2+ 封堵问题定性后再评估。

---

## 5. 关于「iOS 26 是否还支持」的前置风险（影响所有功能）

- 上游 README 现在写的是 **iOS / iPadOS 27 beta 1–4**；GestaltX README 明写「iOS 26.x 不支持本机 MobileGestalt 访问，SystemGroup 访问需要 iOS 27」；Nugget 明写「iOS 26.2+ 不再支持 MG 与 AI Enabler」。
- 本 app 的 `IPHONEOS_DEPLOYMENT_TARGET` 是 26.0，实测在你的设备上可读写——说明当前路径（App Group + worse_query）在你的系统版本上仍成立，但这与上游/同类的公开说明不一致，存在**系统版本或签名方式差异**。
- **建议**：把「能力探测 + 版本事实」做成诊断页一级信息（已有部分），并在 README 里按实测写「已验证版本」，不要复制上游的 27 说法。这项不是新功能，但会决定后续所有功能能否被用户用上。

---

## 6. 建议排期

| 批次 | 内容 | 预计 |
|---|---|---|
| v1.6 | N1 区域设置器、N2 预设搜索/收藏/适用性、N4 整份导入导出 | 2 天 |
| v1.7 | N3 写入历史日志、N5 Date/无损容器、N8 关于页与版本一致性 | 3 天 |
| v1.8 | N6 Shortcuts/Intents（低风险白名单）、N7 繁体+日语 | 3–4 天 |
| 待定 | N9 / N10 / N11 / N12（需产品决策与真机验证计划） | — |

---

## 7. 需要你先定的三件事

1. **区域语义**：RegionCode 与 Sales Region 是否按 GestaltX 的双维度模型做？若做，需要你在一台真机上实测「只改 RegionCode」与「两者同改」的效果差异（这是唯一无法靠代码推断的部分）。
2. **自动化边界**：Shortcuts/Intents 是否接受「只放行低风险预设」这一限制？否则自动化会成为绕过风险确认的后门。
3. **多语言优先级**：繁体（台湾用词）与日语，先做哪个？
