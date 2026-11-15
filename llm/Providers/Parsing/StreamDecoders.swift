import Foundation

/// Decodes one NDJSON line from Ollama's `/api/chat` stream.
nonisolated enum OllamaStreamDecoder {
    struct Line: Decodable {
        struct Message: Decodable {
            var content: String?
            var thinking: String?
        }
        var message: Message?
        var done: Bool?
        var error: String?
        var prompt_eval_count: Int?
        var eval_count: Int?
        var eval_duration: Int64?
    }

    static func chunks(fromLine line: String) throws -> [ChatChunk] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        let decoded: Line
        do {
            decoded = try JSONDecoder().decode(Line.self, from: Data(trimmed.utf8))
        } catch {
            throw ProviderError.decoding("Unexpected response line from Ollama.")
        }
        if let message = decoded.error { throw ProviderError.server(message) }

        var chunks: [ChatChunk] = []
        if let thinking = decoded.message?.thinking, !thinking.isEmpty { chunks.append(.thinking(thinking)) }
        if let content = decoded.message?.content, !content.isEmpty { chunks.append(.content(content)) }
        if decoded.done == true {
            chunks.append(.done(GenerationStats(
                promptTokens: decoded.prompt_eval_count,
                completionTokens: decoded.eval_count,
                generationSeconds: decoded.eval_duration.map { Double($0) / 1_000_000_000 }
            )))
        }
        return chunks
    }
}

/// Decodes one SSE `data:` payload from `/v1/chat/completions`.
nonisolated enum OpenAIStreamDecoder {
    struct Payload: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                var content: String?
                /// llama.cpp, LM Studio, vLLM and DeepSeek use one of these for reasoning.
                var reasoning_content: String?
                var reasoning: String?
            }
            var delta: Delta?
            var finish_reason: String?
        }
        struct Usage: Decodable {
            var prompt_tokens: Int?
            var completion_tokens: Int?
        }
        struct APIError: Decodable { var message: String? }

        var choices: [Choice]?
        var usage: Usage?
        var error: APIError?
    }

    enum Result: Equatable {
        case chunks([ChatChunk], usage: GenerationStats?)
        case done
    }

    static func decode(_ data: String) throws -> Result {
        let trimmed = data.trimmingCharacters(in: .whitespaces)
        if trimmed == "[DONE]" { return .done }
        guard !trimmed.isEmpty else { return .chunks([], usage: nil) }
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: Data(trimmed.utf8))
        } catch {
            throw ProviderError.decoding("Unexpected streaming payload from the server.")
        }
        if let message = payload.error?.message { throw ProviderError.server(message) }

        var chunks: [ChatChunk] = []
        for choice in payload.choices ?? [] {
            if let reasoning = choice.delta?.reasoning_content ?? choice.delta?.reasoning, !reasoning.isEmpty {
                chunks.append(.thinking(reasoning))
            }
            if let content = choice.delta?.content, !content.isEmpty {
                chunks.append(.content(content))
            }
        }
        let usage = payload.usage.map {
            GenerationStats(promptTokens: $0.prompt_tokens, completionTokens: $0.completion_tokens)
        }
        return .chunks(chunks, usage: usage)
    }
}
