//
//  HybridAIProvider.swift
//  Teste Context AI
//
//  Created by Assistant on 15/10/25.
//

import Foundation
import Combine

final class HybridAIProvider: AIModelProvider {
    private let foundationProvider = FoundationModelsProvider()
    private let ollamaStandaloneProvider = OllamaStandaloneProvider()
    private var currentProvider: AIModelProvider?
    
    // Enum para escolha do provider
    enum ProviderType: String, CaseIterable {
        case foundation = "Foundation Models"
        case ollamaStandalone = "Ollama Standalone"
        
        var description: String {
            switch self {
            case .foundation:
                return "Foundation Models (Nativo do macOS)"
            case .ollamaStandalone:
                return "Ollama Standalone (Offline)"
            }
        }
    }
    
    private var selectedProvider: ProviderType = .foundation
    
    var isAvailable: Bool {
        return currentProvider?.isAvailable ?? false
    }
    
    init() {
        selectProvider(.foundation)
    }
    
    func selectProvider(_ type: ProviderType) {
        selectedProvider = type
        
        switch type {
        case .foundation:
            currentProvider = foundationProvider
            print("🔍 HybridAIProvider: Selecionado Foundation Models")
        case .ollamaStandalone:
            currentProvider = ollamaStandaloneProvider
            print("🔍 HybridAIProvider: Selecionado Ollama Standalone")
        }
        
        let isAvailable = currentProvider?.isAvailable ?? false
        print("🔍 HybridAIProvider: Provider \(isAvailable ? "disponível" : "não disponível")")
    }
    
    private func getProviderName(_ provider: AIModelProvider) -> String {
        switch provider {
        case is FoundationModelsProvider:
            return "Foundation Models"
        case is OllamaStandaloneProvider:
            return "Ollama Standalone"
        default:
            return "Provider Desconhecido"
        }
    }
    
    func generate(prompt: String) async throws -> String {
        guard let provider = currentProvider else {
            throw AIProviderError.notAvailable
        }
        
        let providerName = getProviderName(provider)
        print("🤖 HybridAIProvider: Gerando resposta com \(providerName)")
        
        do {
            let response = try await provider.generate(prompt: prompt)
            print("✅ HybridAIProvider: Resposta gerada com sucesso")
            return response
        } catch {
            print("❌ HybridAIProvider: Erro com \(providerName): \(error)")
            
            // Para simplificar, não tenta outros providers automaticamente
            print("🔄 HybridAIProvider: Erro no provider atual, não tentando outros")
            
            throw error
        }
    }
    
    // MARK: - Provider Status
    
    func getCurrentProviderInfo() -> (name: String, isAvailable: Bool) {
        guard let provider = currentProvider else {
            return ("Nenhum", false)
        }
        
        return (getProviderName(provider), provider.isAvailable)
    }
    
    func getAllProvidersStatus() -> [(name: String, isAvailable: Bool, type: ProviderType)] {
        return [
            ("Foundation Models", foundationProvider.isAvailable, .foundation),
            ("Ollama Standalone", ollamaStandaloneProvider.isAvailable, .ollamaStandalone)
        ]
    }
    
    func isProviderAvailable(_ type: ProviderType) -> Bool {
        switch type {
        case .foundation:
            return foundationProvider.isAvailable
        case .ollamaStandalone:
            return ollamaStandaloneProvider.isAvailable
        }
    }
    
    func getCurrentProviderType() -> ProviderType {
        return selectedProvider
    }
}
