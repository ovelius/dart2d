import 'dart:convert';

import 'package:dart2d/net/state_updates.pb.dart';

enum IceState {
  GATHERING,
  GATHER_COMPLETED,
  RESTARTING,
  RESTARTING_COMPLETED;
}

class Negotiator {

  final String ourId;
  final String otherId;

  Negotiator(this.ourId, this.otherId);

  String? _sdp = null;
  String? _sdpType = null;
  List<String> _iceCandidates = [];

  IceState _iceState = IceState.GATHERING;

  dynamic _onNegotiationComplete;
  dynamic _onIceRestartComplete;
  bool _negotiationCompletedFired = false;

  onNegotiationComplete(dynamic f) {
    _onNegotiationComplete = f;
  }

  onIceRestartCompleted(dynamic f) {
    _onIceRestartComplete = f;
  }

  void onIceCandidate(String? candidate) {
    if (candidate != null) {
      _iceCandidates.add(candidate);
    } else {
      if (_iceState == IceState.GATHERING) {
        _iceState = IceState.GATHER_COMPLETED;
        _checkCompleted();
      }
      if (_iceState == IceState.RESTARTING) {
        _iceState = IceState.RESTARTING_COMPLETED;
        _onIceRestartComplete(candidateProto());
      }
    }
  }

  void restartingIce() {
    _iceState = IceState.RESTARTING;
    _iceCandidates.clear();
  }

  void _checkCompleted() {
    // Don't fire off this event again.
    if (_negotiationCompletedFired) {
      return;
    }
    if (_iceState == IceState.GATHER_COMPLETED && _sdp != null) {
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

  WebRtcDanceProto candidateProto() {
    WebRtcDanceProto dance = WebRtcDanceProto();
    for (String candidate in _iceCandidates) {
      dance.candidates.add(candidate);
    }
    return dance;
  }

  WebRtcDanceProto buildProto() {
    if (_sdp == null) {
      throw "Incomplete offer/answer: SDP unset!";
    }
    WebRtcDanceProto dance = candidateProto()
      ..sdpType = _sdpType!
      ..sdp = _sdp!;
    return dance;
  }
}