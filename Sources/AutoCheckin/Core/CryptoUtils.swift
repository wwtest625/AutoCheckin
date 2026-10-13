import Foundation
import CryptoKit
import CommonCrypto

enum CryptoUtils {
    // MARK: - Trae Constants
    private static let traeURE: [UInt8] = [82,9,106,213,48,54,165,56,191,64,163,158,129,243,215,251,124,227,57,130,155,47,255,135,52,142,67,68,196,222,233,203,84,123,148,50,166,194,35,61,238,76,149,11,66,250,195,78,8,46,161,102,40,217,36,178,118,91,162,73,109,139,209,37]
    private static let traeDRE: [UInt8] = [31,221,168,51,136,7,199,49,177,18,16,89,39,128,236,95,96,81,127,169,25,181,74,13,45,229,122,159,147,201,156,239,160,224,59,77,174,42,245,176,200,235,187,60,131,83,153,97,23,43,4,126,186,119,214,38,225,105,20,99,85,33,12,125]
    
    // MARK: - WorkBuddy Constants
    private static let wbAtRestSecret = "Sik9U5aXhCdwTVEwsEySDOmDoB9r9ntFxHF1fst9LQI="
    private static let wbKey = Data(SHA256.hash(data: wbAtRestSecret.data(using: .utf8)!))
    
    // MARK: - Trae Decryption
    static func decryptTraeAuth(b64Text: String) throws -> [String: Any]? {
        guard let data = Data(base64Encoded: b64Text) else { return nil }
        let hdrLen = 6
        let keyLen = 32
        let hmacLen = 64
        
        guard data.count > hdrLen + keyLen + hmacLen else { return nil }
        
        let keyBytes = data.subdata(in: hdrLen..<(hdrLen + keyLen))
        let sha = SHA512.hash(data: keyBytes)
        
        var xor = [UInt8](repeating: 0, count: traeURE.count)
        for i in 0..<traeURE.count {
            xor[i] = traeURE[i] ^ traeDRE[i]
        }
        
        var combined = Data(sha)
        combined.append(contentsOf: xor)
        let h = Data(SHA512.hash(data: combined))
        
        let aesKey = h.subdata(in: 0..<16)
        let iv = h.subdata(in: 16..<32)
        let cipherText = data.subdata(in: (hdrLen + keyLen)..<data.count)
        
        var decrypted = Data(count: cipherText.count + kCCBlockSizeAES128)
        var numBytesDecrypted: size_t = 0
        
        let status = aesKey.withUnsafeBytes { keyBuf in
            iv.withUnsafeBytes { ivBuf in
                cipherText.withUnsafeBytes { cipherBuf in
                    decrypted.withUnsafeMutableBytes { decBuf in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBuf.baseAddress, 16,
                            ivBuf.baseAddress,
                            cipherBuf.baseAddress, cipherText.count,
                            decBuf.baseAddress, decBuf.count,
                            &numBytesDecrypted
                        )
                    }
                }
            }
        }
        
        guard status == kCCSuccess else { return nil }
        decrypted.count = numBytesDecrypted
        guard decrypted.count > hmacLen else { return nil }
        
        let payload = decrypted.subdata(in: hmacLen..<decrypted.count)
        return try JSONSerialization.jsonObject(with: payload) as? [String: Any]
    }
    
    // MARK: - WorkBuddy Decryption
    private static func wbAad(suite: UInt32, keyId: String) -> Data {
        var data = Data()
        data.append(contentsOf: "WB-AAD\0".utf8)
        data.append(0x01)
        
        let tag = "WBEV1".data(using: .utf8)!
        var tagLen = UInt32(tag.count).bigEndian
        data.append(Data(bytes: &tagLen, count: 4))
        data.append(tag)
        
        let sym = "sym-v1".data(using: .utf8)!
        var symLen = UInt32(sym.count).bigEndian
        data.append(Data(bytes: &symLen, count: 4))
        data.append(sym)
        
        var suiteBig = suite.bigEndian
        data.append(Data(bytes: &suiteBig, count: 4))
        
        let kid = keyId.data(using: .utf8)!
        var kidLen = UInt32(kid.count).bigEndian
        data.append(Data(bytes: &kidLen, count: 4))
        data.append(kid)
        
        data.append(2) // field = 2
        data.append(0)
        data.append(0)
        
        return data
    }
    
    static func decryptWbField(value: Any) throws -> String? {
        if let str = value as? String {
            return str
        }
        guard let dict = value as? [String: Any],
              dict["$wbEncrypted"] as? Int == 1,
              let envelopeB64 = dict["envelope"] as? String,
              let envData = Data(base64Encoded: envelopeB64),
              let env = try? JSONSerialization.jsonObject(with: envData) as? [String: Any],
              let keyId = env["keyId"] as? String,
              let suite = (env["suite"] as? UInt32) ?? (env["suite"] as? Int).map({ UInt32($0) }),
              let nonceB64 = env["nonce"] as? String,
              let nonceData = Data(base64Encoded: nonceB64),
              let ctB64 = env["ciphertext"] as? String,
              let ctData = Data(base64Encoded: ctB64),
              let tagB64 = env["authTag"] as? String,
              let tagData = Data(base64Encoded: tagB64) else {
            return nil
        }
        
        let aad = wbAad(suite: suite, keyId: keyId)
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ctData, tag: tagData)
        let key = SymmetricKey(data: wbKey)
        let decrypted = try AES.GCM.open(box, using: key, authenticating: aad)
        return String(data: decrypted, encoding: .utf8)
    }
}
