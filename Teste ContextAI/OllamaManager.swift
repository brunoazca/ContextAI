//
//  OllamaManager.swift
//  Teste Context AI
//
//  Created by Assistant on 15/10/25.
//

import Foundation
import Combine

#if os(macOS)
import AppKit
#endif

final class OllamaManager: ObservableObject {
    static let shared = OllamaManager()
    
    @Published var isInstalling = false
    @Published var isRunning = false
    @Published var installationProgress = ""
    @Published var lastError: String?
    
    private let ollamaURL = "https://ollama.ai/download/Ollama-darwin.zip"
    private let ollamaPath = "Ollama.app"
    private let modelsToDownload = ["llama3.2", "llama3.2:3b"] // Modelos leves para começar
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Verifica se o Ollama está disponível
    var isAvailable: Bool {
        return FileManager.default.fileExists(atPath: ollamaPath) && isRunning
    }
    
    /// Inicia o processo de instalação automática
    func setupOllamaIfNeeded() async {
        if !FileManager.default.fileExists(atPath: ollamaPath) {
            await downloadAndInstallOllama()
        } else if !isRunning {
            await startOllamaService()
        }
    }
    
    /// Baixa e instala o Ollama automaticamente
    private func downloadAndInstallOllama() async {
        await MainActor.run {
            isInstalling = true
            installationProgress = "Baixando Ollama..."
        }
        
        do {
            // Simula download (em produção, você faria o download real)
            try await simulateDownload()
            
            await MainActor.run {
                installationProgress = "Instalando Ollama..."
            }
            
            // Simula instalação
            try await simulateInstallation()
            
            await MainActor.run {
                installationProgress = "Iniciando serviço..."
            }
            
            await startOllamaService()
            
        } catch {
            await MainActor.run {
                lastError = "Erro na instalação: \(error.localizedDescription)"
                isInstalling = false
            }
        }
    }
    
    /// Inicia o serviço Ollama
    private func startOllamaService() async {
        await MainActor.run {
            installationProgress = "Iniciando Ollama..."
        }
        
        // Em produção, você executaria o Ollama como processo
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 segundos
        
        await MainActor.run {
            isRunning = true
            isInstalling = false
            installationProgress = "Ollama pronto!"
        }
        
        // Baixa modelos essenciais em background
        Task {
            await downloadEssentialModels()
        }
    }
    
    /// Baixa modelos essenciais
    private func downloadEssentialModels() async {
        for model in modelsToDownload {
            await MainActor.run {
                installationProgress = "Baixando modelo \(model)..."
            }
            
            // Simula download do modelo
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 segundos por modelo
        }
        
        await MainActor.run {
            installationProgress = "Todos os modelos prontos!"
        }
    }
    
    // MARK: - Simulation Methods (para demonstração)
    
    private func simulateDownload() async throws {
        // Simula progresso de download
        for i in 1...10 {
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 segundos
            await MainActor.run {
                installationProgress = "Baixando Ollama... \(i * 10)%"
            }
        }
    }
    
    private func simulateInstallation() async throws {
        // Simula progresso de instalação
        for i in 1...5 {
            try await Task.sleep(nanoseconds: 800_000_000) // 0.8 segundos
            await MainActor.run {
                installationProgress = "Instalando... \(i * 20)%"
            }
        }
    }
    
    // MARK: - Model Management
    
    /// Lista modelos disponíveis
    func listModels() async -> [String] {
        // Em produção, faria requisição para /api/tags
        return modelsToDownload
    }
    
    /// Baixa um modelo específico
    func downloadModel(_ modelName: String) async throws {
        await MainActor.run {
            installationProgress = "Baixando \(modelName)..."
        }
        
        // Simula download do modelo
        try await Task.sleep(nanoseconds: 5_000_000_000) // 5 segundos
        
        await MainActor.run {
            installationProgress = "Modelo \(modelName) pronto!"
        }
    }
}

// MARK: - Ollama Standalone Provider

final class OllamaStandaloneProvider: AIModelProvider {
    private let ollamaManager = OllamaManager.shared
    private let baseURL = "http://localhost:11434"
    private let defaultModel = "llama3.2:3b" // Modelo leve para app standalone
    
    var isAvailable: Bool {
        return ollamaManager.isAvailable
    }
    
    func generate(prompt: String) async throws -> String {
        // Verifica se o Ollama está pronto
        if !isAvailable {
            throw AIProviderError.notAvailable
        }
        
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
            options: OllamaOptions(
                temperature: 0.7,
                top_p: 0.9,
                max_tokens: 800 // Reduzido para app standalone
            )
        )
        
        request.httpBody = try JSONEncoder().encode(payload)
        
        // Timeout reduzido para app standalone
        request.timeoutInterval = 30.0
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw AIProviderError.generationFailed("Status code: \(status)")
        }
        
        let decoded = try JSONDecoder().decode(OllamaResponse.self, from: data)
        return decoded.response
    }
}

