import Foundation
import SQLite3

final class Database {
    static let shared = Database()

    private var db: OpaquePointer?
    private let dbName = "beerusFramework.sqlite"

    private init() {
        openDatabase()
        createProfilesTable()
        addStatusColumnIfNeeded()
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Model

    struct Profile {
        let name: String
        let proxy: String
        let status: String
    }

    // MARK: - Database Path

    private func databaseURL() -> URL? {
        do {
            let baseURL = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )

            let folderURL = baseURL.appendingPathComponent("BeerusFramework", isDirectory: true)

            if !FileManager.default.fileExists(atPath: folderURL.path) {
                try FileManager.default.createDirectory(
                    at: folderURL,
                    withIntermediateDirectories: true
                )
            }

            return folderURL.appendingPathComponent(dbName)
        } catch {
            print("[-] Failed to create database directory: \(error)")
            return nil
        }
    }

    // MARK: - Open Database

    private func openDatabase() {
        guard let url = databaseURL() else {
            print("[-] Invalid database URL")
            return
        }

        if sqlite3_open(url.path, &db) == SQLITE_OK {
            print("[+] Database opened at: \(url.path)")
        } else {
            print("[-] Failed to open database")
            sqlite3_close(db)
            db = nil
        }
    }

    // MARK: - Create Table

    private func createProfilesTable() {
        guard db != nil else {
            print("[-] Database not open, skipping table creation")
            return
        }

        let query = """
        CREATE TABLE IF NOT EXISTS Profiles (
            Name TEXT NOT NULL UNIQUE,
            Proxy TEXT NOT NULL,
            Status TEXT NOT NULL DEFAULT 'off'
        );
        """

        guard sqlite3_exec(db, query, nil, nil, nil) == SQLITE_OK else {
            if let error = sqlite3_errmsg(db) {
                print("[-] Failed to create Profiles table: \(String(cString: error))")
            }
            return
        }

        print("[+] Profiles table is ready")
    }

    // MARK: - Migration

    private func addStatusColumnIfNeeded() {
        guard db != nil else {
            print("[-] Database not open, skipping migration")
            return
        }

        let query = "ALTER TABLE Profiles ADD COLUMN Status TEXT NOT NULL DEFAULT 'off';"

        if sqlite3_exec(db, query, nil, nil, nil) == SQLITE_OK {
            print("[+] Status column added")
        } else if let error = sqlite3_errmsg(db) {
            let message = String(cString: error)

            if message.contains("duplicate column name") {
                print("[*] Status column already exists")
            } else {
                print("[-] Failed to add Status column: \(message)")
            }
        }
    }

    // MARK: - Insert Profile

    @discardableResult
    func addProfile(name: String, proxy: String) -> Bool {
        guard db != nil else {
            print("[-] Database not open")
            return false
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedProxy = proxy.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedStatus = "off"

        guard !trimmedName.isEmpty else {
            print("[-] Profile name cannot be empty")
            return false
        }

        guard !trimmedProxy.isEmpty else {
            print("[-] Proxy cannot be empty")
            return false
        }

        guard !profileExists(name: trimmedName) else {
            print("[-] A profile with this name already exists")
            return false
        }

        let query = "INSERT INTO Profiles (Name, Proxy, Status) VALUES (?, ?, ?);"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            if let error = sqlite3_errmsg(db) {
                print("[-] Failed to prepare insert: \(String(cString: error))")
            }
            return false
        }

        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_text(statement, 1, (trimmedName as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (trimmedProxy as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 3, (trimmedStatus as NSString).utf8String, -1, nil)

        if sqlite3_step(statement) == SQLITE_DONE {
            print("[+] Profile added successfully")
            return true
        } else {
            if let error = sqlite3_errmsg(db) {
                print("[-] Failed to insert profile: \(String(cString: error))")
            }
            return false
        }
    }

    // MARK: - Delete Profile By Name

    @discardableResult
    func deleteProfile(name: String) -> Bool {
        guard db != nil else {
            print("[-] Database not open")
            return false
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            print("[-] Profile name cannot be empty")
            return false
        }

        let query = "DELETE FROM Profiles WHERE Name = ?;"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            if let error = sqlite3_errmsg(db) {
                print("[-] Failed to prepare delete: \(String(cString: error))")
            }
            return false
        }

        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_text(statement, 1, (trimmedName as NSString).utf8String, -1, nil)

        if sqlite3_step(statement) == SQLITE_DONE {
            let changes = sqlite3_changes(db)
            if changes > 0 {
                print("[+] Profile deleted successfully")
                return true
            } else {
                print("[-] No profile found with this name")
                return false
            }
        } else {
            if let error = sqlite3_errmsg(db) {
                print("[-] Failed to delete profile: \(String(cString: error))")
            }
            return false
        }
    }

    // MARK: - Fetch Profiles

    func fetchProfiles() -> [Profile] {
        guard db != nil else {
            print("[-] Database not open")
            return []
        }

        let query = "SELECT Name, Proxy, Status FROM Profiles ORDER BY Name ASC;"
        var statement: OpaquePointer?
        var profiles: [Profile] = []

        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            if let error = sqlite3_errmsg(db) {
                print("[-] Failed to prepare fetch: \(String(cString: error))")
            }
            return []
        }

        defer {
            sqlite3_finalize(statement)
        }

        while sqlite3_step(statement) == SQLITE_ROW {
            let name = sqlite3_column_text(statement, 0).flatMap { String(cString: $0) } ?? ""
            let proxy = sqlite3_column_text(statement, 1).flatMap { String(cString: $0) } ?? ""
            let status = sqlite3_column_text(statement, 2).flatMap { String(cString: $0) } ?? ""

            profiles.append(Profile(name: name, proxy: proxy, status: status))
        }

        return profiles
    }

    // MARK: - Check Existing Profile

    private func profileExists(name: String) -> Bool {
        guard db != nil else { return false }

        let query = "SELECT 1 FROM Profiles WHERE Name = ? LIMIT 1;"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return false
        }

        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_text(statement, 1, (name as NSString).utf8String, -1, nil)

        return sqlite3_step(statement) == SQLITE_ROW
    }

    @discardableResult
    func updateStatus(name: String, status: String) -> Bool {
        guard db != nil else {
            print("[-] Database not open")
            return false
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedStatus = status.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            print("[-] Profile name cannot be empty")
            return false
        }

        guard !trimmedStatus.isEmpty else {
            print("[-] Status cannot be empty")
            return false
        }

        let query = "UPDATE Profiles SET Status = ? WHERE Name = ?;"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            if let error = sqlite3_errmsg(db) {
                print("[-] Failed to prepare update: \(String(cString: error))")
            }
            return false
        }

        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_text(statement, 1, (trimmedStatus as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (trimmedName as NSString).utf8String, -1, nil)

        if sqlite3_step(statement) == SQLITE_DONE {
            let changes = sqlite3_changes(db)
            if changes > 0 {
                print("[+] Status updated successfully")
                return true
            } else {
                print("[-] No profile found with this name")
                return false
            }
        } else {
            if let error = sqlite3_errmsg(db) {
                print("[-] Failed to update status: \(String(cString: error))")
            }
            return false
        }
    }
}