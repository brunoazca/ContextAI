//
//  ContentView.swift
//  Teste Context AI
//
//  Created by Bruno Azambuja Carvalho on 15/10/25.
//

import SwiftUI
import Foundation
import Vision
import ScreenCaptureKit
#if os(macOS)
import AppKit
#endif

enum ScreenCaptureError: Error {
    case noDisplayFound
    case captureFailed
}

class StreamOutput: NSObject, SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // This is required for the stream output protocol
    }
}

class FrameCapture: NSObject, SCStreamOutput {
    private let completion: (CGImage) -> Void
    private var hasCaptured = false
    
    init(completion: @escaping (CGImage) -> Void) {
        self.completion = completion
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard !hasCaptured else { return }
        hasCaptured = true
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        
        completion(cgImage)
    }
}

struct ContentView: View {
    @State private var recognizedText: String = ""
    @State private var isProcessing: Bool = false
    @State private var lastErrorMessage: String? = nil
    @StateObject private var llmManager = LLMManager()
    @State private var showLLMAnalysis: Bool = false
    @State private var customPrompt: String = ""
    @State private var isContinuousCapture: Bool = false
    @State private var captureTimer: Timer? = nil
    @State private var captureCount: Int = 0
    @State private var lastCaptureTime: Date = Date()
    @State private var lastAnalysisTime: Date = Date()
    @State private var showContextInfo: Bool = false
    @State private var manualContext: String = ""
    @State private var overlayTextSuggestion: String? = nil
    @State private var showSuggestionOverlay: Bool = false
    @State private var currentAnalysisTask: Task<Void, Never>? = nil
    @State private var showingDashboard: Bool = false
    
    private var timeUntilNextCapture: Int {
        guard isContinuousCapture else { return 0 }
        let elapsed = Date().timeIntervalSince(lastCaptureTime)
        let remaining = max(0, 3 - Int(elapsed))
        return remaining
    }
    
    private var timeUntilNextAnalysis: Int {
        guard isContinuousCapture else { return 0 }
        let elapsed = Date().timeIntervalSince(lastAnalysisTime)
        let remaining = max(0, 15 - Int(elapsed))
        return remaining
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Gravação de tela, OCR e Análise com IA")
                    .font(.title2)
                
                Spacer()
                
                Button("Dashboard") {
                    showingDashboard = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if let lastErrorMessage {
                Text(lastErrorMessage)
                    .foregroundStyle(.red)
            }
            
            if let llmError = llmManager.lastError {
                Text("Erro LLM: \(llmError)")
                    .foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                Button(action: performSingleCapture) {
                    HStack {
                        if isProcessing {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isProcessing ? "Processando..." : "Captura única")
                    }
                }
                .disabled(isProcessing || isContinuousCapture)
                
                Button(action: toggleContinuousCapture) {
                    HStack {
                        if isContinuousCapture {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isContinuousCapture ? "Parar gravação contínua" : "Iniciar gravação contínua")
                    }
                }
                .disabled(isProcessing)
                .foregroundColor(isContinuousCapture ? .red : .primary)
                
                if !recognizedText.isEmpty {
                    Button(action: analyzeWithLLM) {
                        HStack {
                            if llmManager.isLoading {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(llmManager.isLoading ? "Analisando..." : "Analisar com IA")
                        }
                    }
                    .disabled(llmManager.isLoading || recognizedText.isEmpty)
                }
            }
            
            if isContinuousCapture {
                VStack(spacing: 4) {
                    HStack {
                        Text("Capturas realizadas: \(captureCount)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Próxima captura em: \(timeUntilNextCapture)s")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Capturas a cada 3s, Análises a cada 15s")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Próxima análise em: \(timeUntilNextAnalysis)s")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
            }

            Text("Texto reconhecido:")
                .font(.headline)
                .padding(.top, 8)

            ScrollView {
                Text(recognizedText.isEmpty ? "(sem texto)" : recognizedText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(8)
                    .background(Color.gray.opacity(0.08))
                    .cornerRadius(6)
            }
            .frame(minHeight: 160)
            
            if !llmManager.lastResponse.isEmpty {
                Text("Análise da IA:")
                    .font(.headline)
                    .padding(.top, 8)
                
                ScrollView {
                    Text(llmManager.lastResponse)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(8)
                        .background(Color.blue.opacity(0.08))
                        .cornerRadius(6)
                }
                .frame(minHeight: 120)
            }
            
            // Campo para prompt customizado
            VStack(alignment: .leading, spacing: 8) {
                Text("Prompt customizado:")
                    .font(.headline)
                
                TextField("Digite um prompt personalizado...", text: $customPrompt, axis: .vertical)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .lineLimit(3...6)
                
                HStack(spacing: 12) {
                    // Botão para análise com texto capturado
                    if !customPrompt.isEmpty && !recognizedText.isEmpty {
                        Button("Analisar com texto capturado") {
                            analyzeWithCustomPrompt()
                        }
                        .disabled(llmManager.isLoading)
                    }
                    
                    // Botão para análise usando apenas contexto
                    if !customPrompt.isEmpty {
                        Button("Analisar com contexto histórico") {
                            analyzeWithContextOnly()
                        }
                        .disabled(llmManager.isLoading)
                        .foregroundColor(.blue)
                    }
                }
                
                if !customPrompt.isEmpty {
                    Text("💡 Dica: Use 'Analisar com contexto histórico' para fazer perguntas sobre informações anteriores sem precisar capturar tela")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
                
                // Exemplos de prompts para contexto histórico
                if showContextInfo && !customPrompt.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Exemplos de prompts para contexto histórico:")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        let examples = [
                            "Resuma as principais informações que foram capturadas hoje",
                            "Que tipos de documentos ou textos foram analisados?",
                            "Quais foram os principais insights das análises anteriores?",
                            "Há algum padrão ou tendência nas informações capturadas?",
                            "Me dê um resumo executivo do meu histórico de uso"
                        ]
                        
                        ForEach(examples, id: \.self) { example in
                            Button(action: {
                                customPrompt = example
                            }) {
                                Text("• \(example)")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                    .multilineTextAlignment(.leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.horizontal, 8)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
                }
            }
            .padding(.top, 8)
            
            // Status dos provedores de IA
            AIProviderStatusView(llmManager: llmManager)
                .padding(.top, 8)
        }
        .padding()
        .overlay(alignment: .topTrailing) {
            if showSuggestionOverlay, let overlayTextSuggestion {
                SuggestionOverlayView(text: overlayTextSuggestion) {
                    withAnimation { showSuggestionOverlay = false }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(10)
            }
        }
        .onAppear {
            // Timer para atualizar a UI do contador
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                if isContinuousCapture {
                    // Força a atualização da UI
                }
            }
        }
        .onDisappear {
            stopContinuousCapture()
        }
        .sheet(isPresented: $showingDashboard) {
            UserDashboardView(llmManager: llmManager)
        }
    }

    private func performSingleCapture() {
        isProcessing = true
        lastErrorMessage = nil

        Task {
            do {
                let cgImage = try await captureScreen()
                await performOCR(on: cgImage)
            } catch {
                await MainActor.run {
                    self.lastErrorMessage = "Erro na captura: \(error.localizedDescription)"
                    self.isProcessing = false
                }
            }
        }
    }
    
    private func toggleContinuousCapture() {
        if isContinuousCapture {
            stopContinuousCapture()
        } else {
            startContinuousCapture()
        }
    }
    
    private func startContinuousCapture() {
        isContinuousCapture = true
        captureCount = 0
        lastCaptureTime = Date()
        lastAnalysisTime = Date()
        
        // Primeira captura imediata
        performContinuousCapture()
        
        // Timer para capturas subsequentes a cada 3 segundos
        captureTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            performContinuousCapture()
        }
    }
    
    private func stopContinuousCapture() {
        isContinuousCapture = false
        captureTimer?.invalidate()
        captureTimer = nil
        
        // Cancela análise em andamento
        currentAnalysisTask?.cancel()
        currentAnalysisTask = nil
    }
    
    private func performContinuousCapture() {
        guard isContinuousCapture else { return }
        
        Task {
            do {
                let cgImage = try await captureScreen()
                await performOCR(on: cgImage)
                
                 // Só analisa a cada 15 segundos
                 let now = Date()
                 let timeSinceLastAnalysis = now.timeIntervalSince(lastAnalysisTime)
                 if timeSinceLastAnalysis >= 15.0 {
                     // Cancela análise anterior se existir
                     currentAnalysisTask?.cancel()
                     
                     // Verifica se já não há uma análise em andamento
                     guard !llmManager.isLoading else {
                         print("⏳ Análise já em andamento, pulando esta captura")
                         return
                     }
                     
                     // Inicia nova análise
                     currentAnalysisTask = Task {
                         await suggestActionIfPossible()
                     }
                     await MainActor.run {
                         self.lastAnalysisTime = now
                     }
                 }
                
                await MainActor.run {
                    self.captureCount += 1
                    self.lastCaptureTime = Date()
                }
            } catch {
                await MainActor.run {
                    self.lastErrorMessage = "Erro na captura contínua: \(error.localizedDescription)"
                    // Não para a captura contínua por causa de um erro
                }
            }
        }
    }
    
    private func captureScreen() async throws -> CGImage {
        let availableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        
        guard let mainDisplay = availableContent.displays.first else {
            throw ScreenCaptureError.noDisplayFound
        }
        
        let filter = SCContentFilter(display: mainDisplay, excludingWindows: [])
        
        let configuration = SCStreamConfiguration()
        configuration.width = Int(mainDisplay.width)
        configuration.height = Int(mainDisplay.height)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 5
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.captureResolution = .best
        configuration.showsCursor = false
        
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        
        var capturedImage: CGImage?
        var captureError: Error?
        
        let semaphore = DispatchSemaphore(value: 0)
        
        // Create a custom stream output to capture the first frame
        let frameCapture = FrameCapture { image in
            capturedImage = image
            stream.stopCapture()
            semaphore.signal()
        }
        
        try stream.addStreamOutput(frameCapture, type: .screen, sampleHandlerQueue: DispatchQueue.global())
        
        stream.startCapture { error in
            if let error = error {
                captureError = error
                semaphore.signal()
            }
        }
        
        semaphore.wait()
        
        if let error = captureError {
            throw error
        }
        
        guard let image = capturedImage else {
            throw ScreenCaptureError.captureFailed
        }
        
        return image
    }
    
    private func performOCR(on cgImage: CGImage) async {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["pt-BR", "en-US"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            let observations = request.results as? [VNRecognizedTextObservation] ?? []
            let lines: [String] = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }
            let text = lines.joined(separator: "\n")
            await MainActor.run {
                self.recognizedText = text
                self.isProcessing = false
            }
             // Só analisa se passou tempo suficiente desde a última análise
             let now = Date()
             let timeSinceLastAnalysis = now.timeIntervalSince(lastAnalysisTime)
             if timeSinceLastAnalysis >= 15.0 {
                 // Cancela análise anterior se existir
                 currentAnalysisTask?.cancel()
                 
                 // Verifica se já não há uma análise em andamento
                 guard !llmManager.isLoading else {
                     print("⏳ Análise já em andamento, pulando esta captura")
                     return
                 }
                 
                 // Inicia nova análise
                 currentAnalysisTask = Task {
                     await suggestActionIfPossible()
                 }
                 await MainActor.run {
                     self.lastAnalysisTime = now
                 }
             }
        } catch {
            await MainActor.run {
                self.lastErrorMessage = "Falha no OCR: \(error.localizedDescription)"
                self.isProcessing = false
            }
        }
    }
    
    private func analyzeWithLLM() {
        Task {
            do {
                _ = try await llmManager.processOCRText(recognizedText)
            } catch {
                print("Erro na análise LLM: \(error)")
            }
        }
    }
    
    private func analyzeWithCustomPrompt() {
        Task {
            do {
                _ = try await llmManager.processWithCustomPrompt(recognizedText, customPrompt: customPrompt)
            } catch {
                print("Erro na análise LLM customizada: \(error)")
            }
        }
    }
    
    private func analyzeWithContextOnly() {
        Task {
            do {
                _ = try await llmManager.processCustomPromptWithContext(customPrompt)
            } catch {
                print("Erro na análise com contexto histórico: \(error)")
            }
        }
    }
}

#Preview {
    ContentView()
}

// MARK: - Suggestion Overlay View
private struct SuggestionOverlayView: View {
    let text: String
    let onClose: () -> Void
    @State private var isVisible: Bool = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sugestão da IA")
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
            }
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Ok") { onClose() }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .cornerRadius(10)
        .shadow(radius: 8)
        .frame(maxWidth: 320)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                onClose()
            }
        }
        .padding(.top, 12)
        .padding(.trailing, 12)
    }
}

// MARK: - Suggestion trigger
extension ContentView {
    @MainActor private func presentSuggestionText(_ text: String) {
        overlayTextSuggestion = text
        withAnimation { showSuggestionOverlay = true }
    }
    
    private func suggestActionIfPossible() async {
        guard !recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { 
            print("📝 Nenhum texto reconhecido para análise")
            return 
        }
        
        // Verifica se a task foi cancelada
        if Task.isCancelled {
            print("🚫 Análise cancelada antes de iniciar")
            return
        }
        
        print("🚀 Iniciando análise de sugestão...")
        
        do {
            let suggestionText = try await llmManager.generateSuggestionText(from: recognizedText)
            
            // Verifica novamente se foi cancelada
            if Task.isCancelled {
                print("🚫 Análise cancelada após processamento")
                return
            }
            
            await MainActor.run {
                presentSuggestionText(suggestionText)
                #if os(macOS)
                SuggestionPopupManager.shared.present(text: suggestionText)
                #endif
            }
            
            print("✅ Sugestão apresentada com sucesso")
            
        } catch {
            if Task.isCancelled {
                print("🚫 Análise cancelada durante processamento")
            } else {
                print("❌ Erro na análise: \(error)")
            }
        }
    }
}
