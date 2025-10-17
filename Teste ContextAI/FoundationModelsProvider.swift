//
//  FoundationModelsProvider.swift
//  Teste Context AI
//
//  Created by Assistant on 15/10/25.
//

import Foundation

// Importa o framework quando disponível (Xcode/SDK que tenham o módulo)
#if canImport(FoundationModels)
import FoundationModels

/// Parâmetros simples para geração de texto com Foundation Models
struct FMGenerationConfig {
    var modelIdentifier: String? = nil // Use o default do sistema se nil
    var temperature: Double = 0.7
    var maxTokens: Int? = nil
}
#endif

final class FoundationModelsProvider: AIModelProvider {
    // Configuração básica; pode ser exposta/publicada conforme necessidade
    private let config: FMGenerationConfig

    init(config: FMGenerationConfig = FMGenerationConfig()) {
        self.config = config
    }

    var isAvailable: Bool {
        #if canImport(FoundationModels)
        // Consideramos disponível se o módulo puder ser importado.
        return true
        #else
        return false
        #endif
    }

    func generate(prompt: String) async throws -> String {
        #if canImport(FoundationModels)
        // Implementação baseada na API pública do Foundation Models.
        // Observação: Os nomes de tipos podem variar entre versões do SDK.
        // Este código tenta usar uma interface típica de geração de texto.
        do {
            // Cria uma sessão com o modelo padrão ou instruções customizadas
            let temperature = config.temperature

            let options = GenerationOptions(temperature: temperature)
            let session = LanguageModelSession()
           
            let response = try await session.respond(to: prompt, options: options)
            return response.content
        } catch {
            throw AIProviderError.generationFailed(error.localizedDescription)
        }
        #else
        // Quando o módulo não está disponível, indica indisponibilidade para fallback externo
        throw AIProviderError.notAvailable
        #endif
    }
}

