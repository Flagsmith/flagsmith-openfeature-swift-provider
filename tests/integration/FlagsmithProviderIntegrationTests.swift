import FlagsmithClient
import FlagsmithOpenFeature
import FlagsmithOpenFeatureTestSupport
import FlyingFox
import Foundation
import Logging
import OpenFeature
import Testing

// Flagsmith.shared is a process-wide singleton, so these tests cannot run in parallel.
@Suite(.serialized)
final class FlagsmithProviderIntegrationTests {
    let api: FlagsmithAPIMock
    let logs = LogCapture()
    let openFeature = OpenFeatureAPI()

    init() async throws {
        api = try FlagsmithAPIMock()
        Flagsmith.shared.baseURL = try await api.start()
        Flagsmith.shared.apiKey = "environment-key"
        Flagsmith.shared.enableAnalytics = false
        Flagsmith.shared.enableRealtimeUpdates = false
        Flagsmith.shared.defaultFlags = []
    }

    var provider: FlagsmithProvider {
        FlagsmithProvider(logger: logs.logger)
    }

    let environmentFlags = """
        [
            {"feature": {"name": "string-flag", "id": 1}, "feature_state_value": "a string value", "enabled": true},
            {"feature": {"name": "int-flag", "id": 2}, "feature_state_value": 42, "enabled": true},
            {"feature": {"name": "double-flag", "id": 3}, "feature_state_value": "3.14", "enabled": true},
            {
                "feature": {"name": "object-flag", "id": 4},
                "feature_state_value": "{\\"colour\\": \\"pink\\"}",
                "enabled": true
            },
            {"feature": {"name": "disabled-flag", "id": 5}, "feature_state_value": "off", "enabled": false}
        ]
        """

    let identityFlags = """
        {
            "flags": [
                {
                    "feature": {"name": "identity-flag", "id": 6},
                    "feature_state_value": "identity value",
                    "enabled": true
                }
            ],
            "traits": [{"trait_key": "favourite-colour", "trait_value": "electric pink"}]
        }
        """

    @Test
    func test_setProviderAndWait__environment_flags__evaluates_each_flag_type() async throws {
        // Given
        await api.respond("GET /api/v1/flags/", json: environmentFlags)

        // When
        await openFeature.setProviderAndWait(provider: provider)

        // Then
        let client = openFeature.getClient()
        #expect(openFeature.getProviderStatus() == .ready)
        #expect(client.getBooleanValue(key: "string-flag", defaultValue: false) == true)
        #expect(client.getStringValue(key: "string-flag", defaultValue: "default") == "a string value")
        #expect(client.getIntegerValue(key: "int-flag", defaultValue: 0) == 42)
        #expect(client.getDoubleValue(key: "double-flag", defaultValue: 0.0) == 3.14)
        #expect(
            client.getObjectValue(key: "object-flag", defaultValue: .null) == .structure(["colour": .string("pink")]))
        #expect(
            client.getStringDetails(key: "string-flag", defaultValue: "default").reason == Reason.staticReason.rawValue)
        #expect(
            logs.entries.contains(
                LogCapture.Entry(level: .info, message: "Flags fetched from Flagsmith", metadata: ["count": "5"])))
    }

    @Test
    func test_setProviderAndWait__targeting_key_in_context__evaluates_identity_flags() async throws {
        // Given
        await api.respond("GET /api/v1/identities/", json: identityFlags)

        // When
        await openFeature.setProviderAndWait(
            provider: provider, initialContext: ImmutableContext(targetingKey: "person"))

        // Then
        let details = openFeature.getClient().getStringDetails(key: "identity-flag", defaultValue: "default")
        #expect(details.value == "identity value")
        #expect(details.reason == Reason.targetingMatch.rawValue)
        let request = try #require(await api.requests.all.first)
        #expect(request.method == .GET)
        #expect(request.path == "/api/v1/identities")
        #expect(request.query == [HTTPRequest.QueryItem(name: "identifier", value: "person")])
        let fetching = LogCapture.Entry(
            level: .info,
            message: "Fetching flags from Flagsmith",
            metadata: ["identity": "person", "traits": "0"]
        )
        #expect(logs.entries.contains(fetching))
    }

    @Test
    func test_setProviderAndWait__server_error__reports_error_status_and_defaults() async throws {
        // Given
        await api.respond("GET /api/v1/flags/", status: .internalServerError)

        // When
        await openFeature.setProviderAndWait(provider: provider)

        // Then
        #expect(openFeature.getProviderStatus() == .error)
        let details = openFeature.getClient().getStringDetails(key: "string-flag", defaultValue: "default")
        #expect(details.value == "default")
        #expect(details.errorCode == .providerNotReady)
        let failure = try #require(logs.entries.first { $0.level == .error })
        #expect(failure.message == "Failed to fetch flags from Flagsmith")
        #expect(failure.metadata["error"]?.isEmpty == false)
    }

    @Test
    func test_evaluation__disabled_flag__returns_default_with_general_error() async throws {
        // Given
        await api.respond("GET /api/v1/flags/", json: environmentFlags)
        await openFeature.setProviderAndWait(provider: provider)

        // When
        let details = openFeature.getClient().getStringDetails(key: "disabled-flag", defaultValue: "default")

        // Then
        #expect(details.value == "default")
        #expect(details.errorCode == .general)
        #expect(details.reason == Reason.error.rawValue)
        #expect(
            logs.entries.contains(
                LogCapture.Entry(
                    level: .warning,
                    message: "Flag evaluation failed",
                    metadata: ["flag": "disabled-flag", "error": "General error: Flag 'disabled-flag' is not enabled."]
                )))
    }

    @Test
    func test_evaluation__missing_flag__returns_default_with_flag_not_found_error() async throws {
        // Given
        await api.respond("GET /api/v1/flags/", json: environmentFlags)
        await openFeature.setProviderAndWait(provider: provider)

        // When
        let details = openFeature.getClient().getBooleanDetails(key: "missing-flag", defaultValue: false)

        // Then
        #expect(details.value == false)
        #expect(details.errorCode == .flagNotFound)
        #expect(
            logs.entries.contains(
                LogCapture.Entry(
                    level: .warning,
                    message: "Flag evaluation failed",
                    metadata: ["flag": "missing-flag", "error": "Could not find flag for key: missing-flag"]
                )))
    }

    @Test
    func test_setEvaluationContextAndWait__context_with_traits__posts_traits_and_refreshes_flags() async throws {
        // Given
        await api.respond("GET /api/v1/flags/", json: environmentFlags)
        await api.respond("POST /api/v1/identities/", json: identityFlags)
        await openFeature.setProviderAndWait(provider: provider)
        let context = ImmutableContext(
            targetingKey: "person",
            structure: ImmutableStructure(attributes: [
                "favourite-colour": .string("electric pink")
            ]))

        // When
        await openFeature.setEvaluationContextAndWait(evaluationContext: context)

        // Then
        #expect(openFeature.getProviderStatus() == .ready)
        #expect(
            openFeature.getClient().getStringValue(key: "identity-flag", defaultValue: "default") == "identity value")
        let post = try #require(await api.requests.all.first { $0.method == .POST })
        #expect(post.path == "/api/v1/identities")
        let body = try JSONSerialization.jsonObject(with: try await post.bodyData) as? [String: Any]
        #expect(body?["identifier"] as? String == "person")
        let trait = try #require((body?["traits"] as? [[String: Any]])?.first)
        #expect(trait["trait_key"] as? String == "favourite-colour")
        #expect(trait["trait_value"] as? String == "electric pink")
        let fetching = LogCapture.Entry(
            level: .info,
            message: "Fetching flags from Flagsmith",
            metadata: ["identity": "person", "traits": "1"]
        )
        #expect(logs.entries.contains(fetching))
    }
}
