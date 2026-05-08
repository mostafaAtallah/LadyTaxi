import Foundation

struct User: Codable, Equatable {
    let id: Int
    let firstName: String
    let familyName: String
    let email: String
    let phoneNumber: String
    let gender: String
}
