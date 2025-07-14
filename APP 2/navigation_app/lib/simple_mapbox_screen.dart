import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:convert';

class SimpleMapScreen extends StatefulWidget {
  @override
  _SimpleMapScreenState createState() => _SimpleMapScreenState();
}

class _SimpleMapScreenState extends State<SimpleMapScreen> {
  final MapController mapController = MapController();
  List<Polygon> geoJsonPolygons = [];
  List<Marker> geoJsonMarkers = [];
  List<Polyline> geoJsonPolylines = [];
  bool isLoading = true;
  
  // Center of your GeoJSON polygons (updated for draft_elements.geojson)
  static const LatLng centerLocation = LatLng(33.77466, -84.40163);  // Center of draft polygons
  
  // Bounds of your GeoJSON data for better initial view (updated for draft_elements.geojson)
  static const double minLat = 33.7744;
  static const double maxLat = 33.7748;
  static const double minLng = -84.4021;
  static const double maxLng = -84.4014;

  @override
  void initState() {
    super.initState();
    loadGeoJsonData();
  }

  Future<void> loadGeoJsonData() async {
    try {
      print("🔍 Starting to load GeoJSON...");
      
      // Load GeoJSON from assets
      String jsonString = await rootBundle.loadString('assets/draft_elements.geojson');
      
      print("📄 Raw JSON length: ${jsonString.length}");
      print("📄 First 100 chars: ${jsonString.length > 100 ? jsonString.substring(0, 100) : jsonString}");
      
      if (jsonString.isEmpty) {
        throw Exception("GeoJSON file is empty");
      }
      
      final geoJsonData = jsonDecode(jsonString);
      print("✅ JSON parsed successfully");
      
      List<Polygon> polygons = [];
      List<Marker> markers = [];
      List<Polyline> polylines = [];
      
      // Parse features from GeoJSON
      final features = geoJsonData['features'] as List?;
      if (features == null) {
        throw Exception("No 'features' array found in GeoJSON");
      }
      
      print("📍 Processing ${features.length} features...");
      
      for (var feature in features) {
        final properties = feature['properties'];
        final geometry = feature['geometry'];
        final String name = properties['name'] ?? 'Unknown';
        final String icon = properties['icon'] ?? 'marker';
        
        if (geometry['type'] == 'Polygon') {
          final coordinates = geometry['coordinates'][0]; // First ring of polygon
          
          List<LatLng> points = coordinates.map<LatLng>((coord) => 
            LatLng(coord[1], coord[0]) // Note: GeoJSON is [lng, lat], LatLng is (lat, lng)
          ).toList();
          
          polygons.add(Polygon(
            points: points,
            color: Colors.blue.withOpacity(0.6),
            borderColor: Colors.black,
            borderStrokeWidth: 2.0,
            label: name,
            labelStyle: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ));
          
        } else if (geometry['type'] == 'Point') {
          final coordinates = geometry['coordinates'];
          final LatLng point = LatLng(coordinates[1], coordinates[0]);
          
          // Choose icon based on type
          IconData iconData;
          Color iconColor;
          switch (icon) {
            case 'entrance':
              iconData = Icons.door_front_door;
              iconColor = Colors.green;
              break;
            case 'exit':
              iconData = Icons.exit_to_app;
              iconColor = Colors.red;
              break;
            case 'toilet':
              iconData = Icons.wc;
              iconColor = Colors.blue;
              break;
            default:
              iconData = Icons.place;
              iconColor = Colors.orange;
          }
          
          markers.add(Marker(
            point: point,
            width: 40,
            height: 40,
            child: Container(
              decoration: BoxDecoration(
                color: iconColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Icon(
                iconData,
                color: Colors.white,
                size: 20,
              ),
            ),
          ));
          
        } else if (geometry['type'] == 'LineString') {
          final coordinates = geometry['coordinates'];
          List<LatLng> points = coordinates.map<LatLng>((coord) => 
            LatLng(coord[1], coord[0])
          ).toList();
          
          polylines.add(Polyline(
            points: points,
            color: Colors.brown,
            strokeWidth: 4.0,
          ));
        }
      }
      
      setState(() {
        geoJsonPolygons = polygons;
        geoJsonMarkers = markers;
        geoJsonPolylines = polylines;
        isLoading = false;
      });
      
      print("🎯 Loaded ${polygons.length} polygons, ${markers.length} markers, ${polylines.length} polylines from GeoJSON");
      
    } catch (e) {
      print("❌ Error loading draft_elements.geojson: $e");
      
      // Try fallback to sample_elements.geojson
      try {
        print("🔄 Trying fallback to sample_elements.geojson...");
        String jsonString = await rootBundle.loadString('assets/sample_elements.geojson');
        final geoJsonData = jsonDecode(jsonString);
        
        List<Polygon> polygons = [];
        
        for (var feature in geoJsonData['features']) {
          final properties = feature['properties'];
          final geometry = feature['geometry'];
          
          if (geometry['type'] == 'Polygon') {
            final coordinates = geometry['coordinates'][0];
            
            List<LatLng> points = coordinates.map<LatLng>((coord) => 
              LatLng(coord[1], coord[0])
            ).toList();
            
            Color polygonColor;
            String type = properties['type'] ?? 'other';
            switch (type) {
              case 'booth':
                polygonColor = Colors.green.withOpacity(0.6);
                break;
              case 'blocker':
                polygonColor = Colors.red.withOpacity(0.6);
                break;
              default:
                polygonColor = Colors.blue.withOpacity(0.6);
            }
            
            polygons.add(Polygon(
              points: points,
              color: polygonColor,
              borderColor: Colors.black,
              borderStrokeWidth: 2.0,
              label: properties['name'] ?? 'Unknown',
              labelStyle: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ));
          }
        }
        
        setState(() {
          geoJsonPolygons = polygons;
          geoJsonMarkers = [];
          geoJsonPolylines = [];
          isLoading = false;
        });
        
        print("🎯 Fallback successful: Loaded ${polygons.length} polygons from sample_elements.geojson");
        
      } catch (fallbackError) {
        print("❌ Fallback also failed: $fallbackError");
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // Helper function to check if a point is inside a polygon
  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    int i, j = polygon.length - 1;
    bool oddNodes = false;

    for (i = 0; i < polygon.length; i++) {
      if ((polygon[i].latitude < point.latitude && polygon[j].latitude >= point.latitude ||
          polygon[j].latitude < point.latitude && polygon[i].latitude >= point.latitude) &&
          (polygon[i].longitude <= point.longitude || polygon[j].longitude <= point.longitude)) {
        if (polygon[i].longitude + (point.latitude - polygon[i].latitude) /
            (polygon[j].latitude - polygon[i].latitude) *
            (polygon[j].longitude - polygon[i].longitude) < point.longitude) {
          oddNodes = !oddNodes;
        }
      }
      j = i;
    }
    return oddNodes;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset('assets/images/logo.png'),
        ),
        title: const Text("Simple Map Test"),
        actions: [
          IconButton(
            icon: const Icon(Icons.fit_screen),
            onPressed: () {
              // Fit map to show all GeoJSON polygons
              final bounds = LatLngBounds(
                LatLng(minLat - 0.0001, minLng - 0.0001), // Southwest corner with padding
                LatLng(maxLat + 0.0001, maxLng + 0.0001), // Northeast corner with padding
              );
              mapController.fitCamera(CameraFit.bounds(bounds: bounds, padding: EdgeInsets.all(50)));
            },
            tooltip: 'Fit to polygons',
          ),
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: () {
              // Center the map on the location
              mapController.move(centerLocation, 19.0);
            },
            tooltip: 'Center on location',
          ),
        ],
      ),
      body: isLoading 
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text("Loading GeoJSON polygons..."),
              ],
            ),
          )
        : FlutterMap(
          mapController: mapController,
          options: MapOptions(
            initialCenter: centerLocation,
            initialZoom: 19.0,  // Much closer zoom to see the small polygons
            minZoom: 15.0,
            maxZoom: 22.0,
            onTap: (tapPosition, point) {
              print("🗺️ Map tapped at: ${point.latitude}, ${point.longitude}");
              
              // Check if tap hit any polygon
              String tappedPolygon = "None";
              for (var polygon in geoJsonPolygons) {
                if (_isPointInPolygon(point, polygon.points)) {
                  tappedPolygon = polygon.label ?? "Unknown";
                  break;
                }
              }
              
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("Tapped: $tappedPolygon at ${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}"),
                  duration: Duration(seconds: 3),
                ),
              );
            },
          ),
          children: [
            // Step 1: Basic tile layer
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.navigation_app',
            ),
            
            // Step 2A: GeoJSON Polygons Layer
            PolygonLayer(
              polygons: geoJsonPolygons,
            ),
            
            // Step 2B: GeoJSON Polylines Layer (for doors/lines)
            PolylineLayer(
              polylines: geoJsonPolylines,
            ),
            
            // Step 2C: GeoJSON Markers Layer (for POIs)
            MarkerLayer(
              markers: [
                // User location marker
                Marker(
                  point: centerLocation,
                  width: 40,
                  height: 40,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.purple,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: Icon(
                      Icons.person,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
                // Add all GeoJSON markers
                ...geoJsonMarkers,
              ],
            ),
          ],
        ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Test: Add a new marker when pressed
          print("🔵 Add marker button pressed");
        },
        child: Icon(Icons.add_location),
        tooltip: 'Add marker',
      ),
    );
  }
}
