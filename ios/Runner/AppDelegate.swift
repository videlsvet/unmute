import Flutter
import UIKit
import AVFoundation
import MediaPlayer

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var nowPlayingChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    setupAudioSession()
    setupRemoteCommandCenter()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "UnmuteNowPlaying") {
      setupMethodChannel(messenger: registrar.messenger())
    }
  }

  private func setupAudioSession() {
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      print("AVAudioSession error: \(error)")
    }
  }

  private func setupMethodChannel(messenger: FlutterBinaryMessenger) {
    nowPlayingChannel = FlutterMethodChannel(name: "unmute/now_playing", binaryMessenger: messenger)
    nowPlayingChannel?.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      if call.method == "updateNowPlaying" {
        if let args = call.arguments as? [String: Any] {
          self?.updateNowPlayingInfo(args: args)
          result(true)
        } else {
          result(false)
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func updateNowPlayingInfo(args: [String: Any]) {
    var info = [String: Any]()
    info[MPMediaItemPropertyTitle] = args["title"] as? String ?? ""
    info[MPMediaItemPropertyArtist] = args["artist"] as? String ?? ""
    info[MPMediaItemPropertyAlbumTitle] = args["album"] as? String ?? ""

    let duration = (args["duration"] as? Double) ?? 0.0
    let position = (args["position"] as? Double) ?? 0.0
    let isPlaying = (args["isPlaying"] as? Bool) ?? false

    info[MPMediaItemPropertyPlaybackDuration] = duration
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
    info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

    if let artworkUrlString = args["artworkUrl"] as? String,
       let artworkUrl = URL(string: artworkUrlString),
       !artworkUrlString.isEmpty {
      DispatchQueue.global(qos: .utility).async {
        if let data = try? Data(contentsOf: artworkUrl),
           let image = UIImage(data: data) {
          DispatchQueue.main.async {
            var currentInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            let artwork = MPMediaItemArtwork(boundsSize: image.size, requestHandler: { _ in image })
            currentInfo[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = currentInfo
          }
        }
      }
    }

    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }

  private func setupRemoteCommandCenter() {
    let center = MPRemoteCommandCenter.shared()

    center.playCommand.isEnabled = true
    _ = center.playCommand.addTarget(handler: { [weak self] _ in
      self?.nowPlayingChannel?.invokeMethod("play", arguments: nil)
      return MPRemoteCommandHandlerStatus.success
    })

    center.pauseCommand.isEnabled = true
    _ = center.pauseCommand.addTarget(handler: { [weak self] _ in
      self?.nowPlayingChannel?.invokeMethod("pause", arguments: nil)
      return MPRemoteCommandHandlerStatus.success
    })

    center.togglePlayPauseCommand.isEnabled = true
    _ = center.togglePlayPauseCommand.addTarget(handler: { [weak self] _ in
      self?.nowPlayingChannel?.invokeMethod("togglePlayPause", arguments: nil)
      return MPRemoteCommandHandlerStatus.success
    })

    center.nextTrackCommand.isEnabled = true
    _ = center.nextTrackCommand.addTarget(handler: { [weak self] _ in
      self?.nowPlayingChannel?.invokeMethod("next", arguments: nil)
      return MPRemoteCommandHandlerStatus.success
    })

    center.previousTrackCommand.isEnabled = true
    _ = center.previousTrackCommand.addTarget(handler: { [weak self] _ in
      self?.nowPlayingChannel?.invokeMethod("previous", arguments: nil)
      return MPRemoteCommandHandlerStatus.success
    })

    center.changePlaybackPositionCommand.isEnabled = true
    _ = center.changePlaybackPositionCommand.addTarget(handler: { [weak self] (event: MPRemoteCommandEvent) in
      if let posEvent = event as? MPChangePlaybackPositionCommandEvent {
        self?.nowPlayingChannel?.invokeMethod("seek", arguments: ["position": posEvent.positionTime])
        return MPRemoteCommandHandlerStatus.success
      }
      return MPRemoteCommandHandlerStatus.commandFailed
    })
  }
}
