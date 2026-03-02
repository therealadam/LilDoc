import Foundation
import FoundationModels

// MARK: - Verify Foundation Models availability

let model = SystemLanguageModel.default
print("Model availability: \(model.availability)")

// MARK: - Test through the model

let text = SampleText.meetingNotes

let session = LanguageModelSession(
    tools: [
        GetInfoTool(text: text),
        FindTool(text: text),
        CountPatternTool(text: text),
    ],
    instructions: "You are a text editing assistant. Use the provided tools to answer questions about the document. Be concise."
)

let r1 = try await session.respond(to: "How many TODOs are in this document?")
print("Q1:", r1.content)
