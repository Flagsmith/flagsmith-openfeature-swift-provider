import FlagsmithClient
import FlagsmithOpenFeatureTestSupport
import OpenFeature
import Testing

@testable import FlagsmithOpenFeature

extension FlagsmithProviderTests {
    @Test
    func test_getBooleanEvaluation__provider_not_initialized__throws_provider_not_ready_error() {
        // Given
        let provider = provider(FlagSourceMock(.success([])))

        // When / Then
        #expect(throws: OpenFeatureError.providerNotReadyError) {
            try provider.getBooleanEvaluation(key: "feature", defaultValue: false, context: nil)
        }
        let failure = LogCapture.Entry(
            level: .warning,
            message: "Flag evaluation failed",
            metadata: ["flag": "feature", "error": "The value was resolved before the provider was ready"]
        )
        #expect(logs.entries == [failure])
    }

    @Test
    func test_getBooleanEvaluation__missing_flag__throws_flag_not_found_error() async {
        // Given
        let provider = await initialized(Flag(featureName: "feature", enabled: true))

        // When / Then
        #expect(throws: OpenFeatureError.flagNotFoundError(key: "missing")) {
            try provider.getBooleanEvaluation(key: "missing", defaultValue: false, context: nil)
        }
        let failure = LogCapture.Entry(
            level: .warning,
            message: "Flag evaluation failed",
            metadata: ["flag": "missing", "error": "Could not find flag for key: missing"]
        )
        #expect(logs.entries.last == failure)
    }

    @Test
    func test_getBooleanEvaluation__non_boolean_config_value__throws_type_mismatch_error() async {
        // Given
        let provider = await initialized(
            Flag(featureName: "feature", stringValue: "yes", enabled: true), useBooleanConfigValue: true)

        // When / Then
        #expect(throws: OpenFeatureError.typeMismatchError) {
            try provider.getBooleanEvaluation(key: "feature", defaultValue: false, context: nil)
        }
        let mismatch = LogCapture.Entry(
            level: .debug,
            message: "Flag value is not of the requested type",
            metadata: ["flag": "feature", "type": "Boolean"]
        )
        let failure = LogCapture.Entry(
            level: .warning,
            message: "Flag evaluation failed",
            metadata: ["flag": "feature", "error": "Type mismatch"]
        )
        #expect(logs.entries.suffix(2) == [mismatch, failure])
    }

    @Test
    func test_getBooleanEvaluation__flag_enabled__returns_true_with_static_reason() async throws {
        // Given
        let provider = await initialized(Flag(featureName: "feature", enabled: true))

        // When
        let evaluation = try provider.getBooleanEvaluation(key: "feature", defaultValue: false, context: nil)

        // Then
        #expect(evaluation.value == true)
        #expect(evaluation.reason == Reason.staticReason.rawValue)
        #expect(logs.entries.map(\.level) == [.info, .info])
    }

    @Test
    func test_getBooleanEvaluation__flags_fetched_for_identity__reason_is_targeting_match() async throws {
        // Given
        let provider = await initialized(
            Flag(featureName: "feature", enabled: true),
            context: ImmutableContext(targetingKey: "user-123")
        )

        // When
        let evaluation = try provider.getBooleanEvaluation(key: "feature", defaultValue: false, context: nil)

        // Then
        #expect(evaluation.reason == Reason.targetingMatch.rawValue)
        #expect(logs.entries.map(\.level) == [.info, .info])
    }

    @Test
    func test_getBooleanEvaluation__enabled_state__exposes_feature_metadata() async throws {
        // Given
        let provider = await initialized(Flag(featureName: "feature", enabled: true))

        // When
        let evaluation = try provider.getBooleanEvaluation(key: "feature", defaultValue: false, context: nil)

        // Then
        #expect(evaluation.flagMetadata == ["feature_name": .string("feature")])
        #expect(logs.entries.map(\.level) == [.info, .info])
    }

    @Test
    func test_getBooleanEvaluation__flag_disabled__returns_false() async throws {
        // Given
        let provider = await initialized(Flag(featureName: "feature", enabled: false))

        // When
        let evaluation = try provider.getBooleanEvaluation(key: "feature", defaultValue: true, context: nil)

        // Then
        #expect(evaluation.value == false)
        #expect(logs.entries.map(\.level) == [.info, .info])
    }

    @Test
    func test_getBooleanEvaluation__boolean_config_value__returns_value() async throws {
        // Given
        let provider = await initialized(
            Flag(featureName: "feature", boolValue: true, enabled: true), useBooleanConfigValue: true)

        // When
        let evaluation = try provider.getBooleanEvaluation(key: "feature", defaultValue: false, context: nil)

        // Then
        #expect(evaluation.value == true)
        #expect(logs.entries.map(\.level) == [.info, .info])
    }

    @Test
    func test_getBooleanEvaluation__boolean_config_value_of_disabled_flag__throws_general_error() async {
        // Given
        let provider = await initialized(
            Flag(featureName: "feature", boolValue: true, enabled: false), useBooleanConfigValue: true)

        // When / Then
        #expect(throws: OpenFeatureError.generalError(message: "Flag 'feature' is not enabled.")) {
            try provider.getBooleanEvaluation(key: "feature", defaultValue: false, context: nil)
        }
        let failure = LogCapture.Entry(
            level: .warning,
            message: "Flag evaluation failed",
            metadata: ["flag": "feature", "error": "General error: Flag 'feature' is not enabled."]
        )
        #expect(logs.entries.last == failure)
    }
}
