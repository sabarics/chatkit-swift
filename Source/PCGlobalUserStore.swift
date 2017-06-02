import Foundation
import PusherPlatform

public class PCGlobalUserStore {

    public var users: Set<PCUser> {
        get {
            return self.userStoreCore.users
        }
    }

    public internal(set) var userStoreCore: PCUserStoreCore
    let app: App

    init(userStoreCore: PCUserStoreCore = PCUserStoreCore(), app: App) {
        self.userStoreCore = userStoreCore
        self.app = app
    }

    public func user(id: String, completionHandler: @escaping (PCUser?, Error?) -> Void) {
        self.findOrGetUser(id: id, completionHander: completionHandler)
    }

    func addOrMerge(_ user: PCUser) -> PCUser {
        return self.userStoreCore.addOrMerge(user)
    }

    func remove(id: String) -> PCUser? {
        return self.userStoreCore.remove(id: id)
    }

    func findOrGetUser(id: String, completionHander: @escaping (PCUser?, Error?) -> Void) {
        if let user = self.userStoreCore.users.first(where: { $0.id == id }) {
            completionHander(user, nil)
        } else {
            self.getUser(id: id) { user, err in
                guard let user = user, err == nil else {
                    self.app.logger.log(err!.localizedDescription, logLevel: .error)
                    completionHander(nil, err!)
                    return
                }

                let userToReturn = self.userStoreCore.addOrMerge(user)
                completionHander(userToReturn, nil)
            }
        }
    }

    func getUser(id: String, completionHandler: @escaping (PCUser?, Error?) -> Void) {
        let path = "/\(ChatManager.namespace)/users/\(id)"
        let generalRequest = PPRequestOptions(method: HTTPMethod.GET.rawValue, path: path)

        self.app.requestWithRetry(
            using: generalRequest,
            onSuccess: { data in
                guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) else {
                    completionHandler(nil, PCError.failedToDeserializeJSON(data))
                    return
                }

                guard let userPayload = jsonObject as? [String: Any] else {
                    completionHandler(nil, PCError.failedToCastJSONObjectToDictionary(jsonObject))
                    return
                }

                do {
                    let user = try PCPayloadDeserializer.createUserFromPayload(userPayload)
                    completionHandler(user, nil)
                } catch let err {
                    self.app.logger.log(err.localizedDescription, logLevel: .debug)
                    completionHandler(nil, err)
                    return
                }
            },
            onError: { err in
                completionHandler(nil, err)
            }
        )
    }

    func handleInitialPresencePayloads(_ payloads: [PCPresencePayload]) {
        payloads.forEach { payload in
            self.findOrGetUser(id: payload.userId) { user, err in
                guard let user = user, err == nil else {
                    self.app.logger.log(err!.localizedDescription, logLevel: .error)
                    return
                }

                user.presenceState = payload.state
                user.lastSeenAt = payload.lastSeenAt
            }
        }
    }

    // This will do the de-duping of userIds
    func fetchUsersWithIds(_ userIds: [String], completionHandler: (([PCUser]?, Error?) -> Void)? = nil) {
        guard userIds.count > 0 else {
            self.app.logger.log("Requested to fetch users for a list of user ids which was empty", logLevel: .debug)
            completionHandler?([], nil)
            return
        }

        let uniqueUserIds = Array(Set<String>(userIds))
        let userIdsString = uniqueUserIds.joined(separator: ",")

        let path = "/\(ChatManager.namespace)/users"
        let generalRequest = PPRequestOptions(method: HTTPMethod.GET.rawValue, path: path)
        generalRequest.addQueryItems([URLQueryItem(name: "user_ids", value: userIdsString)])

        // We want this to complete quickly, whether it succeeds or not
        generalRequest.retryStrategy = PPDefaultRetryStrategy(maxNumberOfAttempts: 1)

        self.app.requestWithRetry(
            using: generalRequest,
            onSuccess: { data in
                guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) else {
                    let err = PCError.failedToDeserializeJSON(data)
                    self.app.logger.log(
                        "Error fetching user information: \(err.localizedDescription)",
                        logLevel: .debug
                    )
                    completionHandler?(nil, err)
                    return
                }

                guard let userPayloads = jsonObject as? [[String: Any]] else {
                    let err = PCError.failedToCastJSONObjectToDictionary(jsonObject)
                    self.app.logger.log(
                        "Error fetching user information: \(err.localizedDescription)",
                        logLevel: .debug
                    )
                    completionHandler?(nil, err)
                    return
                }

                let users = userPayloads.flatMap { userPayload -> PCUser? in
                    do {
                        let user = try PCPayloadDeserializer.createUserFromPayload(userPayload)
                        let addedOrUpdatedUser = self.userStoreCore.addOrMerge(user)
                        return addedOrUpdatedUser
                    } catch let err {
                        self.app.logger.log("Error fetching user information: \(err.localizedDescription)", logLevel: .debug)
                        return nil
                    }
                }
                completionHandler?(users, nil)
            },
            onError: { err in
                self.app.logger.log("Error fetching user information: \(err.localizedDescription)", logLevel: .debug)
            }
        )
    }

    func initialFetchOfUsersWithIds(_ userIds: [String], completionHandler: (([PCUser]?, Error?) -> Void)? = nil) {
        self.fetchUsersWithIds(userIds)
    }

}