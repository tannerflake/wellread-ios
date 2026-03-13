//
//  ProfilePhotoCropView.swift
//  WellRead
//
//  Pinch-to-zoom and pan to select the area of the photo that fills the profile circle.
//

import SwiftUI
import UIKit

struct ProfilePhotoCropView: View {
    let image: UIImage
    let onUse: (UIImage) -> Void
    let onCancel: () -> Void

    @State private var cropProvider: (() -> UIImage?)?

    var body: some View {
        VStack(spacing: 0) {
            ProfilePhotoCropRepresentable(image: image, registerCropProvider: { cropProvider = $0 })
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 20) {
                Button("Cancel") {
                    onCancel()
                }
                .font(Theme.headline())
                .foregroundStyle(Theme.textSecondary)

                Spacer()

                Button("Use Photo") {
                    if let cropped = cropProvider?() {
                        onUse(cropped)
                    }
                }
                .font(Theme.headline())
                .foregroundStyle(Theme.background)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Theme.accent)
                .clipShape(Capsule())
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(Theme.background)
        }
        .background(Theme.background)
    }
}

private struct ProfilePhotoCropRepresentable: UIViewRepresentable {
    let image: UIImage
    let registerCropProvider: (@escaping () -> UIImage?) -> Void

    func makeUIView(context: Context) -> ProfilePhotoCropHostView {
        let host = ProfilePhotoCropHostView(image: image)
        registerCropProvider { [weak host] in host?.cropImage() }
        return host
    }

    func updateUIView(_ uiView: ProfilePhotoCropHostView, context: Context) {}
}

private final class ProfilePhotoCropHostView: UIView {
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let circleOverlay = CircleCropOverlayView()
    private let sourceImage: UIImage

    private let circleSize: CGFloat = 280

    init(image: UIImage) {
        self.sourceImage = image
        super.init(frame: .zero)
        backgroundColor = .black
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        circleOverlay.isUserInteractionEnabled = false
        circleOverlay.translatesAutoresizingMaskIntoConstraints = false

        addSubview(scrollView)
        scrollView.addSubview(imageView)
        addSubview(circleOverlay)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            circleOverlay.centerXAnchor.constraint(equalTo: centerXAnchor),
            circleOverlay.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -60),
            circleOverlay.widthAnchor.constraint(equalToConstant: circleSize),
            circleOverlay.heightAnchor.constraint(equalToConstant: circleSize),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let img = imageView.image else { return }
        let scrollSize = scrollView.bounds.size
        let imgSize = img.size
        let scaleW = scrollSize.width / imgSize.width
        let scaleH = scrollSize.height / imgSize.height
        let minScale = max(scaleW, scaleH)
        scrollView.minimumZoomScale = minScale
        if scrollView.zoomScale < minScale || scrollView.zoomScale.isNaN { scrollView.zoomScale = minScale }
        let contentW = imgSize.width * scrollView.zoomScale
        let contentH = imgSize.height * scrollView.zoomScale
        imageView.frame = CGRect(x: 0, y: 0, width: contentW, height: contentH)
        scrollView.contentSize = CGSize(width: contentW, height: contentH)
        let insetX = max(0, (scrollSize.width - contentW) / 2)
        let insetY = max(0, (scrollSize.height - contentH) / 2)
        scrollView.contentInset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        setNeedsLayout()
        layoutIfNeeded()
    }

    /// Converts the visible circle in scroll view to image coordinates and crops to a square (circle's bounding box).
    func cropImage() -> UIImage? {
        let img = sourceImage
        let imgSize = img.size
        let zoom = scrollView.zoomScale
        let contentOffset = scrollView.contentOffset
        let circleFrame = circleOverlay.frame

        // Circle in scroll view bounds; content point under circle top-left
        let circleLeftInContent = contentOffset.x + circleFrame.minX
        let circleTopInContent = contentOffset.y + circleFrame.minY
        // Content coordinates match imageView; imageView is zoomed so content -> image = 1/zoom
        let scaleToImage = 1.0 / zoom
        var cropX = circleLeftInContent * scaleToImage
        var cropY = circleTopInContent * scaleToImage
        let cropSide = circleSize * scaleToImage

        cropX = max(0, min(cropX, imgSize.width - cropSide))
        cropY = max(0, min(cropY, imgSize.height - cropSide))
        let side = min(cropSide, imgSize.width - cropX, imgSize.height - cropY)
        guard side > 0 else { return nil }
        let scale = img.scale
        let pixelRect = CGRect(x: cropX * scale, y: cropY * scale, width: side * scale, height: side * scale)
        guard let cg = img.cgImage?.cropping(to: pixelRect) else { return nil }
        return UIImage(cgImage: cg, scale: scale, orientation: img.imageOrientation)
    }
}

extension ProfilePhotoCropHostView: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
}

private final class CircleCropOverlayView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        UIColor.black.withAlphaComponent(0.5).setFill()
        ctx.fill(rect)
        ctx.addEllipse(in: rect)
        ctx.setBlendMode(.clear)
        ctx.fillPath()
        ctx.setBlendMode(.normal)
        UIColor.white.withAlphaComponent(0.6).setStroke()
        ctx.setLineWidth(2)
        ctx.addEllipse(in: rect.insetBy(dx: 1, dy: 1))
        ctx.strokePath()
    }
}
