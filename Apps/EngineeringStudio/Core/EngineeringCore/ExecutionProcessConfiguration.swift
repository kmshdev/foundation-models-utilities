import Foundation

public struct ExecutionProcessConfiguration: Sendable {
    public let executableURL: URL
    public let workingDirectory: URL
    public let codexHome: URL
    public let usesChatGPTPlanProvider: Bool
    public let requestTimeout: Duration
    public init(executableURL: URL, workingDirectory: URL, codexHome: URL,
                usesChatGPTPlanProvider: Bool = true, requestTimeout: Duration = .seconds(30)) {
        self.executableURL = executableURL; self.workingDirectory = workingDirectory; self.codexHome = codexHome
        self.usesChatGPTPlanProvider = usesChatGPTPlanProvider; self.requestTimeout = requestTimeout
    }
    public var arguments: [String] {
        var result = ["app-server", "--listen", "stdio://", "-c", "shell_environment_policy.inherit=\"core\"",
                      "-c", "shell_environment_policy.exclude=[\"ACCESS_TOKEN\"]", "-c", "features.multi_agent=false"]
        if usesChatGPTPlanProvider {
            result += ["-c", "model_provider=\"openai_chatgpt_plan\"",
                       "-c", "model_providers.openai_chatgpt_plan.name=\"ChatGPT plan\"",
                       "-c", "model_providers.openai_chatgpt_plan.base_url=\"https://api.openai.com/v1\"",
                       "-c", "model_providers.openai_chatgpt_plan.env_key=\"ACCESS_TOKEN\"",
                       "-c", "model_providers.openai_chatgpt_plan.wire_api=\"responses\"",
                       "-c", "model_providers.openai_chatgpt_plan.requires_openai_auth=false",
                       "-c", "model_providers.openai_chatgpt_plan.supports_websockets=false"]
        }
        return result
    }
}
