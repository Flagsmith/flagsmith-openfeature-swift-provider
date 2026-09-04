import FlagsmithClient
import FlagsmithOpenFeatureTestSupport
import OpenFeature
import Testing

@testable import FlagsmithOpenFeature

extension FlagsmithProviderTests {
    @Test
    func test_getObjectEvaluation__json_object_value__returns_structure() async throws {
        // Given
        let json = """
            {
                "string": "text", "int": 1, "double": 1.5, "bool": true, "null": null,
                "list": [2], "nested": {"key": "value"}
            }
            """
        let provider = await initialized(Flag(featureName: "feature", stringValue: json, enabled: true))

        // When
        let evaluation = try provider.getObjectEvaluation(key: "feature", defaultValue: .null, context: nil)

        // Then
        #expect(
            evaluation.value
                == .structure([
                    "string": .string("text"),
                    "int": .integer(1),
                    "double": .double(1.5),
                    "bool": .boolean(true),
                    "null": .null,
                    "list": .list([.integer(2)]),
                    "nested": .structure(["key": .string("value")]),
                ]))
        #expect(logs.entries.map(\.level) == [.info, .info])
    }

    @Test
    func test_getObjectEvaluation__json_numbers_beyond_int64_range__returns_doubles() async throws {
        // Given
        let json = #"{"huge": 99999999999999999999, "max": 9223372036854775807}"#
        let provider = await initialized(Flag(featureName: "feature", stringValue: json, enabled: true))

        // When
        let evaluation = try provider.getObjectEvaluation(key: "feature", defaultValue: .null, context: nil)

        // Then
        #expect(evaluation.value == .structure(["huge": .double(1e20), "max": .integer(Int64.max)]))
        #expect(logs.entries.map(\.level) == [.info, .info])
    }

    @Test
    func test_getObjectEvaluation__bare_word_value__throws_parse_error() async {
        // Given
        let provider = await initialized(Flag(featureName: "feature", stringValue: "hello", enabled: true))

        // When / Then
        #expect(throws: OpenFeatureError.parseError(message: "Unable to parse object from value for flag 'feature'")) {
            try provider.getObjectEvaluation(key: "feature", defaultValue: .null, context: nil)
        }
        let failure = LogCapture.Entry(
            level: .warning,
            message: "Flag evaluation failed",
            metadata: ["flag": "feature", "error": "Parse error: Unable to parse object from value for flag 'feature'"]
        )
        #expect(logs.entries.last == failure)
    }

    @Test
    func test_getObjectEvaluation__trailing_content_after_json_value__throws_parse_error() async {
        // Given
        let provider = await initialized(
            Flag(featureName: "feature", stringValue: #"{"key": "value"} trailing"#, enabled: true))

        // When / Then
        #expect(throws: OpenFeatureError.parseError(message: "Unable to parse object from value for flag 'feature'")) {
            try provider.getObjectEvaluation(key: "feature", defaultValue: .null, context: nil)
        }
        #expect(logs.entries.last?.message == "Flag evaluation failed")
    }

    @Test
    func test_getObjectEvaluation__malformed_json_value__throws_parse_error() async {
        // Given
        let provider = await initialized(Flag(featureName: "feature", stringValue: "{invalid json", enabled: true))

        // When / Then
        #expect(throws: OpenFeatureError.parseError(message: "Unable to parse object from value for flag 'feature'")) {
            try provider.getObjectEvaluation(key: "feature", defaultValue: .null, context: nil)
        }
        #expect(logs.entries.last?.message == "Flag evaluation failed")
    }

    @Test
    func test_getObjectEvaluation__non_string_value__throws_type_mismatch_error() async {
        // Given
        let provider = await initialized(Flag(featureName: "feature", intValue: 42, enabled: true))

        // When / Then
        #expect(throws: OpenFeatureError.typeMismatchError) {
            try provider.getObjectEvaluation(key: "feature", defaultValue: .null, context: nil)
        }
        let mismatch = LogCapture.Entry(
            level: .debug,
            message: "Flag value is not of the requested type",
            metadata: ["flag": "feature", "type": "Object"]
        )
        #expect(logs.entries.contains(mismatch))
    }
}
