//
//  ContextManager.swift
//  Teste Context AI
//
//  Created by Assistant on 15/10/25.
//

import Foundation
import Combine

// MARK: - Context Data Models

struct ContextEntry: Codable, Identifiable {
    let id: UUID
    let content: String
    let vector: [Double] // Representação vetorial simplificada
    let timestamp: Date
    let source: String // Origem do contexto (OCR, manual, etc.)
    let metadata: [String: String] // Metadados adicionais
    
    init(content: String, source: String, metadata: [String: String] = [:]) {
        self.id = UUID()
        self.content = content
        self.vector = Self.simpleVectorization(content)
        self.timestamp = Date()
        self.source = source
        self.metadata = metadata
    }
    
    // Vetorização simples baseada em frequência de palavras e características do texto
    static func simpleVectorization(_ text: String) -> [Double] {
        let words = text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        var features: [Double] = []
        
        // 1. Comprimento do texto normalizado
        features.append(Double(text.count) / 1000.0)
        
        // 2. Número de palavras normalizado
        features.append(Double(words.count) / 100.0)
        
        // 3. Frequência de palavras comuns em português (simplificado)
        let commonWords = ["o", "a", "de", "e", "do", "da", "em", "um", "uma", "para", "com", "não", "que", "é", "se", "mais", "mas", "como", "sobre", "por", "tem", "ser", "foi", "são", "pode", "pela", "pelos", "pode", "muito", "já", "ou", "quando", "onde", "como", "porque", "então", "assim", "também", "ainda", "depois", "antes", "agora", "hoje", "ontem", "amanhã"]
        
        let wordFrequency = Dictionary(grouping: words, by: { $0 })
            .mapValues { $0.count }
        
        var commonWordCount = 0
        for word in commonWords {
            commonWordCount += wordFrequency[word] ?? 0
        }
        features.append(Double(commonWordCount) / Double(words.count + 1))
        
        // 4. Presença de números
        let hasNumbers = text.rangeOfCharacter(from: .decimalDigits) != nil
        features.append(hasNumbers ? 1.0 : 0.0)
        
        // 5. Presença de pontuação especial
        let specialChars = Set("!@#$%^&*()_+-=[]{}|;':\",./<>?")
        let specialCharCount = text.filter { specialChars.contains($0) }.count
        features.append(Double(specialCharCount) / Double(text.count + 1))
        
        // 6. Número de linhas
        let lineCount = text.components(separatedBy: .newlines).count
        features.append(Double(lineCount) / 10.0)
        
        // 7. Densidade de caracteres especiais (maiúsculas, etc.)
        let upperCaseCount = text.filter { $0.isUppercase }.count
        features.append(Double(upperCaseCount) / Double(text.count + 1))
        
        // 8. Hash simples do conteúdo (normalizado)
        let hash = text.hashValue
        features.append(Double(abs(hash % 1000)) / 1000.0)
        
        return features
    }
}

struct ContextDatabase: Codable {
    var entries: [ContextEntry] = []
    var lastUpdated: Date = Date()
    var version: String = "1.0"
    
    mutating func addEntry(_ entry: ContextEntry) {
        entries.append(entry)
        lastUpdated = Date()
    }
    
    mutating func removeEntry(withId id: UUID) {
        entries.removeAll { $0.id == id }
        lastUpdated = Date()
    }
    
    mutating func clearOldEntries(olderThan days: Int = 30) {
        let cutoffDate = Date().addingTimeInterval(-Double(days * 24 * 60 * 60))
        entries.removeAll { $0.timestamp < cutoffDate }
        lastUpdated = Date()
    }
}

// MARK: - Context Manager

@MainActor
class ContextManager: ObservableObject {
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var totalEntries: Int = 0
    @Published var lastUpdated: Date?
    
    var database = ContextDatabase()
    private let fileManager = FileManager.default
    private let documentsDirectory: URL
    
    // Buffer recente de embeddings (últimos ~5 minutos, máx. 100)
    private struct RecentVector: Codable {
        let vector: [Double]
        let timestamp: Date
        let app: String
        let key: String // hash/ident para frequência de ação
    }
    private var recentVectors: [RecentVector] = []
    
    // Resumo incremental do estado do usuário
    private(set) var summaryText: String = ""
    private(set) var summaryVector: [Double] = []
    
    // Configurações
    private let maxEntries = 1000 // Limite máximo de entradas
    private let maxEntryAge = 30 // Dias para manter entradas antigas
    private let recentMaxCount = 100
    private let recentMaxAgeSeconds: TimeInterval = 5 * 60 // 5 minutos
    private let recencyHalfLifeSeconds: TimeInterval = 120 // meia-vida de 2 min
    
    init() {
        // Define o diretório de documentos
        documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        print("🔧 ContextManager: Inicializando gerenciador de contexto")
        print("📁 ContextManager: Diretório de documentos: \(documentsDirectory.path)")
        
        // Carrega o contexto ao inicializar
        Task {
            await loadContext()
        }
    }
    
    // MARK: - Public Methods
    
    /// Adiciona uma nova entrada de contexto
    func addContext(_ content: String, source: String, metadata: [String: String] = [:]) {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let entry = ContextEntry(content: content, source: source, metadata: metadata)
        database.addEntry(entry)
        indexRecent(entry: entry)
        
        print("📝 ContextManager: Nova entrada adicionada - Fonte: \(source)")
        print("📝 ContextManager: Conteúdo: \(String(content.prefix(100)))...")
        print("📝 ContextManager: Timestamp: \(entry.timestamp)")
        
        // Limita o número de entradas
        if database.entries.count > maxEntries {
            let removedCount = database.entries.count - maxEntries
            database.entries = Array(database.entries.suffix(maxEntries))
            print("🗑️ ContextManager: Removidas \(removedCount) entradas antigas (limite: \(maxEntries))")
        }
        
        // Remove entradas muito antigas
        let oldCount = database.entries.count
        database.clearOldEntries(olderThan: maxEntryAge)
        let newCount = database.entries.count
        if oldCount != newCount {
            print("🗑️ ContextManager: Removidas \(oldCount - newCount) entradas muito antigas (>\(maxEntryAge) dias)")
        }
        
        updatePublishedProperties()
        
        // Salva automaticamente
        Task {
            await saveContext()
        }
    }
    
    /// Adiciona e indexa contexto, retornando a entrada criada
    @discardableResult
    func addContextAndIndex(_ content: String, source: String, metadata: [String: String] = [:]) -> ContextEntry {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ContextEntry(content: "", source: source, metadata: metadata)
        }
        let entry = ContextEntry(content: trimmed, source: source, metadata: metadata)
        database.addEntry(entry)
        indexRecent(entry: entry)
        updatePublishedProperties()
        Task { await saveContext() }
        return entry
    }
    
    /// Busca entradas similares usando similaridade vetorial, priorizando entradas mais novas
    func findSimilarEntries(to content: String, limit: Int = 5) -> [ContextEntry] {
        let queryVector = ContextEntry(content: content, source: "query", metadata: [:]).vector
        
        print("🔍 ContextManager: Buscando entradas similares para: \(String(content.prefix(50)))...")
        
        let similarities = database.entries.map { entry in
            let baseSimilarity = cosineSimilarity(queryVector, entry.vector)
            // Bonus para entradas mais novas (últimas 24 horas)
            let hoursSinceCreation = Date().timeIntervalSince(entry.timestamp) / 3600
            let timeBonus = hoursSinceCreation < 24 ? 0.1 : 0.0
            let finalSimilarity = min(1.0, baseSimilarity + timeBonus)
            
            return (entry: entry, similarity: finalSimilarity, originalSimilarity: baseSimilarity)
        }
        
        let filteredSimilarities = similarities
            .filter { $0.similarity > 0.3 } // Threshold mínimo de similaridade
            .sorted { first, second in
                // Primeiro por similaridade final, depois por timestamp (mais recente primeiro)
                if abs(first.similarity - second.similarity) < 0.05 {
                    return first.entry.timestamp > second.entry.timestamp
                }
                return first.similarity > second.similarity
            }
            .prefix(limit)
            .map { $0.entry }
        
        print("🔍 ContextManager: Encontradas \(filteredSimilarities.count) entradas similares (priorizando mais novas)")
        for (index, entry) in filteredSimilarities.enumerated() {
            let similarityData = similarities.first { $0.entry.id == entry.id }
            let originalSim = similarityData?.originalSimilarity ?? 0.0
            let finalSim = similarityData?.similarity ?? 0.0
            let hoursOld = Date().timeIntervalSince(entry.timestamp) / 3600
            
            print("🔍 ContextManager: [\(index + 1)] \(entry.source) - Sim: \(String(format: "%.2f", finalSim)) (orig: \(String(format: "%.2f", originalSim))) - \(String(format: "%.1f", hoursOld))h atrás")
        }
        
        return filteredSimilarities
    }
    
    /// Busca as entradas mais recentes para sugestões (prioriza por tempo, não por similaridade)
    func findRecentEntriesForSuggestions(limit: Int = 3) -> [ContextEntry] {
        print("🔍 ContextManager: Buscando entradas mais recentes para sugestões")
        
        let recentEntries = database.entries
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(limit)
        
        print("🔍 ContextManager: Encontradas \(recentEntries.count) entradas recentes para sugestões")
        for (index, entry) in recentEntries.enumerated() {
            let hoursOld = Date().timeIntervalSince(entry.timestamp) / 3600
            print("🔍 ContextManager: [\(index + 1)] \(entry.source) - \(String(format: "%.1f", hoursOld))h atrás")
        }
        
        return Array(recentEntries)
    }
    
    /// Gera contexto consolidado para uso com LLM
    func generateContextForLLM(currentContent: String, maxEntries: Int = 10) -> String {
        let similarEntries = findSimilarEntries(to: currentContent, limit: maxEntries)
        
        guard !similarEntries.isEmpty else {
            print("📋 ContextManager: Nenhum contexto relevante encontrado para o conteúdo atual")
            return "Nenhum contexto relevante encontrado."
        }
        
        print("📋 ContextManager: Gerando contexto consolidado com \(similarEntries.count) entradas")
        
        var contextString = "=== CONTEXTO HISTÓRICO DO USUÁRIO ===\n\n"
        
        for (index, entry) in similarEntries.enumerated() {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .short
            dateFormatter.timeStyle = .short
            
            contextString += "[\(index + 1)] \(entry.source) - \(dateFormatter.string(from: entry.timestamp))\n"
            contextString += "\(entry.content)\n\n"
            
            if !entry.metadata.isEmpty {
                contextString += "Metadados: \(entry.metadata.map { "\($0.key): \($0.value)" }.joined(separator: ", "))\n\n"
            }
        }
        
        contextString += "=== FIM DO CONTEXTO HISTÓRICO ===\n\n"
        
        print("📋 ContextManager: Contexto consolidado gerado (\(contextString.count) caracteres)")
        
        return contextString
    }
    
    /// Gera contexto ponderado por similaridade, recência e frequência de uso
    func generateWeightedContextForLLM(currentContent: String, maxItems: Int = 12) -> String {
        pruneRecent()
        let now = Date()
        let queryVector = ContextEntry(content: currentContent, source: "query", metadata: [:]).vector
        
        // Frequência por app/key nas recentes
        let freqByApp = Dictionary(grouping: recentVectors, by: { $0.app }).mapValues { Double($0.count) }
        let maxAppFreq = max(freqByApp.values.max() ?? 1.0, 1.0)
        
        let scored = database.entries.map { entry -> (entry: ContextEntry, score: Double) in
            let sim = cosineSimilarity(queryVector, entry.vector) // 0..1
            // Recência: exponencial com meia-vida
            let age = now.timeIntervalSince(entry.timestamp)
            let recencyWeight = pow(0.5, age / recencyHalfLifeSeconds) // 1 recente -> ~0 distante
            // Frequência por app
            let app = entry.metadata["app"] ?? entry.source
            let appFreqNorm = (freqByApp[app] ?? 0.0) / maxAppFreq // 0..1
            // Score final
            let score = sim * 0.6 + recencyWeight * 0.25 + appFreqNorm * 0.15
            return (entry, score)
        }
        .filter { $0.score > 0.15 }
        .sorted { $0.score > $1.score }
        .prefix(maxItems)
        
        guard !scored.isEmpty else {
            return summaryText.isEmpty ? "Nenhum contexto relevante encontrado." : "Resumo atual do usuário:\n\(summaryText)\n"
        }
        
        var contextString = "=== CONTEXTO PONDERADO DO USUÁRIO ===\n\n"
        for (index, item) in scored.enumerated() {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .short
            dateFormatter.timeStyle = .short
            contextString += "[\(index + 1)] \(item.entry.source) - \(dateFormatter.string(from: item.entry.timestamp))\n"
            contextString += "(score: \(String(format: "%.2f", item.score)))\n"
            contextString += "\(item.entry.content)\n\n"
        }
        if !summaryText.isEmpty {
            contextString += "Resumo incremental atual:\n\(summaryText)\n\n"
        }
        contextString += "=== FIM DO CONTEXTO PONDERADO ===\n\n"
        return contextString
    }
    
    /// Gera contexto resumido para evitar overflow do context window
    func generateSummarizedContextForLLM(currentContent: String, maxChars: Int = 2000) -> String {
        let fullContext = generateWeightedContextForLLM(currentContent: currentContent, maxItems: 20)
        
        // Se o contexto é pequeno, retorna direto
        if fullContext.count <= maxChars {
            return fullContext
        }
        
        // Se temos resumo, usa ele + contexto mais recente
        if !summaryText.isEmpty {
            let recentEntries = database.entries
                .sorted { $0.timestamp > $1.timestamp }
                .prefix(3)
            
            var summarizedContext = "=== CONTEXTO RESUMIDO ===\n\n"
            summarizedContext += "Resumo do estado do usuário:\n\(summaryText)\n\n"
            
            if !recentEntries.isEmpty {
                summarizedContext += "Atividades mais recentes:\n"
                for entry in recentEntries {
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateStyle = .short
                    dateFormatter.timeStyle = .short
                    summarizedContext += "• \(entry.source) (\(dateFormatter.string(from: entry.timestamp))): \(String(entry.content.prefix(100)))...\n"
                }
            }
            
            summarizedContext += "\n=== FIM DO CONTEXTO RESUMIDO ===\n\n"
            return summarizedContext
        }
        
        // Fallback: apenas o resumo se existir
        return summaryText.isEmpty ? "Nenhum contexto relevante encontrado." : "Resumo atual do usuário:\n\(summaryText)\n"
    }
    
    /// Registra/atualiza o resumo incremental do estado do usuário
    func recordSummary(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        summaryText = trimmed
        summaryVector = ContextEntry.simpleVectorization(trimmed)
    }
    
    /// Limpa todo o contexto
    func clearAllContext() {
        let entryCount = database.entries.count
        database.entries.removeAll()
        database.lastUpdated = Date()
        updatePublishedProperties()
        
        print("🗑️ ContextManager: Limpeza completa - \(entryCount) entradas removidas")
        
        Task {
            await saveContext()
        }
    }
    
    /// Remove entradas antigas
    func cleanupOldEntries() {
        let oldCount = database.entries.count
        database.clearOldEntries(olderThan: maxEntryAge)
        let newCount = database.entries.count
        updatePublishedProperties()
        
        if oldCount != newCount {
            print("🗑️ ContextManager: Limpeza de entradas antigas - \(oldCount - newCount) entradas removidas")
        } else {
            print("🗑️ ContextManager: Limpeza de entradas antigas - nenhuma entrada removida")
        }
        
        Task {
            await saveContext()
        }
    }
    
    // MARK: - Private Methods
    
    private func updatePublishedProperties() {
        totalEntries = database.entries.count
        lastUpdated = database.lastUpdated
    }
    
    private func indexRecent(entry: ContextEntry) {
        let app = entry.metadata["app"] ?? entry.metadata["bundle"] ?? entry.source
        let key = String(entry.content.hashValue)
        let recent = RecentVector(vector: entry.vector, timestamp: entry.timestamp, app: app, key: key)
        recentVectors.append(recent)
        pruneRecent()
    }
    
    private func pruneRecent() {
        let cutoff = Date().addingTimeInterval(-recentMaxAgeSeconds)
        recentVectors = recentVectors.filter { $0.timestamp >= cutoff }
        if recentVectors.count > recentMaxCount {
            recentVectors = Array(recentVectors.suffix(recentMaxCount))
        }
    }
    
    private func saveContext() async {
        do {
            let data = try JSONEncoder().encode(database)
            let fileURL = documentsDirectory.appendingPathComponent("user_context.json")
            try data.write(to: fileURL)
            
            print("💾 ContextManager: Contexto salvo com sucesso")
            print("💾 ContextManager: Arquivo: \(fileURL.path)")
            print("💾 ContextManager: Tamanho: \(data.count) bytes")
            print("💾 ContextManager: Entradas salvas: \(database.entries.count)")
        } catch {
            print("❌ ContextManager: Erro ao salvar contexto: \(error.localizedDescription)")
            await MainActor.run {
                self.lastError = "Erro ao salvar contexto: \(error.localizedDescription)"
            }
        }
    }
    
    private func loadContext() async {
        isLoading = true
        lastError = nil
        
        print("📥 ContextManager: Iniciando carregamento do contexto...")
        
        defer {
            isLoading = false
        }
        
        do {
            let fileURL = documentsDirectory.appendingPathComponent("user_context.json")
            
            if fileManager.fileExists(atPath: fileURL.path) {
                let data = try Data(contentsOf: fileURL)
                database = try JSONDecoder().decode(ContextDatabase.self, from: data)
                
                print("📥 ContextManager: Contexto carregado com sucesso!")
                print("📥 ContextManager: Arquivo: \(fileURL.path)")
                print("📥 ContextManager: Tamanho: \(data.count) bytes")
                print("📥 ContextManager: Entradas carregadas: \(database.entries.count)")
                print("📥 ContextManager: Última atualização: \(database.lastUpdated)")
                
                if !database.entries.isEmpty {
                    let oldestEntry = database.entries.map { $0.timestamp }.min()
                    let newestEntry = database.entries.map { $0.timestamp }.max()
                    print("📥 ContextManager: Entrada mais antiga: \(oldestEntry ?? Date())")
                    print("📥 ContextManager: Entrada mais recente: \(newestEntry ?? Date())")
                    
                    let sourcesCount = Dictionary(grouping: database.entries, by: { $0.source }).mapValues { $0.count }
                    print("📥 ContextManager: Entradas por fonte: \(sourcesCount)")
                }
            } else {
                // Cria um banco vazio se não existir
                database = ContextDatabase()
                print("📥 ContextManager: Arquivo de contexto não encontrado - criando novo banco vazio")
            }
            
            updatePublishedProperties()
        } catch {
            print("❌ ContextManager: Erro ao carregar contexto: \(error.localizedDescription)")
            lastError = "Erro ao carregar contexto: \(error.localizedDescription)"
            // Cria um banco vazio em caso de erro
            database = ContextDatabase()
            updatePublishedProperties()
        }
        
        print("📥 ContextManager: Carregamento do contexto concluído")
    }
    
    // MARK: - Similarity Calculation
    
    private func cosineSimilarity(_ vectorA: [Double], _ vectorB: [Double]) -> Double {
        guard vectorA.count == vectorB.count else { return 0.0 }
        
        let dotProduct = zip(vectorA, vectorB).map(*).reduce(0, +)
        let magnitudeA = sqrt(vectorA.map { $0 * $0 }.reduce(0, +))
        let magnitudeB = sqrt(vectorB.map { $0 * $0 }.reduce(0, +))
        
        guard magnitudeA > 0 && magnitudeB > 0 else { return 0.0 }
        
        return dotProduct / (magnitudeA * magnitudeB)
    }
}

// MARK: - Extensions

extension ContextManager {
    /// Estatísticas do contexto
    var contextStats: (totalEntries: Int, oldestEntry: Date?, newestEntry: Date?) {
        let entries = database.entries
        let total = entries.count
        let oldest = entries.map { $0.timestamp }.min()
        let newest = entries.map { $0.timestamp }.max()
        
        return (totalEntries: total, oldestEntry: oldest, newestEntry: newest)
    }
    
    /// Entradas por fonte
    var entriesBySource: [String: Int] {
        Dictionary(grouping: database.entries, by: { $0.source })
            .mapValues { $0.count }
    }
}
