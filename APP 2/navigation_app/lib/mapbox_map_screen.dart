import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:math';
import 'package:flutter_compass/flutter_compass.dart';
import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';
import './utils/vector2d.dart';
import 'package:flutter/services.dart' show rootBundle;

class MapboxMapScreen extends StatefulWidget {
  final List<List<dynamic>> path;
  final List<int> startLocation;
  final double headingDegrees;
  final Vector2D initialPosition;
  final String selectedBoothName;
  final Function(bool)? onArrival;

  MapboxMapScreen({
    required this.path,
    required this.startLocation,
    required this.headingDegrees,
    required this.initialPosition,
    required this.selectedBoothName,
    this.onArrival,
  });

  @override
  _MapboxMapScreenState createState() => _MapboxMapScreenState();
}

class _MapboxMapScreenState extends State<MapboxMapScreen> {
  MapboxMap? mapboxMap;
  List<dynamic> elements = [];
  List<List<dynamic>> currentPath = [];
  double currentHeading = 0.0;
  StreamSubscription<CompassEvent>? _headingSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;
  late String selectedBoothName;
  
  // Convert your pixel coordinates to lat/lng
  // You'll need to define your map bounds and conversion factors
  static const double mapCenterLat = 33.7756;  // Example: Georgia Tech coordinates
  static const double mapCenterLng = -84.3963;
  static const double pixelsToDegreesLat = 0.00001; // Adjust based on your coordinate system
  static const double pixelsToDegreesLng = 0.00001;

  Vector2D imuOffset = Vector2D(0, 0);
  Point userLocation = Point(coordinates: Position(mapCenterLng, mapCenterLat));

  @override
  void initState() {
    super.initState();
    selectedBoothName = widget.selectedBoothName;
    currentPath = List.from(widget.path);
    
    // Convert initial position to lat/lng
    userLocation = _pixelToLatLng(widget.initialPosition);
    
    setupSensors();
    fetchMapData();
  }

  // Convert your pixel coordinates to lat/lng coordinates
  Point _pixelToLatLng(Vector2D pixelPosition) {
    final lat = mapCenterLat + (pixelPosition.y * pixelsToDegreesLat);
    final lng = mapCenterLng + (pixelPosition.x * pixelsToDegreesLng);
    return Point(coordinates: Position(lng, lat));
  }

  void setupSensors() {
    _headingSub = FlutterCompass.events?.listen((event) {
      if (event.heading != null) {
        setState(() {
          currentHeading = event.heading!;
        });
        updateUserLocationOnMap();
      }
    });

    _accelSub = accelerometerEvents.listen((event) {
      double magnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      if (magnitude > 12) {
        final stepDistanceInPixels = 28.0; // Adjust based on your scale
        final headingRadians = currentHeading * pi / 180;
        
        imuOffset = Vector2D(
          imuOffset.x + cos(headingRadians) * stepDistanceInPixels,
          imuOffset.y + sin(headingRadians) * stepDistanceInPixels,
        );
        
        userLocation = _pixelToLatLng(Vector2D(
          widget.initialPosition.x + imuOffset.x,
          widget.initialPosition.y + imuOffset.y,
        ));
        
        updateUserLocationOnMap();
        updatePath();
      }
    });
  }

  Future<void> fetchMapData() async {
    final url = Uri.parse("https://inmaps.onrender.com/map-data");
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        setState(() {
          elements = json["elements"];
        });
        
        // Add elements to map after mapbox is initialized
        if (mapboxMap != null) {
          await addElementsToMap();
        }
      }
    } catch (e) {
      print("❌ Map fetch failed: $e");
    }
  }

  Future<void> updatePath() async {
    // Your existing path update logic, but convert to GeoJSON
    final userPixelX = widget.initialPosition.x + imuOffset.x;
    final userPixelY = widget.initialPosition.y + imuOffset.y;
    
    final xGrid = (userPixelX / 40.0).floor();
    final yGrid = (userPixelY / 40.0).floor();

    try {
      final response = await http.post(
        Uri.parse('https://inmaps.onrender.com/path'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({"from_": [xGrid, yGrid], "to": selectedBoothName}),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          currentPath = List<List<dynamic>>.from(data['path']);
        });
        
        if (mapboxMap != null) {
          await addPathToMap();
        }
      }
    } catch (e) {
      print('❌ Path fetch failed: $e');
    }
  }

  Future<void> addElementsToMap() async {
    // Convert your elements to GeoJSON features
    final features = elements.map((element) {
      final start = element["start"];
      final end = element["end"];
      
      // Convert pixel coordinates to lat/lng
      final startLatLng = _pixelToLatLng(Vector2D(start["x"].toDouble(), start["y"].toDouble()));
      final endLatLng = _pixelToLatLng(Vector2D(end["x"].toDouble(), end["y"].toDouble()));
      
      // Create a rectangle polygon for each booth/element
      final coordinates = [
        [
          [startLatLng.coordinates.lng, startLatLng.coordinates.lat],
          [endLatLng.coordinates.lng, startLatLng.coordinates.lat],
          [endLatLng.coordinates.lng, endLatLng.coordinates.lat],
          [startLatLng.coordinates.lng, endLatLng.coordinates.lat],
          [startLatLng.coordinates.lng, startLatLng.coordinates.lat], // Close the polygon
        ]
      ];
      
      return {
        "type": "Feature",
        "properties": {
          "name": element["name"],
          "type": element["type"],
          "description": element["description"] ?? "No description",
        },
        "geometry": {
          "type": "Polygon",
          "coordinates": coordinates,
        }
      };
    }).toList();

    final geoJsonData = {
      "type": "FeatureCollection",
      "features": features,
    };

    // Add source and layer to map
    await mapboxMap!.style.addSource(GeoJsonSource(
      id: "elements-source",
      data: jsonEncode(geoJsonData),
    ));

    // Add fill layer for booths
    await mapboxMap!.style.addLayer(FillLayer(
      id: "booths-fill",
      sourceId: "elements-source",
      paint: FillLayerPaint(
        fillColor: [
          "case",
          ["==", ["get", "type"], "booth"], "#4CAF50", // Green for booths
          ["==", ["get", "type"], "blocker"], "#F44336", // Red for blockers
          "#607D8B" // Blue-grey for others
        ],
        fillOpacity: 0.7,
      ),
    ));

    // Add outline layer
    await mapboxMap!.style.addLayer(LineLayer(
      id: "booths-outline",
      sourceId: "elements-source",
      paint: LineLayerPaint(
        lineColor: "#000000",
        lineWidth: 1.0,
      ),
    ));

    // Add labels layer
    await mapboxMap!.style.addLayer(SymbolLayer(
      id: "booths-labels",
      sourceId: "elements-source",
      layout: SymbolLayerLayout(
        textField: ["get", "name"],
        textSize: 12.0,
        textAnchor: TextAnchor.CENTER,
      ),
      paint: SymbolLayerPaint(
        textColor: "#000000",
        textHaloColor: "#FFFFFF",
        textHaloWidth: 1.0,
      ),
    ));
  }

  Future<void> addPathToMap() async {
    if (currentPath.isEmpty) return;

    // Convert path points to lat/lng coordinates
    final pathCoordinates = currentPath.map((point) {
      final pixelPos = Vector2D((point[0] + 0.5) * 40.0, (point[1] + 0.5) * 40.0);
      final latLng = _pixelToLatLng(pixelPos);
      return [latLng.coordinates.lng, latLng.coordinates.lat];
    }).toList();

    final pathGeoJson = {
      "type": "FeatureCollection",
      "features": [
        {
          "type": "Feature",
          "properties": {},
          "geometry": {
            "type": "LineString",
            "coordinates": pathCoordinates,
          }
        }
      ]
    };

    // Remove existing path if it exists
    try {
      await mapboxMap!.style.removeLayer("path-layer");
      await mapboxMap!.style.removeSource("path-source");
    } catch (e) {
      // Layer/source doesn't exist yet
    }

    // Add new path
    await mapboxMap!.style.addSource(GeoJsonSource(
      id: "path-source",
      data: jsonEncode(pathGeoJson),
    ));

    await mapboxMap!.style.addLayer(LineLayer(
      id: "path-layer",
      sourceId: "path-source",
      paint: LineLayerPaint(
        lineColor: "#2196F3",
        lineWidth: 4.0,
        lineOpacity: 0.8,
      ),
    ));

    // Add polyline layer for the path
    PolylineLayer(
      polylines: [pathPolyline], // From your backend
    );
  }

  Future<void> updateUserLocationOnMap() async {
    if (mapboxMap == null) return;

    // Remove existing user location
    try {
      await mapboxMap!.style.removeLayer("user-location");
      await mapboxMap!.style.removeSource("user-location-source");
    } catch (e) {
      // Layer doesn't exist yet
    }

    final userGeoJson = {
      "type": "FeatureCollection",
      "features": [
        {
          "type": "Feature",
          "properties": {},
          "geometry": {
            "type": "Point",
            "coordinates": [userLocation.coordinates.lng, userLocation.coordinates.lat],
          }
        }
      ]
    };

    await mapboxMap!.style.addSource(GeoJsonSource(
      id: "user-location-source",
      data: jsonEncode(userGeoJson),
    ));

    await mapboxMap!.style.addLayer(CircleLayer(
      id: "user-location",
      sourceId: "user-location-source",
      paint: CircleLayerPaint(
        circleRadius: 8.0,
        circleColor: "#2196F3",
        circleStrokeColor: "#FFFFFF",
        circleStrokeWidth: 2.0,
      ),
    ));
  }

  void _onMapCreated(MapboxMap mapboxMap) {
    this.mapboxMap = mapboxMap;
    
    // Set initial camera position
    mapboxMap.setCamera(CameraOptions(
      center: userLocation,
      zoom: 18.0, // High zoom for indoor navigation
    ));
    
    // Add elements and path once map is ready
    addElementsToMap();
    addPathToMap();
    updateUserLocationOnMap();
    
    // Set up tap listener for POI selection
    mapboxMap.setOnMapTapListener((coordinate) {
      _onMapTap(coordinate);
    });
  }

  void _onMapTap(Point coordinate) {
    // Handle tap on map elements - you can query features at the tap location
    // This replaces your onTapUp gesture detection
    print("Map tapped at: ${coordinate.coordinates.lat}, ${coordinate.coordinates.lng}");
  }

  Future<void> loadGeoJsonData() async {
    String jsonString = await rootBundle.loadString('assets/sample_elements.geojson');
    final geoJsonData = jsonDecode(jsonString);
    // Convert to map layers
  }

  @override
  void dispose() {
    _headingSub?.cancel();
    _accelSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset('assets/images/logo.png'),
        ),
        title: const Text("Mapbox Navigation"),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: () {
              mapboxMap?.setCamera(CameraOptions(
                center: userLocation,
                zoom: 18.0,
              ));
            },
            tooltip: 'Center on my location',
          ),
        ],
      ),
      body: MapWidget(
        key: ValueKey("mapWidget"),
        resourceOptions: ResourceOptions(
          accessToken: "YOUR_MAPBOX_ACCESS_TOKEN", // Replace with your token
        ),
        cameraOptions: CameraOptions(
          center: userLocation,
          zoom: 18.0,
        ),
        onMapCreated: _onMapCreated,
      ),
    );
  }
}
