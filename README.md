# 隐形水印 · iOS 复刻版

由 `隐形水印.apk`（`com.watermark.app` 1.0，腾讯系 Kotlin 应用）逆向复刻的
SwiftUI iOS 应用。水印算法与原版**位级互通**：安卓打的标 iOS 能查，iOS 打的标
安卓也能查。

## 功能对照

| 原 APK | iOS 复刻 | 说明 |
| --- | --- | --- |
| `AuthSplash` + `LicenseGate` | `ActivationView` | 设备码 + ECDSA 授权码，一机一码 |
| `MainActivity` | `HomeView` | 批量打标 / 批量查标 / 邮箱配置 |
| `EmbedActivity` | `EmbedView` | 多图 × 多 QQ 循环匹配、两种模式、导出 ZIP、发邮件、存相册 |
| `DetectActivity` | `DetectView` | 单图 / 多图 / 压缩包查标 |
| `EmailConfigActivity` | `EmailConfigView` | SMTP 主机、端口、账号、授权码，支持 465 SSL / 587 STARTTLS |
| `DCTWatermark` | `Core/DCTWatermark.swift` | 标准模式，见下 |
| `RobustWatermark` | `Core/RobustWatermark.swift` | 增强模式，见下 |
| `PSDEncoder` / `PSDDecoder` | `Core/PSD.swift` | 平铺 PSD 读写，支持 raw 与 RLE |
| `ZipUtil` | `Core/ZipUtil.swift` | store-only ZIP 读写，防路径穿越 |
| `EmailUtil` (JavaMail) | `Core/EmailUtil.swift` + `SMTPClient.swift` | 自实现 SMTP + MIME |

## 算法参数（逆向自 APK，勿随意改动）

**标准模式** — 76 bit 载荷重复 3 次，写入每个 8×8 块的 Y 通道：

- 16 bit 同步头 `0xAA55`
- 11 位 BCD 数字（左侧补 0）
- 16 bit CRC16-CCITT（多项式 `0x1021`）覆盖前 60 bit
- 系数对：`(4,2)-(2,4)`、`(5,1)-(1,5)`、`(5,3)-(3,5)`，每组把两系数围绕均值拉开 ±6.0
- 检测：3 对中 2 对投票；按 228 bit 窗口滑动 + 多数表决 + 增强表决

**增强模式** — 32 bit 同步头 `0xB52B34D7` + 128 bit ASCII 载荷：

- 160 个 chip，每个复制 32 次，共 5120 个 PN 调制位
- LCG：乘 `6364136223846793005`，加 `1442695040888963407`，取 `state >> 33`
- 嵌入种子 `9172315309759666981`，洗牌种子 `9172315309759740000`
- QIM：`step = 16`、`guard = 8`；bit 0 的目标值被钳制到 `-0.5`（原实现的特性）
- 块顺序洗牌时 LCG **不推进**，因此嵌入与检测的洗牌顺序完全一致
- 检测需至少容纳 5120 个块的图像（约 640×640 以上），否则同步窗口不足

## 授权码：重要

原 APK 校验的是 **ECDSA P-256 / SHA-256 签名**，公钥硬编码在包里。本复刻内置了
同一把公钥，签名逻辑完全一致，**但不含私钥**，所以：

- 面向安卓生成的授权码**不能**直接在 iOS 上用：设备指纹来源不同
  （安卓用 `ANDROID_ID` 的 SHA-256 前 8 字节，iOS 用 `identifierForVendor`）。
- 需要在你的授权码生成器里，把 iOS 应用「软件激活」页显示的**设备码**填进去，
  用同一把私钥重新签名，产出的授权码即可在 iOS 上通过校验。
- 授权码格式：`<base32(13字节载荷)>.<base32(DER 或 raw ECDSA 签名)>`，
  载荷 = 版本(1) + 到期秒(4, 大端) + 设备指纹(8)，到期值 `0xFFFFFFFF` 表示永久。

如果只想本地自用、不走授权流程，把 `AppModel.checkLicense()` 改为直接置
`licenseOK = true` 即可。

## 构建

### 1. 算法自测（无需 Xcode）

```bash
./run_tests.sh
```

已通过的项目：Base32 往返、CRC16、同步头、标准模式往返、增强模式往返、无假阳性、
PSD 往返、ZIP 往返、文件名解析、MIME 构造、授权码容错。

跨平台互通也用 Python 参考实现双向验证过（Python 嵌入 → Swift 检出，
Swift 嵌入 → Python 检出）。

### 2. 构建 iOS 应用

需要 **Xcode + iOS SDK**（当前机器只有 Command Line Tools，没有 iOS SDK，
因此无法在这里直接产出 IPA）：

```bash
open InvisibleWatermark.xcodeproj
```

在 Xcode 中：

1. 选中 `InvisibleWatermark` target → Signing & Capabilities
2. 选择你的 Team（免费 Apple ID 也可，有效期 7 天）
3. 修改 Bundle Identifier 为唯一值（默认 `com.watermark.app`，与他人冲突会被拒）
4. 连接真机或选择模拟器运行

### 一次产出两个未签名 IPA

```bash
./build_all_ipas.sh
```

| 产物 | 用途 | Bundle ID |
| --- | --- | --- |
| `build/InvisibleWatermark.ipa` | 完整功能：激活 + 打标 + 查标 + 邮件 | `com.watermark.app` |
| `build/ActivationTool.ipa` | 授权工具：显示设备码、校验授权码 | `com.watermark.activationtool` |

第二个包用 `ACTIVATION_TOOL` 编译条件切换入口，只保留激活相关界面，供发码方核对。
它**不包含私钥**，所以同样不能签发出授权码，签名必须在授权码生成器侧完成。

两个包都未签名。未签名 IPA 装不进普通 iPhone，需要：

- 用 Sideloadly / AltStore / TrollStore 重签后安装，或
- 在 Xcode 里选免费 Team 直接真机运行，或
- 用你自己的 Development / Distribution 证书重签

### 3. 打包单个 IPA

```bash
TEAM_ID=你的TeamID ./build_ipa.sh
```

产出 `build/InvisibleWatermark.ipa`。未签名的 IPA 无法直接安装到普通设备，
需要用证书重签，或走 Xcode Organizer 导出。

## 常见问题

### App Store 提示「你的 Apple ID 暂时不符合使用此应用程序的条件」

这是 App Store 账号侧的资格校验，与磁盘、系统版本无关。按以下顺序排查：

1. **账号未完成验证**：打开 [appleid.apple.com](https://appleid.apple.com) 检查邮箱/手机号是否已验证，并确认已开启双重认证。
2. **付款方式问题**：App Store → 账户 → 账户设置，确认付款方式有效（部分区域即使下载免费应用也要求有付款方式）。
3. **登录状态陈旧**：App Store 退出登录（菜单栏「商店 → 退出登录」），重启 App Store 后重新登录。
4. **管理式 Apple ID**：学校或公司管理的 Apple ID 无法下载 Xcode，需改用个人 Apple ID。
5. **儿童账号 / 屏幕使用时间限制**：关闭「内容与隐私限制」后重试。

若仍不行，**绕过 App Store**：用同一个 Apple ID 登录
[developer.apple.com/download/all](https://developer.apple.com/download/all/?q=xcode)
下载 `.xip`（免费账号即可，无需付费开发者计划）。若该账号在开发者站点同样被拒，
换一个个人 Apple ID 登录即可。

### 不装 Xcode 直接拿 IPA

仓库里带 `.github/workflows/build-ipa.yml`，在 GitHub 的 macOS runner 上构建：

```bash
./publish_to_github.sh git@github.com:<你的账号>/invisible-watermark.git
```

推送后在仓库的 **Actions → Build IPA → Run workflow**，跑完下载 artifact
`InvisibleWatermark-unsigned-ipa`。注意产物是未签名 IPA，安装到设备仍需重签
（Sideloadly / AltStore / 自己的证书），或直接把工程导入 Xcode 用免费账号真机调试。

## 已知差异

- **WebP**：iOS 无系统编码器，选了 `.webp` 时实际写出 PNG 字节（扩展名保持）。
  原版用 Android 的 WebP 编码器。
- **相册分类**：原版写入 `DCIM/隐形水印/`，iOS 走 PhotoKit，保存到用户相册，
  无法指定自定义相册目录（需要额外相册权限与 `PHAssetCollection` 操作）。
- **文件选择**：iOS 用 `UIDocumentPicker` 而非相册选择器，这样才能同时选 PSD 和 ZIP。
- **大图采样**：原版按最长边 4096 下采样，复刻保持同样阈值。
- **邮件附件**：自实现 SMTP，若服务商要求 OAuth2（而非授权码）则不支持。

## 目录

```
Core/                 与平台无关的算法与工具（macOS 可编译）
  DCT.swift           8×8 正交 DCT / 逆变换
  DCTWatermark.swift  标准模式
  RobustWatermark.swift 增强模式
  RGBAImage.swift     平台无关位图 + CGImage 桥接
  Encoder.swift       PNG / JPEG 编解码与下采样
  License.swift       设备指纹、Base32、ECDSA 校验
  MediaStore.swift    命名规则、目录、保存
  PSD.swift           PSD 读写
  ZipUtil.swift       ZIP 读写
  EmailUtil.swift     SMTP 配置、MIME 构造
  SMTPClient.swift    CFStream 实现的 SMTP 客户端
UI/                   SwiftUI 界面
Tests/CoreTests.swift 自测入口
Resources/            Info.plist、Assets.xcassets
```
