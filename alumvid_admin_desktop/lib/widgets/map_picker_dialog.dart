import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/location_search_service.dart';
import '../theme/app_theme.dart';

class MapPickerResult {
  final LatLng location;
  final String address;

  MapPickerResult({required this.location, required this.address});
}

class MapPickerDialog extends StatefulWidget {
  final LatLng initialLocation;
  final String title;

  const MapPickerDialog({
    super.key,
    this.initialLocation = const LatLng(-0.1807, -78.4678), // Quito Centro
    this.title = 'Elegir Ubicación de Parada en Google Maps',
  });

  @override
  State<MapPickerDialog> createState() => _MapPickerDialogState();
}

class _MapPickerDialogState extends State<MapPickerDialog> {
  late LatLng _selectedLocation;
  final MapController _mapController = MapController();
  final TextEditingController _searchCtrl = TextEditingController();

  Timer? _searchDebounce;
  Timer? _mapMoveDebounce;
  List<PlaceSearchResult> _searchResults = [];
  bool _isSearching = false;
  bool _isResolvingAddress = false;
  String _selectedAddress = '';

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.initialLocation;
    _reverseGeocode(_selectedLocation);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _mapMoveDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return;

    setState(() => _isSearching = true);

    try {
      final results = await LocationSearchService.searchPlaces(
        cleanQuery,
        center: _selectedLocation,
      );
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      debugPrint('[MapPicker] Error en búsqueda de lugares: $e');
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _reverseGeocode(LatLng point) async {
    if (!mounted) return;
    setState(() => _isResolvingAddress = true);

    try {
      final addr = await LocationSearchService.reverseGeocode(point);
      if (mounted) {
        setState(() {
          _selectedAddress = addr;
          _isResolvingAddress = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isResolvingAddress = false);
    }
  }

  void _selectSearchResult(PlaceSearchResult item) {
    setState(() {
      _selectedLocation = item.location;
      _selectedAddress = item.address;
      _searchCtrl.text = item.name;
      _searchResults = [];
    });
    _mapController.move(item.location, 16.0);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppTheme.border),
      ),
      child: Container(
        width: 860,
        height: 640,
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Encabezado
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.location_on, color: AppTheme.primaryLight, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      widget.title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppTheme.textMuted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(color: AppTheme.border, height: 16),

            // Barra de Búsqueda Inteligente (Google Places / POIs)
            TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              onSubmitted: (q) => _performSearch(q),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Buscar en Quito y Ecuador (ej: Listo Primax, Conjunto Ciudad Alegría, Casales, Carcelén...)',
                hintStyle: const TextStyle(color: AppTheme.textDim, fontSize: 12),
                prefixIcon: const Icon(Icons.search, color: AppTheme.textMuted, size: 18),
                suffixIcon: _isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryLight),
                        ),
                      )
                    : (_searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16, color: AppTheme.textMuted),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchResults = []);
                            },
                          )
                        : null),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                isDense: true,
                filled: true,
                fillColor: AppTheme.surfaceCard,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppTheme.primaryLight),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Canvas del Mapa con Pin Fijo Central y Overlay de Resultados
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _selectedLocation,
                        initialZoom: 15.5,
                        onPositionChanged: (camera, hasGesture) {
                          if (hasGesture) {
                            setState(() {
                              _selectedLocation = camera.center;
                              _isResolvingAddress = true;
                            });
                            _mapMoveDebounce?.cancel();
                            _mapMoveDebounce = Timer(const Duration(milliseconds: 380), () {
                              _reverseGeocode(camera.center);
                            });
                          }
                        },
                        onTap: (tapPosition, point) {
                          _mapController.move(point, _mapController.camera.zoom);
                          setState(() {
                            _selectedLocation = point;
                            _isResolvingAddress = true;
                          });
                          _mapMoveDebounce?.cancel();
                          _mapMoveDebounce = Timer(const Duration(milliseconds: 300), () {
                            _reverseGeocode(point);
                          });
                        },
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
                          userAgentPackageName: 'com.alumvid.admin',
                        ),
                      ],
                    ),

                    // Pin Rojo Fijo en el Centro del Visor
                    Center(
                      child: FractionalTranslation(
                        translation: const Offset(0.0, -0.42),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: AppTheme.statusAlerta,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.statusAlerta.withValues(alpha: 0.65),
                                    blurRadius: 10,
                                    spreadRadius: 2,
                                  ),
                                  const BoxShadow(
                                    color: Colors.black54,
                                    blurRadius: 6,
                                    offset: Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.location_pin, color: Colors.white, size: 24),
                            ),
                            Container(
                              width: 5,
                              height: 5,
                              margin: const EdgeInsets.only(top: 1),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    blurRadius: 3,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Overlay Flotante de Sugerencias de Autocompletado Inteligente
                    if (_searchResults.isNotEmpty)
                      Positioned(
                        top: 8,
                        left: 8,
                        right: 8,
                        child: Container(
                          constraints: const BoxConstraints(maxHeight: 240),
                          decoration: BoxDecoration(
                            color: const Color(0xF80F172A),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.6)),
                            boxShadow: const [
                              BoxShadow(color: Colors.black87, blurRadius: 12, offset: Offset(0, 4)),
                            ],
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: _searchResults.length,
                            separatorBuilder: (ctx, i) => const Divider(color: AppTheme.border, height: 1),
                            itemBuilder: (ctx, idx) {
                              final item = _searchResults[idx];
                              return ListTile(
                                dense: true,
                                leading: const Icon(Icons.location_on, color: AppTheme.primaryLight, size: 18),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item.name,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1E293B),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: AppTheme.border),
                                      ),
                                      child: Text(
                                        item.source,
                                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 9.5),
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Text(
                                  item.address,
                                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () => _selectSearchResult(item),
                              );
                            },
                          ),
                        ),
                      ),

                    // Badge flotante con la Dirección Resuelta bajo el Pin
                    Positioned(
                      bottom: 12,
                      left: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        decoration: BoxDecoration(
                          color: const Color(0xF20F172A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.statusCompletada.withValues(alpha: 0.6)),
                          boxShadow: const [
                            BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 2)),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.pin_drop, color: AppTheme.statusCompletada, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _isResolvingAddress
                                  ? const Row(
                                      children: [
                                        SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(strokeWidth: 1.5, color: AppTheme.statusCompletada),
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Detectando dirección exacta...',
                                          style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                                        ),
                                      ],
                                    )
                                  : Text(
                                      _selectedAddress.isNotEmpty
                                          ? _selectedAddress
                                          : 'Buscando punto de entrega...',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${_selectedLocation.latitude.toStringAsFixed(4)}, ${_selectedLocation.longitude.toStringAsFixed(4)}',
                              style: const TextStyle(color: AppTheme.textDim, fontSize: 10, fontFamily: 'monospace'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Botones inferiores
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar', style: TextStyle(color: AppTheme.textMuted)),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.statusCompletada,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Confirmar Ubicación', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  onPressed: () {
                    final resolvedAddr = _selectedAddress.isNotEmpty
                        ? _selectedAddress
                        : (_searchCtrl.text.isNotEmpty ? _searchCtrl.text : 'Ubicación seleccionada en Quito');
                    Navigator.pop(context, MapPickerResult(location: _selectedLocation, address: resolvedAddr));
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
