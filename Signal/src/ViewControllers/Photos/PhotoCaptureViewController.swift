//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import AVFoundation
import PromiseKit
import Lottie

protocol PhotoCaptureViewControllerDelegate: AnyObject {
    func photoCaptureViewController(_ photoCaptureViewController: PhotoCaptureViewController, didFinishProcessingAttachment attachment: SignalAttachment)
    func photoCaptureViewControllerDidCancel(_ photoCaptureViewController: PhotoCaptureViewController)
    func photoCaptureViewControllerDidTryToCaptureTooMany(_ photoCaptureViewController: PhotoCaptureViewController)
    func photoCaptureViewControllerCanCaptureMoreItems(_ photoCaptureViewController: PhotoCaptureViewController) -> Bool
    func photoCaptureViewController(_ photoCaptureViewController: PhotoCaptureViewController, isRecordingMovie: Bool)
}

enum PhotoCaptureError: Error {
    case assertionError(description: String)
    case initializationFailed
    case captureFailed
}

extension PhotoCaptureError: LocalizedError {
    var localizedDescription: String {
        switch self {
        case .initializationFailed:
            return NSLocalizedString("PHOTO_CAPTURE_UNABLE_TO_INITIALIZE_CAMERA", comment: "alert title")
        case .captureFailed:
            return NSLocalizedString("PHOTO_CAPTURE_UNABLE_TO_CAPTURE_IMAGE", comment: "alert title")
        case .assertionError:
            return NSLocalizedString("PHOTO_CAPTURE_GENERIC_ERROR", comment: "alert title, generic error preventing user from capturing a photo")
        }
    }
}

// MARK: -

@objc
class PhotoCaptureViewController: OWSViewController, InteractiveDismissDelegate {

    weak var delegate: PhotoCaptureViewControllerDelegate?
    var interactiveDismiss: PhotoCaptureInteractiveDismiss!

    @objc public lazy var photoCapture = PhotoCapture()

    lazy var tapToFocusView: AnimationView = {
        let view = AnimationView(name: "tap_to_focus")
        view.animationSpeed = 1
        view.backgroundBehavior = .forceFinish
        view.contentMode = .scaleAspectFit
        view.autoSetDimensions(to: CGSize(square: 150))
        view.setContentHuggingHigh()
        return view
    }()

    deinit {
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        photoCapture.stopCapture().done {
            Logger.debug("stopCapture completed")
        }
    }

    // MARK: - Overrides

    override func loadView() {
        self.view = UIView()
        self.view.backgroundColor = Theme.darkThemeBackgroundColor
        definesPresentationContext = true

        view.addSubview(previewView)

        previewView.autoPinEdgesToSuperviewEdges()

        view.addSubview(captureButton)
        if UIDevice.current.isIPad {
            captureButton.autoVCenterInSuperview()
            captureButton.centerXAnchor.constraint(equalTo: view.trailingAnchor, constant: SendMediaNavigationController.bottomButtonsCenterOffset).isActive = true
            captureButton.movieLockView.autoSetDimension(.width, toSize: 120)
        } else {
            captureButton.autoHCenterInSuperview()
            // we pin to edges rather than margin, because on notched devices the margin changes
            // as the device rotates *EVEN THOUGH* the interface is locked to portrait.
            captureButton.centerYAnchor.constraint(equalTo: view.bottomAnchor,
                                                   constant: SendMediaNavigationController.bottomButtonsCenterOffset).isActive = true
            captureButton.movieLockView.autoPinEdge(.trailing, to: .trailing, of: view, withOffset: -16)
        }

        // If the view is already visible, setup the volume button listener
        // now that the capture UI is ready. Otherwise, we'll wait until
        // we're visible.
        if isVisible {
            VolumeButtons.shared?.addObserver(observer: photoCapture)
        }

        view.addSubview(tapToFocusView)
        tapToFocusView.isUserInteractionEnabled = false
        tapToFocusLeftConstraint = tapToFocusView.centerXAnchor.constraint(equalTo: view.leftAnchor)
        tapToFocusLeftConstraint.isActive = true
        tapToFocusTopConstraint = tapToFocusView.centerYAnchor.constraint(equalTo: view.topAnchor)
        tapToFocusTopConstraint.isActive = true

        view.addSubview(topBar)
        topBar.autoPinWidthToSuperview()
        topBarOffset = topBar.autoPinEdge(toSuperviewEdge: .top)
        topBar.autoSetDimension(.height, toSize: 44)
    }

    var topBarOffset: NSLayoutConstraint!

    override func viewDidLoad() {
        super.viewDidLoad()

        setupPhotoCapture()

        updateNavigationItems()
        updateFlashModeControl()

        view.addGestureRecognizer(pinchZoomGesture)
        view.addGestureRecognizer(tapToFocusGesture)
        view.addGestureRecognizer(doubleTapToSwitchCameraGesture)

        if let navController = self.navigationController {
            interactiveDismiss = PhotoCaptureInteractiveDismiss(viewController: navController)
            interactiveDismiss.interactiveDismissDelegate = self
            interactiveDismiss.addGestureRecognizer(to: view)
        }

        tapToFocusGesture.require(toFail: doubleTapToSwitchCameraGesture)
    }

    private var isVisible = false
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isVisible = true
        let previewOrientation: AVCaptureVideoOrientation
        if UIDevice.current.isIPad {
            previewOrientation = AVCaptureVideoOrientation(interfaceOrientation: CurrentAppContext().interfaceOrientation)  ?? .portrait
        } else {
            previewOrientation = .portrait
        }
        UIViewController.attemptRotationToDeviceOrientation()
        photoCapture.updateVideoPreviewConnection(toOrientation: previewOrientation)
        updateIconOrientations(isAnimated: false, captureOrientation: previewOrientation)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if hasCaptureStarted {
            BenchEventComplete(eventId: "Show-Camera")
            VolumeButtons.shared?.addObserver(observer: photoCapture)
        }
        UIApplication.shared.isIdleTimerDisabled = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isVisible = false
        VolumeButtons.shared?.removeObserver(photoCapture)
        UIApplication.shared.isIdleTimerDisabled = false
    }

    override var prefersStatusBarHidden: Bool {
        guard !OWSWindowManager.shared.hasCall else {
            return false
        }

        return true
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        if UIDevice.current.isIPad {
            // Since we support iPad multitasking, we cannot *disable* rotation of our views.
            // Rotating the preview layer is really distracting, so we fade out the preview layer
            // while the rotation occurs.
            self.previewView.alpha = 0
            coordinator.animate(alongsideTransition: { _ in }) { _ in
                UIView.animate(withDuration: 0.1) {
                    self.previewView.alpha = 1
                }
            }
        }
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        if !UIDevice.current.isIPad {
            // we pin to a constant rather than margin, because on notched devices the
            // safeAreaInsets/margins change as the device rotates *EVEN THOUGH* the interface
            // is locked to portrait.
            // Only grab this once -- otherwise when we swipe to dismiss this is updated and the top bar jumps to having zero offset
            if topBarOffset.constant == 0 {
                topBarOffset.constant = max(view.safeAreaInsets.top, view.safeAreaInsets.left, view.safeAreaInsets.bottom)
            }
        }
    }

    func interactiveDismissDidBegin(_ interactiveDismiss: UIPercentDrivenInteractiveTransition) {
    }
    func interactiveDismissDidFinish(_ interactiveDismiss: UIPercentDrivenInteractiveTransition) {
        dismiss(animated: true)
    }
    func interactiveDismissDidCancel(_ interactiveDismiss: UIPercentDrivenInteractiveTransition) {
    }

    // MARK: -
    var isRecordingMovie: Bool = false

    private class TopBar: UIView {
        let recordingTimerView = RecordingTimerView()
        let navStack: UIStackView

        init(navbarItems: [UIView]) {
            self.navStack = UIStackView(arrangedSubviews: navbarItems)
            navStack.spacing = 16

            super.init(frame: .zero)

            addSubview(navStack)
            navStack.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: 4, leading: 0, bottom: 0, trailing: 16))

            addSubview(recordingTimerView)
            recordingTimerView.isHidden = true
            recordingTimerView.autoCenterInSuperview()
        }

        required init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        enum Mode {
            case navigation, recordingMovie
        }

        var mode: Mode = .navigation {
            didSet {
                switch mode {
                case .recordingMovie:
                    navStack.isHidden = true
                    recordingTimerView.sizeToFit()
                    recordingTimerView.isHidden = false
                case .navigation:
                    navStack.isHidden = false
                    recordingTimerView.isHidden = true
                }
            }
        }
    }

    private lazy var topBar: TopBar = {
        let dismissButton: UIButton
        if UIDevice.current.isIPad {
            dismissButton = OWSButton.shadowedCancelButton { [weak self] in
                self?.didTapClose()
            }
            dismissButton.contentEdgeInsets = UIEdgeInsets(top: 7, leading: 20, bottom: 6, trailing: 20)
        } else {
            dismissButton = dismissControl.button
            dismissButton.contentEdgeInsets = UIEdgeInsets(top: 1, leading: 16, bottom: 6, trailing: 20)
        }

        return TopBar(navbarItems: [dismissButton,
                                    UIView.hStretchingSpacer(),
                                    switchCameraControl.button,
                                    flashModeControl.button])
    }()

    func updateNavigationItems() {
        if isRecordingMovie {
            topBar.mode = .recordingMovie
        } else {
            topBar.mode = .navigation
        }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }

    // MARK: - Views

    let captureButton = CaptureButton()

    var previewView: CapturePreviewView {
        return photoCapture.previewView
    }

    class PhotoControl {
        let button: OWSButton

        init(imageName: String, block: @escaping () -> Void) {
            self.button = OWSButton(imageName: imageName, tintColor: .ows_white, block: block)
            button.setCompressionResistanceHigh()
            button.layer.shadowOffset = CGSize.zero
            button.layer.shadowOpacity = 0.35
            button.layer.shadowRadius = 4
            button.contentEdgeInsets = UIEdgeInsets(top: 6, leading: 4, bottom: 0, trailing: 4)
        }

        func setImage(imageName: String) {
            button.setImage(imageName: imageName)
        }
    }

    private lazy var dismissControl: PhotoControl = {
        return PhotoControl(imageName: "ic_x_with_shadow") { [weak self] in
            self?.didTapClose()
        }
    }()

    private lazy var switchCameraControl: PhotoControl = {
        return PhotoControl(imageName: "ic_switch_camera") { [weak self] in
            self?.didTapSwitchCamera()
        }
    }()

    private lazy var flashModeControl: PhotoControl = {
        return PhotoControl(imageName: "ic_flash_mode_auto") { [weak self] in
            self?.didTapFlashMode()
        }
    }()

    lazy var pinchZoomGesture: UIPinchGestureRecognizer = {
        return UIPinchGestureRecognizer(target: self, action: #selector(didPinchZoom(pinchGesture:)))
    }()

    lazy var tapToFocusGesture: UITapGestureRecognizer = {
        return UITapGestureRecognizer(target: self, action: #selector(didTapFocusExpose(tapGesture:)))
    }()

    lazy var doubleTapToSwitchCameraGesture: UITapGestureRecognizer = {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didDoubleTapToSwitchCamera(tapGesture:)))
        tapGesture.numberOfTapsRequired = 2
        return tapGesture
    }()

    // MARK: - Events

    @objc
    func didTapClose() {
        self.delegate?.photoCaptureViewControllerDidCancel(self)
    }

    @objc
    func didTapSwitchCamera() {
        Logger.debug("")
        switchCamera()
    }

    @objc
    func didDoubleTapToSwitchCamera(tapGesture: UITapGestureRecognizer) {
        Logger.debug("")
        guard !isRecordingMovie else {
            // - Orientation gets out of sync when switching cameras mid movie.
            // - Audio gets out of sync when switching cameras mid movie
            // https://stackoverflow.com/questions/13951182/audio-video-out-of-sync-after-switch-camera
            return
        }
        switchCamera()
    }

    private func switchCamera() {
        UIView.animate(withDuration: 0.2) {
            let epsilonToForceCounterClockwiseRotation: CGFloat = 0.00001
            self.switchCameraControl.button.transform = self.switchCameraControl.button.transform.rotate(.pi + epsilonToForceCounterClockwiseRotation)
        }
        photoCapture.switchCamera().catch { error in
            self.showFailureUI(error: error)
        }
    }

    @objc
    func didTapFlashMode() {
        Logger.debug("")
        firstly {
            photoCapture.switchFlashMode()
        }.done {
            self.updateFlashModeControl()
        }.catch { error in
            owsFailDebug("Error: \(error)")
        }
    }

    @objc
    func didPinchZoom(pinchGesture: UIPinchGestureRecognizer) {
        switch pinchGesture.state {
        case .began: fallthrough
        case .changed:
            photoCapture.updateZoom(scaleFromPreviousZoomFactor: pinchGesture.scale)
        case .ended:
            photoCapture.completeZoom(scaleFromPreviousZoomFactor: pinchGesture.scale)
        default:
            break
        }
    }

    @objc
    func didTapFocusExpose(tapGesture: UITapGestureRecognizer) {
        let viewLocation = tapGesture.location(in: view)
        let devicePoint = previewView.previewLayer.captureDevicePointConverted(fromLayerPoint: viewLocation)

        photoCapture.focus(with: .autoFocus, exposureMode: .autoExpose, at: devicePoint, monitorSubjectAreaChange: true)

        // If the user taps near the capture button, it's more likely a mis-tap than intentional.
        // Skip the focus animation in that case, since it looks bad.
        let captureButtonOrigin = captureButton.superview!.convert(captureButton.frame.origin, to: view)
        if UIDevice.current.isIPad {
            guard viewLocation.x < captureButtonOrigin.x else {
                Logger.verbose("Skipping animation for right edge on iPad")

                // Finish any outstanding focus animation, otherwise it will remain in an
                // uncompleted state.
                if let lastUserFocusTapPoint = lastUserFocusTapPoint {
                    completeFocusAnimation(forFocusPoint: lastUserFocusTapPoint)
                }
                return
            }
        } else {
            guard viewLocation.y < captureButtonOrigin.y else {
                Logger.verbose("Skipping animation for bottom row on iPhone")

                // Finish any outstanding focus animation, otherwise it will remain in an
                // uncompleted state.
                if let lastUserFocusTapPoint = lastUserFocusTapPoint {
                    completeFocusAnimation(forFocusPoint: lastUserFocusTapPoint)
                }
                return
            }
        }

        lastUserFocusTapPoint = devicePoint
        do {
            let convertedPoint = tapToFocusView.superview!.convert(viewLocation, from: view)
            positionTapToFocusView(center: convertedPoint)
            tapToFocusView.superview?.layoutIfNeeded()
            startFocusAnimation()
        }
    }

    // MARK: - Focus Animations

    var tapToFocusLeftConstraint: NSLayoutConstraint!
    var tapToFocusTopConstraint: NSLayoutConstraint!
    func positionTapToFocusView(center: CGPoint) {
        tapToFocusLeftConstraint.constant = center.x
        tapToFocusTopConstraint.constant = center.y
    }

    func startFocusAnimation() {
        tapToFocusView.stop()
        tapToFocusView.play(fromProgress: 0.0, toProgress: 0.9)
    }

    var lastUserFocusTapPoint: CGPoint?
    func completeFocusAnimation(forFocusPoint focusPoint: CGPoint) {
        guard let lastUserFocusTapPoint = lastUserFocusTapPoint else {
            return
        }

        guard lastUserFocusTapPoint.within(0.005, of: focusPoint) else {
            Logger.verbose("focus completed for obsolete focus point. User has refocused.")
            return
        }

        tapToFocusView.play(toProgress: 1.0)
    }

    // MARK: - Orientation

    // MARK: -

    private func updateIconOrientations(isAnimated: Bool, captureOrientation: AVCaptureVideoOrientation) {
        guard !UIDevice.current.isIPad else {
            return
        }

        Logger.verbose("captureOrientation: \(captureOrientation)")

        let transformFromOrientation: CGAffineTransform
        switch captureOrientation {
        case .portrait:
            transformFromOrientation = .identity
        case .portraitUpsideDown:
            transformFromOrientation = CGAffineTransform(rotationAngle: .pi)
        case .landscapeLeft:
            transformFromOrientation = CGAffineTransform(rotationAngle: .halfPi)
        case .landscapeRight:
            transformFromOrientation = CGAffineTransform(rotationAngle: -1 * .halfPi)
        @unknown default:
            owsFailDebug("unexpected captureOrientation: \(captureOrientation.rawValue)")
            transformFromOrientation = .identity
        }

        // Don't "unrotate" the switch camera icon if the front facing camera had been selected.
        let tranformFromCameraType: CGAffineTransform = photoCapture.desiredPosition == .front ? CGAffineTransform(rotationAngle: -.pi) : .identity

        let updateOrientation = {
            self.flashModeControl.button.transform = transformFromOrientation
            self.switchCameraControl.button.transform = transformFromOrientation.concatenating(tranformFromCameraType)
        }

        if isAnimated {
            UIView.animate(withDuration: 0.3, animations: updateOrientation)
        } else {
            updateOrientation()
        }
    }

    var hasCaptureStarted = false
    private func setupPhotoCapture() {
        photoCapture.delegate = self
        captureButton.delegate = photoCapture

        let captureReady = { [weak self] in
            guard let self = self else { return }
            self.hasCaptureStarted = true
            BenchEventComplete(eventId: "Show-Camera")
        }

        // If the session is already running, we're good to go.
        guard !photoCapture.session.isRunning else {
            return captureReady()
        }

        firstly {
            photoCapture.startVideoCapture()
        }.done {
            captureReady()
        }.catch { [weak self] error in
            guard let self = self else { return }
            self.showFailureUI(error: error)
        }
    }

    private func showFailureUI(error: Error) {
        Logger.error("error: \(error)")

        OWSActionSheets.showActionSheet(title: nil,
                            message: error.localizedDescription,
                            buttonTitle: CommonStrings.dismissButton,
                            buttonAction: { [weak self] _ in self?.dismiss(animated: true) })
    }

    private func updateFlashModeControl() {
        let imageName: String
        switch photoCapture.flashMode {
        case .auto:
            imageName = "ic_flash_mode_auto"
        case .on:
            imageName = "ic_flash_mode_on"
        case .off:
            imageName = "ic_flash_mode_off"
        @unknown default:
            owsFailDebug("unexpected photoCapture.flashMode: \(photoCapture.flashMode.rawValue)")

            imageName = "ic_flash_mode_auto"
        }

        self.flashModeControl.setImage(imageName: imageName)
    }
}

extension PhotoCaptureViewController: PhotoCaptureDelegate {

    // MARK: - Photo

    func photoCaptureDidStartPhotoCapture(_ photoCapture: PhotoCapture) {
        let captureFeedbackView = UIView()
        captureFeedbackView.backgroundColor = .black
        view.insertSubview(captureFeedbackView, aboveSubview: previewView)
        captureFeedbackView.autoPinEdgesToSuperviewEdges()

        // Ensure the capture feedback is laid out before we remove it,
        // depending on where we're coming from a layout pass might not
        // trigger in 0.05 seconds otherwise.
        view.setNeedsLayout()
        view.layoutIfNeeded()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            captureFeedbackView.removeFromSuperview()
        }
    }

    func photoCapture(_ photoCapture: PhotoCapture, didFinishProcessingAttachment attachment: SignalAttachment) {
        delegate?.photoCaptureViewController(self, didFinishProcessingAttachment: attachment)
    }

    func photoCapture(_ photoCapture: PhotoCapture, processingDidError error: Error) {
        showFailureUI(error: error)
    }

    func photoCaptureCanCaptureMoreItems(_ photoCapture: PhotoCapture) -> Bool {
        guard let delegate = delegate else { return false }
        return delegate.photoCaptureViewControllerCanCaptureMoreItems(self)
    }

    func photoCaptureDidTryToCaptureTooMany(_ photoCapture: PhotoCapture) {
        delegate?.photoCaptureViewControllerDidTryToCaptureTooMany(self)
    }

    // MARK: - Movie

    func photoCaptureDidBeginMovie(_ photoCapture: PhotoCapture) {
        isRecordingMovie = true
        updateNavigationItems()
        topBar.recordingTimerView.startCounting()
        delegate?.photoCaptureViewController(self, isRecordingMovie: isRecordingMovie)
    }

    func photoCaptureDidCompleteMovie(_ photoCapture: PhotoCapture) {
        isRecordingMovie = false
        topBar.recordingTimerView.stopCounting()
        updateNavigationItems()
        delegate?.photoCaptureViewController(self, isRecordingMovie: isRecordingMovie)
    }

    func photoCaptureDidCancelMovie(_ photoCapture: PhotoCapture) {
        isRecordingMovie = false
        topBar.recordingTimerView.stopCounting()
        updateNavigationItems()
        delegate?.photoCaptureViewController(self, isRecordingMovie: isRecordingMovie)
    }

    // MARK: -

    var zoomScaleReferenceHeight: CGFloat? {
        return view.bounds.height
    }

    func beginCaptureButtonAnimation(_ duration: TimeInterval) {
        captureButton.beginRecordingAnimation(duration: duration)
    }

    func endCaptureButtonAnimation(_ duration: TimeInterval) {
        captureButton.endRecordingAnimation(duration: duration)
    }

    func photoCapture(_ photoCapture: PhotoCapture, didChangeOrientation orientation: AVCaptureVideoOrientation) {
        updateIconOrientations(isAnimated: true, captureOrientation: orientation)
        if UIDevice.current.isIPad {
            photoCapture.updateVideoPreviewConnection(toOrientation: orientation)
        }
    }

    func photoCapture(_ photoCapture: PhotoCapture, didCompleteFocusingAtPoint focusPoint: CGPoint) {
        completeFocusAnimation(forFocusPoint: focusPoint)
    }
}

// MARK: - Views

protocol CaptureButtonDelegate: AnyObject {
    // MARK: Photo
    func didTapCaptureButton(_ captureButton: CaptureButton)

    // MARK: Video
    func didBeginLongPressCaptureButton(_ captureButton: CaptureButton)
    func didCompleteLongPressCaptureButton(_ captureButton: CaptureButton)
    func didCancelLongPressCaptureButton(_ captureButton: CaptureButton)
    func didPressStopCaptureButton(_ captureButton: CaptureButton)

    var zoomScaleReferenceHeight: CGFloat? { get }
    func longPressCaptureButton(_ captureButton: CaptureButton, didUpdateZoomAlpha zoomAlpha: CGFloat)
}

extension CaptureButton: MovieLockViewDelegate {
    func videoLockViewDidTapStop(_ videoLockView: MovieLockView) {
        assert(movieLockView.isLocked)
        movieLockView.unlock(isAnimated: true)
        UIView.animate(withDuration: 0.2) {
            self.movieLockView.alpha = 0
        }
        delegate?.didPressStopCaptureButton(self)
    }
}

class CaptureButton: UIView {

    let innerButton = CircleView()
    let movieLockView = MovieLockView(swipeDirectionToLock: UIDevice.current.isIPad ? .leading : .trailing)

    var longPressGesture: UILongPressGestureRecognizer!
    let longPressDuration = 0.5

    let zoomIndicator = CircleView()

    weak var delegate: CaptureButtonDelegate?

    let defaultDiameter: CGFloat = min(ScaleFromIPhone5To7Plus(60, 80), 80)
    static let recordingDiameter: CGFloat = min(ScaleFromIPhone5To7Plus(68, 120), 120)
    var innerButtonSizeConstraints: [NSLayoutConstraint]!
    var zoomIndicatorSizeConstraints: [NSLayoutConstraint]!

    override init(frame: CGRect) {
        super.init(frame: frame)

        // The long press handles both the tap and the hold interaction, as well as the animation
        // the presents as the user begins to hold (and the button begins to grow prior to recording)
        longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(didLongPress))
        longPressGesture.minimumPressDuration = 0
        innerButton.addGestureRecognizer(longPressGesture)

        addSubview(innerButton)
        innerButtonSizeConstraints = autoSetDimensions(to: CGSize(square: defaultDiameter))
        innerButton.backgroundColor = UIColor.ows_white.withAlphaComponent(0.33)
        innerButton.layer.shadowOffset = .zero
        innerButton.layer.shadowOpacity = 0.33
        innerButton.layer.shadowRadius = 2
        innerButton.autoPinEdgesToSuperviewEdges()

        addSubview(zoomIndicator)
        zoomIndicatorSizeConstraints = zoomIndicator.autoSetDimensions(to: CGSize(square: defaultDiameter))
        zoomIndicator.isUserInteractionEnabled = false
        zoomIndicator.layer.borderColor = UIColor.ows_white.cgColor
        zoomIndicator.layer.borderWidth = 1.5
        zoomIndicator.autoAlignAxis(.horizontal, toSameAxisOf: innerButton)
        zoomIndicator.autoAlignAxis(.vertical, toSameAxisOf: innerButton)

        addSubview(movieLockView)
        movieLockView.autoSetDimension(.height, toSize: 50)
        movieLockView.stopButton.autoAlignAxis(.horizontal, toSameAxisOf: self)
        movieLockView.stopButton.autoAlignAxis(.vertical, toSameAxisOf: self)
        movieLockView.alpha = 0
        movieLockView.delegate = self
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func beginRecordingAnimation(duration: TimeInterval, delay: TimeInterval = 0) {
        UIView.animate(
            withDuration: duration,
            delay: delay,
            options: [.beginFromCurrentState, .curveLinear],
            animations: {
                self.innerButtonSizeConstraints.forEach { $0.constant = type(of: self).recordingDiameter }
                self.zoomIndicatorSizeConstraints.forEach { $0.constant = type(of: self).recordingDiameter }
                self.superview?.layoutIfNeeded()
        },
            completion: nil
        )
    }

    func endRecordingAnimation(duration: TimeInterval, delay: TimeInterval = 0) {
        UIView.animate(
            withDuration: duration,
            delay: delay,
            options: [.beginFromCurrentState, .curveEaseIn],
            animations: {
                self.innerButtonSizeConstraints.forEach { $0.constant = self.defaultDiameter }
                self.zoomIndicatorSizeConstraints.forEach { $0.constant = self.defaultDiameter }
                self.superview?.layoutIfNeeded()
        },
            completion: nil
        )
    }

    // MARK: - Gestures

    var initialTouchLocation: CGPoint?
    var touchTimer: Timer?
    var isLongPressing = false

    @objc
    func didLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard let gestureView = gesture.view else {
            owsFailDebug("gestureView was unexpectedly nil")
            return
        }

        switch gesture.state {
        case .possible: break
        case .began:
            guard !movieLockView.isLocked else {
                return
            }

            initialTouchLocation = gesture.location(in: gesture.view)
            beginRecordingAnimation(duration: 0.4, delay: 0.1)

            isLongPressing = false

            touchTimer?.invalidate()
            touchTimer = WeakTimer.scheduledTimer(
                timeInterval: longPressDuration,
                target: self,
                userInfo: nil,
                repeats: false
            ) { [weak self] _ in
                guard let `self` = self else { return }
                self.isLongPressing = true

                self.movieLockView.unlock(isAnimated: false)
                UIView.animate(withDuration: 0.2) {
                    self.movieLockView.alpha = 1
                }
                self.delegate?.didBeginLongPressCaptureButton(self)
            }
        case .changed:
            guard isLongPressing else { break }

            guard let referenceHeight = delegate?.zoomScaleReferenceHeight else {
                owsFailDebug("referenceHeight was unexpectedly nil")
                return
            }

            guard referenceHeight > 0 else {
                owsFailDebug("referenceHeight was unexpectedly <= 0")
                return
            }

            guard let initialTouchLocation = initialTouchLocation else {
                owsFailDebug("initialTouchLocation was unexpectedly nil")
                return
            }

            let currentLocation = gesture.location(in: gestureView)

            // Zoom
            let minDistanceBeforeActivatingZoom: CGFloat = 30
            let yDistance = initialTouchLocation.y - currentLocation.y - minDistanceBeforeActivatingZoom
            let distanceForFullZoom = referenceHeight / 4
            let yRatio = yDistance / distanceForFullZoom
            let yAlpha = yRatio.clamp(0, 1)

            let zoomIndicatorDiameter = CGFloatLerp(type(of: self).recordingDiameter, 3, yAlpha)
            self.zoomIndicatorSizeConstraints.forEach { $0.constant = zoomIndicatorDiameter }
            zoomIndicator.superview?.layoutIfNeeded()

            delegate?.longPressCaptureButton(self, didUpdateZoomAlpha: yAlpha)

            // Lock

            guard !movieLockView.isLocked else {
                return
            }
            let xOffset = currentLocation.x - initialTouchLocation.x
            movieLockView.update(xOffset: xOffset)
        case .ended:
            endRecordingAnimation(duration: 0.2)
            touchTimer?.invalidate()
            touchTimer = nil

            guard !movieLockView.isLocked else {
                return
            }

            if isLongPressing {
                UIView.animate(withDuration: 0.2) {
                    self.movieLockView.alpha = 0
                }
                delegate?.didCompleteLongPressCaptureButton(self)
            } else {
                delegate?.didTapCaptureButton(self)
            }
        case .cancelled, .failed:
            endRecordingAnimation(duration: 0.2)

            if isLongPressing {
                self.movieLockView.unlock(isAnimated: true)
                UIView.animate(withDuration: 0.2) {
                    self.movieLockView.alpha = 0
                }
                delegate?.didCancelLongPressCaptureButton(self)
            }

            touchTimer?.invalidate()
            touchTimer = nil
        @unknown default:
            owsFailDebug("unexpected gesture state: \(gesture.state.rawValue)")
        }
    }
}

class CapturePreviewView: UIView {

    let previewLayer: AVCaptureVideoPreviewLayer

    override var bounds: CGRect {
        didSet {
            previewLayer.frame = bounds
        }
    }

    override var contentMode: UIView.ContentMode {
        set {
            switch newValue {
            case .scaleAspectFill:
                previewLayer.videoGravity = .resizeAspectFill
            case .scaleAspectFit:
                previewLayer.videoGravity = .resizeAspect
            case .scaleToFill:
                previewLayer.videoGravity = .resize
            default:
                owsFailDebug("Unexpected contentMode")
            }
        }
        get {
            switch previewLayer.videoGravity {
            case .resizeAspectFill:
                return .scaleAspectFill
            case .resizeAspect:
                return .scaleAspectFit
            case .resize:
                return .scaleToFill
            default:
                owsFailDebug("Unexpected contentMode")
                return .scaleToFill
            }
        }
    }

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        if Platform.isSimulator {
            // helpful for debugging layout on simulator which has no real capture device
            previewLayer.backgroundColor = UIColor.green.withAlphaComponent(0.4).cgColor
        }
        super.init(frame: .zero)
        self.contentMode = .scaleAspectFill
        previewLayer.frame = bounds
        layer.addSublayer(previewLayer)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class RecordingTimerView: UIView {

    let stackViewSpacing: CGFloat = 4

    override init(frame: CGRect) {
        super.init(frame: frame)

        let stackView = UIStackView(arrangedSubviews: [icon, label])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = stackViewSpacing

        addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()

        updateView()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Subviews

    private lazy var label: UILabel = {
        let label = UILabel()
        label.font = UIFont.ows_monospacedDigitFont(withSize: 20)
        label.textAlignment = .center
        label.textColor = UIColor.white
        label.layer.shadowOffset = CGSize.zero
        label.layer.shadowOpacity = 0.35
        label.layer.shadowRadius = 4

        return label
    }()

    static let iconWidth: CGFloat = 6

    private let icon: UIView = {
        let icon = CircleView()
        icon.layer.shadowOffset = CGSize.zero
        icon.layer.shadowOpacity = 0.35
        icon.layer.shadowRadius = 4

        icon.backgroundColor = .red
        icon.autoSetDimensions(to: CGSize(square: iconWidth))
        icon.alpha = 0

        return icon
    }()

    // MARK: -
    var recordingStartTime: TimeInterval?

    func startCounting() {
        recordingStartTime = CACurrentMediaTime()
        timer = Timer.weakScheduledTimer(withTimeInterval: 0.1, target: self, selector: #selector(updateView), userInfo: nil, repeats: true)
        UIView.animate(withDuration: 0.5,
                       delay: 0,
                       options: [.autoreverse, .repeat],
                       animations: { self.icon.alpha = 1 })
    }

    func stopCounting() {
        timer?.invalidate()
        timer = nil
        icon.layer.removeAllAnimations()
        UIView.animate(withDuration: 0.4) {
            self.icon.alpha = 0
        }
        label.text = nil
    }

    // MARK: -

    private var timer: Timer?

    private lazy var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")!

        return formatter
    }()

    // This method should only be called when the call state is "connected".
    var recordingDuration: TimeInterval {
        guard let recordingStartTime = recordingStartTime else {
            return 0
        }

        return CACurrentMediaTime() - recordingStartTime
    }

    @objc
    private func updateView() {
        let recordingDuration = self.recordingDuration
        let durationDate = Date(timeIntervalSinceReferenceDate: recordingDuration)
        label.text = timeFormatter.string(from: durationDate)
    }
}

// MARK: Movie Lock

protocol MovieLockViewDelegate: AnyObject {
    func videoLockViewDidTapStop(_ videoLockView: MovieLockView)
}

@objc
public class MovieLockView: UIView {

    weak var delegate: MovieLockViewDelegate?

    public enum SwipeDirection {
        case trailing
        case leading
    }

    public let swipeDirectionToLock: SwipeDirection

    public init(swipeDirectionToLock: SwipeDirection) {
        self.swipeDirectionToLock = swipeDirectionToLock
        super.init(frame: .zero)

        addSubview(stopButton)
        stopButton.autoVCenterInSuperview()
        stopButton.alpha = 0

        addSubview(highlightView)
        highlightView.autoVCenterInSuperview()
        highlightView.alpha = 0

        addSubview(lockIconView)
        lockIconView.autoVCenterInSuperview()

        let trailingView: UIView
        let leadingView: UIView
        switch swipeDirectionToLock {
        case .trailing:
            trailingView = lockIconView
            leadingView = stopButton
            highlightEdgeConstraint = highlightView.autoPinEdge(toSuperviewEdge: .leading)
        case .leading:
            trailingView = stopButton
            leadingView = lockIconView
            highlightEdgeConstraint = highlightView.autoPinEdge(toSuperviewEdge: .trailing)
        }

        trailingView.centerXAnchor.constraint(equalTo: trailingAnchor,
                                              constant: -highlightViewWidth/2).isActive = true
        leadingView.centerXAnchor.constraint(equalTo: leadingAnchor,
                                             constant: highlightViewWidth/2).isActive = true

    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(xOffset: CGFloat) {
        let effectiveDistance: CGFloat
        let distanceToLock: CGFloat
        let highlightOffset: CGFloat
        switch swipeDirectionToLock {
        case .trailing:
            let minDistanceBeforeActivatingLockSlider: CGFloat = 30
            effectiveDistance = xOffset - minDistanceBeforeActivatingLockSlider
            distanceToLock = frame.width - highlightView.frame.width
            highlightOffset = effectiveDistance.clamp(0, distanceToLock)
        case .leading:
            // On iPad, the gesture already feels right, without applying the additional
            // minDistanceBeforeActivatingLockSlider padding.
            effectiveDistance = xOffset
            distanceToLock = -1 * (frame.width - highlightView.frame.width)
            highlightOffset = effectiveDistance.clamp(distanceToLock, 0)
        }
        highlightEdgeConstraint.constant = highlightOffset

        let alpha = (effectiveDistance/distanceToLock).clamp(0, 1)
        highlightView.alpha = alpha

        if alpha == 1.0 {
            lock(isAnimated: true)
        }
        Logger.verbose("xOffset: \(xOffset), effectiveDistance: \(effectiveDistance),  distanceToLock: \(distanceToLock), highlightOffset: \(highlightOffset), alpha: \(alpha)")
    }

    // MARK: -

    private(set) var isLocked = false

    public func unlock(isAnimated: Bool) {
        Logger.debug("")
        guard isLocked else {
            Logger.debug("ignoring redundant request")
            return
        }
        Logger.debug("unlocking")

        isLocked = false
        let changes = {
            self.lockIconView.tintColor = .white
            self.stopButton.alpha = 0
            self.highlightView.alpha = 0
        }

        if isAnimated {
            UIView.animate(withDuration: 0.2, animations: changes)
        } else {
            changes()
        }
    }

    private func lock(isAnimated: Bool) {
        guard !isLocked else {
            Logger.debug("ignoring redundant request")
            return
        }
        Logger.debug("locking")

        isLocked = true
        let changes = {
            self.lockIconView.tintColor = .black
            self.stopButton.alpha = 1.0
        }

        if isAnimated {
            UIView.animate(withDuration: 0.2, animations: changes)
        } else {
            changes()
        }
    }

    // MARK: - Subviews

    let lockIconWidth: CGFloat = 24
    private lazy var lockIconView: UIImageView = {
        let imageView = UIImageView.withTemplateImage(#imageLiteral(resourceName: "ic_lock_outline"), tintColor: .white)
        imageView.autoSetDimensions(to: CGSize(square: lockIconWidth))
        return imageView
    }()

    let highlightViewWidth = SendMediaNavigationController.bottomButtonWidth
    private var highlightEdgeConstraint: NSLayoutConstraint!
    private lazy var highlightView: UIView = {
        let view = CircleView(diameter: highlightViewWidth)
        view.backgroundColor = .white
        return view
    }()

    let stopButtonWidth: CGFloat = 30
    public lazy var stopButton: UIButton = {
        let view = OWSButton { [weak self] in
            guard let self = self else { return }
            self.delegate?.videoLockViewDidTapStop(self)
        }

        view.backgroundColor = .white
        view.autoSetDimensions(to: CGSize(square: stopButtonWidth))

        return view
    }()
}
