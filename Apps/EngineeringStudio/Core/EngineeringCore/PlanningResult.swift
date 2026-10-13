package struct PlanningResult {
    package let plan: WorkPlan?
    package let questions: [Question]

    package init(plan: WorkPlan?, questions: [Question]) {
        self.plan = plan
        self.questions = questions
    }
}
