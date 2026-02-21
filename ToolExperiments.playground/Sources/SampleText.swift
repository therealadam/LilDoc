import Foundation

/// Sample documents for testing tools without reading real files.
public enum SampleText {
    public static let meetingNotes = """
    # Q1 Planning Meeting

    TODO: Finalize budget by Friday
    TODO: Send hiring plan to VP

    We discussed the product roadmap for Q1. The main priorities are:
    1. Ship the new onboarding flow
    2. Fix the search performance regression
    3. FIXME: The analytics dashboard still shows stale data

    Action items:
    - Alice: draft the onboarding spec
    - Bob: profile the search queries
    - NOTE: We need to revisit the pricing model in February

    HACK: The export feature uses a hardcoded path for now.
    """

    public static let shortNote = """
    Pick up milk.
    Call the dentist.
    Finish the report.
    """
}
