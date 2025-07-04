//
//  Generated code. Do not modify.
//  source: dart2d/lib/net/state_updates.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'state_updates.pbenum.dart';

export 'state_updates.pbenum.dart';

/// Message sent over a connection.
class GameStateUpdates extends $pb.GeneratedMessage {
  factory GameStateUpdates({
    $core.int? frame,
    $core.int? lastFrameSeen,
    $core.int? keyFrame,
    $core.Iterable<StateUpdate>? stateUpdate,
    $core.Iterable<SpriteUpdate>? spriteUpdates,
  }) {
    final $result = create();
    if (frame != null) {
      $result.frame = frame;
    }
    if (lastFrameSeen != null) {
      $result.lastFrameSeen = lastFrameSeen;
    }
    if (keyFrame != null) {
      $result.keyFrame = keyFrame;
    }
    if (stateUpdate != null) {
      $result.stateUpdate.addAll(stateUpdate);
    }
    if (spriteUpdates != null) {
      $result.spriteUpdates.addAll(spriteUpdates);
    }
    return $result;
  }
  GameStateUpdates._() : super();
  factory GameStateUpdates.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GameStateUpdates.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GameStateUpdates', package: const $pb.PackageName(_omitMessageNames ? '' : 'dart2d_proto'), createEmptyInstance: create)
    ..a<$core.int>(1, _omitFieldNames ? '' : 'frame', $pb.PbFieldType.O3)
    ..a<$core.int>(2, _omitFieldNames ? '' : 'lastFrameSeen', $pb.PbFieldType.O3)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'keyFrame', $pb.PbFieldType.O3)
    ..pc<StateUpdate>(4, _omitFieldNames ? '' : 'stateUpdate', $pb.PbFieldType.PM, subBuilder: StateUpdate.create)
    ..pc<SpriteUpdate>(5, _omitFieldNames ? '' : 'spriteUpdates', $pb.PbFieldType.PM, subBuilder: SpriteUpdate.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GameStateUpdates clone() => GameStateUpdates()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GameStateUpdates copyWith(void Function(GameStateUpdates) updates) => super.copyWith((message) => updates(message as GameStateUpdates)) as GameStateUpdates;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GameStateUpdates create() => GameStateUpdates._();
  GameStateUpdates createEmptyInstance() => create();
  static $pb.PbList<GameStateUpdates> createRepeated() => $pb.PbList<GameStateUpdates>();
  @$core.pragma('dart2js:noInline')
  static GameStateUpdates getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GameStateUpdates>(create);
  static GameStateUpdates? _defaultInstance;

  /// Game frame generating this update.
  @$pb.TagNumber(1)
  $core.int get frame => $_getIZ(0);
  @$pb.TagNumber(1)
  set frame($core.int v) { $_setSignedInt32(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasFrame() => $_has(0);
  @$pb.TagNumber(1)
  void clearFrame() => clearField(1);

  /// Us telling remote side the last frame we know about.
  @$pb.TagNumber(2)
  $core.int get lastFrameSeen => $_getIZ(1);
  @$pb.TagNumber(2)
  set lastFrameSeen($core.int v) { $_setSignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasLastFrameSeen() => $_has(1);
  @$pb.TagNumber(2)
  void clearLastFrameSeen() => clearField(2);

  /// This is a keyframe, considered a full gamestate update.
  @$pb.TagNumber(3)
  $core.int get keyFrame => $_getIZ(2);
  @$pb.TagNumber(3)
  set keyFrame($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasKeyFrame() => $_has(2);
  @$pb.TagNumber(3)
  void clearKeyFrame() => clearField(3);

  /// List of updates.
  @$pb.TagNumber(4)
  $core.List<StateUpdate> get stateUpdate => $_getList(3);

  /// Sprite updates...
  @$pb.TagNumber(5)
  $core.List<SpriteUpdate> get spriteUpdates => $_getList(4);
}

enum StateUpdate_Update {
  userMessage, 
  spriteRemoval, 
  gameState, 
  keyState, 
  clientPlayerSpec, 
  commanderGameReply, 
  clientEnter, 
  ackedDataReceipts, 
  ping, 
  pong, 
  otherPlayerWorldSelect, 
  transferCommand, 
  byteWorldDestruction, 
  byteWorldDraw, 
  particleEffects, 
  clientStatusData, 
  resourceRequest, 
  resourceResponse, 
  commanderMapSelected, 
  playSound, 
  negotiation, 
  commanderSwitchFromClosedConnection, 
  suggestSelfCommander, 
  notSet
}

class StateUpdate extends $pb.GeneratedMessage {
  factory StateUpdate({
    $core.int? dataReceipt,
    $core.String? userMessage,
    $core.int? spriteRemoval,
    GameStateProto? gameState,
    KeyStateProto? keyState,
    ClientPlayerSpec? clientPlayerSpec,
    CommanderGameReply? commanderGameReply,
    $core.bool? clientEnter,
    $core.int? ackedDataReceipts,
    $fixnum.Int64? ping,
    $fixnum.Int64? pong,
    OtherPlayerWorldSelect? otherPlayerWorldSelect,
    $core.bool? transferCommand,
    ByteWorldDestruction? byteWorldDestruction,
    ByteWorldDraw? byteWorldDraw,
    ParticleEffects? particleEffects,
    ClientStatusData? clientStatusData,
    ResourceRequest? resourceRequest,
    ResourceResponse? resourceResponse,
    $core.String? commanderMapSelected,
    PlaySound? playSound,
    WebRtcNegotiationProto? negotiation,
    $core.String? commanderSwitchFromClosedConnection,
    ClientStatusData? suggestSelfCommander,
  }) {
    final $result = create();
    if (dataReceipt != null) {
      $result.dataReceipt = dataReceipt;
    }
    if (userMessage != null) {
      $result.userMessage = userMessage;
    }
    if (spriteRemoval != null) {
      $result.spriteRemoval = spriteRemoval;
    }
    if (gameState != null) {
      $result.gameState = gameState;
    }
    if (keyState != null) {
      $result.keyState = keyState;
    }
    if (clientPlayerSpec != null) {
      $result.clientPlayerSpec = clientPlayerSpec;
    }
    if (commanderGameReply != null) {
      $result.commanderGameReply = commanderGameReply;
    }
    if (clientEnter != null) {
      $result.clientEnter = clientEnter;
    }
    if (ackedDataReceipts != null) {
      $result.ackedDataReceipts = ackedDataReceipts;
    }
    if (ping != null) {
      $result.ping = ping;
    }
    if (pong != null) {
      $result.pong = pong;
    }
    if (otherPlayerWorldSelect != null) {
      $result.otherPlayerWorldSelect = otherPlayerWorldSelect;
    }
    if (transferCommand != null) {
      $result.transferCommand = transferCommand;
    }
    if (byteWorldDestruction != null) {
      $result.byteWorldDestruction = byteWorldDestruction;
    }
    if (byteWorldDraw != null) {
      $result.byteWorldDraw = byteWorldDraw;
    }
    if (particleEffects != null) {
      $result.particleEffects = particleEffects;
    }
    if (clientStatusData != null) {
      $result.clientStatusData = clientStatusData;
    }
    if (resourceRequest != null) {
      $result.resourceRequest = resourceRequest;
    }
    if (resourceResponse != null) {
      $result.resourceResponse = resourceResponse;
    }
    if (commanderMapSelected != null) {
      $result.commanderMapSelected = commanderMapSelected;
    }
    if (playSound != null) {
      $result.playSound = playSound;
    }
    if (negotiation != null) {
      $result.negotiation = negotiation;
    }
    if (commanderSwitchFromClosedConnection != null) {
      $result.commanderSwitchFromClosedConnection = commanderSwitchFromClosedConnection;
    }
    if (suggestSelfCommander != null) {
      $result.suggestSelfCommander = suggestSelfCommander;
    }
    return $result;
  }
  StateUpdate._() : super();
  factory StateUpdate.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory StateUpdate.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static const $core.Map<$core.int, StateUpdate_Update> _StateUpdate_UpdateByTag = {
    3 : StateUpdate_Update.userMessage,
    4 : StateUpdate_Update.spriteRemoval,
    5 : StateUpdate_Update.gameState,
    6 : StateUpdate_Update.keyState,
    7 : StateUpdate_Update.clientPlayerSpec,
    8 : StateUpdate_Update.commanderGameReply,
    9 : StateUpdate_Update.clientEnter,
    10 : StateUpdate_Update.ackedDataReceipts,
    11 : StateUpdate_Update.ping,
    12 : StateUpdate_Update.pong,
    13 : StateUpdate_Update.otherPlayerWorldSelect,
    14 : StateUpdate_Update.transferCommand,
    15 : StateUpdate_Update.byteWorldDestruction,
    16 : StateUpdate_Update.byteWorldDraw,
    17 : StateUpdate_Update.particleEffects,
    18 : StateUpdate_Update.clientStatusData,
    19 : StateUpdate_Update.resourceRequest,
    20 : StateUpdate_Update.resourceResponse,
    21 : StateUpdate_Update.commanderMapSelected,
    22 : StateUpdate_Update.playSound,
    23 : StateUpdate_Update.negotiation,
    24 : StateUpdate_Update.commanderSwitchFromClosedConnection,
    25 : StateUpdate_Update.suggestSelfCommander,
    0 : StateUpdate_Update.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'StateUpdate', package: const $pb.PackageName(_omitMessageNames ? '' : 'dart2d_proto'), createEmptyInstance: create)
    ..oo(0, [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25])
    ..a<$core.int>(1, _omitFieldNames ? '' : 'dataReceipt', $pb.PbFieldType.O3)
    ..aOS(3, _omitFieldNames ? '' : 'userMessage')
    ..a<$core.int>(4, _omitFieldNames ? '' : 'spriteRemoval', $pb.PbFieldType.O3)
    ..aOM<GameStateProto>(5, _omitFieldNames ? '' : 'gameState', subBuilder: GameStateProto.create)
    ..aOM<KeyStateProto>(6, _omitFieldNames ? '' : 'keyState', subBuilder: KeyStateProto.create)
    ..aOM<ClientPlayerSpec>(7, _omitFieldNames ? '' : 'clientPlayerSpec', subBuilder: ClientPlayerSpec.create)
    ..aOM<CommanderGameReply>(8, _omitFieldNames ? '' : 'commanderGameReply', subBuilder: CommanderGameReply.create)
    ..aOB(9, _omitFieldNames ? '' : 'clientEnter')
    ..a<$core.int>(10, _omitFieldNames ? '' : 'ackedDataReceipts', $pb.PbFieldType.O3)
    ..aInt64(11, _omitFieldNames ? '' : 'ping')
    ..aInt64(12, _omitFieldNames ? '' : 'pong')
    ..aOM<OtherPlayerWorldSelect>(13, _omitFieldNames ? '' : 'otherPlayerWorldSelect', subBuilder: OtherPlayerWorldSelect.create)
    ..aOB(14, _omitFieldNames ? '' : 'transferCommand')
    ..aOM<ByteWorldDestruction>(15, _omitFieldNames ? '' : 'byteWorldDestruction', subBuilder: ByteWorldDestruction.create)
    ..aOM<ByteWorldDraw>(16, _omitFieldNames ? '' : 'byteWorldDraw', subBuilder: ByteWorldDraw.create)
    ..aOM<ParticleEffects>(17, _omitFieldNames ? '' : 'particleEffects', subBuilder: ParticleEffects.create)
    ..aOM<ClientStatusData>(18, _omitFieldNames ? '' : 'clientStatusData', subBuilder: ClientStatusData.create)
    ..aOM<ResourceRequest>(19, _omitFieldNames ? '' : 'resourceRequest', subBuilder: ResourceRequest.create)
    ..aOM<ResourceResponse>(20, _omitFieldNames ? '' : 'resourceResponse', subBuilder: ResourceResponse.create)
    ..aOS(21, _omitFieldNames ? '' : 'commanderMapSelected')
    ..aOM<PlaySound>(22, _omitFieldNames ? '' : 'playSound', subBuilder: PlaySound.create)
    ..aOM<WebRtcNegotiationProto>(23, _omitFieldNames ? '' : 'negotiation', subBuilder: WebRtcNegotiationProto.create)
    ..aOS(24, _omitFieldNames ? '' : 'commanderSwitchFromClosedConnection')
    ..aOM<ClientStatusData>(25, _omitFieldNames ? '' : 'suggestSelfCommander', subBuilder: ClientStatusData.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  StateUpdate clone() => StateUpdate()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  StateUpdate copyWith(void Function(StateUpdate) updates) => super.copyWith((message) => updates(message as StateUpdate)) as StateUpdate;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StateUpdate create() => StateUpdate._();
  StateUpdate createEmptyInstance() => create();
  static $pb.PbList<StateUpdate> createRepeated() => $pb.PbList<StateUpdate>();
  @$core.pragma('dart2js:noInline')
  static StateUpdate getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StateUpdate>(create);
  static StateUpdate? _defaultInstance;

  StateUpdate_Update whichUpdate() => _StateUpdate_UpdateByTag[$_whichOneof(0)]!;
  void clearUpdate() => clearField($_whichOneof(0));

  /// This data has a receipt that needs acknowledgement.
  @$pb.TagNumber(1)
  $core.int get dataReceipt => $_getIZ(0);
  @$pb.TagNumber(1)
  set dataReceipt($core.int v) { $_setSignedInt32(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasDataReceipt() => $_has(0);
  @$pb.TagNumber(1)
  void clearDataReceipt() => clearField(1);

  /// A user visible chat message.
  @$pb.TagNumber(3)
  $core.String get userMessage => $_getSZ(1);
  @$pb.TagNumber(3)
  set userMessage($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(3)
  $core.bool hasUserMessage() => $_has(1);
  @$pb.TagNumber(3)
  void clearUserMessage() => clearField(3);

  /// Remove this sprite.
  @$pb.TagNumber(4)
  $core.int get spriteRemoval => $_getIZ(2);
  @$pb.TagNumber(4)
  set spriteRemoval($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(4)
  $core.bool hasSpriteRemoval() => $_has(2);
  @$pb.TagNumber(4)
  void clearSpriteRemoval() => clearField(4);

  /// The entire gamestate.
  @$pb.TagNumber(5)
  GameStateProto get gameState => $_getN(3);
  @$pb.TagNumber(5)
  set gameState(GameStateProto v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasGameState() => $_has(3);
  @$pb.TagNumber(5)
  void clearGameState() => clearField(5);
  @$pb.TagNumber(5)
  GameStateProto ensureGameState() => $_ensure(3);

  /// Key state update.
  @$pb.TagNumber(6)
  KeyStateProto get keyState => $_getN(4);
  @$pb.TagNumber(6)
  set keyState(KeyStateProto v) { setField(6, v); }
  @$pb.TagNumber(6)
  $core.bool hasKeyState() => $_has(4);
  @$pb.TagNumber(6)
  void clearKeyState() => clearField(6);
  @$pb.TagNumber(6)
  KeyStateProto ensureKeyState() => $_ensure(4);

  /// Client trying to connect command.
  @$pb.TagNumber(7)
  ClientPlayerSpec get clientPlayerSpec => $_getN(5);
  @$pb.TagNumber(7)
  set clientPlayerSpec(ClientPlayerSpec v) { setField(7, v); }
  @$pb.TagNumber(7)
  $core.bool hasClientPlayerSpec() => $_has(5);
  @$pb.TagNumber(7)
  void clearClientPlayerSpec() => clearField(7);
  @$pb.TagNumber(7)
  ClientPlayerSpec ensureClientPlayerSpec() => $_ensure(5);

  /// Server reply to connect message.
  @$pb.TagNumber(8)
  CommanderGameReply get commanderGameReply => $_getN(6);
  @$pb.TagNumber(8)
  set commanderGameReply(CommanderGameReply v) { setField(8, v); }
  @$pb.TagNumber(8)
  $core.bool hasCommanderGameReply() => $_has(6);
  @$pb.TagNumber(8)
  void clearCommanderGameReply() => clearField(8);
  @$pb.TagNumber(8)
  CommanderGameReply ensureCommanderGameReply() => $_ensure(6);

  /// Send by client when ready to spawn.
  @$pb.TagNumber(9)
  $core.bool get clientEnter => $_getBF(7);
  @$pb.TagNumber(9)
  set clientEnter($core.bool v) { $_setBool(7, v); }
  @$pb.TagNumber(9)
  $core.bool hasClientEnter() => $_has(7);
  @$pb.TagNumber(9)
  void clearClientEnter() => clearField(9);

  /// A data receipt for reliable data.
  @$pb.TagNumber(10)
  $core.int get ackedDataReceipts => $_getIZ(8);
  @$pb.TagNumber(10)
  set ackedDataReceipts($core.int v) { $_setSignedInt32(8, v); }
  @$pb.TagNumber(10)
  $core.bool hasAckedDataReceipts() => $_has(8);
  @$pb.TagNumber(10)
  void clearAckedDataReceipts() => clearField(10);

  /// Basic pings.
  @$pb.TagNumber(11)
  $fixnum.Int64 get ping => $_getI64(9);
  @$pb.TagNumber(11)
  set ping($fixnum.Int64 v) { $_setInt64(9, v); }
  @$pb.TagNumber(11)
  $core.bool hasPing() => $_has(9);
  @$pb.TagNumber(11)
  void clearPing() => clearField(11);

  @$pb.TagNumber(12)
  $fixnum.Int64 get pong => $_getI64(10);
  @$pb.TagNumber(12)
  set pong($fixnum.Int64 v) { $_setInt64(10, v); }
  @$pb.TagNumber(12)
  $core.bool hasPong() => $_has(10);
  @$pb.TagNumber(12)
  void clearPong() => clearField(12);

  /// In game selection mode.
  @$pb.TagNumber(13)
  OtherPlayerWorldSelect get otherPlayerWorldSelect => $_getN(11);
  @$pb.TagNumber(13)
  set otherPlayerWorldSelect(OtherPlayerWorldSelect v) { setField(13, v); }
  @$pb.TagNumber(13)
  $core.bool hasOtherPlayerWorldSelect() => $_has(11);
  @$pb.TagNumber(13)
  void clearOtherPlayerWorldSelect() => clearField(13);
  @$pb.TagNumber(13)
  OtherPlayerWorldSelect ensureOtherPlayerWorldSelect() => $_ensure(11);

  /// Other side tells us to become game commander.
  @$pb.TagNumber(14)
  $core.bool get transferCommand => $_getBF(12);
  @$pb.TagNumber(14)
  set transferCommand($core.bool v) { $_setBool(12, v); }
  @$pb.TagNumber(14)
  $core.bool hasTransferCommand() => $_has(12);
  @$pb.TagNumber(14)
  void clearTransferCommand() => clearField(14);

  @$pb.TagNumber(15)
  ByteWorldDestruction get byteWorldDestruction => $_getN(13);
  @$pb.TagNumber(15)
  set byteWorldDestruction(ByteWorldDestruction v) { setField(15, v); }
  @$pb.TagNumber(15)
  $core.bool hasByteWorldDestruction() => $_has(13);
  @$pb.TagNumber(15)
  void clearByteWorldDestruction() => clearField(15);
  @$pb.TagNumber(15)
  ByteWorldDestruction ensureByteWorldDestruction() => $_ensure(13);

  @$pb.TagNumber(16)
  ByteWorldDraw get byteWorldDraw => $_getN(14);
  @$pb.TagNumber(16)
  set byteWorldDraw(ByteWorldDraw v) { setField(16, v); }
  @$pb.TagNumber(16)
  $core.bool hasByteWorldDraw() => $_has(14);
  @$pb.TagNumber(16)
  void clearByteWorldDraw() => clearField(16);
  @$pb.TagNumber(16)
  ByteWorldDraw ensureByteWorldDraw() => $_ensure(14);

  @$pb.TagNumber(17)
  ParticleEffects get particleEffects => $_getN(15);
  @$pb.TagNumber(17)
  set particleEffects(ParticleEffects v) { setField(17, v); }
  @$pb.TagNumber(17)
  $core.bool hasParticleEffects() => $_has(15);
  @$pb.TagNumber(17)
  void clearParticleEffects() => clearField(17);
  @$pb.TagNumber(17)
  ParticleEffects ensureParticleEffects() => $_ensure(15);

  @$pb.TagNumber(18)
  ClientStatusData get clientStatusData => $_getN(16);
  @$pb.TagNumber(18)
  set clientStatusData(ClientStatusData v) { setField(18, v); }
  @$pb.TagNumber(18)
  $core.bool hasClientStatusData() => $_has(16);
  @$pb.TagNumber(18)
  void clearClientStatusData() => clearField(18);
  @$pb.TagNumber(18)
  ClientStatusData ensureClientStatusData() => $_ensure(16);

  @$pb.TagNumber(19)
  ResourceRequest get resourceRequest => $_getN(17);
  @$pb.TagNumber(19)
  set resourceRequest(ResourceRequest v) { setField(19, v); }
  @$pb.TagNumber(19)
  $core.bool hasResourceRequest() => $_has(17);
  @$pb.TagNumber(19)
  void clearResourceRequest() => clearField(19);
  @$pb.TagNumber(19)
  ResourceRequest ensureResourceRequest() => $_ensure(17);

  @$pb.TagNumber(20)
  ResourceResponse get resourceResponse => $_getN(18);
  @$pb.TagNumber(20)
  set resourceResponse(ResourceResponse v) { setField(20, v); }
  @$pb.TagNumber(20)
  $core.bool hasResourceResponse() => $_has(18);
  @$pb.TagNumber(20)
  void clearResourceResponse() => clearField(20);
  @$pb.TagNumber(20)
  ResourceResponse ensureResourceResponse() => $_ensure(18);

  @$pb.TagNumber(21)
  $core.String get commanderMapSelected => $_getSZ(19);
  @$pb.TagNumber(21)
  set commanderMapSelected($core.String v) { $_setString(19, v); }
  @$pb.TagNumber(21)
  $core.bool hasCommanderMapSelected() => $_has(19);
  @$pb.TagNumber(21)
  void clearCommanderMapSelected() => clearField(21);

  @$pb.TagNumber(22)
  PlaySound get playSound => $_getN(20);
  @$pb.TagNumber(22)
  set playSound(PlaySound v) { setField(22, v); }
  @$pb.TagNumber(22)
  $core.bool hasPlaySound() => $_has(20);
  @$pb.TagNumber(22)
  void clearPlaySound() => clearField(22);
  @$pb.TagNumber(22)
  PlaySound ensurePlaySound() => $_ensure(20);

  @$pb.TagNumber(23)
  WebRtcNegotiationProto get negotiation => $_getN(21);
  @$pb.TagNumber(23)
  set negotiation(WebRtcNegotiationProto v) { setField(23, v); }
  @$pb.TagNumber(23)
  $core.bool hasNegotiation() => $_has(21);
  @$pb.TagNumber(23)
  void clearNegotiation() => clearField(23);
  @$pb.TagNumber(23)
  WebRtcNegotiationProto ensureNegotiation() => $_ensure(21);

  /// The other side switched to this commander.
  @$pb.TagNumber(24)
  $core.String get commanderSwitchFromClosedConnection => $_getSZ(22);
  @$pb.TagNumber(24)
  set commanderSwitchFromClosedConnection($core.String v) { $_setString(22, v); }
  @$pb.TagNumber(24)
  $core.bool hasCommanderSwitchFromClosedConnection() => $_has(22);
  @$pb.TagNumber(24)
  void clearCommanderSwitchFromClosedConnection() => clearField(24);

  /// The other side suggest it should become commander.
  /// Provides the ClientStatusData as motiviation.
  @$pb.TagNumber(25)
  ClientStatusData get suggestSelfCommander => $_getN(23);
  @$pb.TagNumber(25)
  set suggestSelfCommander(ClientStatusData v) { setField(25, v); }
  @$pb.TagNumber(25)
  $core.bool hasSuggestSelfCommander() => $_has(23);
  @$pb.TagNumber(25)
  void clearSuggestSelfCommander() => clearField(25);
  @$pb.TagNumber(25)
  ClientStatusData ensureSuggestSelfCommander() => $_ensure(23);
}

class WebRtcNegotiationProto extends $pb.GeneratedMessage {
  factory WebRtcNegotiationProto({
    WebRtcDanceProto? danceProto,
    $core.String? src,
    $core.String? dst,
    WebRtcNegotiationProto_Type? type,
  }) {
    final $result = create();
    if (danceProto != null) {
      $result.danceProto = danceProto;
    }
    if (src != null) {
      $result.src = src;
    }
    if (dst != null) {
      $result.dst = dst;
    }
    if (type != null) {
      $result.type = type;
    }
    return $result;
  }
  WebRtcNegotiationProto._() : super();
  factory WebRtcNegotiationProto.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory WebRtcNegotiationProto.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'WebRtcNegotiationProto', package: const $pb.PackageName(_omitMessageNames ? '' : 'dart2d_proto'), createEmptyInstance: create)
    ..aOM<WebRtcDanceProto>(1, _omitFieldNames ? '' : 'danceProto', subBuilder: WebRtcDanceProto.create)
    ..aOS(2, _omitFieldNames ? '' : 'src')
    ..aOS(3, _omitFieldNames ? '' : 'dst')
    ..e<WebRtcNegotiationProto_Type>(4, _omitFieldNames ? '' : 'type', $pb.PbFieldType.OE, defaultOrMaker: WebRtcNegotiationProto_Type.UNSET, valueOf: WebRtcNegotiationProto_Type.valueOf, enumValues: WebRtcNegotiationProto_Type.values)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  WebRtcNegotiationProto clone() => WebRtcNegotiationProto()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  WebRtcNegotiationProto copyWith(void Function(WebRtcNegotiationProto) updates) => super.copyWith((message) => updates(message as WebRtcNegotiationProto)) as WebRtcNegotiationProto;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static WebRtcNegotiationProto create() => WebRtcNegotiationProto._();
  WebRtcNegotiationProto createEmptyInstance() => create();
  static $pb.PbList<WebRtcNegotiationProto> createRepeated() => $pb.PbList<WebRtcNegotiationProto>();
  @$core.pragma('dart2js:noInline')
  static WebRtcNegotiationProto getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<WebRtcNegotiationProto>(create);
  static WebRtcNegotiationProto? _defaultInstance;

  @$pb.TagNumber(1)
  WebRtcDanceProto get danceProto => $_getN(0);
  @$pb.TagNumber(1)
  set danceProto(WebRtcDanceProto v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasDanceProto() => $_has(0);
  @$pb.TagNumber(1)
  void clearDanceProto() => clearField(1);
  @$pb.TagNumber(1)
  WebRtcDanceProto ensureDanceProto() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.String get src => $_getSZ(1);
  @$pb.TagNumber(2)
  set src($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSrc() => $_has(1);
  @$pb.TagNumber(2)
  void clearSrc() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get dst => $_getSZ(2);
  @$pb.TagNumber(3)
  set dst($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDst() => $_has(2);
  @$pb.TagNumber(3)
  void clearDst() => clearField(3);

  @$pb.TagNumber(4)
  WebRtcNegotiationProto_Type get type => $_getN(3);
  @$pb.TagNumber(4)
  set type(WebRtcNegotiationProto_Type v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasType() => $_has(3);
  @$pb.TagNumber(4)
  void clearType() => clearField(4);
}

class PlaySound extends $pb.GeneratedMessage {
  factory PlaySound({
    $core.int? sound,
    Vec2Proto? location,
  }) {
    final $result = create();
    if (sound != null) {
      $result.sound = sound;
    }
    if (location != null) {
      $result.location = location;
    }
    return $result;
  }
  PlaySound._() : super();
  factory PlaySound.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PlaySound.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PlaySound', package: const $pb.PackageName(_omitMessageNames ? '' : 'dart2d_proto'), createEmptyInstance: create)
    ..a<$core.int>(1, _omitFieldNames ? '' : 'sound', $pb.PbFieldType.O3)
    ..aOM<Vec2Proto>(2, _omitFieldNames ? '' : 'location', subBuilder: Vec2Proto.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PlaySound clone() => PlaySound()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PlaySound copyWith(void Function(PlaySound) updates) => super.copyWith((message) => updates(message as PlaySound)) as PlaySound;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PlaySound create() => PlaySound._();
  PlaySound createEmptyInstance() => create();
  static $pb.PbList<PlaySound> createRepeated() => $pb.PbList<PlaySound>();
  @$core.pragma('dart2js:noInline')
  static PlaySound getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PlaySound>(create);
  static PlaySound? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get sound => $_getIZ(0);
  @$pb.TagNumber(1)
  set sound($core.int v) { $_setSignedInt32(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSound() => $_has(0);
  @$pb.TagNumber(1)
  void clearSound() => clearField(1);

  @$pb.TagNumber(2)
  Vec2Proto get location => $_getN(1);
  @$pb.TagNumber(2)
  set location(Vec2Proto v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasLocation() => $_has(1);
  @$pb.TagNumber(2)
  void clearLocation() => clearField(2);
  @$pb.TagNumber(2)
  Vec2Proto ensureLocation() => $_ensure(1);
}

class ClientStatusData extends $pb.GeneratedMessage {
  factory ClientStatusData({
    $core.double? fps,
    $core.Iterable<ConnectionInfoProto>? connectionInfo,
  }) {
    final $result = create();
    if (fps != null) {
      $result.fps = fps;
    }
    if (connectionInfo != null) {
      $result.connectionInfo.addAll(connectionInfo);
    }
    return $result;
  }
  ClientStatusData._() : super();
  factory ClientStatusData.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ClientStatusData.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ClientStatusData', package: const $pb.PackageName(_omitMessageNames ? '' : 'dart2d_proto'), createEmptyInstance: create)
    ..a<$core.double>(1, _omitFieldNames ? '' : 'fps', $pb.PbFieldType.OF)
    ..pc<ConnectionInfoProto>(2, _omitFieldNames ? '' : 'connectionInfo', $pb.PbFieldType.PM, subBuilder: ConnectionInfoProto.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ClientStatusData clone() => ClientStatusData()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ClientStatusData copyWith(void Function(ClientStatusData) updates) => super.copyWith((message) => updates(message as ClientStatusData)) as ClientStatusData;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ClientStatusData create() => ClientStatusData._();
  ClientStatusData createEmptyInstance() => create();
  static $pb.PbList<ClientStatusData> createRepeated() => $pb.PbList<ClientStatusData>();
  @$core.pragma('dart2js:noInline')
  static ClientStatusData getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ClientStatusData>(create);
  static ClientStatusData? _defaultInstance;

  @$pb.TagNumber(1)
  $core.double get fps => $_getN(0);
  @$pb.TagNumber(1)
  set fps($core.double v) { $_setFloat(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasFps() => $_has(0);
  @$pb.TagNumber(1)
  void clearFps() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<ConnectionInfoProto> get connectionInfo => $_getList(1);
}

/// Request to get resource data.
class ResourceResponse extends $pb.GeneratedMessage {
  factory ResourceResponse({
    $core.int? resourceIndex,
    $core.int? startByte,
    $core.List<$core.int>? data,
    $core.int? size,
  }) {
    final $result = create();
    if (resourceIndex != null) {
      $result.resourceIndex = resourceIndex;
    }
    if (startByte != null) {
      $result.startByte = startByte;
    }
    if (data != null) {
      $result.data = data;
    }
    if (size != null) {
      $result.size = size;
    }
    return $result;
  }
  ResourceResponse._() : super();
  factory ResourceResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ResourceResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ResourceResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'dart2d_proto'), createEmptyInstance: create)
    ..a<$core.int>(1, _omitFieldNames ? '' : 'resourceIndex', $pb.PbFieldType.O3)
    ..a<$core.int>(2, _omitFieldNames ? '' : 'startByte', $pb.PbFieldType.O3)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'size', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ResourceResponse clone() => ResourceResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ResourceResponse copyWith(void Function(ResourceResponse) updates) => super.copyWith((message) => updates(message as ResourceResponse)) as ResourceResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ResourceResponse create() => ResourceResponse._();
  ResourceResponse createEmptyInstance() => create();
  static $pb.PbList<ResourceResponse> createRepeated() => $pb.PbList<ResourceResponse>();
  @$core.pragma('dart2js:noInline')
  static ResourceResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ResourceResponse>(create);
  static ResourceResponse? _defaultInstance;

  /// The index of the resource.
  @$pb.TagNumber(1)
  $core.int get resourceIndex => $_getIZ(0);
  @$pb.TagNumber(1)
  set resourceIndex($core.int v) { $_setSignedInt32(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasResourceIndex() => $_has(0);
  @$pb.TagNumber(1)
  void clearResourceIndex() => clearField(1);

  /// Where in the bytestream this chunk starts.
  @$pb.TagNumber(2)
  $core.int get startByte => $_getIZ(1);
  @$pb.TagNumber(2)
  set startByte($core.int v) { $_setSignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasStartByte() => $_has(1);
  @$pb.TagNumber(2)
  void clearStartByte() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get data => $_getN(2);
  @$pb.TagNumber(3)
  set data($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasData() => $_has(2);
  @$pb.TagNumber(3)
  void clearData() => clearField(3);

  /// The size of this resource.
  @$pb.TagNumber(4)
  $core.int get size => $_getIZ(3);
  @$pb.TagNumber(4)
  set size($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasSize() => $_has(3);
  @$pb.TagNumber(4)
  void clearSize() => clearField(4);
}

/// Request to get resource data.
class ResourceRequest extends $pb.GeneratedMessage {
  factory ResourceRequest({
    $core.int? resourceIndex,
    $core.int? startByte,
    $core.int? endByte,
    $core.int? multiply,
  }) {
    final $result = create();
    if (resourceIndex != null) {
      $result.resourceIndex = resourceIndex;
    }
    if (startByte != null) {
      $result.startByte = startByte;
    }
    if (endByte != null) {
      $result.endByte = endByte;
    }
    if (multiply != null) {
      $result.multiply = multiply;
    }
    return $result;
  }
  ResourceRequest._() : super();
  factory ResourceRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ResourceRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ResourceRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'dart2d_proto'), createEmptyInstance: create)
    ..a<$core.int>(1, _omitFieldNames ? '' : 'resourceIndex', $pb.PbFieldType.O3)
    ..a<$core.int>(2, _omitFieldNames ? '' : 'startByte', $pb.PbFieldType.O3)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'endByte', $pb.PbFieldType.O3)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'multiply', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ResourceRequest clone() => ResourceRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ResourceRequest copyWith(void Function(ResourceRequest) updates) => super.copyWith((message) => updates(message as ResourceRequest)) as ResourceRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ResourceRequest create() => ResourceRequest._();
  ResourceRequest createEmptyInstance() => create();
  static $pb.PbList<ResourceRequest> createRepeated() => $pb.PbList<ResourceRequest>();
  @$core.pragma('dart2js:noInline')
  static ResourceRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ResourceRequest>(create);
  static ResourceRequest? _defaultInstance;

  /// The index of the resource.
  @$pb.TagNumber(1)
  $core.int get resourceIndex => $_getIZ(0);
  @$pb.TagNumber(1)
  set resourceIndex($core.int v) { $_setSignedInt32(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasResourceIndex() => $_has(0);
  @$pb.TagNumber(1)
  void clearResourceIndex() => clearField(1);

  @$pb.TagNumber(2)
  $core.int get startByte => $_getIZ(1);
  @$pb.TagNumber(2)
  set startByte($core.int v) { $_setSignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasStartByte() => $_has(1);
  @$pb.TagNumber(2)
  void clearStartByte() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get endByte => $_getIZ(2);
  @$pb.TagNumber(3)
  set endByte($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasEndByte() => $_has(2);
  @$pb.TagNumber(3)
  void clearEndByte() => clearField(3);

  /// Consider this request multiple times.
  @$pb.TagNumber(4)
  $core.int get multiply => $_getIZ(3);
  @$pb.TagNumber(4)
  set multiply($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasMultiply() => $_has(3);
  @$pb.TagNumber(4)
  void clearMultiply() => clearField(4);
}

/// Clear part of the ByteWorld.
class ByteWorldDestruction extends $pb.GeneratedMessage {
  factory ByteWorldDestruction({
    Vec2Proto? position,
    $core.double? radius,
    $core.int? damage,
    Vec2Proto? velocity,
    $core.bool? addParticles,
  }) {
    final $result = create();
    if (position != null) {
      $result.position = position;
    }
    if (radius != null) {
      $result.radius = radius;
    }
    if (damage != null) {
      $result.damage = damage;
    }
    if (velocity != null) {
      $result.velocity = velocity;
    }
    if (addParticles != null) {
      $result.addParticles = addParticles;
    }
    return $result;
  }
  ByteWorldDestruction._() : super();
  factory ByteWorldDestruction.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ByteWorldDestruction.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ByteWorldDestruction', package: const $pb.PackageName(_omitMessageNames ? '' : 'dart2d_proto'), createEmptyInstance: create)
    ..aOM<Vec2Proto>(1, _omitFieldNames ? '' : 'position', subBuilder: Vec2Proto.create)
    ..a<$core.double>(2, _omitFieldNames ? '' : 'radius', $pb.PbFieldType.OF)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'damage', $pb.PbFieldType.O3)
    ..aOM<Vec2Proto>(4, _omitFieldNames ? '' : 'velocity', subBuilder: Vec2Proto.create)
    ..aOB(5, _omitFieldNames ? '' : 'addParticles', protoName: 'addParticles')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ByteWorldDestruction clone() => ByteWorldDestruction()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ByteWorldDestruction copyWith(void Function(ByteWorldDestruction) updates) => super.copyWith((message) => updates(message as ByteWorldDestruction)) as ByteWorldDestruction;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ByteWorldDestruction create() => ByteWorldDestruction._();
  ByteWorldDestruction createEmptyInstance() => create();
  static $pb.PbList<ByteWorldDestruction> createRepeated() => $pb.PbList<ByteWorldDestruction>();
  @$core.pragma('dart2js:noInline')
  static ByteWorldDestruction getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ByteWorldDestruction>(create);
  static ByteWorldDestruction? _defaultInstance;

  /// What position.
  @$pb.TagNumber(1)
  Vec2Proto get position => $_getN(0);
  @$pb.TagNumber(1)
  set position(Vec2Proto v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasPosition() => $_has(0);
  @$pb.TagNumber(1)
  void clearPosition() => clearField(1);
  @$pb.TagNumber(1)
  Vec2Proto ensurePosition() => $_ensure(0);

  /// What radius to clear.
  @$pb.TagNumber(2)
  $core.double get radius => $_getN(1);
  @$pb.TagNumber(2)
  set radius($core.double v) { $_setFloat(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasRadius() => $_has(1);
  @$pb.TagNumber(2)
  void clearRadius() => clearField(2);

  /// If clearing it should take damage.
  @$pb.TagNumber(3)
  $core.int get damage => $_getIZ(2);
  @$pb.TagNumber(3)
  set damage($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDamage() => $_has(2);
  @$pb.TagNumber(3)
  void clearDamage() => clearField(3);

  /// Velocity of explosion.
  @$pb.TagNumber(4)
  Vec2Proto get velocity => $_getN(3);
  @$pb.TagNumber(4)
  set velocity(Vec2Proto v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasVelocity() => $_has(3);
  @$pb.TagNumber(4)
  void clearVelocity() => clearField(4);
  @$pb.TagNumber(4)
  Vec2Proto ensureVelocity() => $_ensure(3);

  /// Add explosion particles.
  @$pb.TagNumber(5)
  $core.bool get addParticles => $_getBF(4);
  @$pb.TagNumber(5)
  set addParticles($core.bool v) { $_setBool(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasAddParticles() => $_has(4);
  @$pb.TagNumber(5)
  void clearAddParticles() => clearField(5);
}

/// Draw something on the ByteWorld.
class ByteWorldDraw extends $pb.GeneratedMessage {
  factory ByteWorldDraw({
    Vec2Proto? position,
    Vec2Proto? size,
    $core.String? color,
  }) {
    final $result = create();
    if (position != null) {
      $result.position = position;
    }
    if (size != null) {
      $result.size = size;
    }
    if (color != null) {
      $result.color = color;
    }
    return $result;
  }
  ByteWorldDraw._() : super();
  factory ByteWorldDraw.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ByteWorldDraw.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ByteWorldDraw', package: const $pb.PackageName(_omitMessageNames ? '' : 'dart2d_proto'), createEmptyInstance: create)
    ..aOM<Vec2Proto>(1, _omitFieldNames ? '' : 'position', subBuilder: Vec2Proto.create)
    ..aOM<Vec2Proto>(2, _omitFieldNames ? '' : 'size', subBuilder: Vec2Proto.create)
    ..aOS(3, _omitFieldNames ? '' : 'color')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ByteWorldDraw clone() => ByteWorldDraw()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ByteWorldDraw copyWith(void Function(ByteWorldDraw) updates) => super.copyWith((message) => updates(message as ByteWorldDraw)) as ByteWorldDraw;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ByteWorldDraw create() => ByteWorldDraw._();
  ByteWorldDraw createEmptyInstance() => create();
  static $pb.PbList<ByteWorldDraw> createRepeated() => $pb.PbList<ByteWorldDraw>();
  @$core.pragma('dart2js:noInline')
  static ByteWorldDraw getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ByteWorldDraw>(create);
  static ByteWorldDraw? _defaultInstance;

  /// Where.
  @$pb.TagNumber(1)
  Vec2Proto get position => $_getN(0);
  @$pb.TagNumber(1)
  set position(Vec2Proto v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasPosition() => $_has(0);
  @$pb.TagNumber(1)
  void clearPosition() => clearField(1);
  @$pb.TagNumber(1)
  Vec2Proto ensurePosition() => $_ensure(0);

  /// Rectangle size.
  @$pb.TagNumber(2)
  Vec2Proto get size => $_getN(1);
  @$pb.TagNumber(2)
  set size(Vec2Proto v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasSize() => $_has(1);
  @$pb.TagNumber(2)
  void clearSize() => clearField(2);
  @$pb.TagNumber(2)
  Vec2Proto ensureSize() => $_ensure(1);

  /// HTML color string.
  @$pb.TagNumber(3)
  $core.String get color => $_getSZ(2);
  @$pb.TagNumber(3)
  set color($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasColor() => $_has(2);
  @$pb.TagNumber(3)
  void clearColor() => clearField(3);
}

class OtherPlayerWorldSelect extends $pb.GeneratedMessage {
  factory OtherPlayerWorldSelect({
    $core.String? name,
    $core.int? worldSelectedIndex,
  }) {
    final $result = create();
    if (name != null) {
      $result.name = name;
    }
    if (worldSelectedIndex != null) {
      $result.worldSelectedIndex = worldSelectedIndex;
    }
    return $result;
  }
  OtherPlayerWorldSelect._() : super();
  factory OtherPlayerWorldSelect.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory OtherPlayerWorldSelect.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'OtherPlayerWorldSelect', package: const $pb.PackageName(_omitMessageNames ? '' : 'dart2d_proto'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..a<$core.int>(2, _omitFieldNames ? '' : 'worldSelectedIndex', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  OtherPlayerWorldSelect clone() => OtherPlayerWorldSelect()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  OtherPlayerWorldSelect copyWith(void Function(OtherPlayerWorldSelect) updates) => super.copyWith((message) => updates(message as OtherPlayerWorldSelect)) as OtherPlayerWorldSelect;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static OtherPlayerWorldSelect create() => OtherPlayerWorldSelect._();
  OtherPlayerWorldSelect createEmptyInstance() => create();
  static $pb.PbList<OtherPlayerWorldSelect> createRepeated() => $pb.PbList<OtherPlayerWorldSelect>();
  @$core.pragma('dart2js:noInline')
  static OtherPlayerWorldSelect getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<OtherPlayerWorldSelect>(create);
  static OtherPlayerWorldSelect? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => clearField(1);

  @$pb.TagNumber(2)
  $core.int get worldSelectedIndex => $_getIZ(1);
  @$pb.TagNumber(2)
  set worldSelectedIndex($core.int v) { $_setSignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasWorldSelectedIndex() => $_has(1);
  @$pb.TagNumber(2)
  void clearWorldSelectedIndex() => clearField(2);
}

class CommanderGameReply extends $pb.GeneratedMessage {
  factory CommanderGameReply({
    CommanderGameReply_ChallengeReply? challengeReply,
    GameStateProto? gameState,
    $core.int? spriteIndexStart,
    Vec2Proto? startingPosition,
  }) {
    final $result = create();
    if (challengeReply != null) {
      $result.challengeReply = challengeReply;
    }
    if (gameState != null) {
      $result.gameState = gameState;
    }
    if (spriteIndexStart != null) {
      $result.spriteIndexStart = spriteIndexStart;
    }
    if (startingPosition != null) {
      $result.startingPosition = startingPosition;
    }
    return $result;
  }
  CommanderGameReply._() : super();
  factory CommanderGameReply.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory CommanderGameReply.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'CommanderGameReply', package: const $pb.PackageName(_omitMessageNames ? '' : 'dart2d_proto'), createEmptyInstance: create)
    ..e<CommanderGameReply_ChallengeReply>(1, _omitFieldNames ? '' : 'challengeReply', $pb.PbFieldType.OE, defaultOrMaker: CommanderGameReply_ChallengeReply.UNSET, valueOf: CommanderGameReply_ChallengeReply.valueOf, enumValues: CommanderGameReply_ChallengeReply.values)
    ..aOM<GameStateProto>(2, _omitFieldNames ? '' : 'gameState', subBuilder: GameStateProto.create)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'spriteIndexStart', $pb.PbFieldType.O3)
    ..aOM<Vec2Proto>(4, _omitFieldNames ? '' : 'startingPosition', subBuilder: Vec2Proto.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  CommanderGameReply clone() => CommanderGameReply()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  CommanderGameReply copyWith(void Function(CommanderGameReply) updates) => super.copyWith((message) => updates(message as CommanderGameReply)) as CommanderGameReply;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CommanderGameReply create() => CommanderGameReply._();
  CommanderGameReply createEmptyInstance() => create();
  static $pb.PbList<CommanderGameReply> createRepeated() => $pb.PbList<CommanderGameReply>();
  @$core.pragma('dart2js:noInline')
  static CommanderGameReply getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CommanderGameReply>(create);
  static CommanderGameReply? _defaultInstance;

  @$pb.TagNumber(1)
  CommanderGameReply_ChallengeReply get challengeReply => $_getN(0);
  @$pb.TagNumber(1)
  set challengeReply(CommanderGameReply_ChallengeReply v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasChallengeReply() => $_has(0);
  @$pb.TagNumber(1)
  void clearChallengeReply() => clearField(1);

  @$pb.TagNumber(2)
  GameStateProto get gameState => $_getN(1);
  @$pb.TagNumber(2)
  set gameState(GameStateProto v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasGameState() => $_has(1);
  @$pb.TagNumber(2)
  void clearGameState() => clearField(2);
  @$pb.TagNumber(2)
  GameStateProto ensureGameState() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.int get spriteIndexStart => $_getIZ(2);
  @$pb.TagNumber(3)
  set spriteIndexStart($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasSpriteIndexStart() => $_has(2);
  @$pb.TagNumber(3)
  void clearSpriteIndexStart() => clearField(3);

  @$pb.TagNumber(4)
  Vec2Proto get startingPosition => $_getN(3);
  @$pb.TagNumber(4)
  set startingPosition(Vec2Proto v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasStartingPosition() => $_has(3);
  @$pb.TagNumber(4)
  void clearStartingPosition() => clearField(4);
  @$pb.TagNumber(4)
  Vec2Proto ensureStartingPosition() => $_ensure(3);
}

class Vec2Proto extends $pb.GeneratedMessage {
  factory Vec2Proto({
    $core.double? x,
    $core.double? y,
  }) {
    final $result = create();
    if (x != null) {
      $result.x = x;
    }
    if (y != null) {
      $result.y = y;
    }
    return $result;
  }
  Vec2Proto._() : super();
  factory Vec2Proto.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory Vec2Proto.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'Vec2Proto', package: const $pb.PackageName(_omitMessageNames ? '' : 'dart2d_proto'), createEmptyInstance: create)
    ..a<$core.double>(1, _omitFieldNames ? '' : 'x', $pb.PbFieldType.OF)
    ..a<$core.double>(2, _omitFieldNames ? '' : 'y', $pb.PbFieldType.OF)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  Vec2Proto clone() => Vec2Proto()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  Vec2Proto copyWith(void Function(Vec2Proto) updates) => super.copyWith((message) => updates(message as Vec2Proto)) as Vec2Proto;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Vec2Proto create() => Vec2Proto._();
  Vec2Proto createEmptyInstance() => create();
  static $pb.PbList<Vec2Proto> createRepeated() => $pb.PbList<Vec2Proto>();
  @$core.pragma('dart2js:noInline')
  static Vec2Proto getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Vec2Proto>(create);
  static Vec2Proto? _defaultInstance;

  @$pb.TagNumber(1)
  $core.double get x => $_getN(0);
  @$pb.TagNumber(1)
  set x($core.double v) { $_setFloat(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasX() => $_has(0);
  @$pb.TagNumber(1)
  void clearX() => clearField(1);

  @$pb.TagNumber(2)
  $core.double get y => $_getN(1);
  @$pb.TagNumber(2)
  set y($core.double v) { $_setFloat(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasY() => $_has(1);
  @$pb.TagNumber(2)
  void clearY() => clearField(2);
}

class KeyStateProto extends $pb.GeneratedMessage {
  factory KeyStateProto({
    $core.Iterable<$core.int>? keysDown,
  }) {
    final $result = create();
    if (keysDown != null) {
      $result.keysDown.addAll(keysDown);
    }
    return $result;
  }
  KeyStateProto._() : super();
  factory KeyStateProto.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory KeyStateProto.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'KeyStateProto', package: const $pb.PackageName(_omitMessageNames ? '' : 'dart2d_proto'), createEmptyInstance: create)
    ..p<$core.int>(1, _omitFieldNames ? '' : 'keysDown', $pb.PbFieldType.P3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  KeyStateProto clone() => KeyStateProto()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  KeyStateProto copyWith(void Function(KeyStateProto) updates) => super.copyWith((message) => updates(message as KeyStateProto)) as KeyStateProto;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static KeyStateProto create() => KeyStateProto._();
  KeyStateProto createEmptyInstance() => create();
  static $pb.PbList<KeyStateProto> createRepeated() => $pb.PbList<KeyStateProto>();
  @$core.pragma('dart2js:noInline')
  static KeyStateProto getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<KeyStateProto>(create);
  static KeyStateProto? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get keysDown => $_getList(0);
}

class ClientPlayerSpec extends $pb.GeneratedMessage {
  factory ClientPlayerSpec({
    $core.String? name,
    $core.int? playerImageId,
  }) {
    final $result = create();
    if (name != null) {
      $result.name = name;
    }
    if (playerImageId != null) {
      $result.playerImageId = playerImageId;
    }
    return $result;
  }
  ClientPlayerSpec._() : super();
  factory ClientPlayerSpec.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ClientPlayerSpec.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ClientPlayerSpec', package: const $pb.PackageName(_omitMessageNames ? '' : 'dart2d_proto'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..a<$core.int>(2, _omitFieldNames ? '' : 'playerImageId', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ClientPlayerSpec clone() => ClientPlayerSpec()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ClientPlayerSpec copyWith(void Function(ClientPlayerSpec) updates) => super.copyWith((message) => updates(message as ClientPlayerSpec)) as ClientPlayerSpec;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ClientPlayerSpec create() => ClientPlayerSpec._();
  ClientPlayerSpec createEmptyInstance() => create();
  static $pb.PbList<ClientPlayerSpec> createRepeated() => $pb.PbList<ClientPlayerSpec>();
  @$core.pragma('dart2js:noInline')
  static ClientPlayerSpec getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ClientPlayerSpec>(create);
  static ClientPlayerSpec? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => clearField(1);

  @$pb.TagNumber(2)
  $core.int get playerImageId => $_getIZ(1);
  @$pb.TagNumber(2)
  set playerImageId($core.int v) { $_setSignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasPlayerImageId() => $_has(1);
  @$pb.TagNumber(2)
  void clearPlayerImageId() => clearField(2);
}

class GameStateProto extends $pb.GeneratedMessage {
  factory GameStateProto({
    $fixnum.Int64? startedAtEpochMillis,
    $core.Iterable<PlayerInfoProto>? playerInfo,
    $core.String? mapName,
    $core.String? actingCommanderId,
    $core.String? winnerPlayerId,
  }) {
    final $result = create();
    if (startedAtEpochMillis != null) {
      $result.startedAtEpochMillis = startedAtEpochMillis;
    }
    if (playerInfo != null) {
      $result.playerInfo.addAll(playerInfo);
    }
    if (mapName != null) {
      $result.mapName = mapName;
    }
    if (actingCommanderId != null) {
      $result.actingCommanderId = actingCommanderId;
    }
    if (winnerPlayerId != null) {
      $result.winnerPlayerId = winnerPlayerId;
    }
    return $result;
  }
  GameStateProto._() : super();
  factory GameStateProto.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GameStateProto.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GameStateProto', package: const $pb.PackageName(_omitMessageNames ? '' : 'dart2d_proto'), createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'startedAtEpochMillis')
    ..pc<PlayerInfoProto>(2, _omitFieldNames ? '' : 'playerInfo', $pb.PbFieldType.PM, subBuilder: PlayerInfoProto.create)
    ..aOS(3, _omitFieldNames ? '' : 'mapName')
    ..aOS(4, _omitFieldNames ? '' : 'actingCommanderId')
    ..aOS(5, _omitFieldNames ? '' : 'winnerPlayerId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GameStateProto clone() => GameStateProto()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GameStateProto copyWith(void Function(GameStateProto) updates) => super.copyWith((message) => updates(message as GameStateProto)) as GameStateProto;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GameStateProto create() => GameStateProto._();
  GameStateProto createEmptyInstance() => create();
  static $pb.PbList<GameStateProto> createRepeated() => $pb.PbList<GameStateProto>();
  @$core.pragma('dart2js:noInline')
  static GameStateProto getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GameStateProto>(create);
  static GameStateProto? _defaultInstance;

  /// Start time.
  @$pb.TagNumber(1)
  $fixnum.Int64 get startedAtEpochMillis => $_getI64(0);
  @$pb.TagNumber(1)
  set startedAtEpochMillis($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasStartedAtEpochMillis() => $_has(0);
  @$pb.TagNumber(1)
  void clearStartedAtEpochMillis() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<PlayerInfoProto> get playerInfo => $_getList(1);

  /// Named image of map.
  @$pb.TagNumber(3)
  $core.String get mapName => $_getSZ(2);
  @$pb.TagNumber(3)
  set mapName($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasMapName() => $_has(2);
  @$pb.TagNumber(3)
  void clearMapName() => clearField(3);

  /// Current acting commander player.
  @$pb.TagNumber(4)
  $core.String get actingCommanderId => $_getSZ(3);
  @$pb.TagNumber(4)
  set actingCommanderId($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasActingCommanderId() => $_has(3);
  @$pb.TagNumber(4)
  void clearActingCommanderId() => clearField(4);

  /// If non empty we have a winner.
  @$pb.TagNumber(5)
  $core.String get winnerPlayerId => $_getSZ(4);
  @$pb.TagNumber(5)
  set winnerPlayerId($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasWinnerPlayerId() => $_has(4);
  @$pb.TagNumber(5)
  void clearWinnerPlayerId() => clearField(5);
}

class PlayerInfoProto extends $pb.GeneratedMessage {
  factory PlayerInfoProto({
    $core.String? name,
    $core.String? connectionId,
    $core.int? spriteId,
    $core.int? score,
    $core.int? deaths,
    $core.double? fps,
    $fixnum.Int64? addedToGameEpochMillis,
    KeyStateProto? remoteKeyState,
    $core.bool? inGame,
    $core.Iterable<ConnectionInfoProto>? connectionInfo,
  }) {
    final $result = create();
    if (name != null) {
      $result.name = name;
    }
    if (connectionId != null) {
      $result.connectionId = connectionId;
    }
    if (spriteId != null) {
      $result.spriteId = spriteId;
    }
    if (score != null) {
      $result.score = score;
    }
    if (deaths != null) {
      $result.deaths = deaths;
    }
    if (fps != null) {
      $result.fps = fps;
    }
    if (addedToGameEpochMillis != null) {
      $result.addedToGameEpochMillis = addedToGameEpochMillis;
    }
    if (remoteKeyState != null) {
      $result.remoteKeyState = remoteKeyState;
    }
    if (inGame != null) {
      $result.inGame = inGame;
    }
    if (connectionInfo != null) {
      $result.connectionInfo.addAll(connectionInfo);
    }
    return $result;
  }
  PlayerInfoProto._() : super();
  factory PlayerInfoProto.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PlayerInfoProto.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PlayerInfoProto', package: const $pb.PackageName(_omitMessageNames ? '' : 'dart2d_proto'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOS(2, _omitFieldNames ? '' : 'connectionId')
    ..a<$core.int>(3, _omitFieldNames ? '' : 'spriteId', $pb.PbFieldType.O3)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'score', $pb.PbFieldType.O3)
    ..a<$core.int>(5, _omitFieldNames ? '' : 'deaths', $pb.PbFieldType.O3)
    ..a<$core.double>(6, _omitFieldNames ? '' : 'fps', $pb.PbFieldType.OF)
    ..aInt64(7, _omitFieldNames ? '' : 'addedToGameEpochMillis')
    ..aOM<KeyStateProto>(8, _omitFieldNames ? '' : 'remoteKeyState', subBuilder: KeyStateProto.create)
    ..aOB(9, _omitFieldNames ? '' : 'inGame')
    ..pc<ConnectionInfoProto>(10, _omitFieldNames ? '' : 'connectionInfo', $pb.PbFieldType.PM, subBuilder: ConnectionInfoProto.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PlayerInfoProto clone() => PlayerInfoProto()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PlayerInfoProto copyWith(void Function(PlayerInfoProto) updates) => super.copyWith((message) => updates(message as PlayerInfoProto)) as PlayerInfoProto;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PlayerInfoProto create() => PlayerInfoProto._();
  PlayerInfoProto createEmptyInstance() => create();
  static $pb.PbList<PlayerInfoProto> createRepeated() => $pb.PbList<PlayerInfoProto>();
  @$core.pragma('dart2js:noInline')
  static PlayerInfoProto getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PlayerInfoProto>(create);
  static PlayerInfoProto? _defaultInstance;

  /// User visible name.
  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => clearField(1);

  /// Connection in the mesh.
  @$pb.TagNumber(2)
  $core.String get connectionId => $_getSZ(1);
  @$pb.TagNumber(2)
  set connectionId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasConnectionId() => $_has(1);
  @$pb.TagNumber(2)
  void clearConnectionId() => clearField(2);

  /// World controlled sprite.
  @$pb.TagNumber(3)
  $core.int get spriteId => $_getIZ(2);
  @$pb.TagNumber(3)
  set spriteId($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasSpriteId() => $_has(2);
  @$pb.TagNumber(3)
  void clearSpriteId() => clearField(3);

  /// Score of player.
  @$pb.TagNumber(4)
  $core.int get score => $_getIZ(3);
  @$pb.TagNumber(4)
  set score($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasScore() => $_has(3);
  @$pb.TagNumber(4)
  void clearScore() => clearField(4);

  /// How many times it has died...
  @$pb.TagNumber(5)
  $core.int get deaths => $_getIZ(4);
  @$pb.TagNumber(5)
  set deaths($core.int v) { $_setSignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasDeaths() => $_has(4);
  @$pb.TagNumber(5)
  void clearDeaths() => clearField(5);

  /// Current reported FPS.
  @$pb.TagNumber(6)
  $core.double get fps => $_getN(5);
  @$pb.TagNumber(6)
  set fps($core.double v) { $_setFloat(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasFps() => $_has(5);
  @$pb.TagNumber(6)
  void clearFps() => clearField(6);

  /// When it joined the game.
  @$pb.TagNumber(7)
  $fixnum.Int64 get addedToGameEpochMillis => $_getI64(6);
  @$pb.TagNumber(7)
  set addedToGameEpochMillis($fixnum.Int64 v) { $_setInt64(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasAddedToGameEpochMillis() => $_has(6);
  @$pb.TagNumber(7)
  void clearAddedToGameEpochMillis() => clearField(7);

  /// What keys are down.
  @$pb.TagNumber(8)
  KeyStateProto get remoteKeyState => $_getN(7);
  @$pb.TagNumber(8)
  set remoteKeyState(KeyStateProto v) { setField(8, v); }
  @$pb.TagNumber(8)
  $core.bool hasRemoteKeyState() => $_has(7);
  @$pb.TagNumber(8)
  void clearRemoteKeyState() => clearField(8);
  @$pb.TagNumber(8)
  KeyStateProto ensureRemoteKeyState() => $_ensure(7);

  /// Player currently in the game.
  @$pb.TagNumber(9)
  $core.bool get inGame => $_getBF(8);
  @$pb.TagNumber(9)
  set inGame($core.bool v) { $_setBool(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasInGame() => $_has(8);
  @$pb.TagNumber(9)
  void clearInGame() => clearField(9);

  /// What connections this player has.
  @$pb.TagNumber(10)
  $core.List<ConnectionInfoProto> get connectionInfo => $_getList(9);
}

class ParticleEffects extends $pb.GeneratedMessage {
  factory ParticleEffects({
    Vec2Proto? position,
    Vec2Proto? velocity,
    $core.double? radius,
    $core.int? lifetimeFrames,
    $core.int? spriteLifetimeFrames,
    $core.double? shrinkPerStep,
    $core.int? particleCount,
    ParticleEffects_ParticleType? particleType,
    $core.int? followId,
    Vec2Proto? followOffset,
  }) {
    final $result = create();
    if (position != null) {
      $result.position = position;
    }
    if (velocity != null) {
      $result.velocity = velocity;
    }
    if (radius != null) {
      $result.radius = radius;
    }
    if (lifetimeFrames != null) {
      $result.lifetimeFrames = lifetimeFrames;
    }
    if (spriteLifetimeFrames != null) {
      $result.spriteLifetimeFrames = spriteLifetimeFrames;
    }
    if (shrinkPerStep != null) {
      $result.shrinkPerStep = shrinkPerStep;
    }
    if (particleCount != null) {
      $result.particleCount = particleCount;
    }
    if (particleType != null) {
      $result.particleType = particleType;
    }
    if (followId != null) {
      $result.followId = followId;
    }
    if (followOffset != null) {
      $result.followOffset = followOffset;
    }
    return $result;
  }
  ParticleEffects._() : super();
  factory ParticleEffects.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ParticleEffects.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ParticleEffects', package: const $pb.PackageName(_omitMessageNames ? '' : 'dart2d_proto'), createEmptyInstance: create)
    ..aOM<Vec2Proto>(1, _omitFieldNames ? '' : 'position', subBuilder: Vec2Proto.create)
    ..aOM<Vec2Proto>(2, _omitFieldNames ? '' : 'velocity', subBuilder: Vec2Proto.create)
    ..a<$core.double>(3, _omitFieldNames ? '' : 'radius', $pb.PbFieldType.OF)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'lifetimeFrames', $pb.PbFieldType.O3)
    ..a<$core.int>(5, _omitFieldNames ? '' : 'spriteLifetimeFrames', $pb.PbFieldType.O3)
    ..a<$core.double>(6, _omitFieldNames ? '' : 'shrinkPerStep', $pb.PbFieldType.OF)
    ..a<$core.int>(7, _omitFieldNames ? '' : 'particleCount', $pb.PbFieldType.O3)
    ..e<ParticleEffects_ParticleType>(8, _omitFieldNames ? '' : 'particleType', $pb.PbFieldType.OE, defaultOrMaker: ParticleEffects_ParticleType.UNSET, valueOf: ParticleEffects_ParticleType.valueOf, enumValues: ParticleEffects_ParticleType.values)
    ..a<$core.int>(10, _omitFieldNames ? '' : 'followId', $pb.PbFieldType.O3)
    ..aOM<Vec2Proto>(11, _omitFieldNames ? '' : 'followOffset', subBuilder: Vec2Proto.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ParticleEffects clone() => ParticleEffects()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ParticleEffects copyWith(void Function(ParticleEffects) updates) => super.copyWith((message) => updates(message as ParticleEffects)) as ParticleEffects;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ParticleEffects create() => ParticleEffects._();
  ParticleEffects createEmptyInstance() => create();
  static $pb.PbList<ParticleEffects> createRepeated() => $pb.PbList<ParticleEffects>();
  @$core.pragma('dart2js:noInline')
  static ParticleEffects getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ParticleEffects>(create);
  static ParticleEffects? _defaultInstance;

  /// Where it starts.
  @$pb.TagNumber(1)
  Vec2Proto get position => $_getN(0);
  @$pb.TagNumber(1)
  set position(Vec2Proto v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasPosition() => $_has(0);
  @$pb.TagNumber(1)
  void clearPosition() => clearField(1);
  @$pb.TagNumber(1)
  Vec2Proto ensurePosition() => $_ensure(0);

  /// Movement of particles.
  @$pb.TagNumber(2)
  Vec2Proto get velocity => $_getN(1);
  @$pb.TagNumber(2)
  set velocity(Vec2Proto v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasVelocity() => $_has(1);
  @$pb.TagNumber(2)
  void clearVelocity() => clearField(2);
  @$pb.TagNumber(2)
  Vec2Proto ensureVelocity() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.double get radius => $_getN(2);
  @$pb.TagNumber(3)
  set radius($core.double v) { $_setFloat(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasRadius() => $_has(2);
  @$pb.TagNumber(3)
  void clearRadius() => clearField(3);

  /// How many frames the individual particle pieces will live.
  @$pb.TagNumber(4)
  $core.int get lifetimeFrames => $_getIZ(3);
  @$pb.TagNumber(4)
  set lifetimeFrames($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasLifetimeFrames() => $_has(3);
  @$pb.TagNumber(4)
  void clearLifetimeFrames() => clearField(4);

  /// How long the entire particle sprite lives.
  @$pb.TagNumber(5)
  $core.int get spriteLifetimeFrames => $_getIZ(4);
  @$pb.TagNumber(5)
  set spriteLifetimeFrames($core.int v) { $_setSignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasSpriteLifetimeFrames() => $_has(4);
  @$pb.TagNumber(5)
  void clearSpriteLifetimeFrames() => clearField(5);

  /// Multiplied by it's size each frame.
  @$pb.TagNumber(6)
  $core.double get shrinkPerStep => $_getN(5);
  @$pb.TagNumber(6)
  set shrinkPerStep($core.double v) { $_setFloat(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasShrinkPerStep() => $_has(5);
  @$pb.TagNumber(6)
  void clearShrinkPerStep() => clearField(6);

  /// How many particle effects to spawn.
  @$pb.TagNumber(7)
  $core.int get particleCount => $_getIZ(6);
  @$pb.TagNumber(7)
  set particleCount($core.int v) { $_setSignedInt32(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasParticleCount() => $_has(6);
  @$pb.TagNumber(7)
  void clearParticleCount() => clearField(7);

  @$pb.TagNumber(8)
  ParticleEffects_ParticleType get particleType => $_getN(7);
  @$pb.TagNumber(8)
  set particleType(ParticleEffects_ParticleType v) { setField(8, v); }
  @$pb.TagNumber(8)
  $core.bool hasParticleType() => $_has(7);
  @$pb.TagNumber(8)
  void clearParticleType() => clearField(8);

  /// If the particle sprite should follow another particle.
  @$pb.TagNumber(10)
  $core.int get followId => $_getIZ(8);
  @$pb.TagNumber(10)
  set followId($core.int v) { $_setSignedInt32(8, v); }
  @$pb.TagNumber(10)
  $core.bool hasFollowId() => $_has(8);
  @$pb.TagNumber(10)
  void clearFollowId() => clearField(10);

  @$pb.TagNumber(11)
  Vec2Proto get followOffset => $_getN(9);
  @$pb.TagNumber(11)
  set followOffset(Vec2Proto v) { setField(11, v); }
  @$pb.TagNumber(11)
  $core.bool hasFollowOffset() => $_has(9);
  @$pb.TagNumber(11)
  void clearFollowOffset() => clearField(11);
  @$pb.TagNumber(11)
  Vec2Proto ensureFollowOffset() => $_ensure(9);
}

class ConnectionInfoProto extends $pb.GeneratedMessage {
  factory ConnectionInfoProto({
    $core.String? id,
    $core.int? latencyMillis,
  }) {
    final $result = create();
    if (id != null) {
      $result.id = id;
    }
    if (latencyMillis != null) {
      $result.latencyMillis = latencyMillis;
    }
    return $result;
  }
  ConnectionInfoProto._() : super();
  factory ConnectionInfoProto.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ConnectionInfoProto.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ConnectionInfoProto', package: const $pb.PackageName(_omitMessageNames ? '' : 'dart2d_proto'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..a<$core.int>(2, _omitFieldNames ? '' : 'latencyMillis', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ConnectionInfoProto clone() => ConnectionInfoProto()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ConnectionInfoProto copyWith(void Function(ConnectionInfoProto) updates) => super.copyWith((message) => updates(message as ConnectionInfoProto)) as ConnectionInfoProto;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConnectionInfoProto create() => ConnectionInfoProto._();
  ConnectionInfoProto createEmptyInstance() => create();
  static $pb.PbList<ConnectionInfoProto> createRepeated() => $pb.PbList<ConnectionInfoProto>();
  @$core.pragma('dart2js:noInline')
  static ConnectionInfoProto getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ConnectionInfoProto>(create);
  static ConnectionInfoProto? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => clearField(1);

  @$pb.TagNumber(2)
  $core.int get latencyMillis => $_getIZ(1);
  @$pb.TagNumber(2)
  set latencyMillis($core.int v) { $_setSignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasLatencyMillis() => $_has(1);
  @$pb.TagNumber(2)
  void clearLatencyMillis() => clearField(2);
}

class SpriteUpdate extends $pb.GeneratedMessage {
  factory SpriteUpdate({
    $core.int? spriteId,
    $core.int? flags,
    Vec2Proto? position,
    $core.double? angle,
    Vec2Proto? velocity,
    $core.int? remoteRepresentation,
    $core.int? spriteType,
    $core.int? imageId,
    $core.int? frames,
    $core.String? color,
    Vec2Proto? size,
    $core.double? rotationVelocity,
    ExtraSpriteData? extraSpriteData,
    ExtraSpriteData? commanderToOwnerData,
    $core.int? spawnSound,
    $core.int? removeSound,
    $core.int? lockedFrame,
  }) {
    final $result = create();
    if (spriteId != null) {
      $result.spriteId = spriteId;
    }
    if (flags != null) {
      $result.flags = flags;
    }
    if (position != null) {
      $result.position = position;
    }
    if (angle != null) {
      $result.angle = angle;
    }
    if (velocity != null) {
      $result.velocity = velocity;
    }
    if (remoteRepresentation != null) {
      $result.remoteRepresentation = remoteRepresentation;
    }
    if (spriteType != null) {
      $result.spriteType = spriteType;
    }
    if (imageId != null) {
      $result.imageId = imageId;
    }
    if (frames != null) {
      $result.frames = frames;
    }
    if (color != null) {
      $result.color = color;
    }
    if (size != null) {
      $result.size = size;
    }
    if (rotationVelocity != null) {
      $result.rotationVelocity = rotationVelocity;
    }
    if (extraSpriteData != null) {
      $result.extraSpriteData = extraSpriteData;
    }
    if (commanderToOwnerData != null) {
      $result.commanderToOwnerData = commanderToOwnerData;
    }
    if (spawnSound != null) {
      $result.spawnSound = spawnSound;
    }
    if (removeSound != null) {
      $result.removeSound = removeSound;
    }
    if (lockedFrame != null) {
      $result.lockedFrame = lockedFrame;
    }
    return $result;
  }
  SpriteUpdate._() : super();
  factory SpriteUpdate.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SpriteUpdate.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'SpriteUpdate', package: const $pb.PackageName(_omitMessageNames ? '' : 'dart2d_proto'), createEmptyInstance: create)
    ..a<$core.int>(1, _omitFieldNames ? '' : 'spriteId', $pb.PbFieldType.O3)
    ..a<$core.int>(2, _omitFieldNames ? '' : 'flags', $pb.PbFieldType.O3)
    ..aOM<Vec2Proto>(3, _omitFieldNames ? '' : 'position', subBuilder: Vec2Proto.create)
    ..a<$core.double>(4, _omitFieldNames ? '' : 'angle', $pb.PbFieldType.OF)
    ..aOM<Vec2Proto>(5, _omitFieldNames ? '' : 'velocity', subBuilder: Vec2Proto.create)
    ..a<$core.int>(6, _omitFieldNames ? '' : 'remoteRepresentation', $pb.PbFieldType.O3)
    ..a<$core.int>(7, _omitFieldNames ? '' : 'spriteType', $pb.PbFieldType.O3)
    ..a<$core.int>(8, _omitFieldNames ? '' : 'imageId', $pb.PbFieldType.O3)
    ..a<$core.int>(9, _omitFieldNames ? '' : 'frames', $pb.PbFieldType.O3)
    ..aOS(10, _omitFieldNames ? '' : 'color')
    ..aOM<Vec2Proto>(11, _omitFieldNames ? '' : 'size', subBuilder: Vec2Proto.create)
    ..a<$core.double>(12, _omitFieldNames ? '' : 'rotationVelocity', $pb.PbFieldType.OF)
    ..aOM<ExtraSpriteData>(13, _omitFieldNames ? '' : 'extraSpriteData', subBuilder: ExtraSpriteData.create)
    ..aOM<ExtraSpriteData>(14, _omitFieldNames ? '' : 'commanderToOwnerData', subBuilder: ExtraSpriteData.create)
    ..a<$core.int>(15, _omitFieldNames ? '' : 'spawnSound', $pb.PbFieldType.O3)
    ..a<$core.int>(16, _omitFieldNames ? '' : 'removeSound', $pb.PbFieldType.O3)
    ..a<$core.int>(17, _omitFieldNames ? '' : 'lockedFrame', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SpriteUpdate clone() => SpriteUpdate()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SpriteUpdate copyWith(void Function(SpriteUpdate) updates) => super.copyWith((message) => updates(message as SpriteUpdate)) as SpriteUpdate;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SpriteUpdate create() => SpriteUpdate._();
  SpriteUpdate createEmptyInstance() => create();
  static $pb.PbList<SpriteUpdate> createRepeated() => $pb.PbList<SpriteUpdate>();
  @$core.pragma('dart2js:noInline')
  static SpriteUpdate getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SpriteUpdate>(create);
  static SpriteUpdate? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get spriteId => $_getIZ(0);
  @$pb.TagNumber(1)
  set spriteId($core.int v) { $_setSignedInt32(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSpriteId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSpriteId() => clearField(1);

  /// Flags set.
  @$pb.TagNumber(2)
  $core.int get flags => $_getIZ(1);
  @$pb.TagNumber(2)
  set flags($core.int v) { $_setSignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasFlags() => $_has(1);
  @$pb.TagNumber(2)
  void clearFlags() => clearField(2);

  @$pb.TagNumber(3)
  Vec2Proto get position => $_getN(2);
  @$pb.TagNumber(3)
  set position(Vec2Proto v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasPosition() => $_has(2);
  @$pb.TagNumber(3)
  void clearPosition() => clearField(3);
  @$pb.TagNumber(3)
  Vec2Proto ensurePosition() => $_ensure(2);

  @$pb.TagNumber(4)
  $core.double get angle => $_getN(3);
  @$pb.TagNumber(4)
  set angle($core.double v) { $_setFloat(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasAngle() => $_has(3);
  @$pb.TagNumber(4)
  void clearAngle() => clearField(4);

  @$pb.TagNumber(5)
  Vec2Proto get velocity => $_getN(4);
  @$pb.TagNumber(5)
  set velocity(Vec2Proto v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasVelocity() => $_has(4);
  @$pb.TagNumber(5)
  void clearVelocity() => clearField(5);
  @$pb.TagNumber(5)
  Vec2Proto ensureVelocity() => $_ensure(4);

  /// The Sprite constructor to run.
  @$pb.TagNumber(6)
  $core.int get remoteRepresentation => $_getIZ(5);
  @$pb.TagNumber(6)
  set remoteRepresentation($core.int v) { $_setSignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasRemoteRepresentation() => $_has(5);
  @$pb.TagNumber(6)
  void clearRemoteRepresentation() => clearField(6);

  /// What type of ImageSprite this is.
  @$pb.TagNumber(7)
  $core.int get spriteType => $_getIZ(6);
  @$pb.TagNumber(7)
  set spriteType($core.int v) { $_setSignedInt32(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasSpriteType() => $_has(6);
  @$pb.TagNumber(7)
  void clearSpriteType() => clearField(7);

  /// Typically only one of these are set.
  @$pb.TagNumber(8)
  $core.int get imageId => $_getIZ(7);
  @$pb.TagNumber(8)
  set imageId($core.int v) { $_setSignedInt32(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasImageId() => $_has(7);
  @$pb.TagNumber(8)
  void clearImageId() => clearField(8);

  /// Animation frames of above image.
  @$pb.TagNumber(9)
  $core.int get frames => $_getIZ(8);
  @$pb.TagNumber(9)
  set frames($core.int v) { $_setSignedInt32(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasFrames() => $_has(8);
  @$pb.TagNumber(9)
  void clearFrames() => clearField(9);

  /// Or color.
  @$pb.TagNumber(10)
  $core.String get color => $_getSZ(9);
  @$pb.TagNumber(10)
  set color($core.String v) { $_setString(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasColor() => $_has(9);
  @$pb.TagNumber(10)
  void clearColor() => clearField(10);

  @$pb.TagNumber(11)
  Vec2Proto get size => $_getN(10);
  @$pb.TagNumber(11)
  set size(Vec2Proto v) { setField(11, v); }
  @$pb.TagNumber(11)
  $core.bool hasSize() => $_has(10);
  @$pb.TagNumber(11)
  void clearSize() => clearField(11);
  @$pb.TagNumber(11)
  Vec2Proto ensureSize() => $_ensure(10);

  @$pb.TagNumber(12)
  $core.double get rotationVelocity => $_getN(11);
  @$pb.TagNumber(12)
  set rotationVelocity($core.double v) { $_setFloat(11, v); }
  @$pb.TagNumber(12)
  $core.bool hasRotationVelocity() => $_has(11);
  @$pb.TagNumber(12)
  void clearRotationVelocity() => clearField(12);

  /// Sprite specific data.
  @$pb.TagNumber(13)
  ExtraSpriteData get extraSpriteData => $_getN(12);
  @$pb.TagNumber(13)
  set extraSpriteData(ExtraSpriteData v) { setField(13, v); }
  @$pb.TagNumber(13)
  $core.bool hasExtraSpriteData() => $_has(12);
  @$pb.TagNumber(13)
  void clearExtraSpriteData() => clearField(13);
  @$pb.TagNumber(13)
  ExtraSpriteData ensureExtraSpriteData() => $_ensure(12);

  /// Data flowing from a commander to the owner of the sprite.
  /// This may be the only field set.
  @$pb.TagNumber(14)
  ExtraSpriteData get commanderToOwnerData => $_getN(13);
  @$pb.TagNumber(14)
  set commanderToOwnerData(ExtraSpriteData v) { setField(14, v); }
  @$pb.TagNumber(14)
  $core.bool hasCommanderToOwnerData() => $_has(13);
  @$pb.TagNumber(14)
  void clearCommanderToOwnerData() => clearField(14);
  @$pb.TagNumber(14)
  ExtraSpriteData ensureCommanderToOwnerData() => $_ensure(13);

  /// Play this sound when sprite is added to world.
  /// Will be paused when sprite is removed.
  @$pb.TagNumber(15)
  $core.int get spawnSound => $_getIZ(14);
  @$pb.TagNumber(15)
  set spawnSound($core.int v) { $_setSignedInt32(14, v); }
  @$pb.TagNumber(15)
  $core.bool hasSpawnSound() => $_has(14);
  @$pb.TagNumber(15)
  void clearSpawnSound() => clearField(15);

  /// Play this sound when sprite is removed from the world.
  @$pb.TagNumber(16)
  $core.int get removeSound => $_getIZ(15);
  @$pb.TagNumber(16)
  set removeSound($core.int v) { $_setSignedInt32(15, v); }
  @$pb.TagNumber(16)
  $core.bool hasRemoveSound() => $_has(15);
  @$pb.TagNumber(16)
  void clearRemoveSound() => clearField(16);

  /// If set, the image will be locked to only showing
  /// this frame and not animate.
  @$pb.TagNumber(17)
  $core.int get lockedFrame => $_getIZ(16);
  @$pb.TagNumber(17)
  set lockedFrame($core.int v) { $_setSignedInt32(16, v); }
  @$pb.TagNumber(17)
  $core.bool hasLockedFrame() => $_has(16);
  @$pb.TagNumber(17)
  void clearLockedFrame() => clearField(17);
}

class ExtraSpriteData extends $pb.GeneratedMessage {
  factory ExtraSpriteData({
    $core.Iterable<$core.int>? extraInt,
    $core.Iterable<$core.double>? extraFloat,
    $core.Iterable<$core.String>? extraString,
    $core.Iterable<$core.bool>? extraBool,
  }) {
    final $result = create();
    if (extraInt != null) {
      $result.extraInt.addAll(extraInt);
    }
    if (extraFloat != null) {
      $result.extraFloat.addAll(extraFloat);
    }
    if (extraString != null) {
      $result.extraString.addAll(extraString);
    }
    if (extraBool != null) {
      $result.extraBool.addAll(extraBool);
    }
    return $result;
  }
  ExtraSpriteData._() : super();
  factory ExtraSpriteData.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ExtraSpriteData.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ExtraSpriteData', package: const $pb.PackageName(_omitMessageNames ? '' : 'dart2d_proto'), createEmptyInstance: create)
    ..p<$core.int>(1, _omitFieldNames ? '' : 'extraInt', $pb.PbFieldType.P3)
    ..p<$core.double>(2, _omitFieldNames ? '' : 'extraFloat', $pb.PbFieldType.PF)
    ..pPS(3, _omitFieldNames ? '' : 'extraString')
    ..p<$core.bool>(4, _omitFieldNames ? '' : 'extraBool', $pb.PbFieldType.PB)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ExtraSpriteData clone() => ExtraSpriteData()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ExtraSpriteData copyWith(void Function(ExtraSpriteData) updates) => super.copyWith((message) => updates(message as ExtraSpriteData)) as ExtraSpriteData;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ExtraSpriteData create() => ExtraSpriteData._();
  ExtraSpriteData createEmptyInstance() => create();
  static $pb.PbList<ExtraSpriteData> createRepeated() => $pb.PbList<ExtraSpriteData>();
  @$core.pragma('dart2js:noInline')
  static ExtraSpriteData getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ExtraSpriteData>(create);
  static ExtraSpriteData? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get extraInt => $_getList(0);

  @$pb.TagNumber(2)
  $core.List<$core.double> get extraFloat => $_getList(1);

  @$pb.TagNumber(3)
  $core.List<$core.String> get extraString => $_getList(2);

  @$pb.TagNumber(4)
  $core.List<$core.bool> get extraBool => $_getList(3);
}

class WebRtcDanceProto extends $pb.GeneratedMessage {
  factory WebRtcDanceProto({
    $core.String? sdp,
    $core.Iterable<$core.String>? candidates,
    $core.String? sdpType,
  }) {
    final $result = create();
    if (sdp != null) {
      $result.sdp = sdp;
    }
    if (candidates != null) {
      $result.candidates.addAll(candidates);
    }
    if (sdpType != null) {
      $result.sdpType = sdpType;
    }
    return $result;
  }
  WebRtcDanceProto._() : super();
  factory WebRtcDanceProto.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory WebRtcDanceProto.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'WebRtcDanceProto', package: const $pb.PackageName(_omitMessageNames ? '' : 'dart2d_proto'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'sdp')
    ..pPS(2, _omitFieldNames ? '' : 'candidates')
    ..aOS(3, _omitFieldNames ? '' : 'sdpType')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  WebRtcDanceProto clone() => WebRtcDanceProto()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  WebRtcDanceProto copyWith(void Function(WebRtcDanceProto) updates) => super.copyWith((message) => updates(message as WebRtcDanceProto)) as WebRtcDanceProto;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static WebRtcDanceProto create() => WebRtcDanceProto._();
  WebRtcDanceProto createEmptyInstance() => create();
  static $pb.PbList<WebRtcDanceProto> createRepeated() => $pb.PbList<WebRtcDanceProto>();
  @$core.pragma('dart2js:noInline')
  static WebRtcDanceProto getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<WebRtcDanceProto>(create);
  static WebRtcDanceProto? _defaultInstance;

  /// Raw SDP string.
  @$pb.TagNumber(1)
  $core.String get sdp => $_getSZ(0);
  @$pb.TagNumber(1)
  set sdp($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSdp() => $_has(0);
  @$pb.TagNumber(1)
  void clearSdp() => clearField(1);

  /// Raw ICE candidates.
  @$pb.TagNumber(2)
  $core.List<$core.String> get candidates => $_getList(1);

  /// Offer or answer etc.
  @$pb.TagNumber(3)
  $core.String get sdpType => $_getSZ(2);
  @$pb.TagNumber(3)
  set sdpType($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasSdpType() => $_has(2);
  @$pb.TagNumber(3)
  void clearSdpType() => clearField(3);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
