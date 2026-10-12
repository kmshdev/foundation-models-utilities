import Foundation
import Testing
@testable import EngineeringCore

@Suite("Native outcome navigation")
struct StudioDeepLinkTests {
    private let outcome = "761FCA8F-1A92-4F41-8F4F-EA14C46650F4"

    @Test func opensAnOutcomeWithoutDispatchingTaskContext() throws {
        let url = try #require(URL(string: "engineeringstudio://outcome/\(outcome)"))
        let route = try #require(StudioDeepLink.parse(url))
        #expect(route.outcomeID == UUID(uuidString: outcome))
        #expect(route.taskID == nil)
    }

    @Test func retainsTheDecodedTaskIdentity() throws {
        let url = try #require(URL(string: "engineeringstudio://outcome/\(outcome)?task=core%2Fownership"))
        let route = try #require(StudioDeepLink(url: url))
        #expect(route.taskID == "core/ownership")
    }

    @Test func treatsSchemeHostAndUUIDCaseAsNavigationEquivalent() throws {
        let first = try #require(URL(string: "engineeringstudio://outcome/\(outcome)"))
        let second = try #require(URL(string: "ENGINEERINGSTUDIO://OUTCOME/\(outcome.lowercased())"))
        #expect(StudioDeepLink.parse(first) == StudioDeepLink.parse(second))
    }

    @Test func rejectsOtherDestinationsAndCredentials() throws {
        for value in [
            "https://outcome/\(outcome)",
            "other://outcome/\(outcome)",
            "engineeringstudio://task/\(outcome)",
            "engineeringstudio://user@outcome/\(outcome)",
            "engineeringstudio://user:secret@outcome/\(outcome)",
            "engineeringstudio://outcome:443/\(outcome)"
        ] {
            #expect(StudioDeepLink.parse(try #require(URL(string: value))) == nil)
        }
    }

    @Test func rejectsExtraOrEncodedPathSegments() throws {
        for path in ["", "/", "/not-a-uuid", "/\(outcome)/", "/\(outcome)/task-1", "/\(outcome)/../", "/%37\(outcome.dropFirst())"] {
            #expect(StudioDeepLink.parse(try #require(URL(string: "engineeringstudio://outcome\(path)"))) == nil)
        }
    }

    @Test func rejectsFragmentsEvenWhenEmpty() throws {
        for fragment in ["#", "#task-1"] {
            #expect(StudioDeepLink.parse(try #require(URL(string: "engineeringstudio://outcome/\(outcome)\(fragment)"))) == nil)
        }
    }

    @Test func rejectsAmbiguousOrMissingTaskArguments() throws {
        for query in ["task", "task=", "task=%20", "task=one&task=two", "task=one&task=one", "unknown=one", "task=one&extra=two", "task=%00"] {
            #expect(StudioDeepLink.parse(try #require(URL(string: "engineeringstudio://outcome/\(outcome)?\(query)"))) == nil)
        }
    }

    @Test func boundsTaskAndURLBytes() throws {
        let prefix = "engineeringstudio://outcome/\(outcome)?task="
        let maximumTask = String(repeating: "x", count: 256)
        #expect(StudioDeepLink.parse(try #require(URL(string: prefix + maximumTask)))?.taskID == maximumTask)
        #expect(StudioDeepLink.parse(try #require(URL(string: prefix + maximumTask + "x"))) == nil)
        #expect(StudioDeepLink.parse(try #require(URL(string: prefix + String(repeating: "x", count: 2_049)))) == nil)
        // A percent-encoded scalar expands the total URL despite its small decoded task length.
        let expanded = String(repeating: "%F0%9F%92%BB", count: 200)
        #expect(StudioDeepLink.parse(try #require(URL(string: prefix + expanded))) == nil)
    }

    @Test func requiresAnAbsoluteLink() throws {
        let base = try #require(URL(string: "engineeringstudio://outcome/"))
        let relative = try #require(URL(string: outcome, relativeTo: base))
        #expect(StudioDeepLink.parse(relative) == nil)
    }
}
