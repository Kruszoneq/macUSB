import Foundation

extension MacOSDownloaderLogic {
    static func makeGroups(from entries: [MacOSInstallerEntry]) -> [MacOSInstallerFamilyGroup] {
        let grouped = Dictionary(grouping: entries) { $0.family }
        let groups = grouped.map { family, familyEntries in
            MacOSInstallerFamilyGroup(
                family: family,
                entries: familyEntries.sorted { lhs, rhs in
                    if lhs.version.compare(rhs.version, options: .numeric) != .orderedSame {
                        return lhs.version.compare(rhs.version, options: .numeric) == .orderedDescending
                    }
                    if lhs.build.compare(rhs.build, options: .numeric) != .orderedSame {
                        return lhs.build.compare(rhs.build, options: .numeric) == .orderedDescending
                    }
                    return lhs.name < rhs.name
                }
            )
        }

        return groups.sorted { lhs, rhs in
            let lhsTopVersion = lhs.entries.first?.version ?? "0"
            let rhsTopVersion = rhs.entries.first?.version ?? "0"
            if lhsTopVersion.compare(rhsTopVersion, options: .numeric) != .orderedSame {
                return lhsTopVersion.compare(rhsTopVersion, options: .numeric) == .orderedDescending
            }
            return lhs.family < rhs.family
        }
    }
}
