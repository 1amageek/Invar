public protocol ChangeAnalyzing: Sendable {
    func analyze(_ request: ChangeAnalysisRequest) throws -> ChangeAnalysis
}
