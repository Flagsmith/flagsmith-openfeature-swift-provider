import FlagsmithClient
import FlagsmithOpenFeatureTestSupport
import OpenFeature
import Testing

@testable import FlagsmithOpenFeature

extension FlagsmithProviderTests {
    @Test
    func test_getStringEvaluation__flags_fetched_for_identity__reason_is_targeting_match() async throws {
        // Given
        let provider = await initialized(
            Flag(featureName: "feature", stringValue: "some value", enabled: true),
            context: ImmutableContext(targetingKey: "user-123")
        )

        // When
        let evaluation = try provider.getStringEvaluation(key: "feature", defaultValue: "default", context: nil)

        // Then
        #expect(evaluation.reason == Reason.targetingMatch.rawValue)
        #expect(logs.entries.map(\.level) == [.info, .info])
    }

    @Test
    func test_getStringEvaluation__non_string_value__throws_type_mismatch_error() async {
        // Given
        let provider = await initialized(Flag(featureName: "feature", floatValue: 3.14, enabled: true))

        // When / Then
        #expect(throws: OpenFeatureError.typeMismatchError) {
            try provider.getStringEvaluation(key: "feature", defaultValue: "default", context: nil)
        }
        let mismatch = LogCapture.Entry(
            level: .debug,
            message: "Flag value is not of the requested type",
            metadata: ["flag": "feature", "type": "String"]
        )
        #expect(logs.entries.contains(mismatch))
    }

    @Test
    func test_getStringEvaluation__disabled_flag__throws_general_error() async {
        // Given
        let provider = await initialized(Flag(featureName: "feature", stringValue: "some value", enabled: false))

        // When / Then
        #expect(throws: OpenFeatureError.generalError(message: "Flag 'feature' is not enabled.")) {
            try provider.getStringEvaluation(key: "feature", defaultValue: "default", context: nil)
        }
        let failure = LogCapture.Entry(
            level: .warning,
            message: "Flag evaluation failed",
            metadata: ["flag": "feature", "error": "General error: Flag 'feature' is not enabled."]
        )
        #expect(logs.entries.last == failure)
    }

    @Test
    func test_getStringEvaluation__disabled_flag_allowed__returns_value_with_disabled_reason() async throws {
        // Given
        let provider = await initialized(
            Flag(featureName: "feature", stringValue: "some value", enabled: false),
            returnValueForDisabledFlags: true
        )

        // When
        let evaluation = try provider.getStringEvaluation(key: "feature", defaultValue: "default", context: nil)

        // Then
        #expect(evaluation.value == "some value")
        #expect(evaluation.reason == Reason.disabled.rawValue)
        #expect(logs.entries.map(\.level) == [.info, .info])
    }

    @Test
    func test_getStringEvaluation__logger_passed_by_sdk__logs_failures_to_it() async {
        // Given
        let provider = await initialized(Flag(featureName: "feature", enabled: true))
        let evaluationLogs = LogCapture()

        // When / Then
        #expect(throws: OpenFeatureError.flagNotFoundError(key: "missing")) {
            try provider.getStringEvaluation(
                key: "missing", defaultValue: "default", context: nil, logger: evaluationLogs.logger)
        }
        #expect(evaluationLogs.entries.map(\.message) == ["Flag evaluation failed"])
        #expect(logs.entries.map(\.level) == [.info, .info])
    }
}
