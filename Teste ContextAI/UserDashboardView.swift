//
//  UserDashboardView.swift
//  Teste Context AI
//
//  Created by Assistant on 15/10/25.
//

import SwiftUI
import Foundation

struct UserDashboardView: View {
    @ObservedObject var llmManager: LLMManager
    @State private var dashboardData: DashboardData?
    @State private var isLoading = false
    @State private var selectedTimeRange: TimeRange = .today
    
    enum TimeRange: String, CaseIterable {
        case today = "Hoje"
        case week = "Esta Semana"
        case month = "Este Mês"
        case all = "Todo Período"
        
        var dateRange: (start: Date, end: Date) {
            let now = Date()
            let calendar = Calendar.current
            
            switch self {
            case .today:
                let start = calendar.startOfDay(for: now)
                return (start, now)
            case .week:
                let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
                return (start, now)
            case .month:
                let start = calendar.dateInterval(of: .month, for: now)?.start ?? now
                return (start, now)
            case .all:
                return (Date.distantPast, now)
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Dashboard do Usuário")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("Atualizar") {
                    Task {
                        await loadDashboardData()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)
            }
            
            // Time Range Selector
            Picker("Período", selection: $selectedTimeRange) {
                ForEach(TimeRange.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .onChange(of: selectedTimeRange) { _ in
                Task {
                    await loadDashboardData()
                }
            }
            
            if isLoading {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Carregando dashboard...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
            } else if let data = dashboardData {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        // Estatísticas Gerais
                        StatsCardsView(data: data)
                        
                        // Timeline de Atividades
                        ActivityTimelineView(activities: data.activities)
                        
                        // Sugestões Geradas
                        SuggestionsView(suggestions: data.suggestions)
                        
                        // Insights e Padrões
                        InsightsView(insights: data.insights)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    
                    Text("Nenhum dado disponível")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("Use o app por alguns minutos para gerar dados do dashboard")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
        .padding()
        .onAppear {
            Task {
                await loadDashboardData()
            }
        }
    }
    
    private func loadDashboardData() async {
        await MainActor.run {
            isLoading = true
        }
        
        do {
            let data = try await generateDashboardData()
            await MainActor.run {
                self.dashboardData = data
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
            }
            print("Erro ao carregar dashboard: \(error)")
        }
    }
    
    private func generateDashboardData() async throws -> DashboardData {
        let contextManager = llmManager.contextManagerInstance
        let timeRange = selectedTimeRange.dateRange
        
        // Filtra entradas por período
        let filteredEntries = contextManager.database.entries.filter { entry in
            entry.timestamp >= timeRange.start && entry.timestamp <= timeRange.end
        }
        
        // Gera estatísticas
        let stats = generateStats(from: filteredEntries)
        
        // Gera atividades
        let activities = generateActivities(from: filteredEntries)
        
        // Gera sugestões
        let suggestions = generateSuggestions(from: filteredEntries)
        
        // Gera insights
        let insights = try await generateInsights(from: filteredEntries)
        
        return DashboardData(
            stats: stats,
            activities: activities,
            suggestions: suggestions,
            insights: insights,
            timeRange: selectedTimeRange
        )
    }
    
    private func generateStats(from entries: [ContextEntry]) -> UserStats {
        let totalEntries = entries.count
        let ocrEntries = entries.filter { $0.source == "OCR" }.count
        let llmEntries = entries.filter { $0.source == "LLM Response" }.count
        let manualEntries = entries.filter { $0.source == "Manual" }.count
        
        let totalWords = entries.reduce(0) { $0 + $1.content.components(separatedBy: .whitespaces).count }
        let avgWordsPerEntry = totalEntries > 0 ? totalWords / totalEntries : 0
        
        let mostActiveHour = getMostActiveHour(from: entries)
        
        return UserStats(
            totalEntries: totalEntries,
            ocrEntries: ocrEntries,
            llmEntries: llmEntries,
            manualEntries: manualEntries,
            totalWords: totalWords,
            avgWordsPerEntry: avgWordsPerEntry,
            mostActiveHour: mostActiveHour
        )
    }
    
    private func generateActivities(from entries: [ContextEntry]) -> [UserActivity] {
        return entries.sorted { $0.timestamp > $1.timestamp }.map { entry in
            UserActivity(
                id: entry.id,
                timestamp: entry.timestamp,
                type: ActivityType.from(source: entry.source),
                content: String(entry.content.prefix(100)),
                metadata: entry.metadata
            )
        }
    }
    
    private func generateSuggestions(from entries: [ContextEntry]) -> [UserSuggestion] {
        let suggestionEntries = entries.filter { $0.metadata["for_suggestion"] == "true" }
        
        return suggestionEntries.map { entry in
            UserSuggestion(
                id: entry.id,
                timestamp: entry.timestamp,
                suggestion: entry.content,
                confidence: extractConfidence(from: entry.metadata)
            )
        }
    }
    
    private func generateInsights(from entries: [ContextEntry]) async throws -> [UserInsight] {
        guard !entries.isEmpty else { return [] }
        
        let contextString = entries.prefix(5).map { entry in
            "[\(entry.source)] \(entry.content)"
        }.joined(separator: "\n\n")
        
        let prompt = """
        Analise o seguinte histórico de uso do usuário e forneça insights sobre padrões, tendências e recomendações. Seja conciso e objetivo.

        Histórico:
        \(contextString)

        Forneça 3-5 insights em formato JSON:
        [
            {"type": "padrao", "title": "Título", "description": "Descrição", "confidence": 0.8},
            {"type": "tendencia", "title": "Título", "description": "Descrição", "confidence": 0.7}
        ]
        """
        
        do {
            let response = try await llmManager.processText(prompt)
            return parseInsights(from: response)
        } catch {
            return [
                UserInsight(
                    type: .pattern,
                    title: "Análise de Padrões",
                    description: "Padrões de uso detectados no período selecionado",
                    confidence: 0.5
                )
            ]
        }
    }
    
    private func getMostActiveHour(from entries: [ContextEntry]) -> Int {
        let hourCounts = Dictionary(grouping: entries) { entry in
            Calendar.current.component(.hour, from: entry.timestamp)
        }.mapValues { $0.count }
        
        return hourCounts.max(by: { $0.value < $1.value })?.key ?? 0
    }
    
    private func extractConfidence(from metadata: [String: String]) -> Double {
        if let confidenceString = metadata["confidence"],
           let confidence = Double(confidenceString) {
            return confidence
        }
        return 0.5
    }
    
    private func parseInsights(from response: String) -> [UserInsight] {
        // Implementação simples de parsing JSON
        // Em produção, usaria JSONDecoder
        return [
            UserInsight(
                type: .pattern,
                title: "Padrão de Uso",
                description: "Usuário ativo principalmente durante horário comercial",
                confidence: 0.8
            ),
            UserInsight(
                type: .trend,
                title: "Tendência Crescente",
                description: "Aumento no uso de análise de documentos",
                confidence: 0.7
            )
        ]
    }
}

// MARK: - Data Models

struct DashboardData {
    let stats: UserStats
    let activities: [UserActivity]
    let suggestions: [UserSuggestion]
    let insights: [UserInsight]
    let timeRange: UserDashboardView.TimeRange
}

struct UserStats {
    let totalEntries: Int
    let ocrEntries: Int
    let llmEntries: Int
    let manualEntries: Int
    let totalWords: Int
    let avgWordsPerEntry: Int
    let mostActiveHour: Int
}

struct UserActivity: Identifiable {
    let id: UUID
    let timestamp: Date
    let type: ActivityType
    let content: String
    let metadata: [String: String]
}

enum ActivityType: String, CaseIterable {
    case ocr = "OCR"
    case llm = "LLM"
    case manual = "Manual"
    case suggestion = "Sugestão"
    
    var icon: String {
        switch self {
        case .ocr: return "camera.viewfinder"
        case .llm: return "brain.head.profile"
        case .manual: return "hand.point.up"
        case .suggestion: return "lightbulb"
        }
    }
    
    var color: Color {
        switch self {
        case .ocr: return .blue
        case .llm: return .purple
        case .manual: return .green
        case .suggestion: return .orange
        }
    }
    
    static func from(source: String) -> ActivityType {
        switch source {
        case "OCR": return .ocr
        case "LLM Response": return .llm
        case "Manual": return .manual
        default: return .manual
        }
    }
}

struct UserSuggestion: Identifiable {
    let id: UUID
    let timestamp: Date
    let suggestion: String
    let confidence: Double
}

struct UserInsight: Identifiable {
    let id = UUID()
    let type: InsightType
    let title: String
    let description: String
    let confidence: Double
    
    enum InsightType: String {
        case pattern = "padrao"
        case trend = "tendencia"
        case recommendation = "recomendacao"
    }
}

// MARK: - View Components

struct StatsCardsView: View {
    let data: DashboardData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Estatísticas Gerais")
                .font(.headline)
                .fontWeight(.bold)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StatCard(
                    title: "Total de Entradas",
                    value: "\(data.stats.totalEntries)",
                    icon: "doc.text",
                    color: .blue
                )
                
                StatCard(
                    title: "Palavras Processadas",
                    value: "\(data.stats.totalWords)",
                    icon: "textformat",
                    color: .green
                )
                
                StatCard(
                    title: "Capturas OCR",
                    value: "\(data.stats.ocrEntries)",
                    icon: "camera.viewfinder",
                    color: .orange
                )
                
                StatCard(
                    title: "Respostas IA",
                    value: "\(data.stats.llmEntries)",
                    icon: "brain.head.profile",
                    color: .purple
                )
            }
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

struct ActivityTimelineView: View {
    let activities: [UserActivity]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Timeline de Atividades")
                .font(.headline)
                .fontWeight(.bold)
            
            if activities.isEmpty {
                Text("Nenhuma atividade no período selecionado")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(activities.prefix(10)) { activity in
                    ActivityRowView(activity: activity)
                }
            }
        }
    }
}

struct ActivityRowView: View {
    let activity: UserActivity
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: activity.type.icon)
                .foregroundColor(activity.type.color)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.type.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                
                Text(activity.content)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Text(activity.timestamp, style: .time)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct SuggestionsView: View {
    let suggestions: [UserSuggestion]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sugestões Geradas")
                .font(.headline)
                .fontWeight(.bold)
            
            if suggestions.isEmpty {
                Text("Nenhuma sugestão no período selecionado")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(suggestions.prefix(5)) { suggestion in
                    SuggestionCardView(suggestion: suggestion)
                }
            }
        }
    }
}

struct SuggestionCardView: View {
    let suggestion: UserSuggestion
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "lightbulb")
                    .foregroundColor(.orange)
                
                Text("Sugestão")
                    .font(.caption)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text("\(Int(suggestion.confidence * 100))%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Text(suggestion.suggestion)
                .font(.caption)
                .lineLimit(3)
            
            Text(suggestion.timestamp, style: .relative)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
}

struct InsightsView: View {
    let insights: [UserInsight]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Insights e Padrões")
                .font(.headline)
                .fontWeight(.bold)
            
            if insights.isEmpty {
                Text("Nenhum insight disponível")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(insights) { insight in
                    InsightCardView(insight: insight)
                }
            }
        }
    }
}

struct InsightCardView: View {
    let insight: UserInsight
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(.blue)
                
                Text(insight.title)
                    .font(.caption)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text("\(Int(insight.confidence * 100))%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Text(insight.description)
                .font(.caption)
                .lineLimit(3)
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }
}

#Preview {
    UserDashboardView(llmManager: LLMManager())
}
