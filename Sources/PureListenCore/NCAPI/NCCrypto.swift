import Foundation
import CommonCrypto
import Security

// 网易云音乐 weapi / eapi 请求加密。
// weapi: AES-128-CBC 双重加密 + RSA(raw) 加密随机密钥; eapi: AES-128-ECB + MD5 摘要。
public enum NCCrypto {
    static let weapiPresetKey = "0CoJUm6Qyw8W8jud"
    static let weapiIV = "0102030405060708"
    static let eapiKey = "e82ckenh8dichen8"
    static let eapiDelimiter = "-36cd479b6b5-"
    static let rsaModulusHex =
        "00e0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7b7251" +
        "52b3ab17a876aea8a5aa76d2e417629ec4ee341f56135fccf695280104e0312ec" +
        "bda92557c93870114af6c9d05c4f7f0c3685b7a46bee255932575cce10b424d81" +
        "3cfe4875d3e82047b97ddef52741d546b8e289dc6935b3ece0462db0a22b8e7"
    static let rsaExponentHex = "010001"

    public enum CryptoError: Error {
        case ccCrypt(CCCryptorStatus)
        case sec(OSStatus, String)
        case encoding
    }

    // MARK: - 基础算法

    public static func md5Hex(_ string: String) -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        let bytes = Array(string.utf8)
        CC_MD5(bytes, CC_LONG(bytes.count), &digest)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func aesEncrypt(_ data: Data, key: Data, iv: Data?) throws -> Data {
        precondition(key.count == kCCKeySizeAES128)
        var output = Data(count: data.count + kCCBlockSizeAES128 * 2)
        var moved = 0
        let options: CCOptions = iv == nil
            ? CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding)
            : CCOptions(kCCOptionPKCS7Padding)
        let status = output.withUnsafeMutableBytes { outPtr -> CCCryptorStatus in
            data.withUnsafeBytes { inPtr -> CCCryptorStatus in
                key.withUnsafeBytes { keyPtr -> CCCryptorStatus in
                    if let iv = iv {
                        return iv.withUnsafeBytes { ivPtr -> CCCryptorStatus in
                            CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES128), options,
                                    keyPtr.bindMemory(to: UInt8.self).baseAddress, key.count,
                                    ivPtr.bindMemory(to: UInt8.self).baseAddress,
                                    inPtr.bindMemory(to: UInt8.self).baseAddress, data.count,
                                    outPtr.bindMemory(to: UInt8.self).baseAddress, outPtr.count, &moved)
                        }
                    } else {
                        return CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES128), options,
                                       keyPtr.bindMemory(to: UInt8.self).baseAddress, key.count, nil,
                                       inPtr.bindMemory(to: UInt8.self).baseAddress, data.count,
                                       outPtr.bindMemory(to: UInt8.self).baseAddress, outPtr.count, &moved)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw CryptoError.ccCrypt(status) }
        return output.prefix(moved)
    }

    static func randomSecretKey() -> Data {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".utf8)
        return Data((0..<16).map { _ in chars.randomElement()! })
    }

    // MARK: - RSA (textbook, 无填充: m^65537 mod n)

    private static func derLength(_ length: Int) -> [UInt8] {
        if length < 0x80 { return [UInt8(length)] }
        var bytes = [UInt8]()
        var v = length
        while v > 0 { bytes.insert(UInt8(v & 0xff), at: 0); v >>= 8 }
        return [UInt8(0x80 | bytes.count)] + bytes
    }

    private static func derInteger(_ data: Data) -> [UInt8] {
        var body = [UInt8](data)
        while body.first == 0 && body.count > 1 { body.removeFirst() }
        if body.first! & 0x80 != 0 { body.insert(0, at: 0) }
        return [0x02] + derLength(body.count) + body
    }

    static func rsaPublicKey() throws -> SecKey {
        guard let modulus = Data(hexString: rsaModulusHex),
              let exponent = Data(hexString: rsaExponentHex) else {
            throw CryptoError.encoding
        }
        var content = Data(derInteger(modulus))
        content.append(Data(derInteger(exponent)))
        var der = Data([0x30])
        der.append(Data(derLength(content.count)))
        der.append(content)

        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits: 1024,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(der as CFData, attributes as CFDictionary, &error) else {
            throw CryptoError.sec(Int32((error?.takeRetainedValue() as? NSError)?.code ?? -1),
                                  "SecKeyCreateWithData failed")
        }
        return key
    }

    /// raw RSA: 输入左补零到密钥长度(128字节), 输出 128 字节密文。
    static func rsaRawEncrypt(_ message: Data) throws -> Data {
        let key = try rsaPublicKey()
        let blockSize = SecKeyGetBlockSize(key)
        guard message.count <= blockSize else { throw CryptoError.encoding }
        let padded = Data(repeating: 0, count: blockSize - message.count) + message
        var error: Unmanaged<CFError>?
        guard let cipher = SecKeyCreateEncryptedData(key, .rsaEncryptionRaw, padded as CFData, &error) else {
            throw CryptoError.sec(Int32((error?.takeRetainedValue() as? NSError)?.code ?? -1),
                                  "SecKeyCreateEncryptedData failed")
        }
        return cipher as Data
    }

    // MARK: - JSON 序列化(键序稳定)

    static func jsonString(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let s = String(data: data, encoding: .utf8) else { throw CryptoError.encoding }
        return s
    }

    // MARK: - weapi / eapi

    public static func weapi(_ payload: [String: Any]) throws -> (params: String, encSecKey: String) {
        var body = payload
        body["csrf_token"] = payload["csrf_token"] ?? ""   // 由调用方注入
        let text = try jsonString(body)
        let secretKey = randomSecretKey()

        let enc1 = try aesEncrypt(Data(text.utf8), key: Data(weapiPresetKey.utf8), iv: Data(weapiIV.utf8))
        let enc2 = try aesEncrypt(Data(enc1.base64EncodedString().utf8),
                                  key: secretKey, iv: Data(weapiIV.utf8))
        let params = enc2.base64EncodedString()

        let reversed = Data(secretKey.reversed())
        let encSecKey = try rsaRawEncrypt(reversed).map { String(format: "%02x", $0) }.joined()
        return (params, encSecKey)
    }

    public static func eapi(_ url: String, payload: [String: Any]) throws -> String {
        let text = try jsonString(payload)
        let digest = md5Hex("nobody\(url)use\(text)md5forencrypt")
        let message = url + eapiDelimiter + text + eapiDelimiter + digest
        let enc = try aesEncrypt(Data(message.utf8), key: Data(eapiKey.utf8), iv: nil)
        return enc.map { String(format: "%02X", $0) }.joined()
    }
}

extension Data {
    init?(hexString: String) {
        let chars = Array(hexString)
        guard chars.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(chars.count / 2)
        var index = 0
        while index < chars.count {
            guard let byte = UInt8(String(chars[index...index + 1]), radix: 16) else { return nil }
            bytes.append(byte)
            index += 2
        }
        self = Data(bytes)
    }
}
