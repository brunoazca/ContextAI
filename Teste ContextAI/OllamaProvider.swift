//
//  OllamaProvider.swift
//  Teste Context AI
//
//  Created by Assistant on 15/10/25.
//

import Foundation

struct OllamaRequest: Codable {
    let model: String
    let prompt: String
    let stream: Bool
    let options: OllamaOptions?
}

struct OllamaOptions: Codable {
    let temperature: Double?
    let top_p: Double?
    let max_tokens: Int?
}

struct OllamaResponse: Codable {
    let model: String
    let created_at: String
    let response: String
    let done: Bool
    let context: [Int]?
    let total_duration: Int?
    let load_duration: Int?
    let prompt_eval_duration: Int?
    let eval_duration: Int?
    let eval_count: Int?
}

final class OllamaProvider: AIModelProvider {
    private let baseURL: String
    private let defaultModel: String

    init(baseURL: String = "http://localhost:11434", defaultModel: String = "llama3.2") {
        self.baseURL = baseURL
        self.defaultModel = defaultModel
    }

    var isAvailable: Bool {
        // Opportunistic check: attempt to reach tags endpoint synchronously with short timeout
        guard let url = URL(string: "\(baseURL)/api/tags") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.0
        let semaphore = DispatchSemaphore(value: 0)
        var reachable = false
        URLSession.shared.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                reachable = true
            }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 1.2)
        return reachable
    }

    func generate(prompt: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/generate") else {
            throw AIProviderError.generationFailed("URL inválida")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = OllamaRequest(
            model: defaultModel,
            prompt: prompt,
            stream: false,
            options: OllamaOptions(temperature: 0.7, top_p: 0.9, max_tokens: 1000)
        )

        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw AIProviderError.generationFailed("Status code: \(status)")
        }
        let decoded = try JSONDecoder().decode(OllamaResponse.self, from: data)
        return decoded.response
    }
}


