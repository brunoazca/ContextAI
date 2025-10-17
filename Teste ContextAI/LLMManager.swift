
//
//  LLMManager.swift
//  Teste Context AI
//
//  Created by Bruno Azambuja Carvalho on 15/10/25.
//

import Foundation
import Combine
// MARK: - LLM Manager

@MainActor
class LLMManager: ObservableObject {
    
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var lastResponse: String = ""
    
    let provider: AIModelProvider
    private let contextManager: ContextManager
    
    enum LLMError: Error, LocalizedError {
        case providerUnavailable
        
        var errorDescription: String? {
            switch self {
            case .providerUnavailable:
                return "Nenhum provedor de IA disponível."
            }
        }
    }
    
    init(provider: AIModelProvider? = nil, contextManager: ContextManager? = nil) {
        if let provider = provider {
            self.provider = provider
        } else {
            // Usa o HybridAIProvider com Foundation Models como padrão
            self.provider = HybridAIProvider()
        }
        
        self.contextManager = contextManager ?? ContextManager()
    }
    
    /// Método para trocar o provider do LLM
    func switchProvider(to type: HybridAIProvider.ProviderType) {
        if let hybridProvider = provider as? HybridAIProvider {
            hybridProvider.selectProvider(type)
        }
    }
    
    // MARK: - Public Methods
    
    /// Processa texto com o modelo LLM
    func processText(_ prompt: String, model: String? = nil) async throws -> String {
        isLoading = true
        lastError = nil
        
        defer {
            isLoading = false
        }
        
        guard provider.isAvailable else {
            throw LLMError.providerUnavailable
        }
        do {
            print("🤖 LLMManager: Enviando prompt para o provedor de IA (\(prompt.count) caracteres)")
            let responseText = try await provider.generate(prompt: prompt)
            self.lastResponse = responseText
            
            print("🤖 LLMManager: Resposta recebida do LLM (\(responseText.count) caracteres)")
            
            // Salva a resposta no contexto para futuras referências
            contextManager.addContext(responseText, source: "LLM Response", metadata: [
                "model": model ?? "default",
                "prompt_length": String(prompt.count),
                "response_length": String(responseText.count)
            ])
            
            print("🤖 LLMManager: Resposta salva no contexto para futuras referências")
            
            return responseText
        } catch {
            print("❌ LLMManager: Erro no processamento: \(error.localizedDescription)")
            self.lastError = error.localizedDescription
            throw error
        }
    }
    
    /// Processa texto reconhecido pelo OCR com contexto específico
    func processOCRText(_ recognizedText: String) async throws -> String {
        print("🤖 LLMManager: Processando texto OCR com contexto histórico")
        
        // Salva o texto OCR no contexto
        contextManager.addContext(recognizedText, source: "OCR", metadata: [
            "text_length": String(recognizedText.count),
            "word_count": String(recognizedText.components(separatedBy: .whitespaces).count)
        ])
        
        // Busca contexto histórico relevante
        let historicalContext = contextManager.generateContextForLLM(currentContent: recognizedText)
        
        let prompt = """
        Analise o seguinte texto extraído de uma captura de tela e forneça um resumo ou análise útil:
        
        \(historicalContext)
        
        Texto extraído:
        \(recognizedText)
        
        Por favor, forneça:
        1. Um resumo conciso do conteúdo
        2. Principais pontos ou informações importantes
        3. Sugestões ou insights relevantes
        4. Relacionamento com o contexto histórico do usuário (se relevante)
        
        Responda em português brasileiro.
        """
        
        print("🤖 LLMManager: Enviando prompt para análise com contexto histórico")
        return try await processText(prompt)
    }
    
    /// Processa texto com prompt customizado
    func processWithCustomPrompt(_ text: String, customPrompt: String) async throws -> String {
        // Salva o texto no contexto
        contextManager.addContext(text, source: "Custom Analysis", metadata: [
            "prompt_type": "custom",
            "prompt_length": String(customPrompt.count),
            "text_length": String(text.count)
        ])
        
        // Busca contexto histórico relevante
        let historicalContext = contextManager.generateContextForLLM(currentContent: text)
        
        let fullPrompt = """
        \(customPrompt)
        
        \(historicalContext)
        
        Texto para análise:
        \(text)
        """
        
        return try await processText(fullPrompt)
    }
    
    /// Processa prompt customizado usando apenas o contexto histórico (sem texto adicional)
    func processCustomPromptWithContext(_ customPrompt: String) async throws -> String {
        print("🤖 LLMManager: Processando prompt customizado com contexto histórico (sem captura)")
        print("🤖 LLMManager: Prompt: \(customPrompt)")
        
        // Busca contexto histórico relevante baseado no prompt
        let historicalContext = contextManager.generateContextForLLM(currentContent: customPrompt)
        
        print("🤖 LLMManager: Contexto histórico encontrado: \(historicalContext.count) caracteres")
        
        let fullPrompt = """
        \(customPrompt)
        
        \(historicalContext)
        
        Use o contexto histórico acima para responder ao prompt. Se não houver contexto relevante, indique isso na resposta.
        """
        
        print("🤖 LLMManager: Enviando prompt customizado com contexto histórico")
        return try await processText(fullPrompt)
    }
    
    // MARK: - Action Suggestion (raw text)
    /// Gera uma sugestão de ação em TEXTO PURO priorizando contexto atual
    func generateSuggestionText(from recognizedText: String) async throws -> String {
        print("🤖 LLMManager: Gerando sugestão priorizando contexto atual (análise a cada 15s)")
        
        // Indexa o texto OCR no contexto
        contextManager.addContext(recognizedText, source: "OCR", metadata: [
            "text_length": String(recognizedText.count),
            "for_suggestion": "true",
            "timestamp": Date().timeIntervalSince1970.description
        ])
        
        // Busca apenas as 2 entradas mais recentes (incluindo a atual)
        let recentEntries = contextManager.findRecentEntriesForSuggestions(limit: 2)
        
        var contextString = ""
        if !recentEntries.isEmpty {
            contextString = "=== CONTEXTO ATUAL (Máximo 2 entradas mais recentes) ===\n\n"
            for (index, entry) in recentEntries.enumerated() {
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .short
                dateFormatter.timeStyle = .short
                
                contextString += "[\(index + 1)] \(entry.source) - \(dateFormatter.string(from: entry.timestamp))\n"
                contextString += "\(entry.content)\n\n"
            }
            contextString += "=== FIM DO CONTEXTO ATUAL ===\n\n"
        }
        
        let prompt = """
        Você é um assistente proativo. Com base APENAS no que o usuário está vendo AGORA (contexto atual), escreva UMA sugestão objetiva, curta e diretamente acionável do que você pode fazer para ajudar o usuário neste momento. IGNORE contexto antigo e foque no que está acontecendo agora. Responda APENAS com a sugestão em texto (sem JSON, sem prefixos, sem porcentagens).

        \(contextString)
        
        TEXTO ATUAL (O que está na tela AGORA):
        \(recognizedText)
        """
        
        print("🤖 LLMManager: Enviando prompt para sugestão com contexto atual")
        let suggestion = try await processText(prompt).trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("🤖 LLMManager: Sugestão gerada: \(String(suggestion.prefix(100)))...")
        
        return suggestion
    }
    
    /// Retorna o gerenciador de contexto para acesso externo
    var contextManagerInstance: ContextManager {
        return contextManager
    }
}
