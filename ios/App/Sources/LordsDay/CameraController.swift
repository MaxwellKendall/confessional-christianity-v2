// The back camera for photographing notes (TKL-860): a live preview and a
// still capture. The session runs on its own queue, as AVFoundation asks.
// The simulator has no camera, so there `status` ends at `.unavailable` and
// the capture screen leads with "Choose from Photos" and "Type instead".
@preconcurrency import AVFoundation
import SwiftUI
import UIKit

final class CameraController: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    enum Status: Equatable { case starting, running, denied, unavailable }

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "com.confessionalchristianity.camera")
    private var pending: CheckedContinuation<UIImage?, Never>?
    private var configured = false

    func start() async -> Status {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { return .denied }
        default: return .denied
        }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return .unavailable }
        return await withCheckedContinuation { done in
            queue.async {
                if !self.configured {
                    self.session.beginConfiguration()
                    self.session.sessionPreset = .photo
                    if self.session.canAddInput(input) { self.session.addInput(input) }
                    if self.session.canAddOutput(self.output) { self.session.addOutput(self.output) }
                    self.session.commitConfiguration()
                    self.configured = true
                }
                if !self.session.isRunning { self.session.startRunning() }
                done.resume(returning: self.session.isRunning ? .running : .unavailable)
            }
        }
    }

    func stop() {
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    func capture() async -> UIImage? {
        await withCheckedContinuation { done in
            queue.async {
                guard self.pending == nil, self.session.isRunning else { done.resume(returning: nil); return }
                self.pending = done
                self.output.capturePhoto(with: AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg]), delegate: self)
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        queue.async {
            self.pending?.resume(returning: image)
            self.pending = nil
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
