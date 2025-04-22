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

import 'package:protobuf/protobuf.dart' as $pb;

class CommanderGameReply_ChallengeReply extends $pb.ProtobufEnum {
  static const CommanderGameReply_ChallengeReply UNSET = CommanderGameReply_ChallengeReply._(0, _omitEnumNames ? '' : 'UNSET');
  static const CommanderGameReply_ChallengeReply ACCEPT = CommanderGameReply_ChallengeReply._(1, _omitEnumNames ? '' : 'ACCEPT');
  static const CommanderGameReply_ChallengeReply REJECT_FULL = CommanderGameReply_ChallengeReply._(2, _omitEnumNames ? '' : 'REJECT_FULL');
  static const CommanderGameReply_ChallengeReply REJECT_ENDED = CommanderGameReply_ChallengeReply._(3, _omitEnumNames ? '' : 'REJECT_ENDED');

  static const $core.List<CommanderGameReply_ChallengeReply> values = <CommanderGameReply_ChallengeReply> [
    UNSET,
    ACCEPT,
    REJECT_FULL,
    REJECT_ENDED,
  ];

  static final $core.Map<$core.int, CommanderGameReply_ChallengeReply> _byValue = $pb.ProtobufEnum.initByValue(values);
  static CommanderGameReply_ChallengeReply? valueOf($core.int value) => _byValue[value];

  const CommanderGameReply_ChallengeReply._($core.int v, $core.String n) : super(v, n);
}

class ParticleEffects_ParticleType extends $pb.ProtobufEnum {
  static const ParticleEffects_ParticleType UNSET = ParticleEffects_ParticleType._(0, _omitEnumNames ? '' : 'UNSET');
  static const ParticleEffects_ParticleType COLORFUL = ParticleEffects_ParticleType._(1, _omitEnumNames ? '' : 'COLORFUL');
  static const ParticleEffects_ParticleType FIRE = ParticleEffects_ParticleType._(2, _omitEnumNames ? '' : 'FIRE');
  static const ParticleEffects_ParticleType SODA = ParticleEffects_ParticleType._(3, _omitEnumNames ? '' : 'SODA');
  static const ParticleEffects_ParticleType CONFETTI = ParticleEffects_ParticleType._(4, _omitEnumNames ? '' : 'CONFETTI');
  static const ParticleEffects_ParticleType BLOOD = ParticleEffects_ParticleType._(5, _omitEnumNames ? '' : 'BLOOD');

  static const $core.List<ParticleEffects_ParticleType> values = <ParticleEffects_ParticleType> [
    UNSET,
    COLORFUL,
    FIRE,
    SODA,
    CONFETTI,
    BLOOD,
  ];

  static final $core.Map<$core.int, ParticleEffects_ParticleType> _byValue = $pb.ProtobufEnum.initByValue(values);
  static ParticleEffects_ParticleType? valueOf($core.int value) => _byValue[value];

  const ParticleEffects_ParticleType._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');
