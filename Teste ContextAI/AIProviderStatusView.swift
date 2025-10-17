//
//  AIProviderStatusView.swift
//  Teste Context AI
//
//  Created by Assistant on 15/10/25.
//

import SwiftUI

struct AIProviderStatusView: View {
    @ObservedObject var llmManager: LLMManager
    @StateObject private var ollamaManager = OllamaManager.shared
    @State private var showingSetup = false
    @State private var selectedProvider: HybridAIProvider.ProviderType = .foundation
    
    private func updateSelectedProvider() {
        if let hybridProvider = llmManager.provider as? HybridAIProvider {
            selectedProvider = hybridProvider.getCurrentProviderType()
        }
    }
    
    private var hybridProvider: HybridAIProvider {
        llmManager.provider as? HybridAIProvider ?? HybridAIProvider()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Provedor de IA")
                    .font(.headline)
                
                Spacer()
                
                Button("Configurar Ollama") {
                    showingSetup = true
                }
                .font(.caption)
                .foregroundColor(.blue)
                .disabled(selectedProvider == .foundation)
            }
            
            // Seleção do provider
            VStack(alignment: .leading, spacing: 8) {
                Text("Escolha o provedor:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Picker("Provedor", selection: $selectedProvider) {
                    ForEach(HybridAIProvider.ProviderType.allCases, id: \.self) { providerType in
                        Text(providerType.description)
                            .tag(providerType)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .onChange(of: selectedProvider) { newValue in
                    llmManager.switchProvider(to: newValue)
                }
                .onAppear {
                    updateSelectedProvider()
                }
            }
            
            // Status atual
            let currentInfo = hybridProvider.getCurrentProviderInfo()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Circle()
                        .fill(currentInfo.isAvailable ? .green : .red)
                        .frame(width: 8, height: 8)
                    
                    Text("Status: \(currentInfo.name)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                }
                
                if currentInfo.isAvailable {
                    Text("✅ Funcionando corretamente")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Text("❌ Não disponível")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding(.vertical, 4)
            
            // Lista de todos os providers
            VStack(alignment: .leading, spacing: 4) {
                Text("Disponibilidade:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                ForEach(hybridProvider.getAllProvidersStatus(), id: \.name) { providerInfo in
                    HStack {
                        Circle()
                            .fill(providerInfo.isAvailable ? .green : .gray)
                            .frame(width: 6, height: 6)
                        
                        Text(providerInfo.name)
                            .font(.caption)
                        
                        Spacer()
                        
                        if selectedProvider == providerInfo.type {
                            Text("SELECIONADO")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                        } else {
                            Text(providerInfo.isAvailable ? "✅" : "❌")
                                .font(.caption)
                        }
                    }
                }
            }
            
            // Status do Ollama Manager
            if ollamaManager.isInstalling {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Instalação do Ollama:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        
                        Text(ollamaManager.installationProgress)
                            .font(.caption)
                    }
                }
                .padding(.top, 8)
            }
            
            if let error = ollamaManager.lastError {
                Text("Erro: \(error)")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
        .sheet(isPresented: $showingSetup) {
            OllamaSetupView()
        }
    }
}

struct OllamaSetupView: View {
    @StateObject private var ollamaManager = OllamaManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Configuração do Ollama")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("Fechar") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            
            Text("O Ollama será baixado e configurado automaticamente para funcionar offline no seu app.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            if ollamaManager.isInstalling {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    
                    Text(ollamaManager.installationProgress)
                        .font(.subheadline)
                }
            } else if ollamaManager.isRunning {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.green)
                    
                    Text("Ollama configurado com sucesso!")
                        .font(.headline)
                        .foregroundColor(.green)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 50))
                        .foregroundColor(.blue)
                    
                    Text("Ollama permite que o app funcione completamente offline com modelos de IA locais.")
                        .multilineTextAlignment(.center)
                }
            }
            
            Spacer()
            
            if !ollamaManager.isInstalling && !ollamaManager.isRunning {
                Button("Instalar Ollama") {
                    Task {
                        await ollamaManager.setupOllamaIfNeeded()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding()
        .frame(width: 400, height: 300)
    }
}

#Preview {
    AIProviderStatusView(llmManager: LLMManager())
}
