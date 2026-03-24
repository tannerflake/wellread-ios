//
//  ProfilePhotoCropView.swift
//  WellRead
//
//  Pinch-to-zoom and pan to select the area of the photo that fills the profile circle.
//

import SwiftUI
import UIKit

/// Holds the UIKit crop host so "Use Photo" can call `cropImage()` reliably (avoids stale optional closures).
final class ProfilePhotoCropController: ObservableObject {
    weak var hostView: ProfilePhotoCropHostView?

    func croppedImage() -> UIImage? {
        hostView?.cropImage()
    }
}

struct ProfilePhotoCropView: View {
    let image: UIImage
    let onUse: (UIImage) -> Void
    let onCancel: () -> Void

    @StateObject private var cropController = ProfilePhotoCropController()

    var body: some View {
        VStack(spacing: 0) {
            ProfilePhotoCropRepresentable(image: image, controller: cropController)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 20) {
                Button("Cancel") {
                    onCancel()
                }
                .font(Theme.headline())
                .foregroundStyle(Theme.textSecondary)

                Spacer()

                Button("Use Photo") {
                    if let cropped = cropController.croppedImage() {
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
    @ObservedObject var controller: ProfilePhotoCropController

    func makeUIView(context: Context) -> ProfilePhotoCropHostView {
        let host = ProfilePhotoCropHostView(image: image)
        controller.hostView = host
        return host
    }

    func updateUIView(_ uiView: ProfilePhotoCropHostView, context: Context) {
        controller.hostView = uiView
    }
}

final class ProfilePhotoCropHostView: UIView {
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let circleOverlay = CircleCropOverlayView()
    private let sourceImage: UIImage

    private let circleDiameter: CGFloat = 280

    init(image: UIImage) {
        self.sourceImage = image
        super.init(frame: .zero)
        backgroundColor = .black
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.clipsToBounds = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        imageView.image = image
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
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
            circleOverlay.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            circleOverlay.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            circleOverlay.widthAnchor.constraint(equalToConstant: circleDiameter),
            circleOverlay.heightAnchor.constraint(equalToConstant: circleDiameter),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let img = imageView.image else { return }
        let scrollSize = scrollView.bounds.size
        let imgSize = img.size
        guard scrollSize.width > 1, scrollSize.height > 1,
              imgSize.width > 0, imgSize.height > 0 else { return }

        let scaleW = scrollSize.width / imgSize.width
        let scaleH = scrollSize.height / imgSize.height
        let minScale = max(scaleW, scaleH)
        scrollView.minimumZoomScale = minScale
        if scrollView.zoomScale < minScale || scrollView.zoomScale.isNaN {
            scrollView.zoomScale = minScale
        }

        let z = scrollView.zoomScale
        let contentW = imgSize.width * z
        let contentH = imgSize.height * z
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

    /// Maps the on-screen circle to source image pixels and crops.
    func cropImage() -> UIImage? {
        layoutIfNeeded()
        scrollView.layoutIfNeeded()
        imageView.layoutIfNeeded()
        circleOverlay.layoutIfNeeded()

        let img = sourceImage
        guard let cg = img.cgImage else { return img }
        let imageSizePoints = img.size
        let pixelScale = img.scale

        let circleInImageView = imageView.convert(circleOverlay.bounds, from: circleOverlay)
        let bounds = imageView.bounds
        guard bounds.width > 0.5, bounds.height > 0.5 else { return nil }

        let drawRect = Self.aspectFillDrawRect(imageSize: imageSizePoints, in: bounds)
        let visibleImage = drawRect.intersection(bounds)
        let cropInImageView = circleInImageView.intersection(visibleImage)
        guard cropInImageView.width > 0.5, cropInImageView.height > 0.5 else { return nil }

        let ix = (cropInImageView.minX - drawRect.minX) / drawRect.width * imageSizePoints.width
        let iy = (cropInImageView.minY - drawRect.minY) / drawRect.height * imageSizePoints.height
        let iw = cropInImageView.width / drawRect.width * imageSizePoints.width
        let ih = cropInImageView.height / drawRect.height * imageSizePoints.height

        var cropPoints = CGRect(x: ix, y: iy, width: iw, height: ih)
        cropPoints = cropPoints.intersection(CGRect(origin: .zero, size: imageSizePoints))
        guard cropPoints.width > 0.5, cropPoints.height > 0.5 else { return nil }

        let pixelRect = CGRect(
            x: cropPoints.origin.x * pixelScale,
            y: cropPoints.origin.y * pixelScale,
            width: cropPoints.size.width * pixelScale,
            height: cropPoints.size.height * pixelScale
        ).integral

        guard let croppedCg = cg.cropping(to: pixelRect) else { return nil }
        return UIImage(cgImage: croppedCg, scale: pixelScale, orientation: img.imageOrientation)
    }

    /// Rect (in view coordinates) where the full image is drawn with aspect fill inside `bounds`.
    private static func aspectFillDrawRect(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
        let imageAspect = imageSize.width / imageSize.height
        let viewAspect = bounds.width / bounds.height
        if imageAspect > viewAspect {
            let h = bounds.height
            let w = h * imageAspect
            let x = bounds.midX - w / 2
            return CGRect(x: x, y: bounds.minY, width: w, height: h)
        } else {
            let w = bounds.width
            let h = w / imageAspect
            let y = bounds.midY - h / 2
            return CGRect(x: bounds.minX, y: y, width: w, height: h)
        }
    }
}

extension ProfilePhotoCropHostView: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
}

private final class CircleCropOverlayView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        let region = bounds
        guard let ctx = UIGraphicsGetCurrentContext(), region.width > 0, region.height > 0 else { return }
        UIColor.black.withAlphaComponent(0.5).setFill()
        ctx.fill(region)
        ctx.addEllipse(in: region)
        ctx.setBlendMode(.clear)
        ctx.fillPath()
        ctx.setBlendMode(.normal)
        UIColor.white.withAlphaComponent(0.6).setStroke()
        ctx.setLineWidth(2)
        ctx.addEllipse(in: region.insetBy(dx: 1, dy: 1))
        ctx.strokePath()
    }
}
