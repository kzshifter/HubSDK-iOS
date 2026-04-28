import XCTest
import HubIntegrationCore

// MARK: - Mock Listener

private final class MockEventListener: HubEventListener {
    var receivedEvents: [HubEvent] = []

    func handle(event: HubEvent) {
        receivedEvents.append(event)
    }
}

// MARK: - Tests

final class HubEventBusTests: XCTestCase {

    private var bus: HubEventBus { HubEventBus.shared }

    // MARK: Subscribe / Unsubscribe

    func testPublishDeliversToSubscribedListener() {
        let listener = MockEventListener()
        bus.subscribe(listener)
        defer { bus.unsubscribe(listener) }

        bus.publish(.event(name: "tap", params: [:]))

        XCTAssertEqual(listener.receivedEvents.count, 1)
    }

    func testUnsubscribeStopsDelivery() {
        let listener = MockEventListener()
        bus.subscribe(listener)
        bus.unsubscribe(listener)

        bus.publish(.event(name: "tap", params: [:]))

        XCTAssertEqual(listener.receivedEvents.count, 0)
    }

    func testMultipleListenersReceiveSameEvent() {
        let listener1 = MockEventListener()
        let listener2 = MockEventListener()
        bus.subscribe(listener1)
        bus.subscribe(listener2)
        defer {
            bus.unsubscribe(listener1)
            bus.unsubscribe(listener2)
        }

        bus.publish(.successPurchase(amount: 9.99, currency: "USD"))

        XCTAssertEqual(listener1.receivedEvents.count, 1)
        XCTAssertEqual(listener2.receivedEvents.count, 1)
    }

    func testWeakReferenceDoesNotRetainListener() {
        var listener: MockEventListener? = MockEventListener()
        bus.subscribe(listener!)

        listener = nil // deallocate

        // Should not crash — weak reference cleaned up
        bus.publish(.event(name: "after_dealloc", params: [:]))
    }

    func testMultipleEventsAccumulate() {
        let listener = MockEventListener()
        bus.subscribe(listener)
        defer { bus.unsubscribe(listener) }

        bus.publish(.event(name: "first", params: [:]))
        bus.publish(.event(name: "second", params: [:]))
        bus.publish(.event(name: "third", params: [:]))

        XCTAssertEqual(listener.receivedEvents.count, 3)
    }

    // MARK: Event Types

    func testConversionDataReceivedEvent() {
        let listener = MockEventListener()
        bus.subscribe(listener)
        defer { bus.unsubscribe(listener) }

        let data = ["media_source": "organic", "campaign": "summer"]
        bus.publish(.conversionDataReceived(appsflyerId: "test-id", data: data))

        guard case .conversionDataReceived(let id, let received) = listener.receivedEvents.first else {
            return XCTFail("Expected conversionDataReceived event")
        }
        XCTAssertEqual(id, "test-id")
        XCTAssertEqual(received["media_source"], "organic")
        XCTAssertEqual(received["campaign"], "summer")
    }

    func testSuccessPurchaseEvent() {
        let listener = MockEventListener()
        bus.subscribe(listener)
        defer { bus.unsubscribe(listener) }

        bus.publish(.successPurchase(amount: 4.99, currency: "EUR"))

        guard case .successPurchase(let amount, let currency) = listener.receivedEvents.first else {
            return XCTFail("Expected successPurchase event")
        }
        XCTAssertEqual(amount, 4.99)
        XCTAssertEqual(currency, "EUR")
    }

    func testCustomEventWithParams() {
        let listener = MockEventListener()
        bus.subscribe(listener)
        defer { bus.unsubscribe(listener) }

        bus.publish(.event(name: "level_complete", params: ["level": 5, "score": 100]))

        guard case .event(let name, let params) = listener.receivedEvents.first else {
            return XCTFail("Expected custom event")
        }
        XCTAssertEqual(name, "level_complete")
        XCTAssertEqual(params["level"] as? Int, 5)
        XCTAssertEqual(params["score"] as? Int, 100)
    }
}
