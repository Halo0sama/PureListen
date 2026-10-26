# PureListen 开发约定

- 用户已要求每次新版都安装到 `/Applications/净听.app`，执行保留数据的替换升级；无需再次确认安装。
- 使用 `./build.sh` 完成构建和安装，或用 `bash tools/install-app.sh` 安装已验证的 `dist/净听.app`。
- 升级只替换应用包；保留登录信息、UserDefaults、WebKit 资料及歌曲缓存。安装前保留旧应用备份，失败时恢复旧包。
- 沿用 `com.purelisten.app` 和现有稳定签名身份，避免无故改变授权要求。
- 用户明确只要求检查构建、不安装时，使用 `PURELISTEN_NO_INSTALL=1 ./build.sh`。
