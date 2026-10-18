import Foundation

struct CoreError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

final class RustCore {
    static let shared = RustCore()

    private let queue = DispatchQueue(label: "com.jinoxide.musicfox.core", qos: .userInitiated)

    private init() {}

    func call<T: Decodable>(_ command: String, _ payload: [String: Any] = [:], as type: T.Type) throws -> T {
        let data = try callData(command, payload)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw CoreError(message: "解析核心响应失败: \(error.localizedDescription)")
        }
    }

    func callData(_ command: String, _ payload: [String: Any] = [:]) throws -> Data {
        let request: [String: Any] = ["cmd": command, "payload": payload]
        let requestData = try JSONSerialization.data(withJSONObject: request)
        guard let requestString = String(data: requestData, encoding: .utf8) else {
            throw CoreError(message: "无法编码请求")
        }

        var resultPointer: UnsafeMutablePointer<CChar>?
        requestString.withCString { pointer in
            resultPointer = mf_call(pointer)
        }
        guard let resultPointer else {
            throw CoreError(message: "核心没有返回结果")
        }
        defer { mf_free(resultPointer) }
        let responseText = String(cString: resultPointer)
        guard let responseData = responseText.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw CoreError(message: "核心响应不是有效 JSON")
        }
        if object["ok"] as? Bool == true {
            let data = object["data"] ?? [:]
            return try JSONSerialization.data(withJSONObject: data)
        }
        throw CoreError(message: object["error"] as? String ?? "未知核心错误")
    }

    func callAsync<T: Decodable>(_ command: String, _ payload: [String: Any] = [:], as type: T.Type) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let value = try self.call(command, payload, as: type)
                    continuation.resume(returning: value)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func callDataAsync(_ command: String, _ payload: [String: Any] = [:]) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try self.callData(command, payload))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
