import XCTest
import PusherPlatform
@testable import PusherChatkit

class MessagesTests: XCTestCase {
    var aliceChatManager: ChatManager!
    var bobChatManager: ChatManager!
    var roomID: String!

    override func setUp() {
        super.setUp()

        aliceChatManager = newTestChatManager(userID: "alice")
        bobChatManager = newTestChatManager(userID: "bob")

        let deleteResourcesEx = expectation(description: "delete resources")
        let createRolesEx = expectation(description: "create roles")
        let createAliceEx = expectation(description: "create Alice")
        let createBobEx = expectation(description: "create Bob")
        let createRoomEx = expectation(description: "create room")
        let sendMessagesEx = expectation(description: "send messages")

        deleteInstanceResources() { err in
            XCTAssertNil(err)
            deleteResourcesEx.fulfill()

            createStandardInstanceRoles() { err in
                XCTAssertNil(err)
                createRolesEx.fulfill()
            }

            createUser(id: "alice", name: "Alice") { err in
                XCTAssertNil(err)
                createAliceEx.fulfill()
            }

            createUser(id: "bob", name: "Bob") { err in
                XCTAssertNil(err)
                createBobEx.fulfill()
            }

            // TODO the following should really wait until we know both Alice
            // and Bob exist... for now, sleep!
            sleep(1)

            self.aliceChatManager.connect(delegate: TestingChatManagerDelegate()) { alice, err in
                XCTAssertNil(err)
                alice!.createRoom(name: "mushroom", addUserIDs: ["bob"]) { room, err in
                    XCTAssertNil(err)
                    self.roomID = room!.id
                    createRoomEx.fulfill()

                    let messages = ["hello", "hey", "hi", "ho"]
                    self.sendOrderedMessages(
                        messages: messages,
                        from: alice!,
                        toRoomID: self.roomID
                    ) { sendMessagesEx.fulfill() }
                }
            }
        }

        waitForExpectations(timeout: 15)
    }

    fileprivate func sendOrderedMessages(
        messages: [String],
        from user: PCCurrentUser,
        toRoomID roomID: String,
        completionHandler: @escaping () -> Void
    ) {
        guard let message = messages.first else {
            completionHandler()
            return
        }

        user.sendMessage(roomID: roomID, text: message) { [messages] _, err in
            XCTAssertNil(err)
            self.sendOrderedMessages(
                messages: Array(messages.dropFirst()),
                from: user,
                toRoomID: roomID,
                completionHandler: completionHandler
            )
        }
    }

    override func tearDown() {
        aliceChatManager.disconnect()
        aliceChatManager = nil
        bobChatManager.disconnect()
        bobChatManager = nil
        roomID = nil
    }

    func testFetchMessages() {
        let ex = expectation(description: "fetch four messages")

        bobChatManager.connect(delegate: TestingChatManagerDelegate()) { bob, err in
            XCTAssertNil(err)

            bob!.fetchMessagesFromRoom(
                bob!.rooms.first(where: { $0.id == self.roomID })!
            ) { messages, err in
                XCTAssertNil(err)

                XCTAssertEqual(
                    messages!.map { $0.text },
                    ["hello", "hey", "hi", "ho"]
                )

                XCTAssert(messages!.all { $0.sender.id == "alice" })
                XCTAssert(messages!.all { $0.sender.name == "Alice" })
                XCTAssert(messages!.all { $0.room.id == self.roomID })
                XCTAssert(messages!.all { $0.room.name == "mushroom" })

                ex.fulfill()
            }
        }

        waitForExpectations(timeout: 15)
    }

    func testFetchMessagesPaginated() {
        let ex = expectation(description: "fetch four messages in pairs")

        bobChatManager.connect(delegate: TestingChatManagerDelegate()) { bob, err in
            XCTAssertNil(err)

            bob!.fetchMessagesFromRoom(
                bob!.rooms.first(where: { $0.id == self.roomID })!,
                limit: 2
            ) { messages, err in
                XCTAssertNil(err)

                XCTAssertEqual(messages!.map { $0.text }, ["hi", "ho"])
                XCTAssert(messages!.all { $0.sender.id == "alice" })
                XCTAssert(messages!.all { $0.sender.name == "Alice" })
                XCTAssert(messages!.all { $0.room.id == self.roomID })
                XCTAssert(messages!.all { $0.room.name == "mushroom" })

                bob!.fetchMessagesFromRoom(
                    bob!.rooms.first(where: { $0.id == self.roomID })!,
                    initialID: String(messages!.map { $0.id }.min()!)
                ) { messages, err in
                    XCTAssertNil(err)

                    XCTAssertEqual(messages!.map { $0.text }, ["hello", "hey"])
                    XCTAssert(messages!.all { $0.sender.id == "alice" })
                    XCTAssert(messages!.all { $0.sender.name == "Alice" })
                    XCTAssert(messages!.all { $0.room.id == self.roomID })
                    XCTAssert(messages!.all { $0.room.name == "mushroom" })

                    ex.fulfill()
                }
            }
        }

        waitForExpectations(timeout: 15)
    }

    func testSubscribeToRoomAndFetchInitial() {
        let ex = expectation(description: "subscribe and get initial messages")

        var expectedMessageTexts = ["hello", "hey", "hi", "ho"]

        let bobRoomDelegate = TestingRoomDelegate(onMessage: { message in
            XCTAssertEqual(message.text, expectedMessageTexts.removeFirst())
            XCTAssertEqual(message.sender.id, "alice")
            XCTAssertEqual(message.sender.name, "Alice")
            XCTAssertEqual(message.room.id, self.roomID)
            XCTAssertEqual(message.room.name, "mushroom")

            if expectedMessageTexts.isEmpty {
                ex.fulfill()
            }
        })

        bobChatManager.connect(delegate: TestingChatManagerDelegate()) { bob, err in
            XCTAssertNil(err)

            bob!.subscribeToRoom(
                room: bob!.rooms.first(where: { $0.id == self.roomID })!,
                roomDelegate: bobRoomDelegate,
                completionHandler: { err in
                    XCTAssertNil(err)
                }
            )
        }

        waitForExpectations(timeout: 15)
    }

    func testSubscribeToRoomAndFetchLastTwoMessagesOnly() {
        let ex = expectation(description: "subscribe and fetch last two messages only")

        var expectedMessageTexts = ["ho", "hi"]

        let bobRoomDelegate = TestingRoomDelegate(onMessage: { message in
            XCTAssertEqual(message.text, expectedMessageTexts.popLast()!)
            XCTAssertEqual(message.sender.id, "alice")
            XCTAssertEqual(message.sender.name, "Alice")
            XCTAssertEqual(message.room.id, self.roomID)
            XCTAssertEqual(message.room.name, "mushroom")

            if expectedMessageTexts.isEmpty {
                ex.fulfill()
            }
        })

        bobChatManager.connect(delegate: TestingChatManagerDelegate()) { bob, err in
            XCTAssertNil(err)

            bob!.subscribeToRoom(
                room: bob!.rooms.first(where: { $0.id == self.roomID })!,
                roomDelegate: bobRoomDelegate,
                messageLimit: 2,
                completionHandler: { err in
                    XCTAssertNil(err)
                }
            )
        }

        waitForExpectations(timeout: 15)
    }

    func testSubscribeToRoomAndReceiveSentMessages() {
        let ex = expectation(description: "subscribe and receive sent messages")

        var expectedMessageTexts = ["yooo", "yo"]

        let bobRoomDelegate = TestingRoomDelegate(onMessage: { message in
            XCTAssertEqual(message.text, expectedMessageTexts.popLast()!)
            XCTAssertEqual(message.sender.id, "alice")
            XCTAssertEqual(message.sender.name, "Alice")
            XCTAssertEqual(message.room.id, self.roomID)
            XCTAssertEqual(message.room.name, "mushroom")

            if expectedMessageTexts.isEmpty {
                ex.fulfill()
            }
        })

        bobChatManager.connect(delegate: TestingChatManagerDelegate()) { bob, err in
            XCTAssertNil(err)

            bob!.subscribeToRoom(
                room: bob!.rooms.first(where: { $0.id == self.roomID })!,
                roomDelegate: bobRoomDelegate,
                messageLimit: 0,
                completionHandler: { err in
                    XCTAssertNil(err)

                    self.aliceChatManager.connect(
                        delegate: TestingChatManagerDelegate()
                    ) { alice, err in
                        let messages = ["yo", "yooo"]
                        self.sendOrderedMessages(
                            messages: messages,
                            from: alice!,
                            toRoomID: self.roomID
                        ) {}
                    }
                }
            )
        }

        waitForExpectations(timeout: 15)
    }

    func testSendAndReceiveMessageWithLinkAttachment() {
        let veryImportantImage = "https://i.imgur.com/rJbRKLU.gif"

        let ex = expectation(description: "subscribe and receive sent messages")

        let bobRoomDelegate = TestingRoomDelegate(onMessage: { message in
            XCTAssertEqual(message.text, "see attached")
            XCTAssertEqual(message.sender.id, "alice")
            XCTAssertEqual(message.sender.name, "Alice")
            XCTAssertEqual(message.room.id, self.roomID)
            XCTAssertEqual(message.room.name, "mushroom")
            XCTAssertEqual(message.attachment!.link, veryImportantImage)
            XCTAssertEqual(message.attachment!.type, "image")
            XCTAssertEqual(message.attachment!.name, "rJbRKLU.gif")

            ex.fulfill()
        })

        bobChatManager.connect(delegate: TestingChatManagerDelegate()) { bob, err in
            XCTAssertNil(err)

            bob!.subscribeToRoom(
                room: bob!.rooms.first(where: { $0.id == self.roomID })!,
                roomDelegate: bobRoomDelegate,
                messageLimit: 0,
                completionHandler: { err in
                    XCTAssertNil(err)

                    self.aliceChatManager.connect(
                        delegate: TestingChatManagerDelegate()
                    ) { alice, err in
                        alice!.sendMessage(
                            roomID: self.roomID,
                            text: "see attached",
                            attachment: .link(veryImportantImage, type: "image")
                        ) { _, err in
                            XCTAssertNil(err)
                        }
                    }
                }
            )
        }

        waitForExpectations(timeout: 15)
    }

    // Unsure why this doesn't work on iOS but it does work for macOS. Uploading
    // using the same method as is used here works in the iOS example app, so I
    // think it must be some test-specific oddity
    #if os(macOS)
    func testSendAndReceiveMessageWithDataAttachment() {
        let bundle = Bundle(for: type(of: self))
        let veryImportantImage = bundle.path(
            forResource: "test-image",
            ofType: "gif"
        )!

        let ex = expectation(description: "subscribe and receive sent messages")

        let bobRoomDelegate = TestingRoomDelegate(onMessage: { message in
            XCTAssertEqual(message.text, "see attached")
            XCTAssertEqual(message.sender.id, "alice")
            XCTAssertEqual(message.sender.name, "Alice")
            XCTAssertEqual(message.room.id, self.roomID)
            XCTAssertEqual(message.room.name, "mushroom")
            XCTAssertEqual(message.attachment!.type, "image")
            XCTAssertEqual(message.attachment!.name, "test-image.gif")

            ex.fulfill()
        })

        bobChatManager.connect(delegate: TestingChatManagerDelegate()) { bob, err in
            XCTAssertNil(err)

            bob!.subscribeToRoom(
                room: bob!.rooms.first(where: { $0.id == self.roomID })!,
                roomDelegate: bobRoomDelegate,
                messageLimit: 0,
                completionHandler: { err in
                    XCTAssertNil(err)
                }
            )

            self.aliceChatManager.connect(
                delegate: TestingChatManagerDelegate()
            ) { alice, err in
                alice!.sendMessage(
                    roomID: self.roomID,
                    text: "see attached",
                    attachment: .fileURL(
                        URL(fileURLWithPath: veryImportantImage),
                        name: "test-image.gif"
                    )
                ) { _, err in
                    XCTAssertNil(err)
                }
            }
        }

        waitForExpectations(timeout: 25)
    }

    func testSendAndReceiveMessageWithDataAttachmentThatHasAHorribleName() {
        let bundle = Bundle(for: type(of: self))
        // The resource is written with colons here in place of the slashes that
        // show as being in the filename if you look at it in Finder. This is a
        // weird macOS <-> Unix oddity
        let testFilePath = bundle.path(
            forResource: "lol ? wut ?&..",
            ofType: "json"
        )!

        let ex = expectation(description: "subscribe and receive sent messages")

        let bobRoomDelegate = TestingRoomDelegate(onMessage: { message in
            XCTAssertEqual(message.text, "see attached")
            XCTAssertEqual(message.sender.id, "alice")
            XCTAssertEqual(message.sender.name, "Alice")
            XCTAssertEqual(message.room.id, self.roomID)
            XCTAssertEqual(message.room.name, "mushroom")
            XCTAssertEqual(message.attachment!.type, "file")
            XCTAssertEqual(message.attachment!.name, "lol ? wut ?&...json")

            ex.fulfill()
        })

        bobChatManager.connect(delegate: TestingChatManagerDelegate()) { bob, err in
            XCTAssertNil(err)

            bob!.subscribeToRoom(
                room: bob!.rooms.first(where: { $0.id == self.roomID })!,
                roomDelegate: bobRoomDelegate,
                messageLimit: 0,
                completionHandler: { err in
                    XCTAssertNil(err)
                }
            )

            self.aliceChatManager.connect(
                delegate: TestingChatManagerDelegate()
            ) { alice, err in
                alice!.sendMessage(
                    roomID: self.roomID,
                    text: "see attached",
                    attachment: .fileURL(
                        URL(fileURLWithPath: testFilePath),
                        name: "lol ? wut ?&...json"
                    )
                ) { _, err in
                    XCTAssertNil(err)
                }
            }
        }

        waitForExpectations(timeout: 25)
    }
    #endif
}
