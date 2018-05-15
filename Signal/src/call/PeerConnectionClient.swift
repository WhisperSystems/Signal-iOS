//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import WebRTC
import SignalServiceKit
import SignalMessaging

// HACK - Seeing crazy SEGFAULTs on iOS9 when accessing these objc externs.
// iOS10 seems unaffected. Reproducible for ~1 in 3 calls.
// Binding them to a file constant seems to work around the problem.
let kAudioTrackType = kRTCMediaStreamTrackKindAudio
let kVideoTrackType = kRTCMediaStreamTrackKindVideo
let kMediaConstraintsMinWidth = kRTCMediaConstraintsMinWidth
let kMediaConstraintsMaxWidth = kRTCMediaConstraintsMaxWidth
let kMediaConstraintsMinHeight = kRTCMediaConstraintsMinHeight
let kMediaConstraintsMaxHeight = kRTCMediaConstraintsMaxHeight

/**
 * The PeerConnectionClient notifies it's delegate (the CallService) of key events in the call signaling life cycle
 *
 * The delegate's methods will always be called on the main thread.
 */
protocol PeerConnectionClientDelegate: class {

    /**
     * The connection has been established. The clients can now communicate.
     * This can be called multiple times throughout the call in the event of temporary network disconnects.
     */
    func peerConnectionClientIceConnected(_ peerconnectionClient: PeerConnectionClient)

    /**
     * The connection failed to establish. The clients will not be able to communicate.
     */
    func peerConnectionClientIceFailed(_ peerconnectionClient: PeerConnectionClient)

    /**
     * After initially connecting, the connection disconnected.
     * It maybe be temporary, in which case `peerConnectionClientIceConnected` will be called again once we're reconnected.
     * Otherwise, `peerConnectionClientIceFailed` will eventually called.
     */
    func peerConnectionClientIceDisconnected(_ peerconnectionClient: PeerConnectionClient)

    /**
     * During the Signaling process each client generates IceCandidates locally, which contain information about how to 
     * reach the local client via the internet. The delegate must shuttle these IceCandates to the other (remote) client 
     * out of band, as part of establishing a connection over WebRTC.
     */
    func peerConnectionClient(_ peerconnectionClient: PeerConnectionClient, addedLocalIceCandidate iceCandidate: RTCIceCandidate)

    /**
     * Once the peerconnection is established, we can receive messages via the data channel, and notify the delegate.
     */
    func peerConnectionClient(_ peerconnectionClient: PeerConnectionClient, received dataChannelMessage: OWSWebRTCProtosData)

    /**
     * Fired whenever the local video track become active or inactive.
     */
    func peerConnectionClient(_ peerconnectionClient: PeerConnectionClient, didUpdateLocal videoTrack: RTCVideoTrack?)

    /**
     * Fired whenever the remote video track become active or inactive.
     */
    func peerConnectionClient(_ peerconnectionClient: PeerConnectionClient, didUpdateRemote videoTrack: RTCVideoTrack?)
}

class AtomicFlag: NSObject {
    private var flag = false

    override required init() {
        self.flag = false
        super.init()
    }

    public func isSet() -> Bool {
        objc_sync_enter(self)
        let result = flag
        objc_sync_exit(self)
        return result
    }

    public func set() {
        objc_sync_enter(self)
        flag = true
        objc_sync_exit(self)
    }
}

/**
 * `PeerConnectionClient` is our interface to WebRTC.
 *
 * It is primarily a wrapper around `RTCPeerConnection`, which is responsible for sending and receiving our call data 
 * including audio, video, and some post-connected signaling (hangup, add video)
 */
class PeerConnectionClient: NSObject, RTCPeerConnectionDelegate, RTCDataChannelDelegate {

    let TAG = "[PeerConnectionClient]"
    enum Identifiers: String {
        case mediaStream = "ARDAMS",
             videoTrack = "ARDAMSv0",
             audioTrack = "ARDAMSa0",
             dataChannelSignaling = "signaling"
    }

    // A state in this class should only be accessed on this queue in order to
    // serialize access.
    //
    // This queue is also used to perform expensive calls to the WebRTC API.
    private static let signalingQueue = DispatchQueue(label: "CallServiceSignalingQueue")

    // Delegate is notified of key events in the call lifecycle.
    private weak var delegate: PeerConnectionClientDelegate!

    func setDelegate(delegate: PeerConnectionClientDelegate?) {
        PeerConnectionClient.signalingQueue.async { [weak self] in
            guard let strongSelf = self else { return }

            guard !strongSelf.isTerminated.isSet() else {
                return
            }

            strongSelf.delegate = delegate
        }
    }

    // Connection

    private var peerConnection: RTCPeerConnection!
    private let iceServers: [RTCIceServer]
    private let connectionConstraints: RTCMediaConstraints
    private let configuration: RTCConfiguration
    private let factory = RTCPeerConnectionFactory()

    // DataChannel

    private var dataChannel: RTCDataChannel?

    // Audio

    private var audioSender: RTCRtpSender?
    private var audioTrack: RTCAudioTrack?
    private var audioConstraints: RTCMediaConstraints

    // Video

    private var videoCaptureSession: AVCaptureSession?
    private var videoSender: RTCRtpSender?
    private var localVideoTrack: RTCVideoTrack?
    private var localVideoSource: RTCAVFoundationVideoSource?

    // RTCVideoTrack is fragile and prone to throwing exceptions and/or
    // causing deadlock in its destructor.  Therefore we take great care
    // with this property.
    //
    // We synchronize access to this property and ensure that we never
    // set or use a strong reference to the remote video track if 
    // peerConnection is nil.
    private var remoteVideoTrack: RTCVideoTrack?
    private var cameraConstraints: RTCMediaConstraints

    private let isTerminated = AtomicFlag()

    deinit {
        Logger.info("[PeerConnectionClient] deinit")
    }

    init(iceServers: [RTCIceServer], delegate: PeerConnectionClientDelegate, callDirection: CallDirection, useTurnOnly: Bool) {
        SwiftAssertIsOnMainThread(#function)

        self.iceServers = iceServers
        self.delegate = delegate

        configuration = RTCConfiguration()
        configuration.iceServers = iceServers
        configuration.bundlePolicy = .maxBundle
        configuration.rtcpMuxPolicy = .require
        if useTurnOnly {
            Logger.debug("\(TAG) using iceTransportPolicy: relay")
            configuration.iceTransportPolicy = .relay
        } else {
            Logger.debug("\(TAG) using iceTransportPolicy: default")
        }

        let connectionConstraintsDict = ["DtlsSrtpKeyAgreement": "true"]
        connectionConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: connectionConstraintsDict)

        audioConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        cameraConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)

        super.init()

        peerConnection = factory.peerConnection(with: configuration,
                                                constraints: connectionConstraints,
                                                delegate: self)
        createAudioSender()
        createVideoSender()

        if callDirection == .outgoing {
            // When placing an outgoing call, it's our responsibility to create the DataChannel. 
            // Recipient will not have to do this explicitly.
            createSignalingDataChannel()
        }
    }

    // MARK: - Media Streams

    private func createSignalingDataChannel() {
        SwiftAssertIsOnMainThread(#function)

        let configuration = RTCDataChannelConfiguration()
        // Insist upon an "ordered" TCP data channel for delivery reliability.
        configuration.isOrdered = true
        let dataChannel = peerConnection.dataChannel(forLabel: Identifiers.dataChannelSignaling.rawValue,
                                                     configuration: configuration)
        dataChannel.delegate = self

        assert(self.dataChannel == nil)
        self.dataChannel = dataChannel
    }

    // MARK: Video

    fileprivate func createVideoSender() {
        SwiftAssertIsOnMainThread(#function)

        Logger.debug("\(TAG) in \(#function)")
        assert(self.videoSender == nil, "\(#function) should only be called once.")

        guard !Platform.isSimulator else {
            Logger.warn("\(TAG) Refusing to create local video track on simulator which has no capture device.")
            return
        }

        // TODO: We could cap the maximum video size.
        let cameraConstraints = RTCMediaConstraints(mandatoryConstraints: nil,
                                                    optionalConstraints: nil)

        // TODO: Revisit the cameraConstraints.
        let videoSource = factory.avFoundationVideoSource(with: cameraConstraints)
        self.localVideoSource = videoSource

        self.videoCaptureSession = videoSource.captureSession
        videoSource.useBackCamera = false

        let localVideoTrack = factory.videoTrack(with: videoSource, trackId: Identifiers.videoTrack.rawValue)
        self.localVideoTrack = localVideoTrack

        // Disable by default until call is connected.
        // FIXME - do we require mic permissions at this point?
        // if so maybe it would be better to not even add the track until the call is connected
        // instead of creating it and disabling it.
        localVideoTrack.isEnabled = false

        let videoSender = peerConnection.sender(withKind: kVideoTrackType, streamId: Identifiers.mediaStream.rawValue)
        videoSender.track = localVideoTrack
        self.videoSender = videoSender
    }

    public func setCameraSource(useBackCamera: Bool) {
        SwiftAssertIsOnMainThread(#function)

        PeerConnectionClient.signalingQueue.async {
            guard let localVideoSource = self.localVideoSource else {
                owsFail("\(self.logTag) in \(#function) localVideoSource was unexpectedly nil")
                return
            }

            // certain devices, e.g. 16GB iPod touch don't have a back camera
            guard localVideoSource.canUseBackCamera else {
                owsFail("\(self.logTag) in \(#function) canUseBackCamera was unexpectedly false")
                return
            }

            localVideoSource.useBackCamera = useBackCamera
        }
    }

    public func setLocalVideoEnabled(enabled: Bool) {
        SwiftAssertIsOnMainThread(#function)

        // Define completion early to avoid capturing self within a block
        // that uses weak self.
        let completion = { [weak self] in
            guard let strongSelf = self else { return }

            guard let localVideoTrack = strongSelf.localVideoTrack else {
                let action = enabled ? "enable" : "disable"
                Logger.error("\(strongSelf.TAG)) trying to \(action) videoTrack which doesn't exist")
                return
            }

            guard !strongSelf.isTerminated.isSet() else {
                Logger.verbose("\(strongSelf.TAG) aborting \(#function), terminated.")
                return
            }

            if let delegate = strongSelf.delegate {
                delegate.peerConnectionClient(strongSelf, didUpdateLocal: enabled ? localVideoTrack : nil)
            }
        }

        PeerConnectionClient.signalingQueue.async { [weak self] in
            guard let strongSelf = self else { return }

            guard strongSelf.peerConnection != nil else {
                Logger.debug("\(strongSelf.TAG) \(#function) Ignoring obsolete event in terminated client")
                return
            }
            guard let localVideoTrack = strongSelf.localVideoTrack else {
                let action = enabled ? "enable" : "disable"
                Logger.error("\(strongSelf.TAG)) trying to \(action) videoTrack which doesn't exist")
                return
            }
            guard let videoCaptureSession = strongSelf.videoCaptureSession else {
                Logger.debug("\(strongSelf.TAG) videoCaptureSession was unexpectedly nil")
                return
            }

            guard !strongSelf.isTerminated.isSet() else {
                Logger.verbose("\(strongSelf.TAG) aborting \(#function), terminated.")
                return
            }

            localVideoTrack.isEnabled = enabled

            if enabled {
                Logger.debug("\(strongSelf.TAG) in \(#function) starting videoCaptureSession")
                videoCaptureSession.startRunning()
            } else {
                Logger.debug("\(strongSelf.TAG) in \(#function) stopping videoCaptureSession")
                videoCaptureSession.stopRunning()
            }

            guard !strongSelf.isTerminated.isSet() else {
                Logger.verbose("\(strongSelf.TAG) aborting \(#function), terminated.")
                return
            }

            DispatchQueue.main.async(execute: completion)
        }
    }

    // MARK: Audio

    fileprivate func createAudioSender() {
        SwiftAssertIsOnMainThread(#function)

        Logger.debug("\(TAG) in \(#function)")
        assert(self.audioSender == nil, "\(#function) should only be called once.")

        let audioSource = factory.audioSource(with: self.audioConstraints)

        let audioTrack = factory.audioTrack(with: audioSource, trackId: Identifiers.audioTrack.rawValue)
        self.audioTrack = audioTrack

        // Disable by default until call is connected.
        // FIXME - do we require mic permissions at this point?
        // if so maybe it would be better to not even add the track until the call is connected
        // instead of creating it and disabling it.
        audioTrack.isEnabled = false

        let audioSender = peerConnection.sender(withKind: kAudioTrackType, streamId: Identifiers.mediaStream.rawValue)
        audioSender.track = audioTrack
        self.audioSender = audioSender
    }

    public func setAudioEnabled(enabled: Bool) {
        SwiftAssertIsOnMainThread(#function)

        PeerConnectionClient.signalingQueue.async { [weak self] in
            guard let strongSelf = self else { return }

            guard strongSelf.peerConnection != nil else {
                Logger.debug("\(strongSelf.TAG) \(#function) Ignoring obsolete event in terminated client")
                return
            }
            guard let audioTrack = strongSelf.audioTrack else {
                let action = enabled ? "enable" : "disable"
                Logger.error("\(strongSelf.TAG) trying to \(action) audioTrack which doesn't exist.")
                return
            }

            guard !strongSelf.isTerminated.isSet() else {
                Logger.verbose("\(strongSelf.TAG) aborting \(#function), terminated.")
                return
            }

            audioTrack.isEnabled = enabled
        }
    }

    // MARK: - Session negotiation

    private var defaultOfferConstraints: RTCMediaConstraints {
        let mandatoryConstraints = [
            "OfferToReceiveAudio": "true",
            "OfferToReceiveVideo": "true"
        ]
        return RTCMediaConstraints(mandatoryConstraints: mandatoryConstraints, optionalConstraints: nil)
    }

    public func createOffer() -> Promise<HardenedRTCSessionDescription> {
        SwiftAssertIsOnMainThread(#function)

        let completion = { [weak self] (fulfill: (HardenedRTCSessionDescription) -> Swift.Void, reject: (Error) -> Swift.Void, sdp: RTCSessionDescription?, error: Error?) in
            guard let strongSelf = self else { return }

            guard strongSelf.peerConnection != nil else {
                Logger.debug("\(strongSelf.TAG) \(#function) Ignoring obsolete event in terminated client")
                reject(NSError(domain: "Obsolete client", code: 0, userInfo: nil))
                return
            }
            guard error == nil else {
                reject(error!)
                return
            }

            guard let sessionDescription = sdp else {
                Logger.error("\(strongSelf.TAG) No session description was obtained, even though there was no error reported.")
                let error = OWSErrorMakeUnableToProcessServerResponseError()
                reject(error)
                return
            }

            guard !strongSelf.isTerminated.isSet() else {
                Logger.verbose("\(strongSelf.TAG) aborting \(#function), terminated.")
                reject(OWSErrorWithCodeDescription(.callTerminated, "Call terminated."))
                return
            }

            fulfill(HardenedRTCSessionDescription(rtcSessionDescription: sessionDescription))
        }

        return Promise { fulfill, reject in
            SwiftAssertIsOnMainThread(#function)

            PeerConnectionClient.signalingQueue.async { [weak self] in
                guard let strongSelf = self else { return }

                guard strongSelf.peerConnection != nil else {
                    Logger.debug("\(strongSelf.TAG) \(#function) Ignoring obsolete event in terminated client")
                    reject(NSError(domain: "Obsolete client", code: 0, userInfo: nil))
                    return
                }

                guard !strongSelf.isTerminated.isSet() else {
                    Logger.verbose("\(strongSelf.TAG) aborting \(#function), terminated.")
                    reject(OWSErrorWithCodeDescription(.callTerminated, "Call terminated."))
                    return
                }

                strongSelf.peerConnection.offer(for: strongSelf.defaultOfferConstraints, completionHandler: { (sdp: RTCSessionDescription?, error: Error?) in
                    PeerConnectionClient.signalingQueue.async {
                        completion(fulfill, reject, sdp, error)
                    }
                })
            }
        }
    }

    public func setLocalSessionDescriptionInternal(_ sessionDescription: HardenedRTCSessionDescription) -> Promise<Void> {
        return PromiseKit.wrap { resolve in
            self.assertOnSignalingQueue()
            Logger.verbose("\(self.TAG) setting local session description: \(sessionDescription)")
            self.peerConnection.setLocalDescription(sessionDescription.rtcSessionDescription, completionHandler: resolve)
        }
    }

    public func setLocalSessionDescription(_ sessionDescription: HardenedRTCSessionDescription) -> Promise<Void> {
        SwiftAssertIsOnMainThread(#function)

        return Promise { fulfill, reject in
            PeerConnectionClient.signalingQueue.async { [weak self] in
                guard let strongSelf = self else { return }

                guard strongSelf.peerConnection != nil else {
                    Logger.debug("\(strongSelf.TAG) \(#function) Ignoring obsolete event in terminated client")
                    reject(NSError(domain: "Obsolete client", code: 0, userInfo: nil))
                    return
                }

                guard !strongSelf.isTerminated.isSet() else {
                    Logger.verbose("\(strongSelf.TAG) aborting \(#function), terminated.")
                    reject(OWSErrorWithCodeDescription(.callTerminated, "Call terminated."))
                    return
                }

                Logger.verbose("\(strongSelf.TAG) setting local session description: \(sessionDescription)")
                strongSelf.peerConnection.setLocalDescription(sessionDescription.rtcSessionDescription,
                                                        completionHandler: { error in
                                                            guard error == nil else {
                                                                reject(error!)
                                                                return
                                                            }
                                                            fulfill()
                })
            }
        }
    }

    public func negotiateSessionDescription(remoteDescription: RTCSessionDescription, constraints: RTCMediaConstraints) -> Promise<HardenedRTCSessionDescription> {
        SwiftAssertIsOnMainThread(#function)

        return setRemoteSessionDescription(remoteDescription)
            .then(on: PeerConnectionClient.signalingQueue) {
                return self.negotiateAnswerSessionDescription(constraints: constraints)
        }
    }

    public func setRemoteSessionDescription(_ sessionDescription: RTCSessionDescription) -> Promise<Void> {
        SwiftAssertIsOnMainThread(#function)

        return Promise { fulfill, reject in
            PeerConnectionClient.signalingQueue.async { [weak self] in
                guard let strongSelf = self else { return }

                guard strongSelf.peerConnection != nil else {
                    Logger.debug("\(strongSelf.TAG) \(#function) Ignoring obsolete event in terminated client")
                    reject(NSError(domain: "Obsolete client", code: 0, userInfo: nil))
                    return
                }

                guard !strongSelf.isTerminated.isSet() else {
                    Logger.verbose("\(strongSelf.TAG) aborting \(#function), terminated.")
                    reject(OWSErrorWithCodeDescription(.callTerminated, "Call terminated."))
                    return
                }

                Logger.verbose("\(strongSelf.TAG) setting remote description: \(sessionDescription)")
                strongSelf.peerConnection.setRemoteDescription(sessionDescription,
                                                         completionHandler: { error in
                                                            guard error == nil else {
                                                                reject(error!)
                                                                return
                                                            }
                                                            fulfill()
                })
            }
        }
    }

    private func negotiateAnswerSessionDescription(constraints: RTCMediaConstraints) -> Promise<HardenedRTCSessionDescription> {
        assertOnSignalingQueue()

        return Promise { fulfill, reject in
            assertOnSignalingQueue()

            guard self.peerConnection != nil else {
                Logger.debug("\(self.TAG) \(#function) Ignoring obsolete event in terminated client")
                reject(NSError(domain: "Obsolete client", code: 0, userInfo: nil))
                return
            }

            Logger.debug("\(self.TAG) negotiating answer session.")

            peerConnection.answer(for: constraints, completionHandler: { (sdp: RTCSessionDescription?, error: Error?) in
                PeerConnectionClient.signalingQueue.async { [weak self] in
                    guard let strongSelf = self else { return }

                    guard strongSelf.peerConnection != nil else {
                        Logger.debug("\(strongSelf.TAG) \(#function) Ignoring obsolete event in terminated client")
                        reject(NSError(domain: "Obsolete client", code: 0, userInfo: nil))
                        return
                    }
                    guard error == nil else {
                        reject(error!)
                        return
                    }

                    guard let sessionDescription = sdp else {
                        Logger.error("\(strongSelf.TAG) unexpected empty session description, even though no error was reported.")
                        let error = OWSErrorMakeUnableToProcessServerResponseError()
                        reject(error)
                        return
                    }

                    guard !strongSelf.isTerminated.isSet() else {
                        Logger.verbose("\(strongSelf.TAG) aborting \(#function), terminated.")
                        reject(OWSErrorWithCodeDescription(.callTerminated, "Call terminated."))
                        return
                    }

                    let hardenedSessionDescription = HardenedRTCSessionDescription(rtcSessionDescription: sessionDescription)

                    strongSelf.setLocalSessionDescriptionInternal(hardenedSessionDescription)
                        .then(on: PeerConnectionClient.signalingQueue) {
                            fulfill(hardenedSessionDescription)
                        }.catch { error in
                            reject(error)
                    }
                }
            })
        }
    }

    public func addRemoteIceCandidate(_ candidate: RTCIceCandidate) {
        PeerConnectionClient.signalingQueue.async { [weak self] in
            guard let strongSelf = self else { return }

            guard strongSelf.peerConnection != nil else {
                Logger.debug("\(strongSelf.TAG) \(#function) Ignoring obsolete event in terminated client")
                return
            }

            guard !strongSelf.isTerminated.isSet() else {
                Logger.verbose("\(strongSelf.TAG) aborting \(#function), terminated.")
                return
            }

            Logger.info("\(strongSelf.TAG) adding remote ICE candidate: \(candidate.sdp)")
            strongSelf.peerConnection.add(candidate)
        }
    }

    public func terminate() {
        SwiftAssertIsOnMainThread(#function)
        Logger.debug("\(TAG) in \(#function)")

        // Any other work already enqueued on the signaling queue
        // (and some work enqueued on the main queue)
        // should abort once this flag is set.
        isTerminated.set()

        PeerConnectionClient.signalingQueue.async { [weak self] in
            guard let strongSelf = self else { return }

            strongSelf.terminateInternal()
        }
    }

    private func terminateInternal() {
        assertOnSignalingQueue()

        Logger.debug("\(TAG) in \(#function)")

        //        Some notes on preventing crashes while disposing of peerConnection for video calls
        //        from: https://groups.google.com/forum/#!searchin/discuss-webrtc/objc$20crash$20dealloc%7Csort:relevance/discuss-webrtc/7D-vk5yLjn8/rBW2D6EW4GYJ
        //        The sequence to make it work appears to be
        //
        //        [capturer stop]; // I had to add this as a method to RTCVideoCapturer
        //        [localRenderer stop];
        //        [remoteRenderer stop];
        //        [peerConnection close];

        // audioTrack is a strong property because we need access to it to mute/unmute, but I was seeing it
        // become nil when it was only a weak property. So we retain it and manually nil the reference here, because
        // we are likely to crash if we retain any peer connection properties when the peerconnection is released

        // See the comments on the remoteVideoTrack property.
        objc_sync_enter(self)
        localVideoTrack?.isEnabled = false
        remoteVideoTrack?.isEnabled = false

        dataChannel?.delegate = self
        dataChannel = nil
        audioSender = nil
        audioTrack = nil
        videoSender = nil
        localVideoSource = nil
        localVideoTrack = nil
        remoteVideoTrack = nil

        peerConnection.delegate = nil
        peerConnection.close()
        peerConnection = nil
        objc_sync_exit(self)

        delegate = nil
    }

    // MARK: - Data Channel

    // should only be accessed on PeerConnectionClient.signalingQueue
    var pendingDataChannelMessages: [PendingDataChannelMessage] = []
    struct PendingDataChannelMessage {
        let data: Data
        let description: String
        let isCritical: Bool
    }

    public func sendDataChannelMessage(data: Data, description: String, isCritical: Bool) {
        SwiftAssertIsOnMainThread(#function)

        PeerConnectionClient.signalingQueue.async { [weak self] in
            guard let strongSelf = self else { return }

            guard strongSelf.peerConnection != nil else {
                Logger.debug("\(strongSelf.TAG) \(#function) Ignoring obsolete event in terminated client: \(description)")
                return
            }

            guard let dataChannel = strongSelf.dataChannel else {
                if isCritical {
                    Logger.info("\(strongSelf.TAG) in \(#function) enqueuing critical data channel message for after we have a dataChannel: \(description)")
                    strongSelf.pendingDataChannelMessages.append(PendingDataChannelMessage(data: data, description: description, isCritical: isCritical))
                } else {
                    Logger.error("\(strongSelf.TAG) in \(#function) ignoring sending \(data) for nil dataChannel: \(description)")
                }
                return
            }

            guard !strongSelf.isTerminated.isSet() else {
                Logger.verbose("\(strongSelf.TAG) aborting \(#function), terminated.")
                return
            }

            Logger.debug("\(strongSelf.TAG) sendDataChannelMessage trying: \(description)")

            let buffer = RTCDataBuffer(data: data, isBinary: false)
            let result = dataChannel.sendData(buffer)

            if result {
                Logger.debug("\(strongSelf.TAG) sendDataChannelMessage succeeded: \(description)")
            } else {
                Logger.warn("\(strongSelf.TAG) sendDataChannelMessage failed: \(description)")
                if isCritical {
                    OWSProdError(OWSAnalyticsEvents.peerConnectionClientErrorSendDataChannelMessageFailed(), file: #file, function: #function, line: #line)
                }
            }
        }
    }

    // MARK: RTCDataChannelDelegate

    /** The data channel state changed. */
    internal func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        Logger.debug("\(TAG) dataChannelDidChangeState: \(dataChannel)")
    }

    /** The data channel successfully received a data buffer. */
    internal func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {

        let completion = { [weak self] (dataChannelMessage: OWSWebRTCProtosData) in
            guard let strongSelf = self else { return }

            guard !strongSelf.isTerminated.isSet() else {
                Logger.verbose("\(strongSelf.TAG) aborting \(#function), terminated.")
                return
            }

            if let delegate = strongSelf.delegate {
                delegate.peerConnectionClient(strongSelf, received: dataChannelMessage)
            }
        }

        PeerConnectionClient.signalingQueue.async { [weak self] in
            guard let strongSelf = self else { return }

            guard strongSelf.peerConnection != nil else {
                Logger.debug("\(strongSelf.TAG) \(#function) Ignoring obsolete event in terminated client")
                return
            }

            guard !strongSelf.isTerminated.isSet() else {
                Logger.verbose("\(strongSelf.TAG) aborting \(#function), terminated.")
                return
            }

            Logger.debug("\(strongSelf.TAG) dataChannel didReceiveMessageWith buffer:\(buffer)")

            guard let dataChannelMessage = OWSWebRTCProtosData.parse(from: buffer.data) else {
                // TODO can't proto parsings throw an exception? Is it just being lost in the Objc->Swift?
                Logger.error("\(strongSelf.TAG) failed to parse dataProto")
                return
            }

            DispatchQueue.main.async {
                completion(dataChannelMessage)
            }
        }
    }

    /** The data channel's |bufferedAmount| changed. */
    internal func dataChannel(_ dataChannel: RTCDataChannel, didChangeBufferedAmount amount: UInt64) {
        Logger.debug("\(TAG) didChangeBufferedAmount: \(amount)")
    }

    // MARK: - RTCPeerConnectionDelegate

    /** Called when the SignalingState changed. */
    internal func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        Logger.debug("\(TAG) didChange signalingState:\(stateChanged.debugDescription)")
    }

    /** Called when media is received on a new stream from remote peer. */
    internal func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        guard stream.videoTracks.count > 0 else {
            return
        }
        let remoteVideoTrack = stream.videoTracks[0]
        Logger.debug("\(self.TAG) didAdd stream:\(stream) video tracks: \(stream.videoTracks.count) audio tracks: \(stream.audioTracks.count)")

        // See the comments on the remoteVideoTrack property.
        //
        // We only set the remoteVideoTrack property if peerConnection is non-nil.
        objc_sync_enter(self)
        if self.peerConnection != nil {
            self.remoteVideoTrack = remoteVideoTrack
        }
        objc_sync_exit(self)

        let completion = { [weak self] in
            guard let strongSelf = self else { return }

            guard !strongSelf.isTerminated.isSet() else {
                Logger.verbose("\(strongSelf.TAG) aborting \(#function), terminated.")
                return
            }

            if let delegate = strongSelf.delegate {
                // See the comments on the remoteVideoTrack property.
                //
                // We only access the remoteVideoTrack property if peerConnection is non-nil.
                var remoteVideoTrack: RTCVideoTrack?
                objc_sync_enter(strongSelf)
                if strongSelf.peerConnection != nil {
                    remoteVideoTrack = strongSelf.remoteVideoTrack
                }
                objc_sync_exit(strongSelf)

                delegate.peerConnectionClient(strongSelf, didUpdateRemote: remoteVideoTrack)
            }
        }

        PeerConnectionClient.signalingQueue.async { [weak self] in
            guard let strongSelf = self else { return }

            guard strongSelf.peerConnection != nil else {
                Logger.debug("\(strongSelf.TAG) \(#function) Ignoring obsolete event in terminated client")
                return
            }

            guard !strongSelf.isTerminated.isSet() else {
                Logger.verbose("\(strongSelf.TAG) aborting \(#function), terminated.")
                return
            }

            DispatchQueue.main.async {
                completion()
            }
        }
    }

    /** Called when a remote peer closes a stream. */
    internal func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        Logger.debug("\(TAG) didRemove Stream:\(stream)")
    }

    /** Called when negotiation is needed, for example ICE has restarted. */
    internal func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        Logger.debug("\(TAG) shouldNegotiate")
    }

    /** Called any time the IceConnectionState changes. */
    internal func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {

        let connectionCompletion = { [weak self] in
            guard let strongSelf = self else { return }

            guard !strongSelf.isTerminated.isSet() else {
                Logger.verbose("\(strongSelf.TAG) aborting \(#function), terminated.")
                return
            }

            if let delegate = strongSelf.delegate {
            delegate.peerConnectionClientIceConnected(strongSelf)
            }
        }

        let failedCompletion = { [weak self] in
            guard let strongSelf = self else { return }

            guard !strongSelf.isTerminated.isSet() else {
                Logger.verbose("\(strongSelf.TAG) aborting \(#function), terminated.")
                return
            }

            if let delegate = strongSelf.delegate {
                delegate.peerConnectionClientIceFailed(strongSelf)
            }
        }

        let disconnectedCompletion = { [weak self] in
            guard let strongSelf = self else { return }

            guard !strongSelf.isTerminated.isSet() else {
                Logger.verbose("\(strongSelf.TAG) aborting \(#function), terminated.")
                return
            }

            if let delegate = strongSelf.delegate {
                delegate.peerConnectionClientIceDisconnected(strongSelf)
            }
        }

        PeerConnectionClient.signalingQueue.async { [weak self] in
            guard let strongSelf = self else { return }

            guard !strongSelf.isTerminated.isSet() else {
                Logger.verbose("\(strongSelf.TAG) aborting \(#function), terminated.")
                return
            }

            guard strongSelf.peerConnection != nil else {
                Logger.debug("\(strongSelf.TAG) \(#function) Ignoring obsolete event in terminated client")
                return
            }
            Logger.info("\(strongSelf.TAG) didChange IceConnectionState:\(newState.debugDescription)")
            switch newState {
            case .connected, .completed:
                DispatchQueue.main.async(execute: connectionCompletion)
            case .failed:
                Logger.warn("\(strongSelf.TAG) RTCIceConnection failed.")
                DispatchQueue.main.async(execute: failedCompletion)
            case .disconnected:
                Logger.warn("\(strongSelf.TAG) RTCIceConnection disconnected.")
                DispatchQueue.main.async(execute: disconnectedCompletion)
            default:
                Logger.debug("\(strongSelf.TAG) ignoring change IceConnectionState:\(newState.debugDescription)")
            }
        }
    }

    /** Called any time the IceGatheringState changes. */
    internal func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        Logger.info("\(TAG) didChange IceGatheringState:\(newState.debugDescription)")
    }

    /** New ice candidate has been found. */
    internal func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {

        let completion = { [weak self] in
            guard let strongSelf = self else { return }

            guard !strongSelf.isTerminated.isSet() else {
                Logger.verbose("\(strongSelf.TAG) aborting \(#function), terminated.")
                return
            }

            if let delegate = strongSelf.delegate {
                delegate.peerConnectionClient(strongSelf, addedLocalIceCandidate: candidate)
            }
        }

        PeerConnectionClient.signalingQueue.async { [weak self] in
            guard let strongSelf = self else { return }

            guard !strongSelf.isTerminated.isSet() else {
                Logger.verbose("\(strongSelf.TAG) aborting \(#function), terminated.")
                return
            }

            guard strongSelf.peerConnection != nil else {
                Logger.debug("\(strongSelf.TAG) \(#function) Ignoring obsolete event in terminated client")
                return
            }
            Logger.info("\(strongSelf.TAG) adding local ICE candidate:\(candidate.sdp)")
            DispatchQueue.main.async(execute: completion)
        }
    }

    /** Called when a group of local Ice candidates have been removed. */
    internal func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        Logger.debug("\(TAG) didRemove IceCandidates:\(candidates)")
    }

    /** New data channel has been opened. */
    internal func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {

        let completion = { [weak self] (pendingMessages: [PendingDataChannelMessage]) in
            guard let strongSelf = self else { return }

            guard !strongSelf.isTerminated.isSet() else {
                Logger.verbose("\(strongSelf.TAG) aborting \(#function), terminated.")
                return
            }

            pendingMessages.forEach { message in
                strongSelf.sendDataChannelMessage(data: message.data, description: message.description, isCritical: message.isCritical)
            }
        }

        PeerConnectionClient.signalingQueue.async { [weak self] in
            guard let strongSelf = self else { return }

            guard strongSelf.peerConnection != nil else {
                Logger.debug("\(strongSelf.TAG) \(#function) Ignoring obsolete event in terminated client")
                return
            }

            guard !strongSelf.isTerminated.isSet() else {
                Logger.verbose("\(strongSelf.TAG) aborting \(#function), terminated.")
                return
            }

            Logger.info("\(strongSelf.TAG) didOpen dataChannel:\(dataChannel)")
            assert(strongSelf.dataChannel == nil)
            strongSelf.dataChannel = dataChannel
            dataChannel.delegate = strongSelf

            let pendingMessages = strongSelf.pendingDataChannelMessages
            strongSelf.pendingDataChannelMessages = []
            DispatchQueue.main.async {
                completion(pendingMessages)
            }
        }
    }

    // MARK: Helpers

    /**
     * We synchronize access to state in this class using this queue.
     */
    private func assertOnSignalingQueue() {
        assertOnQueue(type(of: self).signalingQueue)
    }

    // MARK: Test-only accessors

    internal func peerConnectionForTests() -> RTCPeerConnection {
        SwiftAssertIsOnMainThread(#function)

        var result: RTCPeerConnection? = nil
        PeerConnectionClient.signalingQueue.sync {
            result = peerConnection
            Logger.info("\(self.TAG) called \(#function)")
        }
        return result!
    }

    internal func dataChannelForTests() -> RTCDataChannel {
        SwiftAssertIsOnMainThread(#function)

        var result: RTCDataChannel? = nil
        PeerConnectionClient.signalingQueue.sync {
            result = dataChannel
            Logger.info("\(self.TAG) called \(#function)")
        }
        return result!
    }

    internal func flushSignalingQueueForTests() {
        SwiftAssertIsOnMainThread(#function)

        PeerConnectionClient.signalingQueue.sync {
            // Noop.
        }
    }
}

/**
 * Restrict an RTCSessionDescription to more secure parameters
 */
class HardenedRTCSessionDescription {
    let rtcSessionDescription: RTCSessionDescription
    var sdp: String { return rtcSessionDescription.sdp }

    init(rtcSessionDescription: RTCSessionDescription) {
        self.rtcSessionDescription = HardenedRTCSessionDescription.harden(rtcSessionDescription: rtcSessionDescription)
    }

    /**
     * Set some more secure parameters for the session description
     */
    class func harden(rtcSessionDescription: RTCSessionDescription) -> RTCSessionDescription {
        var description = rtcSessionDescription.sdp

        // Enforce Constant bit rate.
        let cbrRegex = try! NSRegularExpression(pattern: "(a=fmtp:111 ((?!cbr=).)*)\r?\n", options: .caseInsensitive)
        description = cbrRegex.stringByReplacingMatches(in: description, options: [], range: NSRange(location: 0, length: description.count), withTemplate: "$1;cbr=1\r\n")

        // Strip plaintext audio-level details
        // https://tools.ietf.org/html/rfc6464
        let audioLevelRegex = try! NSRegularExpression(pattern: ".+urn:ietf:params:rtp-hdrext:ssrc-audio-level.*\r?\n", options: .caseInsensitive)
        description = audioLevelRegex.stringByReplacingMatches(in: description, options: [], range: NSRange(location: 0, length: description.count), withTemplate: "")

        return RTCSessionDescription.init(type: rtcSessionDescription.type, sdp: description)
    }
}

// Mark: Pretty Print Objc enums.

fileprivate extension RTCSignalingState {
    var debugDescription: String {
        switch self {
        case .stable:
            return "stable"
        case .haveLocalOffer:
            return "haveLocalOffer"
        case .haveLocalPrAnswer:
            return "haveLocalPrAnswer"
        case .haveRemoteOffer:
            return "haveRemoteOffer"
        case .haveRemotePrAnswer:
            return "haveRemotePrAnswer"
        case .closed:
            return "closed"
        }
    }
}

fileprivate extension RTCIceGatheringState {
    var debugDescription: String {
        switch self {
        case .new:
            return "new"
        case .gathering:
            return "gathering"
        case .complete:
            return "complete"
        }
    }
}

fileprivate extension RTCIceConnectionState {
    var debugDescription: String {
        switch self {
        case .new:
            return "new"
        case .checking:
            return "checking"
        case .connected:
            return "connected"
        case .completed:
            return "completed"
        case .failed:
            return "failed"
        case .disconnected:
            return "disconnected"
        case .closed:
            return "closed"
        case .count:
            return "count"
        }
    }
}
