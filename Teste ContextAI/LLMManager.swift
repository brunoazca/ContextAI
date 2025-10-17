
//
//  LLMManager.swift
//  Teste Context AI
//
//  Created by Bruno Azambuja Carvalho on 15/10/25.
//

import Foundation
import Combine

// MARK: - Assistente Action Model
struct AssistenteAction {
    let id: String
    let name: String
    let description: String
    let keywords: [String]
}
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
        print("🤖 LLMManager: Processando texto OCR com Foundation Models")
        
        // Primeiro, analisa o texto OCR com Foundation Models para entender o que o usuário está fazendo
        let activityAnalysis = try await analyzeOCRWithFoundationModels(recognizedText)
        
        // Salva a análise da atividade no contexto (não o texto bruto do OCR)
        contextManager.addContext(activityAnalysis, source: "OCR Analysis", metadata: [
            "text_length": String(recognizedText.count),
            "word_count": String(recognizedText.components(separatedBy: .whitespaces).count),
            "original_ocr": String(recognizedText.prefix(200)) // Mantém uma amostra do OCR original
        ])
        
        // Busca contexto histórico relevante
        let historicalContext = contextManager.generateContextForLLM(currentContent: activityAnalysis)
        
        let availableActionsContext = generateAvailableActionsContext()
        
        let prompt = """
        Com base na análise da atividade atual do usuário e no contexto histórico, forneça uma análise útil e sugestões práticas focadas em ações executáveis.
        
        \(availableActionsContext)
        
        ATIVIDADE ATUAL DO USUÁRIO:
        \(activityAnalysis)
        
        CONTEXTO HISTÓRICO:
        \(historicalContext)
        
        INSTRUÇÕES:
        1. Analise a atividade atual do usuário
        2. Identifique se alguma das ações disponíveis é relevante
        3. Se relevante, sugira a ação específica com detalhes práticos
        4. Se nenhuma ação for relevante, responda "Nenhuma ação disponível"
        5. Seja específico sobre qual ação e como executá-la
        6. Responda em português brasileiro
        7. Máximo 3 frases
        """
        
        print("🤖 LLMManager: Enviando prompt para análise de atividade com contexto histórico")
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
        
        let availableActionsContext = generateAvailableActionsContext()
        
        let fullPrompt = """
        \(customPrompt)
        
        \(availableActionsContext)
        
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
        
        let availableActionsContext = generateAvailableActionsContext()
        
        let fullPrompt = """
        \(customPrompt)
        
        \(availableActionsContext)
        
        \(historicalContext)
        
        Use o contexto histórico acima para responder ao prompt. Se não houver contexto relevante, indique isso na resposta.
        """
        
        print("🤖 LLMManager: Enviando prompt customizado com contexto histórico")
        return try await processText(fullPrompt)
    }
    
    // MARK: - Action Suggestion (raw text)
    /// Gera uma sugestão de ação em TEXTO PURO priorizando contexto atual
    func generateSuggestionText(from recognizedText: String) async throws -> String {
        print("🤖 LLMManager: Gerando sugestão priorizando contexto atual (análise a cada 7s)")
        
        // Primeiro, analisa o texto OCR com Foundation Models para entender o que o usuário está fazendo
        let activityAnalysis = try await analyzeOCRWithFoundationModels(recognizedText)
        
        // Indexa a análise da atividade no contexto (não o texto bruto do OCR)
        contextManager.addContext(activityAnalysis, source: "OCR Analysis", metadata: [
            "text_length": String(recognizedText.count),
            "for_suggestion": "true",
            "timestamp": Date().timeIntervalSince1970.description,
            "original_ocr": String(recognizedText.prefix(200)) // Mantém uma amostra do OCR original
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
        
        let availableActionsContext = generateAvailableActionsContext()
        
        let prompt = """
        Você é um assistente proativo com capacidades específicas. Com base na atividade atual do usuário, sugira APENAS ações que você pode realmente executar.

        \(availableActionsContext)
        
        \(contextString)
        
        ATIVIDADE ATUAL (O que o usuário está fazendo AGORA):
        \(activityAnalysis)
        
        INSTRUÇÕES:
        - Analise a atividade atual do usuário
        - Identifique se alguma das ações disponíveis é relevante
        - Se relevante, sugira a ação específica com detalhes práticos
        - Se nenhuma ação for relevante, responda "Nenhuma ação disponível"
        - Seja específico sobre qual ação e como executá-la
        - Responda em português brasileiro
        - Máximo 2 frases
        """
        
        print("🤖 LLMManager: Enviando prompt para sugestão com atividade atual")
        let suggestion = try await processText(prompt).trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("🤖 LLMManager: Sugestão gerada: \(String(suggestion.prefix(100)))...")
        
        return suggestion
    }
    
    /// Retorna o gerenciador de contexto para acesso externo
    var contextManagerInstance: ContextManager {
        return contextManager
    }
    
    // MARK: - Available Actions
    /// Lista de ações que o assistente pode executar
    private let availableActions: [AssistenteAction] = [
        AssistenteAction(
            id: "send_email",
            name: "Enviar Email",
            description: "Enviar emails para contatos específicos",
            keywords: ["email", "enviar", "mensagem", "contato", "comunicar"]
        ),
        AssistenteAction(
            id: "schedule_meeting",
            name: "Marcar Reunião",
            description: "Agendar reuniões com pessoas ou grupos",
            keywords: ["reunião", "agendar", "encontro", "meeting", "calendário"]
        ),
        AssistenteAction(
            id: "schedule_activity",
            name: "Agendar Atividade",
            description: "Criar lembretes e agendar tarefas pessoais",
            keywords: ["lembrete", "tarefa", "atividade", "agendar", "planner"]
        ),
        AssistenteAction(
            id: "purchase_item",
            name: "Comprar Item",
            description: "Adicionar itens a listas de compras ou fazer compras online",
            keywords: ["comprar", "shopping", "lista", "item", "produto", "loja"]
        )
    ]
    
    /// Gera contexto das ações disponíveis para o prompt
    private func generateAvailableActionsContext() -> String {
        var context = "=== AÇÕES DISPONÍVEIS ===\n"
        context += "O assistente pode executar APENAS as seguintes ações:\n\n"
        
        for (index, action) in availableActions.enumerated() {
            context += "\(index + 1). \(action.name)\n"
            context += "   - \(action.description)\n"
            context += "   - Palavras-chave: \(action.keywords.joined(separator: ", "))\n\n"
        }
        
        context += "IMPORTANTE: Sugira APENAS ações desta lista. Se nenhuma ação for relevante, responda 'Nenhuma ação disponível'.\n"
        context += "=== FIM DAS AÇÕES DISPONÍVEIS ===\n\n"
        
        return context
    }
    
    /// Analisa texto OCR usando Foundation Models para entender o que o usuário está fazendo
    func analyzeOCRWithFoundationModels(_ ocrText: String) async throws -> String {
        print("🤖 LLMManager: Analisando OCR com Foundation Models")
        
        let prompt = """
        Analise o seguinte texto extraído de uma captura de tela e forneça um resumo conciso (máximo 2-3 frases) do que o usuário está fazendo atualmente. Seja específico sobre a atividade, aplicativo ou tarefa sendo realizada.

        Texto da tela:
        \(ocrText)

        Resumo da atividade:
        """
        
        print("🤖 LLMManager: Enviando texto OCR para análise com Foundation Models")
        let analysis = try await processText(prompt).trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("🤖 LLMManager: Análise OCR concluída: \(String(analysis.prefix(100)))...")
        
        return analysis
    }
}
