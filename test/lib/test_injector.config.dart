// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:dart2d/bindings/annotations.dart' as _i988;
import 'package:dart2d/net/chunk_helper.dart' as _i600;
import 'package:dart2d/net/helpers.dart' as _i207;
import 'package:dart2d/net/net.dart' as _i835;
import 'package:dart2d/net/network.dart' as _i64;
import 'package:dart2d/res/imageindex.dart' as _i883;
import 'package:dart2d/res/sounds.dart' as _i254;
import 'package:dart2d/sprites/sprite_index.dart' as _i577;
import 'package:dart2d/sprites/sprites.dart' as _i899;
import 'package:dart2d/util/bot.dart' as _i481;
import 'package:dart2d/util/config_params.dart' as _i364;
import 'package:dart2d/util/fps_counter.dart' as _i339;
import 'package:dart2d/util/gamestate.dart' as _i333;
import 'package:dart2d/util/hud_messages.dart' as _i106;
import 'package:dart2d/util/keystate.dart' as _i906;
import 'package:dart2d/util/mobile_controls.dart' as _i31;
import 'package:dart2d/util/util.dart' as _i559;
import 'package:dart2d/worlds/byteworld.dart' as _i401;
import 'package:dart2d/worlds/loader.dart' as _i537;
import 'package:dart2d/worlds/player_world_selector.dart' as _i394;
import 'package:dart2d/worlds/powerup_manager.dart' as _i745;
import 'package:dart2d/worlds/world_listener.dart' as _i241;
import 'package:dart2d/worlds/worm_world.dart' as _i112;
import 'package:get_it/get_it.dart' as _i174;
import 'package:injectable/injectable.dart' as _i526;

import 'fake_canvas.dart' as _i983;
import 'test_env.dart' as _i47;
import 'test_factories.dart' as _i418;
import 'test_peer.dart' as _i886;

extension GetItInjectableX on _i174.GetIt {
// initializes the registration of main-scope dependencies inside of GetIt
  _i174.GetIt init({
    String? environment,
    _i526.EnvironmentFilter? environmentFilter,
  }) {
    final gh = _i526.GetItHelper(
      this,
      environment,
      environmentFilter,
    );
    final envModule = _$EnvModule();
    gh.factory<_i418.TestConnectionFactory>(
        () => envModule.getConnectionFactory);
    gh.factory<_i983.FakeImageFactory>(() => envModule.getImageFactory);
    gh.factory<int>(
      () => envModule.width,
      instanceName: 'world_width',
    );
    gh.factory<_i988.ImageDataFactory>(() => _i983.FakeImageDataFactory());
    gh.factory<bool>(
      () => envModule.touch,
      instanceName: 'touch_supported',
    );
    gh.factory<_i988.WorldCanvas>(() => _i983.FakeCanvas());
    gh.singleton<_i988.ConnectionFactory>(() => _i418.TestConnectionFactory());
    gh.factory<int>(
      () => envModule.height,
      instanceName: 'world_height',
    );
    gh.factory<Function>(
      () => envModule.reload,
      instanceName: 'reload_function',
    );
    gh.factory<_i988.HtmlScreen>(() => _i983.FakeScreen());
    gh.singleton<_i988.SoundFactory>(() => _i418.FakeSoundFactory());
    gh.factory<_i988.GaReporter>(() => _i47.FakeGaReporter());
    gh.factory<_i988.CanvasFactory>(() => _i47.FakeCanvasFactory());
    gh.factory<_i988.ServerChannel>(() => _i886.TestServerChannel());
    gh.factory<Map<String, List<String>>>(
      () => envModule.params,
      instanceName: 'uri_params_map',
    );
    gh.factory<_i481.Bot>(() => _i481.Bot(
          gh<_i559.GameState>(),
          gh<_i899.SpriteIndex>(),
          gh<_i559.SelfPlayerInfoProvider>(),
          gh<_i559.KeyState>(),
        ));
    gh.factory<_i241.WorldListener>(() => _i241.WorldListener(
          gh<_i835.PacketListenerBindings>(),
          gh<_i401.ByteWorld>(),
          gh<_i333.GameState>(),
          gh<_i835.Network>(),
          gh<_i106.HudMessages>(),
          gh<_i31.MobileControls>(),
        ));
    return this;
  }

// initializes the registration of world-scope dependencies inside of GetIt
  _i174.GetIt initWorldScope({_i174.ScopeDisposeFunc? dispose}) {
    return _i526.GetItHelper(this).initScope(
      'world',
      dispose: dispose,
      init: (_i526.GetItHelper gh) {
        gh.singleton<_i988.ImageFactory>(() => _i983.FakeImageFactory());
        gh.singleton<_i207.PacketListenerBindings>(
            () => _i207.PacketListenerBindings());
        gh.singleton<_i577.SpriteIndex>(() => _i577.SpriteIndex());
        gh.singleton<_i339.FpsCounter>(() => _i339.FpsCounter());
        gh.singleton<_i906.KeyState>(() => _i906.KeyState());
        gh.singleton<_i364.ConfigParams>(() => _i364.ConfigParams(
            gh<Map<String, List<String>>>(instanceName: 'uri_params_map')));
        gh.singleton<_i401.ByteWorld>(() => _i401.ByteWorld(
              gh<_i988.ImageFactory>(),
              gh<int>(instanceName: 'world_width'),
              gh<int>(instanceName: 'world_height'),
              gh<_i988.ImageDataFactory>(),
              gh<_i988.CanvasFactory>(),
            ));
        gh.singleton<_i988.LocalStorage>(() => _i47.TestLocalStorage());
        gh.singleton<_i254.Sounds>(
            () => _i254.Sounds(gh<_i988.SoundFactory>()));
        gh.singleton<_i106.HudMessages>(() => _i106.HudMessages(
              gh<_i906.KeyState>(),
              gh<_i207.PacketListenerBindings>(),
            ));
        gh.singleton<_i333.GameState>(() => _i333.GameState(
              gh<_i207.PacketListenerBindings>(),
              gh<_i899.SpriteIndex>(),
            ));
        gh.singleton<_i883.ImageIndex>(() => _i883.ImageIndex(
              gh<_i559.ConfigParams>(),
              gh<_i988.LocalStorage>(),
              gh<_i988.CanvasFactory>(),
              gh<_i988.ImageFactory>(),
            ));
        gh.singleton<_i600.ChunkHelper>(() => _i600.ChunkHelper(
              gh<_i883.ImageIndex>(),
              gh<_i401.ByteWorld>(),
              gh<_i835.PacketListenerBindings>(),
            ));
        gh.singleton<_i745.PowerupManager>(() => _i745.PowerupManager(
              gh<_i899.SpriteIndex>(),
              gh<_i883.ImageIndex>(),
              gh<_i401.ByteWorld>(),
            ));
        gh.singleton<_i64.Network>(() => _i64.Network(
              gh<_i988.GaReporter>(),
              gh<_i988.ConnectionFactory>(),
              gh<_i559.HudMessages>(),
              gh<_i559.GameState>(),
              gh<_i207.PacketListenerBindings>(),
              gh<_i559.FpsCounter>(),
              gh<_i988.ServerChannel>(),
              gh<_i559.ConfigParams>(),
              gh<_i899.SpriteIndex>(),
              gh<_i559.KeyState>(),
            ));
        gh.singleton<_i559.SelfPlayerInfoProvider>(
            () => _i559.SelfPlayerInfoProvider(gh<_i835.Network>()));
        gh.singleton<_i31.MobileControls>(() => _i31.MobileControls(
              gh<_i559.SelfPlayerInfoProvider>(),
              gh<_i559.ConfigParams>(),
              gh<_i559.Bot>(),
              gh<_i988.HtmlScreen>(),
              gh<_i559.KeyState>(),
              gh<bool>(instanceName: 'touch_supported'),
              gh<_i988.WorldCanvas>(),
            ));
        gh.singleton<_i394.PlayerWorldSelector>(() => _i394.PlayerWorldSelector(
              gh<_i835.PacketListenerBindings>(),
              gh<_i835.Network>(),
              gh<_i559.MobileControls>(),
              gh<_i883.ImageIndex>(),
              gh<_i988.GaReporter>(),
              gh<_i559.ConfigParams>(),
              gh<_i988.LocalStorage>(),
              gh<_i559.KeyState>(),
              gh<_i988.WorldCanvas>(),
            ));
        gh.singleton<_i537.Loader>(() => _i537.Loader(
              gh<_i988.LocalStorage>(),
              gh<_i988.WorldCanvas>(),
              gh<_i394.PlayerWorldSelector>(),
              gh<_i883.ImageIndex>(),
              gh<_i835.Network>(),
              gh<_i835.ChunkHelper>(),
              gh<_i401.ByteWorld>(),
            ));
        gh.singleton<_i112.WormWorld>(() => _i112.WormWorld(
              gh<_i64.Network>(),
              gh<_i537.Loader>(),
              gh<Function>(instanceName: 'reload_function'),
              gh<_i559.KeyState>(),
              gh<_i988.WorldCanvas>(),
              gh<_i988.LocalStorage>(),
              gh<_i559.FpsCounter>(),
              gh<_i899.SpriteIndex>(),
              gh<_i883.ImageIndex>(),
              gh<_i559.ConfigParams>(),
              gh<_i745.PowerupManager>(),
              gh<_i988.GaReporter>(),
              gh<_i254.Sounds>(),
              gh<_i600.ChunkHelper>(),
              gh<_i401.ByteWorld>(),
              gh<_i559.HudMessages>(),
              gh<_i241.WorldListener>(),
              gh<_i559.MobileControls>(),
              gh<_i207.PacketListenerBindings>(),
            ));
      },
    );
  }
}

class _$EnvModule extends _i47.EnvModule {}
