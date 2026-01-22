// ignore_for_file: prefer_const_constructors
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:gamepads/gamepads.dart';

/// MiniGamePage provides a top-down FTC-themed mini-game.
/// It features robot movement, shooting mechanics, bot AI, and gamepad support.
class MiniGamePage extends StatefulWidget {
  const MiniGamePage({super.key});

  @override
  State<MiniGamePage> createState() => _MiniGamePageState();
}

enum TeamColor { blue, red }
enum ProjectileOwner { player, bot }

class _MiniGamePageState extends State<MiniGamePage>
    with SingleTickerProviderStateMixin {
  // Field dimensions in meters (FTC field is roughly 3.66m x 3.66m)
  static const double fieldSizeMeters = 3.66;
  static const double robotSizeInches = 22.0;
  static const Duration gameDuration = Duration(minutes: 2);

  // Scaled pixel values calculated in build()
  late double fieldSizePx = 0;
  late double robotSizePx = 0;
  late double scaleFactor = 0;

  // ======================
  // SETTINGS
  // ======================
  final bool botsHaveUnlimitedAmmo = false;
  final int maxAmmo = 3;

  // Bot reload time: fixed 1 second
  final Duration botReloadFixedDuration = Duration(seconds: 1);

  // Cooldown between shots for bots (in milliseconds)
  final int botShotCooldownMs = 140;

  // Bot movement parameters for smoother behavior
  final double botSpeedMetersPerSecond = 0.62;
  final double botSteerGain = 3.6;
  final double botDampingGain = 2.4;
  final double botStrafeWobble = 0.18;
  final double botHoldJitter = 0.05;

  // Player movement speed
  final double moveSpeedMetersPerSecond = 1.30;

  // Player state
  Offset playerPos = Offset.zero;
  double playerAngle = -pi / 2;
  double playerTurretAngle = -pi / 2;

  Offset _playerVel = Offset.zero;
  final double accelMetersPerSec2 = 1.2;
  final double frictionMetersPerSec2 = 1.6;

  // Control mode: Field Centric vs Robot Centric
  bool fieldCentric = false;

  // Player ammo and reloading state
  int playerAmmo = 3;
  bool playerReloading = false;
  double playerReloadProgress = 0;
  DateTime? playerReloadStartTime;
  Duration playerReloadDuration = Duration(seconds: 1);

  DateTime playerLastShotTime =
  DateTime.now().subtract(const Duration(seconds: 1));

  final Random _rng = Random();
  late List<BotState> bots;

  double _simTime = 0;

  final List<Projectile> projectiles = [];
  double projectileRadius = 0;

  double reloadZoneSize = 0;
  Duration remaining = gameDuration;

  late Ticker _ticker;
  final FocusNode _focusNode = FocusNode();

  int blueScore = 0;
  int redScore = 0;

  // Collision handling parameters
  final double pushStrength = 0.9;
  final double minSeparation = 0.5;

  // ======================
  // GAMEPAD SUPPORT
  // ======================
  StreamSubscription<GamepadEvent>? _subEvent;
  Timer? _padPollTimer;
  String? activeGamepadId;
  bool _padConnected = false;

  // Common gamepad mappings (may vary by controller)
  double gpLeftX = 0;
  double gpLeftY = 0;
  double gpRightX = 0;

  bool gpShootPressed = false;
  bool gpBumperL = false;
  bool gpBumperR = false;

  final double deadZone = 0.18;

  // Turning speeds
  final double playerTurretTurnSpeedRadPerSec = pi * 0.8;
  final double playerTurnSpeedRadPerSec = pi * 1.2;

  // ======================
  // ON-SCREEN CONTROLS
  // ======================
  Offset uiLeftStick = Offset.zero; // Range: [-1, 1]
  Offset uiRightStick = Offset.zero;
  bool uiShoot = false;
  bool uiTurnL = false;
  bool uiTurnR = false;

  bool _spawned = false;

  @override
  void initState() {
    super.initState();

    // Initialize bot states
    bots = [
      BotState.initial(id: "B1", team: TeamColor.blue, maxAmmo: maxAmmo),
      BotState.initial(id: "B2", team: TeamColor.blue, maxAmmo: maxAmmo),
      BotState.initial(id: "R1", team: TeamColor.red, maxAmmo: maxAmmo),
    ];

    // Start game ticker
    _ticker = createTicker(_onTick)..start();
    _initGamepad();

    // Ensure focus for keyboard input
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) FocusScope.of(context).requestFocus(_focusNode);
    });
  }

  // ======================
  // GAMEPAD INITIALIZATION
  // ======================
  int? _keyIndex(String key) {
    final m = RegExp(r'\d+').firstMatch(key);
    if (m == null) return null;
    return int.tryParse(m.group(0)!);
  }

  // Apply deadzone to analog inputs
  double _dz(double v) => (v.abs() < deadZone) ? 0.0 : v;

  Future<void> _initGamepad() async {
    // Initial gamepad scan
    try {
      final pads = await Gamepads.list();
      if (pads.isNotEmpty) {
        activeGamepadId = pads.first.id;
        _padConnected = true;
      }
    } catch (_) {}

    // Listen for live gamepad events
    _subEvent = Gamepads.events.listen((event) {
      activeGamepadId ??= event.gamepadId;
      if (event.gamepadId != activeGamepadId) return;

      _padConnected = true;

      final idx = _keyIndex(event.key);

      if (event.type == KeyType.analog) {
        final v = _dz(event.value.toDouble());

        // Typical mapping: 0=LX, 1=LY, 2=RX (some controllers use 3 for RY)
        if (idx == 0) gpLeftX = v;
        if (idx == 1) gpLeftY = v;
        if (idx == 2) gpRightX = v;

        // Fallback for RX if it's on axis 3
        if (idx == 3 && gpRightX == 0) gpRightX = v;
      }

      if (event.type == KeyType.button) {
        final pressed = event.value > 0.5;
        if (idx == 0) gpShootPressed = pressed; // A or Cross button
        if (idx == 4) gpBumperL = pressed; // Left Bumper
        if (idx == 5) gpBumperR = pressed; // Right Bumper
      }
    });

    // Periodically poll for connection status updates
    _padPollTimer?.cancel();
    _padPollTimer = Timer.periodic(const Duration(milliseconds: 250), (_) async {
      bool any = false;
      try {
        final pads = await Gamepads.list();
        any = pads.isNotEmpty;
        if (pads.isNotEmpty) activeGamepadId ??= pads.first.id;
      } catch (_) {}

      if (!mounted) return;
      setState(() => _padConnected = any);
    });
  }

  // ======================
  // GEOMETRY & ZONES
  // ======================
  Rect _robotRect(Offset center) => Rect.fromCenter(
    center: center,
    width: robotSizePx,
    height: robotSizePx,
  );

  bool _pointInTopLeftTriangle(Offset p) {
    if (p.dx < 0 || p.dy < 0) return false;
    return (p.dx + p.dy) <= reloadZoneSize;
  }

  bool _pointInTopRightTriangle(Offset p) {
    if (p.dx > fieldSizePx || p.dy < 0) return false;
    final dx = fieldSizePx - p.dx;
    return (dx + p.dy) <= reloadZoneSize;
  }

  // Check if robot hit forbidden areas (e.g. goals)
  bool _rectHitsForbidden(Rect r) {
    final pts = <Offset>[
      r.topLeft,
      r.topRight,
      r.bottomLeft,
      r.bottomRight,
      Offset((r.left + r.right) / 2, r.top),
      Offset((r.left + r.right) / 2, r.bottom),
      Offset(r.left, (r.top + r.bottom) / 2),
      Offset(r.right, (r.top + r.bottom) / 2),
    ];
    for (final p in pts) {
      if (_pointInTopLeftTriangle(p) || _pointInTopRightTriangle(p)) return true;
    }
    return false;
  }

  bool _inAnyReloadZone(Offset pos) {
    final inBottom = pos.dy > fieldSizePx - reloadZoneSize;
    final inLeft = pos.dx < reloadZoneSize;
    final inRight = pos.dx > fieldSizePx - reloadZoneSize;
    return inBottom && (inLeft || inRight);
  }

  bool _inTeamReloadZone(TeamColor team, Offset pos) {
    final inBottom = pos.dy > fieldSizePx - reloadZoneSize;
    if (!inBottom) return false;
    final inLeft = pos.dx < reloadZoneSize;
    final inRight = pos.dx > fieldSizePx - reloadZoneSize;
    // Red -> Left, Blue -> Right
    return team == TeamColor.red ? inLeft : inRight;
  }

  Offset _teamReloadTarget(TeamColor team) {
    final left =
    Offset(reloadZoneSize * 0.5, fieldSizePx - reloadZoneSize * 0.5);
    final right = Offset(
      fieldSizePx - reloadZoneSize * 0.5,
      fieldSizePx - reloadZoneSize * 0.5,
    );
    return team == TeamColor.red ? left : right;
  }

  // Shooting zones (Rectangular and Triangular areas)
  bool _inBottomShootRectCenter(Offset c) {
    final r = Rect.fromLTWH(
      fieldSizePx * 2 / 6,
      fieldSizePx - fieldSizePx / 6,
      fieldSizePx * 2 / 6,
      fieldSizePx / 6,
    );
    return r.contains(c);
  }

  bool _inTopShootTriangleCenter(Offset c) {
    final topHeight = fieldSizePx / 2;
    if (c.dy < 0 || c.dy > topHeight) return false;
    final centerX = fieldSizePx / 2;
    final allowedX = (fieldSizePx / 2) * (1 - (c.dy / topHeight));
    return (c.dx - centerX).abs() <= allowedX;
  }

  bool _inShootZoneCenter(Offset c) =>
      _inBottomShootRectCenter(c) || _inTopShootTriangleCenter(c);

  // Check if a point is within a goal
  TeamColor? _goalAt(Offset p) {
    final inBlue = p.dx <= reloadZoneSize && p.dy <= reloadZoneSize;
    final inRed =
        p.dx >= fieldSizePx - reloadZoneSize && p.dy <= reloadZoneSize;

    if (inBlue) return TeamColor.blue;
    if (inRed) return TeamColor.red;
    return null;
  }

  Offset _goalCenter(TeamColor team) {
    if (team == TeamColor.blue) {
      return Offset(reloadZoneSize * 0.35, reloadZoneSize * 0.35);
    }
    return Offset(fieldSizePx - reloadZoneSize * 0.35, reloadZoneSize * 0.35);
  }

  bool _inBounds(Offset p) =>
      p.dx >= 0 && p.dy >= 0 && p.dx <= fieldSizePx && p.dy <= fieldSizePx;

  // ======================
  // SPAWNING
  // ======================
  void _spawnIfNeeded() {
    if (_spawned) return;
    if (fieldSizePx <= 0 || robotSizePx <= 0) return;

    playerPos = Offset(fieldSizePx * 0.65, fieldSizePx * 0.65);

    final c = Offset(fieldSizePx / 2, fieldSizePx / 2);

    bots[0] = bots[0].copyWith(
      pos: c + Offset(-robotSizePx * 2.8, -robotSizePx),
      target: _pickShootTarget(bots[0].team, 0),
      nextTargetAt: DateTime.now().subtract(Duration(seconds: 1)),
      ammo: maxAmmo,
      reloading: false,
      reloadProgress: 0,
      reloadStartTime: null,
      reloadDuration: botReloadFixedDuration,
      vel: Offset(1, 0),
    );

    bots[1] = bots[1].copyWith(
      pos: c + Offset(-robotSizePx * 2.8, robotSizePx),
      target: _pickShootTarget(bots[1].team, 1),
      nextTargetAt: DateTime.now().subtract(Duration(seconds: 1)),
      ammo: maxAmmo,
      reloading: false,
      reloadProgress: 0,
      reloadStartTime: null,
      reloadDuration: botReloadFixedDuration,
      vel: Offset(0, 1),
    );

    bots[2] = bots[2].copyWith(
      pos: c + Offset(robotSizePx * 2.8, 0),
      target: _pickShootTarget(bots[2].team, 2),
      nextTargetAt: DateTime.now().subtract(Duration(seconds: 1)),
      ammo: maxAmmo,
      reloading: false,
      reloadProgress: 0,
      reloadStartTime: null,
      reloadDuration: botReloadFixedDuration,
      vel: Offset(-1, 0),
    );

    _spawned = true;
  }

  // ======================
  // MOVEMENT CALCULATIONS
  // ======================
  double _wrap(double a) {
    while (a > pi) a -= 2 * pi;
    while (a < -pi) a += 2 * pi;
    return a;
  }

  Offset _clampLen(Offset v, double maxLen) {
    final d = v.distance;
    if (d <= maxLen || d == 0) return v;
    return v / d * maxLen;
  }

  MoveResult _applyDrivePlayer({
    required Offset pos,
    required double angle,
    required Offset velWorld,
    required double driveX,
    required double driveY,
    required double dt,
    required bool fieldCentricMode,
    required double maxSpeedMetersPerSec,
  }) {
    final speedPxPerSec = maxSpeedMetersPerSec * scaleFactor;
    final maxAccelPxPerSec2 = accelMetersPerSec2 * scaleFactor;
    final maxFrictionPxPerSec2 = frictionMetersPerSec2 * scaleFactor;

    Offset drive = Offset(driveX, driveY);
    if (drive != Offset.zero) drive = drive / drive.distance;

    Offset desiredVelWorld = Offset.zero;

    if (drive != Offset.zero) {
      if (fieldCentricMode) {
        desiredVelWorld = Offset(drive.dx, -drive.dy) * speedPxPerSec;
      } else {
        final forwardVec = Offset.fromDirection(angle) * drive.dy;
        final strafeVec = Offset.fromDirection(angle + pi / 2) * drive.dx;
        desiredVelWorld = (forwardVec + strafeVec) * speedPxPerSec;
      }
    }

    final diff = desiredVelWorld - velWorld;

    if (desiredVelWorld == Offset.zero) {
      final decel = _clampLen(velWorld, maxFrictionPxPerSec2 * dt);
      velWorld -= decel;
      if (velWorld.distance < 0.01) velWorld = Offset.zero;
    } else {
      final step = _clampLen(diff, maxAccelPxPerSec2 * dt);
      velWorld += step;
    }

    final next = pos + velWorld * dt;

    final rect = _robotRect(next);
    final fieldRect = Rect.fromLTWH(0, 0, fieldSizePx, fieldSizePx);

    final insideField =
        fieldRect.contains(rect.topLeft) && fieldRect.contains(rect.bottomRight);

    final hitsForbidden = _rectHitsForbidden(rect);

    if (insideField && !hitsForbidden) {
      pos = next;
    } else {
      velWorld = Offset.zero;
    }

    return MoveResult(pos: pos, vel: velWorld);
  }

  Offset _clampToField(Offset pos) {
    final half = robotSizePx / 2;
    final x = pos.dx.clamp(half, fieldSizePx - half);
    final y = pos.dy.clamp(half, fieldSizePx - half);
    return Offset(x.toDouble(), y.toDouble());
  }

  BotState _stepBotSteering(BotState bot, int i, double dt) {
    final speedPx = botSpeedMetersPerSecond * scaleFactor;

    Offset toT = bot.target - bot.pos;
    double dist = toT.distance;

    // Small jitter when bot reaches target to simulate "holding position"
    if (dist < robotSizePx * 0.25) {
      final seed = bot.id.codeUnits.fold<int>(0, (a, b) => a + b);
      final jx = sin(_simTime * 2.5 + seed) * botHoldJitter;
      final jy = cos(_simTime * 2.0 + seed) * botHoldJitter;
      toT = Offset(jx, jy);
      dist = toT.distance;
    }

    final dir = dist <= 0.0001 ? Offset.zero : (toT / dist);

    // Apply "wobble" for more organic bot movement
    final seed = bot.id.codeUnits.fold<int>(0, (a, b) => a + b);
    final wob =
        sin(_simTime * 2.15 + seed * 0.11) * botStrafeWobble +
            sin(_simTime * 4.30 + seed * 0.07) * (botStrafeWobble * 0.5);
    final perp = Offset(-dir.dy, dir.dx);

    Offset desiredDir = dir;
    if (dir != Offset.zero) {
      final mix = desiredDir + perp * wob;
      desiredDir = mix / mix.distance;
    }

    final desiredVel = desiredDir * speedPx;

    Offset vel = bot.vel;
    vel += (desiredVel - vel) * (botSteerGain * dt);
    vel -= vel * (botDampingGain * dt);

    vel = _clampLen(vel, speedPx);

    Offset next = bot.pos + vel * dt;
    next = _clampToField(next);

    // If bot hits a forbidden area, nudge it back
    if (_rectHitsForbidden(_robotRect(next))) {
      final pushed = _clampToField(bot.pos + Offset(0, robotSizePx * 0.7));
      if (!_rectHitsForbidden(_robotRect(pushed))) {
        next = pushed;
        vel = Offset.zero;
      } else {
        next = bot.pos;
        vel = Offset.zero;
      }
    }

    final heading = (vel.distance > 0.05) ? atan2(vel.dy, vel.dx) : bot.angle;

    // Turret aiming at the team's goal
    final goal = _goalCenter(bot.team);
    final aim = goal - next;
    final turret = atan2(aim.dy, aim.dx);

    return bot.copyWith(
      pos: next,
      vel: vel,
      angle: heading,
      turretAngle: turret,
    );
  }

  // ======================
  // SHOOTING LOGIC
  // ======================
  void _shootPlayer() {
    final now = DateTime.now();
    // Enforce cooldown and ammo limits
    if (now.difference(playerLastShotTime).inMilliseconds < 200) return;
    if (playerAmmo <= 0) return;
    if (!_inShootZoneCenter(playerPos)) return;

    projectiles.add(
      Projectile(
        pos: playerPos,
        dir: Offset.fromDirection(playerTurretAngle),
        owner: ProjectileOwner.player,
        ownerTeam: TeamColor.red,
      ),
    );

    playerAmmo--;
    playerLastShotTime = now;
  }

  BotState _shootBotState(BotState bot) {
    final now = DateTime.now();

    if (now.difference(bot.lastShotTime).inMilliseconds < botShotCooldownMs) {
      return bot;
    }
    if (bot.reloading) return bot;
    if (!botsHaveUnlimitedAmmo && bot.ammo <= 0) return bot;

    // Bots ONLY shoot while in a shooting zone
    if (!_inShootZoneCenter(bot.pos)) return bot;

    final goal = _goalCenter(bot.team);
    final aim = goal - bot.pos;
    final ang = atan2(aim.dy, aim.dx);

    projectiles.add(
      Projectile(
        pos: bot.pos,
        dir: Offset.fromDirection(ang),
        owner: ProjectileOwner.bot,
        ownerTeam: bot.team,
      ),
    );

    final nextAmmo = botsHaveUnlimitedAmmo ? bot.ammo : (bot.ammo - 1);
    return bot.copyWith(
      ammo: nextAmmo.clamp(0, maxAmmo),
      lastShotTime: now,
    );
  }

  // ======================
  // COLLISION RESOLUTION
  // ======================
  Offset _nudgeOutForbidden(Offset pos) {
    if (!_rectHitsForbidden(_robotRect(pos))) return pos;
    final nudged = _clampToField(pos + Offset(0, robotSizePx * 0.8));
    return _rectHitsForbidden(_robotRect(nudged)) ? pos : nudged;
  }

  void _resolveCollisions() {
    const passes = 3;

    for (int pass = 0; pass < passes; pass++) {
      final centers = <String, Offset>{
        "P": playerPos,
        for (final b in bots) b.id: b.pos,
      };

      final keys = centers.keys.toList();
      for (int a = 0; a < keys.length; a++) {
        for (int b = a + 1; b < keys.length; b++) {
          final idA = keys[a];
          final idB = keys[b];

          final pA = centers[idA]!;
          final pB = centers[idB]!;
          final rA = _robotRect(pA);
          final rB = _robotRect(pB);

          if (!rA.overlaps(rB)) continue;

          Offset d = pB - pA;
          double dist = d.distance;
          if (dist < 0.0001) {
            d = Offset(1, 0);
            dist = 1;
          }

          final minDist = robotSizePx + minSeparation;
          final overlap = (minDist - dist);
          if (overlap <= 0) continue;

          final dir = d / dist;
          final push = dir * (overlap * 0.5 * pushStrength);

          Offset newA = _nudgeOutForbidden(_clampToField(pA - push));
          Offset newB = _nudgeOutForbidden(_clampToField(pB + push));

          centers[idA] = newA;
          centers[idB] = newB;
        }
      }

      playerPos = centers["P"]!;
      bots = bots.map((b) => b.copyWith(pos: centers[b.id]!)).toList();
    }
  }

  // ======================
  // BOT TARGET SELECTION
  // ======================
  Offset _teamShootSpotBottom(TeamColor team, int idx) {
    final m = fieldSizePx;
    final y = m - m / 12;
    final xMid = m / 2;
    final x = team == TeamColor.blue
        ? xMid - m * (0.08 + 0.04 * (idx % 2))
        : xMid + m * (0.08 + 0.04 * (idx % 2));
    return Offset(x, y);
  }

  Offset _teamShootSpotTop(TeamColor team, int idx) {
    final m = fieldSizePx;

    final safeMarginX = reloadZoneSize + robotSizePx * 0.9;
    final safeMinX = safeMarginX;
    final safeMaxX = m - safeMarginX;

    final y = m * (0.18 + 0.07 * (idx % 2)) + _rng.nextDouble() * (m * 0.06);

    final bias = (team == TeamColor.blue ? -1.0 : 1.0);
    final xCenter = m / 2 + bias * (m * 0.10);
    final xJitter = (m * 0.14) * (_rng.nextDouble() * 2 - 1);
    final x = (xCenter + xJitter).clamp(safeMinX, safeMaxX);

    return Offset(x.toDouble(), y.toDouble());
  }

  Offset _pickShootTarget(TeamColor team, int idx) {
    // Randomly choose between top and bottom shooting areas
    final goTop = _rng.nextDouble() < 0.40;
    return goTop ? _teamShootSpotTop(team, idx) : _teamShootSpotBottom(team, idx);
  }

  BotState _tickBot(BotState bot, int i, double dt) {
    // If out of ammo, move to team-specific reload corner
    if (!botsHaveUnlimitedAmmo && bot.ammo == 0) {
      bot = bot.copyWith(target: _teamReloadTarget(bot.team));

      if (!bot.reloading && _inTeamReloadZone(bot.team, bot.pos)) {
        bot = bot.copyWith(
          reloading: true,
          reloadStartTime: DateTime.now(),
          reloadProgress: 0,
          reloadDuration: botReloadFixedDuration,
        );
      }

      if (bot.reloading) {
        if (!_inTeamReloadZone(bot.team, bot.pos)) {
          bot = bot.copyWith(reloading: false, reloadProgress: 0);
        } else {
          final elapsed = DateTime.now().difference(bot.reloadStartTime!);
          final prog =
          (elapsed.inMilliseconds / bot.reloadDuration.inMilliseconds)
              .clamp(0.0, 1.0);

          if (prog >= 1.0) {
            bot = bot.copyWith(
              ammo: maxAmmo,
              reloading: false,
              reloadProgress: 0,
              target: _pickShootTarget(bot.team, i),
              nextTargetAt: DateTime.now().add(Duration(milliseconds: 250)),
            );
          } else {
            bot = bot.copyWith(reloadProgress: prog);
          }
        }
      }
    } else {
      // If ammo is available, handle target acquisition
      if (bot.reloading || bot.reloadProgress != 0) {
        bot = bot.copyWith(reloading: false, reloadProgress: 0);
      }

      final shouldReTarget =
          DateTime.now().isAfter(bot.nextTargetAt) ||
              (bot.target - bot.pos).distance < robotSizePx * 0.85;

      if (shouldReTarget) {
        bot = bot.copyWith(
          target: _pickShootTarget(bot.team, i),
          nextTargetAt:
          DateTime.now().add(Duration(milliseconds: 550 + _rng.nextInt(850))),
        );
      }

      // If already in a good shooting position, hold still
      if (_inShootZoneCenter(bot.pos) &&
          (bot.target - bot.pos).distance < robotSizePx * 0.70) {
        bot = bot.copyWith(target: bot.pos);
      }
    }

    // Process movement and shooting
    bot = _stepBotSteering(bot, i, dt);

    if (!bot.reloading) {
      bot = _shootBotState(bot);
    }

    return bot;
  }

  // ======================
  // CORE GAME LOOP (TICK)
  // ======================
  void _onTick(Duration elapsed) {
    if (fieldSizePx <= 0 || robotSizePx <= 0) return;

    _spawnIfNeeded();
    const dt = 1 / 60.0;

    setState(() {
      _simTime += dt;

      double driveX = 0;
      double driveY = 0;

      final keys = RawKeyboard.instance.keysPressed;

      // Keyboard: Movement
      if (keys.contains(LogicalKeyboardKey.keyW)) driveY += 1;
      if (keys.contains(LogicalKeyboardKey.keyS)) driveY -= 1;
      if (keys.contains(LogicalKeyboardKey.keyQ)) driveX -= 1;
      if (keys.contains(LogicalKeyboardKey.keyE)) driveX += 1;

      // Keyboard: Robot Orientation
      if (keys.contains(LogicalKeyboardKey.keyA)) playerAngle -= pi * dt;
      if (keys.contains(LogicalKeyboardKey.keyD)) playerAngle += pi * dt;

      // Keyboard: Turret Orientation
      if (keys.contains(LogicalKeyboardKey.arrowLeft)) {
        playerTurretAngle -= playerTurretTurnSpeedRadPerSec * dt;
      }
      if (keys.contains(LogicalKeyboardKey.arrowRight)) {
        playerTurretAngle += playerTurretTurnSpeedRadPerSec * dt;
      }
      if (keys.contains(LogicalKeyboardKey.space)) _shootPlayer();

      // On-screen UI controls
      driveX += uiLeftStick.dx;
      driveY += uiLeftStick.dy;

      playerTurretAngle += uiRightStick.dx * playerTurretTurnSpeedRadPerSec * dt;

      final uiTurn = (uiTurnR ? 1.0 : 0.0) - (uiTurnL ? 1.0 : 0.0);
      playerAngle += uiTurn * playerTurnSpeedRadPerSec * dt;

      if (uiShoot) _shootPlayer();

      // Gamepad input handling
      if (_padConnected) {
        driveX += _dz(gpLeftX);
        driveY += -_dz(gpLeftY);

        final turn = (gpBumperR ? 1.0 : 0.0) - (gpBumperL ? 1.0 : 0.0);
        playerAngle += turn * playerTurnSpeedRadPerSec * dt;

        playerTurretAngle += _dz(gpRightX) * playerTurretTurnSpeedRadPerSec * dt;

        if (gpShootPressed) _shootPlayer();
      }

      // Apply physics to player movement
      final movedPlayer = _applyDrivePlayer(
        pos: playerPos,
        angle: playerAngle,
        velWorld: _playerVel,
        driveX: driveX,
        driveY: driveY,
        dt: dt,
        fieldCentricMode: fieldCentric,
        maxSpeedMetersPerSec: moveSpeedMetersPerSecond,
      );
      playerPos = movedPlayer.pos;
      _playerVel = movedPlayer.vel;

      // Update bot simulation
      for (int i = 0; i < bots.length; i++) {
        bots[i] = _tickBot(bots[i], i, dt);
      }

      // Resolve robot-to-robot collisions
      _resolveCollisions();

      // Player reload logic (triggered in any reload corner)
      if (!playerReloading && _inAnyReloadZone(playerPos) && playerAmmo < maxAmmo) {
        playerReloading = true;
        playerReloadStartTime = DateTime.now();
        playerReloadDuration = Duration(seconds: 1);
      }

      if (playerReloading) {
        if (!_inAnyReloadZone(playerPos)) {
          playerReloading = false;
          playerReloadProgress = 0;
        } else {
          final elapsedReload = DateTime.now().difference(playerReloadStartTime!);
          playerReloadProgress =
              (elapsedReload.inMilliseconds / playerReloadDuration.inMilliseconds)
                  .clamp(0.0, 1.0);
          if (playerReloadProgress >= 1.0) {
            playerAmmo = maxAmmo;
            playerReloading = false;
            playerReloadProgress = 0;
          }
        }
      }

      // Update projectiles and handle scoring
      remaining = gameDuration - elapsed;

      final toRemove = <Projectile>[];
      for (final p in projectiles) {
        p.move();

        if (!_inBounds(p.pos)) {
          toRemove.add(p);
          continue;
        }

        final goalTeam = _goalAt(p.pos);
        if (goalTeam != null) {
          if (goalTeam == TeamColor.blue) {
            blueScore += 5;
          } else {
            redScore += 5;
          }
          toRemove.add(p);
        }
      }

      projectiles.removeWhere((p) => toRemove.contains(p));
    });

    // Check for game over
    if (remaining <= Duration.zero) {
      _ticker.stop();
      _showEndGameDialog();
    }
  }

  void _showEndGameDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text("End of Game"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Blue: $blueScore"),
            Text("Red: $redScore"),
          ],
        ),
        actions: [
          TextButton(
            child: Text("Close"),
            onPressed: () => Navigator.of(context).pop(),
          )
        ],
      ),
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focusNode.dispose();
    _subEvent?.cancel();
    _padPollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FTC DECODE Mini Game'),
        actions: [
          Row(
            children: [
              Text("Field Centric", style: TextStyle(fontSize: 12)),
              Switch(
                value: fieldCentric,
                onChanged: (v) => setState(() => fieldCentric = v),
              ),
            ],
          ),
          SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final fieldSide = constraints.maxHeight * 0.62;

          // Compute scale factors based on available screen space
          scaleFactor = fieldSide / fieldSizeMeters;
          fieldSizePx = fieldSide;
          robotSizePx = (robotSizeInches * 0.0254) * scaleFactor;
          projectileRadius = 5 * 0.0254 * scaleFactor;
          reloadZoneSize = fieldSizePx * 0.2;

          _spawnIfNeeded();

          return Center(
            child: Column(
              children: [
                // Score and Info HUD
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      remaining <= Duration.zero
                          ? 'End of Game'
                          : 'Time: ${remaining.inMinutes}:${(remaining.inSeconds % 60).toString().padLeft(2, "0")}'
                          '   |   Ammo: $playerAmmo'
                          '   |   Blue: $blueScore  Red: $redScore',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

                // Game Field Rendering Area
                RawKeyboardListener(
                  focusNode: _focusNode,
                  autofocus: true,
                  onKey: (_) {},
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.black, width: 10),
                        ),
                        child: SizedBox(
                          width: fieldSizePx,
                          height: fieldSizePx,
                          child: CustomPaint(
                            painter: GamePainter(
                              playerPos: playerPos,
                              robotSize: robotSizePx,
                              playerAngle: playerAngle,
                              playerTurretAngle: playerTurretAngle,
                              bots: bots,
                              projectiles: projectiles,
                              reloadZoneSize: reloadZoneSize,
                              projectileRadius: projectileRadius,
                            ),
                          ),
                        ),
                      ),
                      // Reload Progress Bar overlay
                      if (playerReloading)
                        Positioned(
                          bottom: 8,
                          left: fieldSizePx / 2 - 100,
                          child: Container(
                            width: 200,
                            height: 14,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.black, width: 2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: LinearProgressIndicator(
                              value: playerReloadProgress,
                              backgroundColor: Colors.grey.shade700,
                              color: Colors.greenAccent,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                SizedBox(height: 10),
                Text(
                  _padConnected ? "Controller: Connected" : "Controller: Not Found",
                  style: TextStyle(color: Colors.grey[700]),
                ),

                // On-screen Virtual Controls
                SizedBox(height: 10),
                SizedBox(
                  width: fieldSizePx,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      OnScreenJoystick(
                        size: 120,
                        onChanged: (v) => setState(() => uiLeftStick = v),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _HoldButton(
                                label: "⟲",
                                onHoldChanged: (h) => setState(() => uiTurnL = h),
                              ),
                              SizedBox(width: 10),
                              _HoldButton(
                                label: "⟳",
                                onHoldChanged: (h) => setState(() => uiTurnR = h),
                              ),
                            ],
                          ),
                          SizedBox(height: 10),
                          _HoldButton(
                            label: "SHOOT",
                            wide: true,
                            onHoldChanged: (h) => setState(() => uiShoot = h),
                          ),
                        ],
                      ),
                      OnScreenJoystick(
                        size: 120,
                        onChanged: (v) => setState(() => uiRightStick = v),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ===================== UI COMPONENTS =====================

class OnScreenJoystick extends StatefulWidget {
  final double size;
  final ValueChanged<Offset> onChanged;

  const OnScreenJoystick({
    super.key,
    required this.size,
    required this.onChanged,
  });

  @override
  State<OnScreenJoystick> createState() => _OnScreenJoystickState();
}

class _OnScreenJoystickState extends State<OnScreenJoystick> {
  Offset _val = Offset.zero;

  void _update(Offset local) {
    final r = widget.size / 2;
    final c = Offset(r, r);
    Offset d = local - c;

    final dist = d.distance;
    if (dist > r) d = d / dist * r;

    final nx = (d.dx / r).clamp(-1.0, 1.0);
    final ny = (d.dy / r).clamp(-1.0, 1.0);

    final out = Offset(nx, -ny); // Up is positive Y

    setState(() => _val = out);
    widget.onChanged(out);
  }

  void _reset() {
    setState(() => _val = Offset.zero);
    widget.onChanged(Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.size / 2;
    final knob = Offset(_val.dx * r, -_val.dy * r);
    final knobCenter = Offset(r, r) + knob;

    return GestureDetector(
      onPanStart: (d) => _update(d.localPosition),
      onPanUpdate: (d) => _update(d.localPosition),
      onPanEnd: (_) => _reset(),
      onPanCancel: _reset,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.15),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black.withOpacity(0.25), width: 2),
        ),
        child: CustomPaint(
          painter: _JoyPainter(knobCenter: knobCenter, radius: r),
        ),
      ),
    );
  }
}

class _JoyPainter extends CustomPainter {
  final Offset knobCenter;
  final double radius;

  _JoyPainter({required this.knobCenter, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()
      ..color = Colors.white.withOpacity(0.10)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(radius, radius), radius * 0.92, base);

    final ring = Paint()
      ..color = Colors.white.withOpacity(0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(Offset(radius, radius), radius * 0.92, ring);

    final knobPaint = Paint()
      ..color = Colors.white.withOpacity(0.75)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(knobCenter, radius * 0.22, knobPaint);

    final knobRing = Paint()
      ..color = Colors.black.withOpacity(0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(knobCenter, radius * 0.22, knobRing);
  }

  @override
  bool shouldRepaint(covariant _JoyPainter oldDelegate) =>
      oldDelegate.knobCenter != knobCenter;
}

class _HoldButton extends StatefulWidget {
  final String label;
  final bool wide;
  final ValueChanged<bool> onHoldChanged;

  const _HoldButton({
    required this.label,
    required this.onHoldChanged,
    this.wide = false,
  });

  @override
  State<_HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<_HoldButton> {
  bool _down = false;

  void _set(bool v) {
    if (_down == v) return;
    setState(() => _down = v);
    widget.onHoldChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.wide ? 110.0 : 52.0;
    final h = 44.0;

    return GestureDetector(
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        width: w,
        height: h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _down
              ? Colors.black.withOpacity(0.35)
              : Colors.black.withOpacity(0.18),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black.withOpacity(0.25), width: 2),
        ),
        child: Text(
          widget.label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

// ===================== DATA MODELS =====================

class Projectile {
  Offset pos;
  final Offset dir;
  final double speed = 5.0;
  final ProjectileOwner owner;
  final TeamColor ownerTeam;

  Projectile({
    required this.pos,
    required this.dir,
    required this.owner,
    required this.ownerTeam,
  });

  void move() => pos += dir * speed;
}

class MoveResult {
  final Offset pos;
  final Offset vel;
  const MoveResult({required this.pos, required this.vel});
}

class BotState {
  final String id;
  final TeamColor team;

  final Offset pos;
  final double angle;
  final Offset vel;
  final double turretAngle;

  final Offset target;
  final DateTime nextTargetAt;

  final int ammo;

  final bool reloading;
  final double reloadProgress;
  final DateTime? reloadStartTime;
  final Duration reloadDuration;

  final DateTime lastShotTime;

  const BotState({
    required this.id,
    required this.team,
    required this.pos,
    required this.angle,
    required this.vel,
    required this.turretAngle,
    required this.target,
    required this.nextTargetAt,
    required this.ammo,
    required this.reloading,
    required this.reloadProgress,
    required this.reloadStartTime,
    required this.reloadDuration,
    required this.lastShotTime,
  });

  static BotState initial({
    required String id,
    required TeamColor team,
    required int maxAmmo,
  }) =>
      BotState(
        id: id,
        team: team,
        pos: Offset.zero,
        angle: -pi / 2,
        vel: Offset.zero,
        turretAngle: -pi / 2,
        target: Offset.zero,
        nextTargetAt: DateTime.now().subtract(Duration(seconds: 1)),
        ammo: maxAmmo,
        reloading: false,
        reloadProgress: 0,
        reloadStartTime: null,
        reloadDuration: Duration(seconds: 1),
        lastShotTime: DateTime.now().subtract(Duration(seconds: 1)),
      );

  BotState copyWith({
    Offset? pos,
    double? angle,
    Offset? vel,
    double? turretAngle,
    Offset? target,
    DateTime? nextTargetAt,
    int? ammo,
    bool? reloading,
    double? reloadProgress,
    DateTime? reloadStartTime,
    Duration? reloadDuration,
    DateTime? lastShotTime,
  }) {
    return BotState(
      id: id,
      team: team,
      pos: pos ?? this.pos,
      angle: angle ?? this.angle,
      vel: vel ?? this.vel,
      turretAngle: turretAngle ?? this.turretAngle,
      target: target ?? this.target,
      nextTargetAt: nextTargetAt ?? this.nextTargetAt,
      ammo: ammo ?? this.ammo,
      reloading: reloading ?? this.reloading,
      reloadProgress: reloadProgress ?? this.reloadProgress,
      reloadStartTime: reloadStartTime ?? this.reloadStartTime,
      reloadDuration: reloadDuration ?? this.reloadDuration,
      lastShotTime: lastShotTime ?? this.lastShotTime,
    );
  }
}

// ===================== RENDERING =====================

class GamePainter extends CustomPainter {
  final Offset playerPos;
  final double robotSize;
  final double playerAngle;
  final double playerTurretAngle;

  final List<BotState> bots;
  final List<Projectile> projectiles;

  final double reloadZoneSize;
  final double projectileRadius;

  GamePainter({
    required this.playerPos,
    required this.robotSize,
    required this.playerAngle,
    required this.playerTurretAngle,
    required this.bots,
    required this.projectiles,
    required this.reloadZoneSize,
    required this.projectileRadius,
  });

  void _drawRobot(Canvas canvas, Offset pos, double angle, Color color) {
    final paint = Paint()..style = PaintingStyle.fill;

    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(angle);

    // Draw main chassis
    paint.color = color;
    canvas.drawRect(
      Rect.fromCenter(center: Offset.zero, width: robotSize, height: robotSize),
      paint,
    );

    // Draw direction indicator (notch)
    paint.color = Colors.white;
    final notchHeight = robotSize * 0.12;
    final notchWidth = robotSize * 0.3;
    final notch = Path()
      ..moveTo(robotSize / 2, 0)
      ..lineTo(robotSize / 2 - notchHeight, -notchWidth / 2)
      ..lineTo(robotSize / 2 - notchHeight, notchWidth / 2)
      ..close();
    canvas.drawPath(notch, paint);

    // Draw wheels
    paint.color = Colors.black;
    final wheelWidth = robotSize * 0.075;
    final wheelLength = robotSize * 0.3;
    final yOffset = robotSize / 2 + wheelWidth / 2;
    for (final dx in [-robotSize / 4, robotSize / 4]) {
      for (final dy in [-yOffset, yOffset]) {
        canvas.save();
        canvas.translate(dx, dy);
        canvas.drawRect(
          Rect.fromCenter(
              center: Offset.zero, width: wheelLength, height: wheelWidth),
          paint,
        );
        canvas.restore();
      }
    }

    canvas.restore();
  }

  void _drawTurret(Canvas canvas, Offset pos, double ang) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    final turretLength = robotSize * 0.45;
    final end = pos + Offset.fromDirection(ang) * turretLength;
    canvas.drawLine(pos, end, paint);
    canvas.drawCircle(pos, robotSize * 0.10, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.grey.shade300;
    canvas.drawRect(Offset.zero & size, paint);

    // Draw green reload zones in the corners
    paint.color = Colors.green.shade200;
    canvas.drawRect(
      Rect.fromLTWH(
          0, size.height - reloadZoneSize, reloadZoneSize, reloadZoneSize),
      paint,
    );
    canvas.drawRect(
      Rect.fromLTWH(size.width - reloadZoneSize, size.height - reloadZoneSize,
          reloadZoneSize, reloadZoneSize),
      paint,
    );

    // Draw bottom shooting zone outline
    final bottomZone = Path()
      ..moveTo(size.width * 2 / 6, size.height)
      ..lineTo(size.width * 4 / 6, size.height)
      ..lineTo(size.width / 2, size.height - size.height / 6)
      ..close();

    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..color = Colors.white.withOpacity(0.5);
    canvas.drawPath(bottomZone, paint);

    // Draw top shooting zone outline
    final topZone = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, (size.height / 6) * 3)
      ..close();
    canvas.drawPath(topZone, paint);

    paint.style = PaintingStyle.fill;

    // Draw bots
    for (final b in bots) {
      final c = (b.team == TeamColor.blue)
          ? Colors.blue.shade600
          : Colors.red.shade600;
      _drawRobot(canvas, b.pos, b.angle, c);
      _drawTurret(canvas, b.pos, b.turretAngle);
    }

    // Draw player (red team)
    _drawRobot(canvas, playerPos, playerAngle, Colors.red);
    _drawTurret(canvas, playerPos, playerTurretAngle);

    // Draw active projectiles
    for (final p in projectiles) {
      paint.color = (p.ownerTeam == TeamColor.blue)
          ? Colors.blueAccent
          : Colors.redAccent;
      if (p.owner == ProjectileOwner.player) paint.color = Colors.purple;
      canvas.drawCircle(p.pos, projectileRadius, paint);
    }

    // Draw scoring goals in the top corners
    final leftTriangle = Path()
      ..moveTo(0, 0)
      ..lineTo(reloadZoneSize, 0)
      ..lineTo(0, reloadZoneSize)
      ..close();
    paint.color = Colors.blue;
    canvas.drawPath(leftTriangle, paint);

    final rightTriangle = Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width - reloadZoneSize, 0)
      ..lineTo(size.width, reloadZoneSize)
      ..close();
    paint.color = Colors.red;
    canvas.drawPath(rightTriangle, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
