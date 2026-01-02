import SwiftUI

struct LLMSettingsView: View {
    @ObservedObject var llmManager = LLMManager.shared
    @State private var apiKeyInput = ""
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("LLM PROVIDER")
                    .font(Theme.uiFont(size: 12, weight: .bold))
                    .tracking(2)
                    .padding(.bottom, 8)
                    .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.borderColor), alignment: .bottom)
                
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $llmManager.useRemote) {
                        Text("Use Remote Inference")
                            .font(Theme.bodyFont(size: 14))
                    }
                    .toggleStyle(.switch)
                    
                    Text("Local Ollama remains the default fallback when remote is disabled or unavailable.")
                        .font(Theme.bodyFont(size: 12))
                        .foregroundColor(Theme.inkBlack.opacity(0.7))
                }
                .padding(16)
                .newsprintCard()
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("REMOTE (OPENAI-COMPATIBLE)")
                        .font(Theme.uiFont(size: 12, weight: .bold))
                        .tracking(2)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("BASE URL")
                            .font(Theme.uiFont(size: 10, weight: .bold))
                        TextField("https://api.venice.ai/api/v1", text: $llmManager.remoteBaseURL)
                            .newsprintInput()
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("API KEY")
                            .font(Theme.uiFont(size: 10, weight: .bold))
                        SecureField("Enter API key", text: $apiKeyInput)
                            .newsprintInput()
                        
                        HStack(spacing: 12) {
                            Button("SAVE KEY") {
                                llmManager.storeRemoteAPIKey(apiKeyInput)
                                apiKeyInput = ""
                            }
                            .newsprintButton(isPrimary: true)
                            .disabled(apiKeyInput.isEmpty)
                            
                            Button("CLEAR KEY") {
                                llmManager.clearRemoteAPIKey()
                                apiKeyInput = ""
                            }
                            .newsprintButton(isPrimary: false)
                        }
                        
                        Text(llmManager.remoteKeyStored ? "API key stored in Keychain." : "No API key stored.")
                            .font(Theme.bodyFont(size: 12))
                            .foregroundColor(Theme.inkBlack.opacity(0.7))
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("MODEL")
                            .font(Theme.uiFont(size: 10, weight: .bold))
                        
                        if llmManager.remoteModels.isEmpty {
                            Text("No models loaded. Refresh to list Venice models.")
                                .font(Theme.bodyFont(size: 12))
                                .foregroundColor(Theme.inkBlack.opacity(0.7))
                        } else {
                            Picker("Model", selection: $llmManager.remoteModel) {
                                ForEach(llmManager.remoteModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        
                        HStack(spacing: 12) {
                            Button("REFRESH MODELS") {
                                Task {
                                    await llmManager.refreshRemoteModels()
                                }
                            }
                            .newsprintButton(isPrimary: false)
                            
                            if llmManager.isRefreshingModels {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                        }
                        
                        if !llmManager.remoteModelsError.isEmpty {
                            Text(llmManager.remoteModelsError)
                                .font(Theme.bodyFont(size: 12))
                                .foregroundColor(Theme.editorialRed)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("VENICE PARAMETERS")
                            .font(Theme.uiFont(size: 10, weight: .bold))
                        
                        if llmManager.isUsingVeniceRemote {
                            Toggle(isOn: $llmManager.veniceIncludeSystemPrompt) {
                                Text("Include Venice system prompt")
                                    .font(Theme.bodyFont(size: 12))
                            }
                            .toggleStyle(.switch)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("WEB SEARCH")
                                    .font(Theme.uiFont(size: 9, weight: .bold))
                                Picker("Web Search", selection: $llmManager.veniceWebSearchMode) {
                                    Text("Auto").tag("auto")
                                    Text("On").tag("on")
                                    Text("Off").tag("off")
                                }
                                .pickerStyle(.segmented)
                            }
                        } else {
                            Text("Set a Venice base URL to enable Venice parameters like web search.")
                                .font(Theme.bodyFont(size: 12))
                                .foregroundColor(Theme.inkBlack.opacity(0.7))
                        }
                    }
                    
                    if let issue = llmManager.remoteSettingsIssue {
                        Text(issue)
                            .font(Theme.bodyFont(size: 12))
                            .foregroundColor(Theme.editorialRed)
                    }
                }
                .padding(16)
                .newsprintCard()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("COMING SOON")
                        .font(Theme.uiFont(size: 12, weight: .bold))
                        .tracking(2)
                    Text("Image, video, and TTS endpoints will be wired into this provider selection.")
                        .font(Theme.bodyFont(size: 12))
                        .foregroundColor(Theme.inkBlack.opacity(0.7))
                }
                .padding(16)
                .newsprintCard()
            }
            .padding()
        }
        .background(Theme.background)
        .onAppear {
            llmManager.refreshRemoteKeyStatus()
        }
    }
}
