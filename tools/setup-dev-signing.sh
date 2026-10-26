#!/bin/bash
# 创建稳定的本地代码签名身份 "PureListen Dev"（一次性，可重复运行）。
#
# 为什么需要它：
#   净听用 ad-hoc 签名（`codesign -s -`）时，每次重新构建 cdhash 都会变，
#   macOS 会把旧的「辅助功能」等 TCC 授权判为失效 —— 表现就是"系统设置里开关明明是开的，
#   但 App 一启动/一重新授权就反复弹窗"。换成固定证书后，App 的 designated requirement
#   只跟 bundle id + 证书根哈希有关，重新构建不会再丢授权。
#
# 用法:
#   tools/setup-dev-signing.sh           # 创建（已存在则跳过）
#   tools/setup-dev-signing.sh --force   # 删除旧身份并重建（会让已有授权再次失效）
#
# 生成物保存在 ~/.purelisten-dev-signing/（权限 700），证书/私钥会导入当前用户登录钥匙串。
# 移除：
#   security delete-identity -c "PureListen Dev"
#   rm -rf ~/.purelisten-dev-signing
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="${PURELISTEN_SIGNING_DIR:-$HOME/.purelisten-dev-signing}"
IDENTITY="${PURELISTEN_SIGN_IDENTITY:-PureListen Dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if [ "${1:-}" = "--force" ]; then
    echo "==> 删除旧身份（已有系统授权会失效，需要重新授权一次）"
    security delete-identity -c "$IDENTITY" >/dev/null 2>&1 || true
    rm -rf "$WORK"
fi

if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    echo "✓ 签名身份已存在: $IDENTITY"
    echo "  （如需重建：tools/setup-dev-signing.sh --force）"
    exit 0
fi

echo "==> 生成自签名代码签名证书"
mkdir -p "$WORK"
chmod 700 "$WORK"
cd "$WORK"

cat > openssl.cnf <<'EOF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = PureListen Dev
O = PureListen
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF

if [ ! -f cert.pem ] || [ ! -f key.pem ]; then
    openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
        -keyout key.pem -out cert.pem -config openssl.cnf 2>/dev/null
fi

if [ ! -f pass.txt ]; then
    openssl rand -hex 16 > pass.txt
fi
PASS=$(cat pass.txt)

# macOS 的 security import 只认旧版 PKCS#12 算法（3DES + SHA1 MAC），
# OpenSSL 3 默认的 AES-256/PBKDF2 会报 "MAC verification failed"。
rm -f id.p12
openssl pkcs12 -export -inkey key.pem -in cert.pem -out id.p12 \
    -passout "pass:$PASS" -name "$IDENTITY" \
    -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 2>/dev/null

chmod 600 key.pem pass.txt id.p12

echo "==> 导入登录钥匙串"
if ! security import id.p12 -k "$KEYCHAIN" -P "$PASS" \
    -T /usr/bin/codesign -T /usr/bin/security -A 2>&1 | tail -1; then
    echo "⚠ 导入失败。请确认登录钥匙串已解锁后重试。" >&2
    exit 1
fi

echo "==> 校验身份"
if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    echo "✓ 已创建签名身份: $IDENTITY"
    openssl x509 -in cert.pem -noout -subject -dates
    echo
    echo "build.sh 会自动使用该身份签名；如果当前已安装的是 ad-hoc 版本，"
    echo "替换安装后请在「系统设置 → 隐私与安全性 → 辅助功能」里把「净听」关掉再打开一次。"
else
    echo "⚠ 身份未出现在钥匙串中，请检查 security import 的输出。" >&2
    exit 1
fi
