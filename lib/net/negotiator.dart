import 'dart:convert';

import 'package:dart2d/net/state_updates.pb.dart';

class Negotiator {

  final String ourId;
  final String otherId;

  Negotiator(this.ourId, this.otherId);

  String? _sdp = null;
  String? _sdpType = null;
  List<String> _iceCandidates = [];
  bool _iceCompleted = false;

  dynamic _onNegotiationComplete;
  bool _negotiationCompletedFired = false;

  onNegotiationComplete(dynamic f) {
    _onNegotiationComplete = f;
  }

  void onIceCandidate(String? candidate) {
    if (candidate != null) {
      _iceCandidates.add(candidate);
    } else {
      _iceCompleted = true;
      _checkCompleted();
    }
  }

  void restartingIce() {
    _iceCompleted = false;
    _negotiationCompletedFired = false;
    _iceCandidates.clear();
  }

  void _checkCompleted() {
    // Don't fire off this event again.
    if (_negotiationCompletedFired) {
      return;
    }
    if (_iceCompleted && _sdp != null) {
      _onNegotiationComplete(buildProto());
      _negotiationCompletedFired = true;
    }
  }

  void sdpReceived(String sdp, String sdpType) {
    _sdp = sdp;
    _sdpType = sdpType;
    _checkCompleted();
  }

  fromProto(WebRtcDanceProto proto) {
    _sdp = proto.sdp;
    _sdpType = proto.sdpType;
    for (String candidate in proto.candidates) {
      _iceCandidates.add(candidate);
    }
  }

  WebRtcDanceProto buildProto() {
    if (!_iceCompleted || _sdp == null) {
      throw "Incomplete offer/answer!";
    }
    WebRtcDanceProto dance = WebRtcDanceProto()
      ..sdpType = _sdpType!
      ..sdp = _sdp!;
    for (String candidate in _iceCandidates) {
      dance.candidates.add(candidate);
    }
    return dance;
  }
}