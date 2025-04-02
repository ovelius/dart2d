//
//  Generated code. Do not modify.
//  source: dart2d/lib/net/state_updates.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use gameStateUpdatesDescriptor instead')
const GameStateUpdates$json = {
  '1': 'GameStateUpdates',
  '2': [
    {'1': 'last_key_frame', '3': 1, '4': 1, '5': 5, '10': 'lastKeyFrame'},
    {'1': 'state_update', '3': 2, '4': 3, '5': 11, '6': '.dart2d_proto.StateUpdate', '10': 'stateUpdate'},
    {'1': 'key_frame_delay_ms', '3': 3, '4': 1, '5': 5, '10': 'keyFrameDelayMs'},
    {'1': 'sprite_updates', '3': 4, '4': 3, '5': 11, '6': '.dart2d_proto.SpriteUpdate', '10': 'spriteUpdates'},
  ],
};

/// Descriptor for `GameStateUpdates`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List gameStateUpdatesDescriptor = $convert.base64Decode(
    'ChBHYW1lU3RhdGVVcGRhdGVzEiQKDmxhc3Rfa2V5X2ZyYW1lGAEgASgFUgxsYXN0S2V5RnJhbW'
    'USPAoMc3RhdGVfdXBkYXRlGAIgAygLMhkuZGFydDJkX3Byb3RvLlN0YXRlVXBkYXRlUgtzdGF0'
    'ZVVwZGF0ZRIrChJrZXlfZnJhbWVfZGVsYXlfbXMYAyABKAVSD2tleUZyYW1lRGVsYXlNcxJBCg'
    '5zcHJpdGVfdXBkYXRlcxgEIAMoCzIaLmRhcnQyZF9wcm90by5TcHJpdGVVcGRhdGVSDXNwcml0'
    'ZVVwZGF0ZXM=');

@$core.Deprecated('Use stateUpdateDescriptor instead')
const StateUpdate$json = {
  '1': 'StateUpdate',
  '2': [
    {'1': 'data_receipt', '3': 1, '4': 1, '5': 5, '10': 'dataReceipt'},
    {'1': 'key_frame', '3': 2, '4': 1, '5': 5, '9': 0, '10': 'keyFrame'},
    {'1': 'user_message', '3': 3, '4': 1, '5': 9, '9': 0, '10': 'userMessage'},
    {'1': 'sprite_removal', '3': 4, '4': 1, '5': 5, '9': 0, '10': 'spriteRemoval'},
    {'1': 'game_state', '3': 5, '4': 1, '5': 11, '6': '.dart2d_proto.GameStateProto', '9': 0, '10': 'gameState'},
    {'1': 'key_state', '3': 6, '4': 1, '5': 11, '6': '.dart2d_proto.KeyStateProto', '9': 0, '10': 'keyState'},
    {'1': 'client_player_spec', '3': 7, '4': 1, '5': 11, '6': '.dart2d_proto.ClientPlayerSpec', '9': 0, '10': 'clientPlayerSpec'},
    {'1': 'commander_game_reply', '3': 8, '4': 1, '5': 11, '6': '.dart2d_proto.CommanderGameReply', '9': 0, '10': 'commanderGameReply'},
    {'1': 'client_enter', '3': 9, '4': 1, '5': 8, '9': 0, '10': 'clientEnter'},
    {'1': 'acked_data_receipts', '3': 10, '4': 1, '5': 5, '9': 0, '10': 'ackedDataReceipts'},
    {'1': 'ping', '3': 11, '4': 1, '5': 8, '9': 0, '10': 'ping'},
    {'1': 'pong', '3': 12, '4': 1, '5': 8, '9': 0, '10': 'pong'},
    {'1': 'other_player_world_select', '3': 13, '4': 1, '5': 11, '6': '.dart2d_proto.OtherPlayerWorldSelect', '9': 0, '10': 'otherPlayerWorldSelect'},
    {'1': 'transfer_command', '3': 14, '4': 1, '5': 8, '9': 0, '10': 'transferCommand'},
    {'1': 'byte_world_destruction', '3': 15, '4': 1, '5': 11, '6': '.dart2d_proto.ByteWorldDestruction', '9': 0, '10': 'byteWorldDestruction'},
    {'1': 'byte_world_draw', '3': 16, '4': 1, '5': 11, '6': '.dart2d_proto.ByteWorldDraw', '9': 0, '10': 'byteWorldDraw'},
    {'1': 'particle_effects', '3': 17, '4': 1, '5': 11, '6': '.dart2d_proto.ParticleEffects', '9': 0, '10': 'particleEffects'},
    {'1': 'client_status_data', '3': 18, '4': 1, '5': 11, '6': '.dart2d_proto.ClientStatusData', '9': 0, '10': 'clientStatusData'},
    {'1': 'resource_request', '3': 19, '4': 1, '5': 11, '6': '.dart2d_proto.ResourceRequest', '9': 0, '10': 'resourceRequest'},
    {'1': 'resource_response', '3': 20, '4': 1, '5': 11, '6': '.dart2d_proto.ResourceResponse', '9': 0, '10': 'resourceResponse'},
  ],
  '8': [
    {'1': 'update'},
  ],
};

/// Descriptor for `StateUpdate`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List stateUpdateDescriptor = $convert.base64Decode(
    'CgtTdGF0ZVVwZGF0ZRIhCgxkYXRhX3JlY2VpcHQYASABKAVSC2RhdGFSZWNlaXB0Eh0KCWtleV'
    '9mcmFtZRgCIAEoBUgAUghrZXlGcmFtZRIjCgx1c2VyX21lc3NhZ2UYAyABKAlIAFILdXNlck1l'
    'c3NhZ2USJwoOc3ByaXRlX3JlbW92YWwYBCABKAVIAFINc3ByaXRlUmVtb3ZhbBI9CgpnYW1lX3'
    'N0YXRlGAUgASgLMhwuZGFydDJkX3Byb3RvLkdhbWVTdGF0ZVByb3RvSABSCWdhbWVTdGF0ZRI6'
    'CglrZXlfc3RhdGUYBiABKAsyGy5kYXJ0MmRfcHJvdG8uS2V5U3RhdGVQcm90b0gAUghrZXlTdG'
    'F0ZRJOChJjbGllbnRfcGxheWVyX3NwZWMYByABKAsyHi5kYXJ0MmRfcHJvdG8uQ2xpZW50UGxh'
    'eWVyU3BlY0gAUhBjbGllbnRQbGF5ZXJTcGVjElQKFGNvbW1hbmRlcl9nYW1lX3JlcGx5GAggAS'
    'gLMiAuZGFydDJkX3Byb3RvLkNvbW1hbmRlckdhbWVSZXBseUgAUhJjb21tYW5kZXJHYW1lUmVw'
    'bHkSIwoMY2xpZW50X2VudGVyGAkgASgISABSC2NsaWVudEVudGVyEjAKE2Fja2VkX2RhdGFfcm'
    'VjZWlwdHMYCiABKAVIAFIRYWNrZWREYXRhUmVjZWlwdHMSFAoEcGluZxgLIAEoCEgAUgRwaW5n'
    'EhQKBHBvbmcYDCABKAhIAFIEcG9uZxJhChlvdGhlcl9wbGF5ZXJfd29ybGRfc2VsZWN0GA0gAS'
    'gLMiQuZGFydDJkX3Byb3RvLk90aGVyUGxheWVyV29ybGRTZWxlY3RIAFIWb3RoZXJQbGF5ZXJX'
    'b3JsZFNlbGVjdBIrChB0cmFuc2Zlcl9jb21tYW5kGA4gASgISABSD3RyYW5zZmVyQ29tbWFuZB'
    'JaChZieXRlX3dvcmxkX2Rlc3RydWN0aW9uGA8gASgLMiIuZGFydDJkX3Byb3RvLkJ5dGVXb3Js'
    'ZERlc3RydWN0aW9uSABSFGJ5dGVXb3JsZERlc3RydWN0aW9uEkUKD2J5dGVfd29ybGRfZHJhdx'
    'gQIAEoCzIbLmRhcnQyZF9wcm90by5CeXRlV29ybGREcmF3SABSDWJ5dGVXb3JsZERyYXcSSgoQ'
    'cGFydGljbGVfZWZmZWN0cxgRIAEoCzIdLmRhcnQyZF9wcm90by5QYXJ0aWNsZUVmZmVjdHNIAF'
    'IPcGFydGljbGVFZmZlY3RzEk4KEmNsaWVudF9zdGF0dXNfZGF0YRgSIAEoCzIeLmRhcnQyZF9w'
    'cm90by5DbGllbnRTdGF0dXNEYXRhSABSEGNsaWVudFN0YXR1c0RhdGESSgoQcmVzb3VyY2Vfcm'
    'VxdWVzdBgTIAEoCzIdLmRhcnQyZF9wcm90by5SZXNvdXJjZVJlcXVlc3RIAFIPcmVzb3VyY2VS'
    'ZXF1ZXN0Ek0KEXJlc291cmNlX3Jlc3BvbnNlGBQgASgLMh4uZGFydDJkX3Byb3RvLlJlc291cm'
    'NlUmVzcG9uc2VIAFIQcmVzb3VyY2VSZXNwb25zZUIICgZ1cGRhdGU=');

@$core.Deprecated('Use clientStatusDataDescriptor instead')
const ClientStatusData$json = {
  '1': 'ClientStatusData',
  '2': [
    {'1': 'fps', '3': 1, '4': 1, '5': 5, '10': 'fps'},
    {'1': 'connection_info', '3': 2, '4': 3, '5': 11, '6': '.dart2d_proto.ConnectionInfoProto', '10': 'connectionInfo'},
  ],
};

/// Descriptor for `ClientStatusData`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List clientStatusDataDescriptor = $convert.base64Decode(
    'ChBDbGllbnRTdGF0dXNEYXRhEhAKA2ZwcxgBIAEoBVIDZnBzEkoKD2Nvbm5lY3Rpb25faW5mbx'
    'gCIAMoCzIhLmRhcnQyZF9wcm90by5Db25uZWN0aW9uSW5mb1Byb3RvUg5jb25uZWN0aW9uSW5m'
    'bw==');

@$core.Deprecated('Use resourceResponseDescriptor instead')
const ResourceResponse$json = {
  '1': 'ResourceResponse',
  '2': [
    {'1': 'resource_index', '3': 1, '4': 1, '5': 5, '10': 'resourceIndex'},
    {'1': 'start_byte', '3': 2, '4': 1, '5': 5, '10': 'startByte'},
    {'1': 'data', '3': 3, '4': 1, '5': 12, '10': 'data'},
  ],
};

/// Descriptor for `ResourceResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List resourceResponseDescriptor = $convert.base64Decode(
    'ChBSZXNvdXJjZVJlc3BvbnNlEiUKDnJlc291cmNlX2luZGV4GAEgASgFUg1yZXNvdXJjZUluZG'
    'V4Eh0KCnN0YXJ0X2J5dGUYAiABKAVSCXN0YXJ0Qnl0ZRISCgRkYXRhGAMgASgMUgRkYXRh');

@$core.Deprecated('Use resourceRequestDescriptor instead')
const ResourceRequest$json = {
  '1': 'ResourceRequest',
  '2': [
    {'1': 'resource_index', '3': 1, '4': 1, '5': 5, '10': 'resourceIndex'},
    {'1': 'start_byte', '3': 2, '4': 1, '5': 5, '10': 'startByte'},
    {'1': 'end_byte', '3': 3, '4': 1, '5': 5, '10': 'endByte'},
  ],
};

/// Descriptor for `ResourceRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List resourceRequestDescriptor = $convert.base64Decode(
    'Cg9SZXNvdXJjZVJlcXVlc3QSJQoOcmVzb3VyY2VfaW5kZXgYASABKAVSDXJlc291cmNlSW5kZX'
    'gSHQoKc3RhcnRfYnl0ZRgCIAEoBVIJc3RhcnRCeXRlEhkKCGVuZF9ieXRlGAMgASgFUgdlbmRC'
    'eXRl');

@$core.Deprecated('Use byteWorldDestructionDescriptor instead')
const ByteWorldDestruction$json = {
  '1': 'ByteWorldDestruction',
  '2': [
    {'1': 'position', '3': 1, '4': 1, '5': 11, '6': '.dart2d_proto.Vec2Proto', '10': 'position'},
    {'1': 'radius', '3': 2, '4': 1, '5': 2, '10': 'radius'},
  ],
};

/// Descriptor for `ByteWorldDestruction`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List byteWorldDestructionDescriptor = $convert.base64Decode(
    'ChRCeXRlV29ybGREZXN0cnVjdGlvbhIzCghwb3NpdGlvbhgBIAEoCzIXLmRhcnQyZF9wcm90by'
    '5WZWMyUHJvdG9SCHBvc2l0aW9uEhYKBnJhZGl1cxgCIAEoAlIGcmFkaXVz');

@$core.Deprecated('Use byteWorldDrawDescriptor instead')
const ByteWorldDraw$json = {
  '1': 'ByteWorldDraw',
  '2': [
    {'1': 'position', '3': 1, '4': 1, '5': 11, '6': '.dart2d_proto.Vec2Proto', '10': 'position'},
    {'1': 'size', '3': 2, '4': 1, '5': 11, '6': '.dart2d_proto.Vec2Proto', '10': 'size'},
    {'1': 'color', '3': 3, '4': 1, '5': 9, '10': 'color'},
  ],
};

/// Descriptor for `ByteWorldDraw`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List byteWorldDrawDescriptor = $convert.base64Decode(
    'Cg1CeXRlV29ybGREcmF3EjMKCHBvc2l0aW9uGAEgASgLMhcuZGFydDJkX3Byb3RvLlZlYzJQcm'
    '90b1IIcG9zaXRpb24SKwoEc2l6ZRgCIAEoCzIXLmRhcnQyZF9wcm90by5WZWMyUHJvdG9SBHNp'
    'emUSFAoFY29sb3IYAyABKAlSBWNvbG9y');

@$core.Deprecated('Use otherPlayerWorldSelectDescriptor instead')
const OtherPlayerWorldSelect$json = {
  '1': 'OtherPlayerWorldSelect',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {'1': 'world_selected', '3': 2, '4': 1, '5': 9, '10': 'worldSelected'},
  ],
};

/// Descriptor for `OtherPlayerWorldSelect`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List otherPlayerWorldSelectDescriptor = $convert.base64Decode(
    'ChZPdGhlclBsYXllcldvcmxkU2VsZWN0EhIKBG5hbWUYASABKAlSBG5hbWUSJQoOd29ybGRfc2'
    'VsZWN0ZWQYAiABKAlSDXdvcmxkU2VsZWN0ZWQ=');

@$core.Deprecated('Use commanderGameReplyDescriptor instead')
const CommanderGameReply$json = {
  '1': 'CommanderGameReply',
  '2': [
    {'1': 'challenge_reply', '3': 1, '4': 1, '5': 14, '6': '.dart2d_proto.CommanderGameReply.ChallengeReply', '10': 'challengeReply'},
    {'1': 'game_state', '3': 2, '4': 1, '5': 11, '6': '.dart2d_proto.GameStateProto', '10': 'gameState'},
    {'1': 'sprite_index_start', '3': 3, '4': 1, '5': 5, '10': 'spriteIndexStart'},
    {'1': 'starting_position', '3': 4, '4': 1, '5': 11, '6': '.dart2d_proto.Vec2Proto', '10': 'startingPosition'},
  ],
  '4': [CommanderGameReply_ChallengeReply$json],
};

@$core.Deprecated('Use commanderGameReplyDescriptor instead')
const CommanderGameReply_ChallengeReply$json = {
  '1': 'ChallengeReply',
  '2': [
    {'1': 'UNSET', '2': 0},
    {'1': 'ACCEPT', '2': 1},
    {'1': 'REJECT_FULL', '2': 2},
  ],
};

/// Descriptor for `CommanderGameReply`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List commanderGameReplyDescriptor = $convert.base64Decode(
    'ChJDb21tYW5kZXJHYW1lUmVwbHkSWAoPY2hhbGxlbmdlX3JlcGx5GAEgASgOMi8uZGFydDJkX3'
    'Byb3RvLkNvbW1hbmRlckdhbWVSZXBseS5DaGFsbGVuZ2VSZXBseVIOY2hhbGxlbmdlUmVwbHkS'
    'OwoKZ2FtZV9zdGF0ZRgCIAEoCzIcLmRhcnQyZF9wcm90by5HYW1lU3RhdGVQcm90b1IJZ2FtZV'
    'N0YXRlEiwKEnNwcml0ZV9pbmRleF9zdGFydBgDIAEoBVIQc3ByaXRlSW5kZXhTdGFydBJEChFz'
    'dGFydGluZ19wb3NpdGlvbhgEIAEoCzIXLmRhcnQyZF9wcm90by5WZWMyUHJvdG9SEHN0YXJ0aW'
    '5nUG9zaXRpb24iOAoOQ2hhbGxlbmdlUmVwbHkSCQoFVU5TRVQQABIKCgZBQ0NFUFQQARIPCgtS'
    'RUpFQ1RfRlVMTBAC');

@$core.Deprecated('Use vec2ProtoDescriptor instead')
const Vec2Proto$json = {
  '1': 'Vec2Proto',
  '2': [
    {'1': 'x', '3': 1, '4': 1, '5': 2, '10': 'x'},
    {'1': 'y', '3': 2, '4': 1, '5': 2, '10': 'y'},
  ],
};

/// Descriptor for `Vec2Proto`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List vec2ProtoDescriptor = $convert.base64Decode(
    'CglWZWMyUHJvdG8SDAoBeBgBIAEoAlIBeBIMCgF5GAIgASgCUgF5');

@$core.Deprecated('Use keyStateProtoDescriptor instead')
const KeyStateProto$json = {
  '1': 'KeyStateProto',
  '2': [
    {'1': 'keys_down', '3': 1, '4': 3, '5': 5, '10': 'keysDown'},
  ],
};

/// Descriptor for `KeyStateProto`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List keyStateProtoDescriptor = $convert.base64Decode(
    'Cg1LZXlTdGF0ZVByb3RvEhsKCWtleXNfZG93bhgBIAMoBVIIa2V5c0Rvd24=');

@$core.Deprecated('Use clientPlayerSpecDescriptor instead')
const ClientPlayerSpec$json = {
  '1': 'ClientPlayerSpec',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
  ],
};

/// Descriptor for `ClientPlayerSpec`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List clientPlayerSpecDescriptor = $convert.base64Decode(
    'ChBDbGllbnRQbGF5ZXJTcGVjEhIKBG5hbWUYASABKAlSBG5hbWU=');

@$core.Deprecated('Use gameStateProtoDescriptor instead')
const GameStateProto$json = {
  '1': 'GameStateProto',
  '2': [
    {'1': 'started_at_epoch_millis', '3': 1, '4': 1, '5': 3, '10': 'startedAtEpochMillis'},
    {'1': 'player_info', '3': 2, '4': 3, '5': 11, '6': '.dart2d_proto.PlayerInfoProto', '10': 'playerInfo'},
    {'1': 'map_name', '3': 3, '4': 1, '5': 9, '10': 'mapName'},
    {'1': 'acting_commander_id', '3': 4, '4': 1, '5': 9, '10': 'actingCommanderId'},
    {'1': 'winner_player_id', '3': 5, '4': 1, '5': 9, '10': 'winnerPlayerId'},
  ],
};

/// Descriptor for `GameStateProto`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List gameStateProtoDescriptor = $convert.base64Decode(
    'Cg5HYW1lU3RhdGVQcm90bxI1ChdzdGFydGVkX2F0X2Vwb2NoX21pbGxpcxgBIAEoA1IUc3Rhcn'
    'RlZEF0RXBvY2hNaWxsaXMSPgoLcGxheWVyX2luZm8YAiADKAsyHS5kYXJ0MmRfcHJvdG8uUGxh'
    'eWVySW5mb1Byb3RvUgpwbGF5ZXJJbmZvEhkKCG1hcF9uYW1lGAMgASgJUgdtYXBOYW1lEi4KE2'
    'FjdGluZ19jb21tYW5kZXJfaWQYBCABKAlSEWFjdGluZ0NvbW1hbmRlcklkEigKEHdpbm5lcl9w'
    'bGF5ZXJfaWQYBSABKAlSDndpbm5lclBsYXllcklk');

@$core.Deprecated('Use playerInfoProtoDescriptor instead')
const PlayerInfoProto$json = {
  '1': 'PlayerInfoProto',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {'1': 'connection_id', '3': 2, '4': 1, '5': 9, '10': 'connectionId'},
    {'1': 'sprite_id', '3': 3, '4': 1, '5': 5, '10': 'spriteId'},
    {'1': 'score', '3': 4, '4': 1, '5': 5, '10': 'score'},
    {'1': 'deaths', '3': 5, '4': 1, '5': 5, '10': 'deaths'},
    {'1': 'fps', '3': 6, '4': 1, '5': 5, '10': 'fps'},
    {'1': 'added_to_game_epoch_millis', '3': 7, '4': 1, '5': 3, '10': 'addedToGameEpochMillis'},
    {'1': 'remote_key_state', '3': 8, '4': 1, '5': 11, '6': '.dart2d_proto.KeyStateProto', '10': 'remoteKeyState'},
    {'1': 'in_game', '3': 9, '4': 1, '5': 8, '10': 'inGame'},
    {'1': 'connection_info', '3': 10, '4': 3, '5': 11, '6': '.dart2d_proto.ConnectionInfoProto', '10': 'connectionInfo'},
  ],
};

/// Descriptor for `PlayerInfoProto`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List playerInfoProtoDescriptor = $convert.base64Decode(
    'Cg9QbGF5ZXJJbmZvUHJvdG8SEgoEbmFtZRgBIAEoCVIEbmFtZRIjCg1jb25uZWN0aW9uX2lkGA'
    'IgASgJUgxjb25uZWN0aW9uSWQSGwoJc3ByaXRlX2lkGAMgASgFUghzcHJpdGVJZBIUCgVzY29y'
    'ZRgEIAEoBVIFc2NvcmUSFgoGZGVhdGhzGAUgASgFUgZkZWF0aHMSEAoDZnBzGAYgASgFUgNmcH'
    'MSOgoaYWRkZWRfdG9fZ2FtZV9lcG9jaF9taWxsaXMYByABKANSFmFkZGVkVG9HYW1lRXBvY2hN'
    'aWxsaXMSRQoQcmVtb3RlX2tleV9zdGF0ZRgIIAEoCzIbLmRhcnQyZF9wcm90by5LZXlTdGF0ZV'
    'Byb3RvUg5yZW1vdGVLZXlTdGF0ZRIXCgdpbl9nYW1lGAkgASgIUgZpbkdhbWUSSgoPY29ubmVj'
    'dGlvbl9pbmZvGAogAygLMiEuZGFydDJkX3Byb3RvLkNvbm5lY3Rpb25JbmZvUHJvdG9SDmNvbm'
    '5lY3Rpb25JbmZv');

@$core.Deprecated('Use particleEffectsDescriptor instead')
const ParticleEffects$json = {
  '1': 'ParticleEffects',
  '2': [
    {'1': 'position', '3': 1, '4': 1, '5': 11, '6': '.dart2d_proto.Vec2Proto', '10': 'position'},
    {'1': 'velocity', '3': 2, '4': 1, '5': 11, '6': '.dart2d_proto.Vec2Proto', '10': 'velocity'},
    {'1': 'radius', '3': 3, '4': 1, '5': 2, '10': 'radius'},
    {'1': 'lifetime_frames', '3': 4, '4': 1, '5': 5, '10': 'lifetimeFrames'},
    {'1': 'sprite_lifetime_frames', '3': 5, '4': 1, '5': 5, '10': 'spriteLifetimeFrames'},
    {'1': 'shrink_per_step', '3': 6, '4': 1, '5': 2, '10': 'shrinkPerStep'},
    {'1': 'particle_count', '3': 7, '4': 1, '5': 5, '10': 'particleCount'},
    {'1': 'particle_type', '3': 8, '4': 1, '5': 14, '6': '.dart2d_proto.ParticleEffects.ParticleType', '10': 'particleType'},
    {'1': 'follow_id', '3': 10, '4': 1, '5': 5, '10': 'followId'},
    {'1': 'follow_offset', '3': 11, '4': 1, '5': 11, '6': '.dart2d_proto.Vec2Proto', '10': 'followOffset'},
  ],
  '4': [ParticleEffects_ParticleType$json],
};

@$core.Deprecated('Use particleEffectsDescriptor instead')
const ParticleEffects_ParticleType$json = {
  '1': 'ParticleType',
  '2': [
    {'1': 'UNSET', '2': 0},
    {'1': 'COLORFUL', '2': 1},
    {'1': 'FIRE', '2': 2},
    {'1': 'SODA', '2': 3},
  ],
};

/// Descriptor for `ParticleEffects`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List particleEffectsDescriptor = $convert.base64Decode(
    'Cg9QYXJ0aWNsZUVmZmVjdHMSMwoIcG9zaXRpb24YASABKAsyFy5kYXJ0MmRfcHJvdG8uVmVjMl'
    'Byb3RvUghwb3NpdGlvbhIzCgh2ZWxvY2l0eRgCIAEoCzIXLmRhcnQyZF9wcm90by5WZWMyUHJv'
    'dG9SCHZlbG9jaXR5EhYKBnJhZGl1cxgDIAEoAlIGcmFkaXVzEicKD2xpZmV0aW1lX2ZyYW1lcx'
    'gEIAEoBVIObGlmZXRpbWVGcmFtZXMSNAoWc3ByaXRlX2xpZmV0aW1lX2ZyYW1lcxgFIAEoBVIU'
    'c3ByaXRlTGlmZXRpbWVGcmFtZXMSJgoPc2hyaW5rX3Blcl9zdGVwGAYgASgCUg1zaHJpbmtQZX'
    'JTdGVwEiUKDnBhcnRpY2xlX2NvdW50GAcgASgFUg1wYXJ0aWNsZUNvdW50Ek8KDXBhcnRpY2xl'
    'X3R5cGUYCCABKA4yKi5kYXJ0MmRfcHJvdG8uUGFydGljbGVFZmZlY3RzLlBhcnRpY2xlVHlwZV'
    'IMcGFydGljbGVUeXBlEhsKCWZvbGxvd19pZBgKIAEoBVIIZm9sbG93SWQSPAoNZm9sbG93X29m'
    'ZnNldBgLIAEoCzIXLmRhcnQyZF9wcm90by5WZWMyUHJvdG9SDGZvbGxvd09mZnNldCI7CgxQYX'
    'J0aWNsZVR5cGUSCQoFVU5TRVQQABIMCghDT0xPUkZVTBABEggKBEZJUkUQAhIICgRTT0RBEAM=');

@$core.Deprecated('Use connectionInfoProtoDescriptor instead')
const ConnectionInfoProto$json = {
  '1': 'ConnectionInfoProto',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'latency_millis', '3': 2, '4': 1, '5': 5, '10': 'latencyMillis'},
  ],
};

/// Descriptor for `ConnectionInfoProto`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List connectionInfoProtoDescriptor = $convert.base64Decode(
    'ChNDb25uZWN0aW9uSW5mb1Byb3RvEg4KAmlkGAEgASgJUgJpZBIlCg5sYXRlbmN5X21pbGxpcx'
    'gCIAEoBVINbGF0ZW5jeU1pbGxpcw==');

@$core.Deprecated('Use spriteUpdateDescriptor instead')
const SpriteUpdate$json = {
  '1': 'SpriteUpdate',
  '2': [
    {'1': 'sprite_id', '3': 1, '4': 1, '5': 5, '10': 'spriteId'},
    {'1': 'flags', '3': 2, '4': 1, '5': 5, '10': 'flags'},
    {'1': 'position', '3': 3, '4': 1, '5': 11, '6': '.dart2d_proto.Vec2Proto', '10': 'position'},
    {'1': 'angle', '3': 4, '4': 1, '5': 2, '10': 'angle'},
    {'1': 'velocity', '3': 5, '4': 1, '5': 11, '6': '.dart2d_proto.Vec2Proto', '10': 'velocity'},
    {'1': 'remote_representation', '3': 6, '4': 1, '5': 5, '10': 'remoteRepresentation'},
    {'1': 'sprite_type', '3': 7, '4': 1, '5': 5, '10': 'spriteType'},
    {'1': 'image_id', '3': 8, '4': 1, '5': 5, '10': 'imageId'},
    {'1': 'frames', '3': 9, '4': 1, '5': 5, '10': 'frames'},
    {'1': 'color', '3': 10, '4': 1, '5': 9, '10': 'color'},
    {'1': 'size', '3': 11, '4': 1, '5': 11, '6': '.dart2d_proto.Vec2Proto', '10': 'size'},
    {'1': 'rotation_velocity', '3': 12, '4': 1, '5': 2, '10': 'rotationVelocity'},
    {'1': 'extra_sprite_data', '3': 13, '4': 1, '5': 11, '6': '.dart2d_proto.ExtraSpriteData', '10': 'extraSpriteData'},
  ],
};

/// Descriptor for `SpriteUpdate`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List spriteUpdateDescriptor = $convert.base64Decode(
    'CgxTcHJpdGVVcGRhdGUSGwoJc3ByaXRlX2lkGAEgASgFUghzcHJpdGVJZBIUCgVmbGFncxgCIA'
    'EoBVIFZmxhZ3MSMwoIcG9zaXRpb24YAyABKAsyFy5kYXJ0MmRfcHJvdG8uVmVjMlByb3RvUghw'
    'b3NpdGlvbhIUCgVhbmdsZRgEIAEoAlIFYW5nbGUSMwoIdmVsb2NpdHkYBSABKAsyFy5kYXJ0Mm'
    'RfcHJvdG8uVmVjMlByb3RvUgh2ZWxvY2l0eRIzChVyZW1vdGVfcmVwcmVzZW50YXRpb24YBiAB'
    'KAVSFHJlbW90ZVJlcHJlc2VudGF0aW9uEh8KC3Nwcml0ZV90eXBlGAcgASgFUgpzcHJpdGVUeX'
    'BlEhkKCGltYWdlX2lkGAggASgFUgdpbWFnZUlkEhYKBmZyYW1lcxgJIAEoBVIGZnJhbWVzEhQK'
    'BWNvbG9yGAogASgJUgVjb2xvchIrCgRzaXplGAsgASgLMhcuZGFydDJkX3Byb3RvLlZlYzJQcm'
    '90b1IEc2l6ZRIrChFyb3RhdGlvbl92ZWxvY2l0eRgMIAEoAlIQcm90YXRpb25WZWxvY2l0eRJJ'
    'ChFleHRyYV9zcHJpdGVfZGF0YRgNIAEoCzIdLmRhcnQyZF9wcm90by5FeHRyYVNwcml0ZURhdG'
    'FSD2V4dHJhU3ByaXRlRGF0YQ==');

@$core.Deprecated('Use extraSpriteDataDescriptor instead')
const ExtraSpriteData$json = {
  '1': 'ExtraSpriteData',
  '2': [
    {'1': 'extra_int', '3': 1, '4': 3, '5': 5, '10': 'extraInt'},
    {'1': 'extra_float', '3': 2, '4': 3, '5': 2, '10': 'extraFloat'},
    {'1': 'extra_string', '3': 3, '4': 3, '5': 9, '10': 'extraString'},
  ],
};

/// Descriptor for `ExtraSpriteData`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List extraSpriteDataDescriptor = $convert.base64Decode(
    'Cg9FeHRyYVNwcml0ZURhdGESGwoJZXh0cmFfaW50GAEgAygFUghleHRyYUludBIfCgtleHRyYV'
    '9mbG9hdBgCIAMoAlIKZXh0cmFGbG9hdBIhCgxleHRyYV9zdHJpbmcYAyADKAlSC2V4dHJhU3Ry'
    'aW5n');

