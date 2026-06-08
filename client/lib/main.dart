import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:async';

List<CameraDescription> cameras = [];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint("Camera error: $e");
  }
  runApp(const GameApp());
}

class GameApp extends StatelessWidget {
  const GameApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: MainMenu(),
    );
  }
}

// --- APP STATE ENUMS ---
enum AppState { menu, hosting, scanning, lobby, playing, gameover }

// --- MAIN WRAPPER ---
class MainMenu extends StatefulWidget {
  const MainMenu({super.key});
  @override
  State<MainMenu> createState() => _MainMenuState();
}

class _MainMenuState extends State<MainMenu> {
  // --- STATE ---
  AppState _state = AppState.menu;
  IO.Socket? socket;
  String? _roomId;
  String _errorMessage = '';
  
  int _myHp = 100;
  int _enemyHp = 100;
  bool _isReady = false;
  bool _enemyReady = false;
  String? _winner;

  // AR Mock State
  double _yaw = 0;
  double _pitch = 0;
  StreamSubscription? _gyroSub;

  double _enemyYaw = 0;
  double _enemyPitch = 0;

  CameraController? _cameraController;

  // --- LIFECYCLE ---
  @override
  void initState() {
    super.initState();
    _connectSocket();
    _initGyro();
    _initCamera();
  }

  void _initCamera() {
    if (cameras.isNotEmpty) {
      _cameraController = CameraController(cameras[0], ResolutionPreset.low);
      _cameraController!.initialize().then((_) {
        if (!mounted) return;
        setState(() {});
      });
    }
  }

  void _initGyro() {
    _gyroSub = gyroscopeEvents.listen((GyroscopeEvent event) {
      setState(() {
        _yaw += event.y * 0.05;
        _pitch += event.x * 0.05;
      });
      if (_state == AppState.playing) {
         socket?.emit('move', {'roomId': _roomId, 'yaw': _yaw, 'pitch': _pitch});
      }
    });
  }

  // --- NETWORK LOGIC ---
  void _connectSocket() {
    socket = IO.io('http://185.216.71.84:3000', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
    });

    socket!.onConnect((_) {
      setState(() => _errorMessage = '');
    });

    socket!.on('roomCreated', (data) {
      setState(() {
        _roomId = data['roomId'];
        _state = AppState.hosting;
      });
    });

    socket!.on('playerJoined', (data) {
      setState(() {
        _state = AppState.lobby;
      });
    });

    socket!.on('playerReady', (data) {
      setState(() => _enemyReady = true);
    });

    socket!.on('gameStart', (data) {
      setState(() {
        _state = AppState.playing;
        _yaw = 0; _pitch = 0; // Reset orientation on start
      });
    });

    socket!.on('enemyMove', (data) {
      setState(() {
        _enemyYaw = data['yaw'];
        _enemyPitch = data['pitch'];
      });
    });

    socket!.on('hit', (data) {
      if (data['targetId'] == socket!.id) {
        setState(() => _myHp = data['hp']);
      } else {
        setState(() => _enemyHp = data['hp']);
      }
    });

    socket!.on('gameOver', (data) {
      setState(() {
        _state = AppState.gameover;
        _winner = data['winner'] == socket!.id ? 'YOU WIN' : 'GAME OVER';
      });
    });

    socket!.on('error', (data) {
      setState(() {
        _errorMessage = data['message'];
        _state = AppState.menu;
      });
    });

    socket!.onDisconnect((_) {
      setState(() {
        _errorMessage = 'Lost connection to VPS';
        _state = AppState.menu;
      });
    });
  }

  // --- NETWORK ERROR HANDLING ---
  void _reconnect() {
    socket?.connect();
  }

  // --- ACTIONS ---
  void _createRoom() {
    socket!.emit('createRoom');
  }

  void _joinRoom(String roomId) {
    setState(() => _roomId = roomId);
    socket!.emit('joinRoom', {'roomId': roomId});
  }

  void _setReady() {
    setState(() => _isReady = true);
    socket!.emit('setReady', {'roomId': _roomId});
  }

  void _shoot() {
    double diffYaw = (_yaw - _enemyYaw).abs();
    double diffPitch = (_pitch - _enemyPitch).abs();
    
    // Raycast hit threshold
    bool isHit = diffYaw < 0.5 && diffPitch < 0.5;

    socket!.emit('shoot', {'roomId': _roomId, 'hit': isHit});
  }

  @override
  void dispose() {
    _gyroSub?.cancel();
    _cameraController?.dispose();
    socket?.dispose();
    super.dispose();
  }

  // --- UI COMPONENTS ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_cameraController != null && _cameraController!.value.isInitialized && _state != AppState.scanning)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _cameraController!.value.previewSize!.height,
                  height: _cameraController!.value.previewSize!.width,
                  child: CameraPreview(_cameraController!),
                ),
              ),
            ),

          SafeArea(
            child: _buildCurrentStateUI(),
          ),

          if (_errorMessage.isNotEmpty)
            Positioned(
              top: 40, left: 20, right: 20,
              child: Container(
                padding: const EdgeInsets.all(10),
                color: Colors.red,
                child: Text(_errorMessage, style: const TextStyle(color: Colors.white)),
              ),
            )
        ],
      ),
    );
  }

  Widget _buildCurrentStateUI() {
    switch (_state) {
      case AppState.menu:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("AR SHOOTER", style: TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold)),
              const SizedBox(height: 50),
              ElevatedButton(
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20)),
                onPressed: _createRoom, 
                child: const Text('CREATE ROOM')
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20)),
                onPressed: () => setState(() => _state = AppState.scanning),
                child: const Text('JOIN (SCAN QR)'),
              ),
            ],
          ),
        );

      case AppState.hosting:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(10),
                child: QrImageView(
                  data: _roomId ?? '',
                  version: QrVersions.auto,
                  size: 250.0,
                ),
              ),
              const SizedBox(height: 30),
              const Text('SCAN ME', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
            ],
          ),
        );

      case AppState.scanning:
        return MobileScanner(
          onDetect: (capture) {
            final List<Barcode> barcodes = capture.barcodes;
            if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
              _joinRoom(barcodes.first.rawValue!);
            }
          },
        );

      case AppState.lobby:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("LOBBY", style: TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              Text("Opponent: ${_enemyReady ? 'READY' : 'WAITING'}", style: const TextStyle(color: Colors.orange, fontSize: 24)),
              const SizedBox(height: 40),
              if (!_isReady)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 20)),
                  onPressed: _setReady, 
                  child: const Text('READY', style: TextStyle(fontSize: 24))
                )
              else
                const Text("WAITING FOR GAME TO START...", style: TextStyle(color: Colors.green, fontSize: 20)),
            ],
          ),
        );

      case AppState.playing:
        double screenW = MediaQuery.of(context).size.width;
        double screenH = MediaQuery.of(context).size.height;
        
        double targetX = screenW / 2 + (_enemyYaw - _yaw) * 400;
        double targetY = screenH / 2 + (_enemyPitch - _pitch) * 400;

        return Stack(
          children: [
            Positioned(
              left: targetX - 50,
              top: targetY - 50,
              child: Column(
                children: [
                  Text('HP: $_enemyHp', style: const TextStyle(color: Colors.red, fontSize: 20, fontWeight: FontWeight.bold)),
                  Container(width: 100, height: 100, color: Colors.red.withOpacity(0.8)),
                ],
              ),
            ),

            const Center(
              child: Icon(Icons.add, color: Colors.greenAccent, size: 80),
            ),

            Positioned(
              top: 20, left: 20,
              child: Text('MY HP: $_myHp', style: const TextStyle(color: Colors.blue, fontSize: 28, fontWeight: FontWeight.bold)),
            ),

            Positioned(
              bottom: 40, left: 0, right: 0,
              child: Center(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 80, vertical: 25),
                    backgroundColor: Colors.orange,
                  ),
                  onPressed: _shoot,
                  child: const Text('SHOOT', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                ),
              ),
            )
          ],
        );

      case AppState.gameover:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_winner ?? '', style: const TextStyle(color: Colors.white, fontSize: 64, fontWeight: FontWeight.bold)),
              const SizedBox(height: 40),
              ElevatedButton(
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20)),
                onPressed: () => setState(() {
                  _state = AppState.menu;
                  _myHp = 100;
                  _enemyHp = 100;
                  _isReady = false;
                  _enemyReady = false;
                }),
                child: const Text('BACK TO MENU', style: TextStyle(fontSize: 20)),
              )
            ],
          ),
        );
    }
  }
}