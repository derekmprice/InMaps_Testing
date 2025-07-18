import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';

class SimpleMapScreen extends StatefulWidget {
  @override
  _SimpleMapScreenState createState() => _SimpleMapScreenState();
}

class _SimpleMapScreenState extends State<SimpleMapScreen> {
  final MapController mapController = MapController();
  List<Polygon> geoJsonPolygons = [];
  List<Marker> geoJsonMarkers = [];
  List<Polyline> geoJsonPolylines = [];
  List<Polyline> graphEdges = [];
  List<Marker> graphNodes = [];
  bool isLoading = true;
  bool showGraph = false;
  Map<String, dynamic>? geoJsonData; // Store parsed GeoJSON data // Store parsed GeoJSON data
  
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
      String jsonString = await rootBundle.loadString('assets/ExhibitionHallFloor1.geojson');
      
      print("📄 Raw JSON length: ${jsonString.length}");
      print("📄 First 100 chars: ${jsonString.length > 100 ? jsonString.substring(0, 100) : jsonString}");
      
      if (jsonString.isEmpty) {
        throw Exception("GeoJSON file is empty");
      }
      final parsedGeoJsonData = jsonDecode(jsonString);
      geoJsonData = parsedGeoJsonData; // Save to class variable
      print("✅ JSON parsed successfully");
      
      List<Polygon> polygons = [];
      List<Marker> markers = [];
      List<Polyline> polylines = [];
      List<Polyline> graphEdgeLines = [];
      List<Marker> graphNodeMarkers = [];

      
      // Parse features from GeoJSON
      final features = geoJsonData != null ? geoJsonData!['features'] as List? : null;
      if (features == null) {
        throw Exception("No 'features' array found in GeoJSON");
      }
      
      print("📍 Processing ${features.length} features...");
      
      for (var feature in features) {
        final properties = feature['properties'];
        final geometry = feature['geometry'];
        final String name = properties['name'] ?? 'Unknown';
        final String icon = properties['icon'] ?? 'marker';
        
        // Skip features with missing or invalid coordinates
        if (geometry['coordinates'] == null || 
            (geometry['coordinates'] is List && (geometry['coordinates'] as List).isEmpty)) {
          print("⚠️ Skipping feature with missing coordinates: $name");
          continue;
        }
        
        if (geometry['type'] == 'Polygon') {
          final coordinates = geometry['coordinates'][0]; // First ring of polygon
          
          if (coordinates == null || coordinates.isEmpty) {
            print("⚠️ Skipping polygon with empty coordinates: $name");
            continue;
          }
          
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
          
          // Handle malformed Point coordinates
          if (coordinates == null || coordinates.isEmpty) {
            print("⚠️ Skipping point with empty coordinates: $name");
            continue;
          }
          
          // Check if coordinates have both longitude and latitude
          if (coordinates.length < 2) {
            print("⚠️ Skipping point with incomplete coordinates: $name (only ${coordinates.length} values)");
            continue;
          }
          
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
          
          // Update: Only add table number markers for 'marker' icon type
          if (icon == 'marker') {
            markers.add(Marker(
              point: point,
              width: 20,
              height: 12,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                alignment: Alignment.center,
                child: Text(
                  properties['tableNumber'] ?? '',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ));
          } else {
            markers.add(Marker(
              point: point,
              width: 30,
              height: 30,
              child: Container(
                decoration: BoxDecoration(
                  color: iconColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Icon(
                  iconData,
                  color: Colors.white,
                  size: 15,
                ),
              ),
            ));
          }
          
        } else if (geometry['type'] == 'LineString') {
          final coordinates = geometry['coordinates'];
          
          if (coordinates == null || coordinates.isEmpty) {
            print("⚠️ Skipping linestring with empty coordinates: $name");
            continue;
          }
          
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
      
      // Process graph data if it exists
      final metadata = geoJsonData!['_metadata'];
      if (metadata != null && metadata['graph'] != null) {
        try {
          final graph = metadata['graph'];
          print("📊 Processing graph data...");
          
          // Process graph nodes
          final nodes = graph['nodes'] as List?;
          Map<String, int> nodeIdToIndex = {};
          
          if (nodes != null) {
            print("📍 Processing ${nodes.length} graph nodes...");
            for (int i = 0; i < nodes.length; i++) {
              var node = nodes[i];
              if (node['coordinates'] != null && node['coordinates'].length >= 2) {
                final LatLng nodePoint = LatLng(node['coordinates'][1], node['coordinates'][0]);
                
                // Store node ID to index mapping
                if (node['id'] != null) {
                  nodeIdToIndex[node['id'].toString()] = i;
                }
                
                graphNodeMarkers.add(Marker(
                  point: nodePoint,
                  width: 20,
                  height: 20,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.purple,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                    child: Icon(
                      Icons.circle,
                      color: Colors.white,
                      size: 8,
                    ),
                  ),
                ));
              }
            }
          }
          
          // Process graph edges
          final edges = graph['edges'] as List?;
          if (edges != null && nodes != null) {
            print("🔗 Processing ${edges.length} graph edges...");
            for (var edge in edges) {
              try {
                int? fromIndex;
                int? toIndex;
                
                // Handle both string IDs and integer indices
                if (edge['from'] is String) {
                  fromIndex = nodeIdToIndex[edge['from']];
                } else if (edge['from'] is int) {
                  fromIndex = edge['from'];
                }
                
                if (edge['to'] is String) {
                  toIndex = nodeIdToIndex[edge['to']];
                } else if (edge['to'] is int) {
                  toIndex = edge['to'];
                }
                
                if (fromIndex != null && toIndex != null && 
                    fromIndex < nodes.length && toIndex < nodes.length) {
                  final fromNode = nodes[fromIndex];
                  final toNode = nodes[toIndex];
                  
                  if (fromNode['coordinates'] != null && fromNode['coordinates'].length >= 2 &&
                      toNode['coordinates'] != null && toNode['coordinates'].length >= 2) {
                    final LatLng fromPoint = LatLng(fromNode['coordinates'][1], fromNode['coordinates'][0]);
                    final LatLng toPoint = LatLng(toNode['coordinates'][1], toNode['coordinates'][0]);
                    
                    graphEdgeLines.add(Polyline(
                      points: [fromPoint, toPoint],
                      color: Colors.red.withOpacity(0.7),
                      strokeWidth: 2.0,
                    ));
                  }
                }
              } catch (e) {
                print("⚠️ Error processing edge: $e");
              }
            }
          }
          
          print("🔗 Loaded ${graphNodeMarkers.length} graph nodes and ${graphEdgeLines.length} graph edges");
        } catch (e) {
          print("⚠️ Error processing graph data: $e");
          // Continue without graph data
        }
      }
      
      setState(() {
        geoJsonPolygons = polygons;
        geoJsonMarkers = markers;
        geoJsonPolylines = polylines;
        graphNodes = graphNodeMarkers;
        graphEdges = graphEdgeLines;
        isLoading = false;
      });
      
      print("🎯 Loaded ${polygons.length} polygons, ${markers.length} markers, ${polylines.length} polylines from GeoJSON");
      
    } catch (e) {
      print("❌ Error loading DemoDayRoughDraft.geojson: $e");
      
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
          graphNodes = [];
          graphEdges = [];
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
  
  // Helper method to build action buttons for the popup
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.blue),
            SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // Helper method to build tag chips
  Widget _buildTag(String label) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: Colors.blue,
        ),
      ),
    );
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
            icon: Icon(showGraph ? Icons.visibility_off : Icons.visibility),
            onPressed: () {
              setState(() {
                showGraph = !showGraph;
              });
            },
            tooltip: showGraph ? 'Hide Graph' : 'Show Graph',
          ),
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
              // Check if the tap hit any marker
              for (var marker in geoJsonMarkers) {
                if ((marker.point.latitude - point.latitude).abs() < 0.000005 &&
                    (marker.point.longitude - point.longitude).abs() < 0.000005) {
                  // Access the properties of the tapped marker
                  Map<String, dynamic>? tappedFeature;
                  
                  if (geoJsonData != null && geoJsonData!['features'] != null) {
                    for (var feature in geoJsonData!['features']) {
                      if (feature['geometry'] != null && 
                          feature['geometry']['type'] == 'Point' &&
                          feature['geometry']['coordinates'] != null) {
                        var coords = feature['geometry']['coordinates'];
                        if (coords.length >= 2 && 
                            (coords[1] - marker.point.latitude).abs() < 0.0000005 &&
                            (coords[0] - marker.point.longitude).abs() < 0.0000005) {
                          tappedFeature = feature;
                          break;
                        }
                      }
                    }
                  }
                  
                  if (tappedFeature != null) {
                    final properties = tappedFeature['properties'];
                    final name = properties['name'] ?? 'Unknown';
                    final icon = properties['icon'] ?? 'marker';
                    
                    // Check if this is a marker type POI (table) or another type of POI
                    if (icon == 'marker') {
                      // For marker type POIs, show the detailed popup
                      final description = properties['description'] ?? 'No description available';
                      final link = properties['link'] ?? 'No link available';

                      // Get additional properties with default values
                      final email = properties['email'] ?? 'No email available';
                      final phone = properties['phone'] ?? properties['tableNumber'] ?? 'No phone available';
                      
                      // Show a dialog with the enhanced table details
                      showDialog(
                        context: context,
                        builder: (context) {
                        return Dialog(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Container(
                            width: double.maxFinite,
                            constraints: BoxConstraints(maxWidth: 500),
                            padding: EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Title with close button
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        name,
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.close),
                                      onPressed: () => Navigator.of(context).pop(),
                                    ),
                                  ],
                                ),
                                
                                // Action buttons row
                                Container(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                    children: [
                                      _buildActionButton(
                                        icon: Icons.directions,
                                        label: 'Directions',
                                        onPressed: () {
                                          // Directions action
                                          Navigator.of(context).pop();
                                          // Navigate to directions screen
                                        },
                                      ),
                                      _buildActionButton(
                                        icon: Icons.schedule,
                                        label: 'Visit',
                                        onPressed: () {
                                          // Visit action
                                        },
                                      ),
                                      _buildActionButton(
                                        icon: Icons.bookmark_border,
                                        label: 'Bookmark',
                                        onPressed: () {
                                          // Bookmark action
                                        },
                                      ),
                                      _buildActionButton(
                                        icon: Icons.language,
                                        label: 'Website',
                                        onPressed: () {
                                          // Open link in browser
                                          if (link.isNotEmpty && link != 'No link available') {
                                            launchUrl(Uri.parse(link));
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                
                                Divider(),
                                
                                // Tags area (placeholder for now)
                                Container(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Tags:',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 4,
                                        children: [
                                          _buildTag('Exhibition'),
                                          _buildTag('Technology'),
                                          _buildTag('Innovation'),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                
                                Divider(),
                                
                                // Description and logo area
                                Container(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Description
                                      Expanded(
                                        flex: 3,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Description:',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                            SizedBox(height: 4),
                                            Text(
                                              description.isEmpty || description == 'No description available' 
                                                ? 'No description available for this exhibitor.'
                                                : description,
                                              style: TextStyle(fontSize: 14),
                                            ),
                                          ],
                                        ),
                                      ),
                                      
                                      SizedBox(width: 12),
                                      
                                      // Logo
                                      Expanded(
                                        flex: 1,
                                        child: Container(
                                          height: 80,
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade200,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: properties['imageUrl'] != null && properties['imageUrl'].toString().isNotEmpty
                                            ? Image.network(
                                                properties['imageUrl'],
                                                fit: BoxFit.contain,
                                                errorBuilder: (context, error, stackTrace) => 
                                                  Icon(Icons.business, size: 40, color: Colors.grey),
                                              )
                                            : Icon(Icons.business, size: 40, color: Colors.grey),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                
                                Divider(),
                                
                                // Contact information
                                Container(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Contact:',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(Icons.phone, size: 16, color: Colors.blue),
                                          SizedBox(width: 8),
                                          Text(phone, style: TextStyle(fontSize: 14)),
                                        ],
                                      ),
                                      SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(Icons.email, size: 16, color: Colors.blue),
                                          SizedBox(width: 8),
                                          Text(email, style: TextStyle(fontSize: 14)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                    } else {
                      // For non-marker type POIs, show a simple popup with just the name
                      showDialog(
                        context: context,
                        builder: (context) {
                          return AlertDialog(
                            title: Text(name),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: Text('Close'),
                              ),
                            ],
                          );
                        },
                      );
                    }
                  }
                  return;
                }
              }


              // If no marker was tapped, check polygons
              String tappedPolygon = "None";
              for (var polygon in geoJsonPolygons) {
                if (_isPointInPolygon(point, polygon.points)) {
                  tappedPolygon = polygon.label ?? "Unknown";
                  break;
                }
              }

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("Tapped: \\${tappedPolygon} at \\${point.latitude.toStringAsFixed(6)}, \\${point.longitude.toStringAsFixed(6)}"),
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
            
            // Step 2C: Graph Edges Layer (for navigation graph)
            if (showGraph) PolylineLayer(
              polylines: graphEdges,
            ),
            
            // Step 2D: GeoJSON Markers Layer (for POIs)
            MarkerLayer(
              markers: [
                // User location marker
                Marker(
                  point: centerLocation,
                  width: 20,
                  height: 20,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.blue, // Blue dot for GPS-like appearance
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
                // Add all GeoJSON markers
                ...geoJsonMarkers,
                // Add all graph node markers
                if (showGraph) ...graphNodes,
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
