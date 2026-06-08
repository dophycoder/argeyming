import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:async';

void main() {
  runApp(const GameApp());
}

class GameApp extends StatelessWidget {
  const GameApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: GameScreen(),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  // --- STATE ---
  IO.Socket? socket;
  Map<String, dynamic> players = {};
  String myId = '';
  bool _isShooting = false;
  bool _isHit = false;
  Offset _myPosition = const Offset(100, 100);

  @override
  void initState() {
    super.initState();
    _connectSocket();
  }

  // --- NETWORK LOGIC ---
  void _connectSocket() {
    socket = IO.io('http://185.216.71.84:3000', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });

    socket!.connect();

    socket!.onConnect((_) {
      myId = socket!.id ?? '';
      socket!.emit('join', {'x': _myPosition.dx, 'y': _myPosition.dy});
    });

    socket!.on('stateUpdate', (data) {
      if (mounted) {
        setState(() {
          players = Map<String, dynamic>.from(data);
        });
      }
    });

    socket!.on('hit', (data) {
      if (data['targetId'] == myId) {
        _triggerHitFlash();
      }
    });
  }

  void _updatePosition(Offset delta) {
    setState(() {
      _myPosition = Offset(_myPosition.dx + delta.dx, _myPosition.dy + delta.dy);
    });
    socket!.emit('move', {'x': _myPosition.dx, 'y': _myPosition.dy});
  }

  void _shoot() {
    _triggerShootFlash();
    socket!.emit('shoot', {'x': _myPosition.dx, 'y': _myPosition.dy});
  }

  // --- EFFECTS LOGIC ---
  void _triggerShootFlash() {
    setState(() => _isShooting = true);
    Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _isShooting = false);
    });
  }

  void _triggerHitFlash() {
    setState(() => _isHit = true);
    Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _isHit = false);
    });
  }

  @override
  void dispose() {
    socket?.disconnect();
    super.dispose();
  }

  // --- UI COMPONENTS ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GestureDetector(
            onPanUpdate: (details) => _updatePosition(details.delta),
            child: Container(color: Colors.white),
          ),
          
          ...players.entries.map((entry) {
            final id = entry.key;
            final data = entry.value;
            final isMe = id == myId;
            final double x = (data['x'] as num).toDouble();
            final double y = (data['y'] as num).toDouble();
            final int hp = data['hp'] as int;

            return Positioned(
              left: x,
              top: y,
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 5,
                    color: Colors.grey,
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: hp / 100,
                      child: Container(color: Colors.green),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Container(
                    width: 40,
                    height: 40,
                    color: isMe ? Colors.blue : Colors.red,
                  ),
                ],
              ),
            );
          }),

          if (_isShooting)
            IgnorePointer(
              child: Container(color: Colors.orange.withOpacity(0.3)),
            ),
          if (_isHit)
            IgnorePointer(
              child: Container(color: Colors.red.withOpacity(0.5)),
            ),

          Positioned(
            bottom: 50,
            right: 50,
            child: ElevatedButton(
              onPressed: _shoot,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                textStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              child: const Text('SHOOT'),
            ),
          ),
        ],
      ),
    );
  }
}