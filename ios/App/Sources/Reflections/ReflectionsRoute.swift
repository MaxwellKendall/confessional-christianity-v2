// Push target for a reflection essay (mirrors /reflections/[slug]). The
// Reflections tab went away in TKL-825; a Library entry's "† Commentary" link
// pushes it through the shared tab destinations (AppDestinations).
import Foundation

enum ReflectionsRoute: Hashable {
    case detail(slug: String)
}
