# 稳定代码签名（开发用）

净听构建时优先使用 `PureListen Dev` 稳定签名，找不到该身份才回退到 ad-hoc（`codesign --sign -`）。ad-hoc 在 macOS 上带来一个副作用：

- 每次重新构建，二进制的 **cdhash** 都会变化；
- 「隐私与安全性 → 辅助功能」等 TCC 授权记录的是**签名要求**（designated requirement）；
- ad-hoc 签名的要求里带着 cdhash，重建后旧授权不再匹配 —— 系统设置里开关看着是开的，
  但 App 每次重新请求权限都会重新弹窗。

`tools/setup-dev-signing.sh` 会创建一个固定的自签名证书 **PureListen Dev**。用它签名后：

```
designated => identifier "com.purelisten.app" and certificate root = H"2494fbd8…"
```

要求只与 bundle id 和证书根哈希有关，**重新构建不会变**。因此辅助功能授权可以一直保留
（我们已在 macOS 27 上用 `codesign --verify -R` 验证该要求能正常评估）。

## 一次性配置

```bash
tools/setup-dev-signing.sh        # 已存在则跳过；--force 重建（会再丢一次授权）
```

脚本做的事：

1. 在 `~/.purelisten-dev-signing/`（权限 700）生成 RSA-2048 自签名证书与私钥；
2. 用旧版 PKCS#12 算法（3DES + SHA1 MAC）打包并导入登录钥匙串（`-A`：允许 codesign 无提示使用）；
3. 校验 `security find-identity -p codesigning` 能看到 `PureListen Dev`。

之后 `./build.sh` 会自动优先使用该身份签名；**找不到时自动回退 ad-hoc** 并提示。
可用环境变量覆盖身份名：

```bash
PURELISTEN_SIGN_IDENTITY="My Cert" ./build.sh
```

## 从 ad-hoc 切换到稳定签名后

签名要求变了，**需要重新授权一次**（之后 rebuild 不再丢）：

1. 重新 `./build.sh`，脚本会备份旧版并保留数据安装到 `/Applications/净听.app`；
2. 净听 → 设置 → 播放保护 → 点「去授权」；
3. 系统设置 → 隐私与安全性 → 辅助功能 → 把「净听」**关掉再打开**；
4. 回到净听，几秒内自动接管媒体键（App 内会静默轮询权限变化）。

## 安全说明

这是**本地开发用**的自签名证书，只用于让本机 macOS 识别同一个 App：

- 私钥与证书在 `~/.purelisten-dev-signing/`（key.pem 权限 600），并导入登录钥匙串；
- 证书**没有**加入系统信任根（`security add-trusted-cert`），因此不会被当作可信 CA；
- 不要把这个目录或 `id.p12` / `pass.txt` 提交到仓库（已在仓库外）。

## 移除

```bash
security delete-identity -c "PureListen Dev"
rm -rf ~/.purelisten-dev-signing
```

移除后 `./build.sh` 会回退 ad-hoc 签名，App 照常可用，只是重新构建后需要重新授权辅助功能。
