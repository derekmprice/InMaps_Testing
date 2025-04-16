import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:http/http.dart' as http;

/// A simple 2D vector class used for trilateration.
class Vector2D {
  final double x, y;
  Vector2D(this.x, this.y);
}

class GameScreen extends StatefulWidget {
  const GameScreen({Key? key}) : super(key: key);

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin {
  // ---------------- BLE & Positioning ----------------
  final flutterReactiveBle = FlutterReactiveBle();
  StreamSubscription<DiscoveredDevice>? _scanSubscription;

  // Example mapping from beacon IDs to positions.
  final Map<String, List<int>> beaconIdToPosition = {
    "14j906Gy": [0, 0],
    "14jr08Ef": [200, 0],
    "14j606Gv": [0, 200],
  };

  // Scanned devices: key is beaconID, value is RSSI.
  Map<String, int> scannedDevices = {};

  // User location as a string "x, y".
  String userLocation = "";

  // ---------------- Game Tasks Data ----------------
  List<Map<String, dynamic>> tasks = [];
  int totalPoints = 0;

  // ---------------- Reward Popup Animation ----------------
  bool showReward = false;
  String rewardText = "";
  late final AnimationController _animationController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _opacityAnimation;

  // ---------------- Proximity Timer ----------------
  Timer? _proximityTimer;

  // ---------------- Lifecycle ----------------
  @override
  void initState() {
    super.initState();
    _startBleScan();
    _fetchTasks();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _scaleAnimation = Tween<double>(begin: 0, end: 1).animate(_animationController);
    _opacityAnimation = Tween<double>(begin: 0, end: 1).animate(_animationController);

    // Every second, update user location and check proximity.
    _proximityTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _estimateUserLocation();
      _checkProximity();
    });
  }


  @override
  void dispose() {
    _scanSubscription?.cancel();
    _animationController.dispose();
    _proximityTimer?.cancel();
    super.dispose();
  }


  // ---------------- BLE Scanning ----------------
  void _startBleScan() async {
    await _scanSubscription?.cancel();
    if (mounted) {
      setState(() => scannedDevices.clear());
    }
    _scanSubscription = flutterReactiveBle
        .scanForDevices(withServices: [], scanMode: ScanMode.lowLatency)
        .listen((device) {
      if (device.name.toLowerCase() == "kontakt" &&
          device.serviceData.containsKey(Uuid.parse("FE6A"))) {
        final rawData = device.serviceData[Uuid.parse("FE6A")]!;
        final asciiBytes = rawData.sublist(13);
        final beaconId = String.fromCharCodes(asciiBytes);
        if (beaconIdToPosition.containsKey(beaconId)) {
          if (mounted) {
            setState(() {
              scannedDevices[beaconId] = device.rssi;
            });
          }
        }
      }
    }, onError: (err) {
      debugPrint("❌ BLE scan error: $err");
    });
  }

  // ---------------- Distance & Trilateration ----------------
  double _estimateDistance(int rssi, int txPower) {
    return pow(10, (txPower - rssi) / 20).toDouble();
  }

  Vector2D? _trilaterate(Map<String, double> distances) {
    if (distances.length < 3) return null;
    final keys = distances.keys.toList();
    final p1 = Vector2D(
        beaconIdToPosition[keys[0]]![0].toDouble(),
        beaconIdToPosition[keys[0]]![1].toDouble());
    final p2 = Vector2D(
        beaconIdToPosition[keys[1]]![0].toDouble(),
        beaconIdToPosition[keys[1]]![1].toDouble());
    final p3 = Vector2D(
        beaconIdToPosition[keys[2]]![0].toDouble(),
        beaconIdToPosition[keys[2]]![1].toDouble());
    final r1 = distances[keys[0]]!;
    final r2 = distances[keys[1]]!;
    final r3 = distances[keys[2]]!;

    final A = 2 * (p2.x - p1.x);
    final B = 2 * (p2.y - p1.y);
    final C = r1 * r1 - r2 * r2 - p1.x * p1.x + p2.x * p2.x - p1.y * p1.y + p2.y * p2.y;
    final D = 2 * (p3.x - p2.x);
    final E = 2 * (p3.y - p2.y);
    final F = r2 * r2 - r3 * r3 - p2.x * p2.x + p3.x * p3.x - p2.y * p2.y + p3.y * p3.y;
    final denom = A * E - B * D;
    if (denom.abs() < 1e-6) return null;

    final x = (C * E - B * F) / denom;
    final y = (A * F - C * D) / denom;
    return Vector2D(x, y);
  }

  // ---------------- Estimate User Location ----------------
  void _estimateUserLocation() {
    final distances = <String, double>{};
    scannedDevices.forEach((id, rssi) {
      distances[id] = _estimateDistance(rssi, -59); // using an approximate TX power.
    });
    final position = _trilaterate(distances);
    if (position != null && mounted) {
      setState(() => userLocation = "${position.x.round()}, ${position.y.round()}");
    }
  }

  // ---------------- Fetch Tasks ----------------
  Future<void> _fetchTasks() async {
    final url = Uri.parse('http://143.215.53.49:8001/booths');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final dynamic data = jsonDecode(response.body);
        List<dynamic> booths;
        if (data is List) {
          booths = data;
        } else if (data is Map && data.containsKey("elements")) {
          booths = data["elements"];
        } else {
          throw Exception("Unexpected JSON format");
        }
        if (mounted) {
          setState(() {
            tasks = booths.map<Map<String, dynamic>>((b) {
              final start = b["start"] ?? {"x": 0, "y": 0};
              final end = b["end"] ?? {"x": 0, "y": 0};
              final centerX = ((start["x"] as num) + (end["x"] as num)) / 2;
              final centerY = ((start["y"] as num) + (end["y"] as num)) / 2;
              return {
                "id": b["booth_id"]?.toString() ?? "",
                "name": b["name"] ?? "Unnamed",
                "category": b["category"] ?? "Visit",
                "description": b["description"] ?? "No description available",
                "x": centerX,
                "y": centerY,
                "points": b["points"] ?? 20,
                "completed": false,
              };
            }).toList();
          });
        }
      } else {
        debugPrint("❌ Could not fetch tasks. Status = ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("❌ Task fetch error: $e");
    }
  }

  // ---------------- Check Proximity ----------------
  void _checkProximity() {
    if (userLocation.isEmpty || tasks.isEmpty) return;
    final parts = userLocation.split(',');
    if (parts.length < 2) return;
    final userX = double.tryParse(parts[0].trim()) ?? 0;
    final userY = double.tryParse(parts[1].trim()) ?? 0;
    const proximityThreshold = 5.0; // Adjust based on your coordinate system.

    for (var task in tasks) {
      if (!task["completed"]) {
        final dx = (task["x"] as double) - userX;
        final dy = (task["y"] as double) - userY;
        final dist = sqrt(dx * dx + dy * dy);
        if (dist < proximityThreshold) {
          if (mounted) {
            setState(() {
              task["completed"] = true;
              totalPoints += (task["points"] as int);
              rewardText = "+${task["points"]} points!";
              showReward = true;
            });
          }
          _animationController.forward(from: 0);
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (mounted) {
              setState(() => showReward = false);
            }
          });
        }
      }
    }
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Game Mode")),
      body: Stack(
        children: [
          // Main content: header, task list, etc.
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  "Total Points: $totalPoints",
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  "Game Tasks:",
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  itemCount: tasks.length,
                  itemBuilder: (context, index) {
                    final t = tasks[index];
                    final isCompleted = t["completed"] == true;
                    return InkWell(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: Text(t["name"]),
                            content: Text(t["description"]),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text("Close"),
                              ),
                            ],
                          ),
                        );
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isCompleted ? Colors.green[50] : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isCompleted ? Colors.green : Colors.grey.shade300,
                            width: isCompleted ? 2 : 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              offset: const Offset(0, 2),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t["name"],
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Text(t["category"] ?? "Visit"),
                            Text(isCompleted ? "✅ Completed" : "🕓 Pending"),
                            Text("Reward: ${t["points"]} pts"),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          // Reward popup overlay.
          if (showReward)
            Positioned.fill(
              child: Center(
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: FadeTransition(
                    opacity: _opacityAnimation,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black38,
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Text(
                        rewardText,
                        style: const TextStyle(fontSize: 24, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------- Dummy MapScreen ----------------
// Replace this dummy MapScreen with your actual implementation if available.
class MapScreen extends StatelessWidget {
  final List<List<dynamic>> path;
  final List<int> startLocation;
  const MapScreen({Key? key, required this.path, required this.startLocation}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Map View")),
      body: Center(
        child: Text(
          "Map Screen - Path length: ${path.length}\nStart: $startLocation",
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
