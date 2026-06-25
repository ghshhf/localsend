import Foundation

class SecurityScopedResourceManager {
    static let shared = SecurityScopedResourceManager()
    private var openResources: [URL: Data] = [:]
    
    private init() {}
    
    deinit {
        cleanupAll()
    }
    
    /// Start accessing a security-scoped resource from a bookmark.
    /// Returns the resolved URL, or nil if resolution or access fails.
    /// - Important: The caller must call `stopAccessing(url:)` when the resource is no longer needed
    ///   to avoid leaking kernel file descriptors. See: https://developer.apple.com/documentation/foundation/url/1779698-startaccessingsecurityscopedreso
    func startAccessing(bookmark: Data) -> URL? {
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmark, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &isStale)
            
            if url.startAccessingSecurityScopedResource() {
                openResources[url] = bookmark
                return url
            } else {
                print("Failed to start accessing security-scoped resource: \(url)")
                return nil
            }
        } catch {
            print("Failed to resolve security-scoped bookmark: \(error)")
            return nil
        }
    }
    
    /// Stop accessing a security-scoped resource and release its kernel reference.
    /// Should be called when the file is no longer needed.
    /// - Parameter url: The URL to stop accessing.
    func stopAccessing(url: URL) {
        if openResources.keys.contains(url) {
            url.stopAccessingSecurityScopedResource()
            openResources.removeValue(forKey: url)
        }
    }
    
    /// Stop accessing all currently open security-scoped resources.
    /// Called automatically on `deinit` to prevent kernel FD leaks.
    func cleanupAll() {
        for (url, _) in openResources {
            url.stopAccessingSecurityScopedResource()
        }
        openResources.removeAll()
    }
}
