import SwiftUI

/// Product imagery, loaded through `ImageStore` and never blocking layout.
///
/// Photography carries the visual weight in this design language, so the image
/// container is fixed-ratio and the image itself fills it. While loading, the
/// container shows the surface fill — the frame never resizes when the image
/// arrives, so a grid does not reflow under the user's thumb.
struct CatalogueImageView: View {
    let imageRef: CatalogueImageRef
    var contentMode: ContentMode = .fill
    var cornerRadius: CGFloat = Radius.card

    @EnvironmentObject private var imageStore: ImageStore
    @State private var image: UIImage?
    @State private var didFail = false

    init(
        imageRef: CatalogueImageRef,
        contentMode: ContentMode = .fill,
        cornerRadius: CGFloat = Radius.card
    ) {
        self.imageRef = imageRef
        self.contentMode = contentMode
        self.cornerRadius = cornerRadius
    }

    /// Convenience for imagery published alongside the catalogue.
    init(
        imageName: String,
        contentMode: ContentMode = .fill,
        cornerRadius: CGFloat = Radius.card
    ) {
        self.init(
            imageRef: CatalogueImageRef(cacheKey: imageName, absoluteURL: nil),
            contentMode: contentMode,
            cornerRadius: cornerRadius
        )
    }

    var body: some View {
        // The container is a Shape, so it takes exactly the size it is given.
        // The image sits in an overlay: an overlay cannot enlarge its parent,
        // which is what keeps a `.fill` image from spilling past the frame it
        // was handed and out over the row margin.
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Palette.surface)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .transition(.opacity)
                } else if didFail {
                    Image(systemName: "photo")
                        .font(.system(size: IconSize.large, weight: .light))
                        .foregroundStyle(Palette.textPlaceholder)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .animation(Motion.standard, value: image != nil)
        .task(id: imageRef) {
            image = nil
            didFail = false
            guard !imageRef.isEmpty else {
                didFail = true
                return
            }
            let loaded = await imageStore.image(for: imageRef)
            image = loaded
            didFail = loaded == nil
        }
        .accessibilityHidden(true)
    }
}
