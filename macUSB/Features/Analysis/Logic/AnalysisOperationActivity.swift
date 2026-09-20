import Foundation

extension AnalysisLogic {
    func updateAnalysisOperationActivity(from wasAnalyzing: Bool) {
        guard wasAnalyzing != isAnalyzing else { return }
        if isAnalyzing {
            analysisOperationToken?.finish()
            let context = selectedFileUrl?.lastPathComponent ?? "selected_source"
            analysisOperationToken = AppActiveOperationRegistry.shared.begin(
                kind: .analysis,
                context: "source_analysis:\(context)"
            )
        } else {
            analysisOperationToken?.finish()
            analysisOperationToken = nil
        }
    }
}
