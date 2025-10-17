//
//  AIModelProvider.swift
//  Teste Context AI
//
//  Created by Assistant on 15/10/25.
//

import Foundation

enum AIProviderError: Error, LocalizedError {
    case notAvailable
    case unsupportedPlatform
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Modelo de IA não disponível no dispositivo."
        case .unsupportedPlatform:
            return "Plataforma não suportada para este provedor."
        case .generationFailed(let message):
            return "Falha ao gerar resposta: \(message)"
        }
    }
}

protocol AIModelProvider {
    /// Retorna true quando o provedor está pronto para uso no dispositivo atual
    var isAvailable: Bool { get }

    /// Gera uma resposta de texto para o prompt informado
    func generate(prompt: String) async throws -> String
}


