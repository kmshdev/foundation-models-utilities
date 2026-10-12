import StudioWorkflows
import StudioServices
import StudioUI
import EngineeringCore
import SwiftUI

struct QuestionBatchView: View {
    let batch: QuestionBatch
    let submit: ([UUID: String]) -> Void
    @State private var answers: [UUID: String] = [:]
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionEyebrow(text: "Your input / Answer together")
            ForEach(batch.questions) { question in
                VStack(alignment: .leading, spacing: 10) {
                    Text(question.prompt).font(.headline)
                    ForEach(question.options, id: \.self) { option in
                        Button {
                            answers[question.id] = option
                        } label: {
                            HStack {
                                Image(systemName: (answers[question.id] ?? question.answer) == option ? "largecircle.fill.circle" : "circle")
                                    .accessibilityHidden(true)
                                Text(option).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }.padding(.vertical, 6).frame(minHeight: 44)
                        }.buttonStyle(.bordered)
                            .accessibilityLabel(option)
                            .accessibilityAddTraits((answers[question.id] ?? question.answer) == option ? [.isSelected] : [])
                    }
                    TextField("Your answer", text: Binding(
                        get: { answers[question.id] ?? question.answer ?? "" },
                        set: { answers[question.id] = $0 }
                    ), axis: .vertical).textFieldStyle(.roundedBorder).accessibilityLabel(question.prompt)
                }
            }
            Button("Save answers") { submit(answers) }.buttonStyle(.borderedProminent)
                .disabled(answers.isEmpty)
            Text("Partial answers are saved. Planning waits until this batch is complete.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 16).overlay(alignment: .top) { Divider() }
    }
}
