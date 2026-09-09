import FlagsmithClient
import FlagsmithOpenFeatureTestSupport
import OpenFeature
import Testing

@testable import FlagsmithOpenFeature

extension FlagsmithProviderTests {
    @Test
    func test_getIntegerEvaluation__int_value__returns_int64() async throws {
        // Given
        let provider = await initialized(Flag(featureName: "feature", intValue: 7, enabled: true))

        // When
        let evaluation = try provider.getIntegerEvaluation(key: "feature", defaultValue: 0, context: nil)

        // Then
        #expect(evaluation.value == 7)
        #expect(logs.entries.map(\.level) == [.info, .info])
    }

    @Test
    func test_getIntegerEvaluation__value_beyond_32_bits__returns_exact_int64() async throws {
        // Given
        let provider = await initialized(Flag(featureName: "feature", intValue: 9_999_999_999, enabled: true))

        // When
        let evaluation = try provider.getIntegerEvaluation(key: "feature", defaultValue: 0, context: nil)

        // Then
        #expect(evaluation.value == 9_999_999_999)
        #expect(logs.entries.map(\.level) == [.info, .info])
    }

    @Test
    func test_getIntegerEvaluation__integral_float_value__returns_int64() async throws {
        // Given
        let provider = await initialized(Flag(featureName: "feature", floatValue: 42.0, enabled: true))

        // When
        let evaluation = try provider.getIntegerEvaluation(key: "feature", defaultValue: 0, context: nil)

        // Then
        #expect(evaluation.value == 42)
        #expect(logs.entries.map(\.level) == [.info, .info])
    }

    @Test
    func test_getIntegerEvaluation__fractional_float_value__throws_type_mismatch_error() async {
        // Given
        let provider = await initialized(Flag(featureName: "feature", floatValue: 4.5, enabled: true))

        // When / Then
        #expect(throws: OpenFeatureError.typeMismatchError) {
            try provider.getIntegerEvaluation(key: "feature", defaultValue: 0, context: nil)
        }
        let mismatch = LogCapture.Entry(
            level: .debug,
            message: "Flag value is not of the requested type",
            metadata: ["flag": "feature", "type": "Integer"]
        )
        #expect(logs.entries.contains(mismatch))
    }

    @Test
    func test_getIntegerEvaluation__float_beyond_int64_range__throws_type_mismatch_error() async {
        // Given
        let provider = await initialized(Flag(featureName: "feature", floatValue: 1e30, enabled: true))

        // When / Then
        #expect(throws: OpenFeatureError.typeMismatchError) {
            try provider.getIntegerEvaluation(key: "feature", defaultValue: 0, context: nil)
        }
        #expect(logs.entries.last?.message == "Flag evaluation failed")
    }

    @Test
    func test_getIntegerEvaluation__string_value__throws_type_mismatch_error() async {
        // Given
        let provider = await initialized(Flag(featureName: "feature", stringValue: "42", enabled: true))

        // When / Then
        #expect(throws: OpenFeatureError.typeMismatchError) {
            try provider.getIntegerEvaluation(key: "feature", defaultValue: 0, context: nil)
        }
        let failure = LogCapture.Entry(
            level: .warning,
            message: "Flag evaluation failed",
            metadata: ["flag": "feature", "error": "Type mismatch"]
        )
        #expect(logs.entries.last == failure)
    }

    @Test
    func test_getDoubleEvaluation__float_value__returns_value() async throws {
        // Given
        let provider = await initialized(Flag(featureName: "feature", floatValue: 3.5, enabled: true))

        // When
        let evaluation = try provider.getDoubleEvaluation(key: "feature", defaultValue: 0.0, context: nil)

        // Then
        #expect(evaluation.value == 3.5)
        #expect(logs.entries.map(\.level) == [.info, .info])
    }

    @Test
    func test_getDoubleEvaluation__int_value__returns_value() async throws {
        // Given
        let provider = await initialized(Flag(featureName: "feature", intValue: 42, enabled: true))

        // When
        let evaluation = try provider.getDoubleEvaluation(key: "feature", defaultValue: 0.0, context: nil)

        // Then
        #expect(evaluation.value == 42.0)
        #expect(logs.entries.map(\.level) == [.info, .info])
    }

    @Test
    func test_getDoubleEvaluation__decimal_string_value__returns_value() async throws {
        // Given
        let provider = await initialized(Flag(featureName: "feature", stringValue: "3.14", enabled: true))

        // When
        let evaluation = try provider.getDoubleEvaluation(key: "feature", defaultValue: 0.0, context: nil)

        // Then
        #expect(evaluation.value == 3.14)
        #expect(logs.entries.map(\.level) == [.info, .info])
    }

    @Test
    func test_getDoubleEvaluation__non_numeric_value__throws_type_mismatch_error() async {
        // Given
        let provider = await initialized(Flag(featureName: "feature", stringValue: "not a number", enabled: true))

        // When / Then
        #expect(throws: OpenFeatureError.typeMismatchError) {
            try provider.getDoubleEvaluation(key: "feature", defaultValue: 0.0, context: nil)
        }
        let mismatch = LogCapture.Entry(
            level: .debug,
            message: "Flag value is not of the requested type",
            metadata: ["flag": "feature", "type": "Double"]
        )
        #expect(logs.entries.contains(mismatch))
    }

    @Test
    func test_getDoubleEvaluation__boolean_value__throws_type_mismatch_error() async {
        // Given
        let provider = await initialized(Flag(featureName: "feature", boolValue: true, enabled: true))

        // When / Then
        #expect(throws: OpenFeatureError.typeMismatchError) {
            try provider.getDoubleEvaluation(key: "feature", defaultValue: 0.0, context: nil)
        }
        #expect(logs.entries.last?.message == "Flag evaluation failed")
    }
}
