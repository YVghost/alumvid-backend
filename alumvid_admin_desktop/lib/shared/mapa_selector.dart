import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/location_search_service.dart';
import 'tema.dart';

const mapaTiles = 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}';
const mapaAgente = 'com.alumvid.app';
const quito = LatLng(-0.1807, -78.4678);

/// Punto elegido en el mapa y, si se buscó, su dirección.
class UbicacionElegida {
  const UbicacionElegida(this.punto, [this.direccion]);
  final LatLng punto;
  final String? direccion;
}

/// Pantalla para marcar la ubicación de entrega: buscando la dirección o tocando el mapa.
class MapaSelectorScreen extends StatefulWidget {
  const MapaSelectorScreen({super.key, this.inicial, this.titulo = 'Ubicación de entrega'});
  final LatLng? inicial;
  final String titulo;

  @override
  State<MapaSelectorScreen> createState() => _MapaSelectorScreenState();
}

class _MapaSelectorScreenState extends State<MapaSelectorScreen> {
  final _mapa = MapController();
  final _busqueda = TextEditingController();
  late LatLng? _punto = widget.inicial;
  String? _direccion;
  List<PlaceSearchResult> _resultados = [];
  bool _buscando = false;
  Timer? _espera;

  @override
  void dispose() {
    _espera?.cancel();
    _busqueda.dispose();
    super.dispose();
  }

  void _escribir(String texto) {
    _espera?.cancel();
    if (texto.trim().length < 3) {
      setState(() => _resultados = []);
      return;
    }
    _espera = Timer(const Duration(milliseconds: 450), () async {
      setState(() => _buscando = true);
      try {
        final r = await LocationSearchService.searchPlaces(texto, center: _punto ?? quito);
        if (mounted) setState(() => _resultados = r.take(6).toList());
      } catch (_) {
        if (mounted) setState(() => _resultados = []);
      } finally {
        if (mounted) setState(() => _buscando = false);
      }
    });
  }

  void _elegir(PlaceSearchResult r) {
    FocusScope.of(context).unfocus();
    setState(() {
      _punto = r.location;
      _direccion = r.address.isNotEmpty ? r.address : r.name;
      _resultados = [];
      _busqueda.text = r.name;
    });
    _mapa.move(r.location, 17);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.titulo)),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _punto == null ? null : () => Navigator.pop(context, UbicacionElegida(_punto!, _direccion)),
            icon: const Icon(Icons.check),
            label: Text(_punto == null ? 'Busca la dirección o toca el mapa' : 'Usar esta ubicación'),
          ),
        ),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapa,
            options: MapOptions(
              initialCenter: widget.inicial ?? quito,
              initialZoom: widget.inicial == null ? 12 : 16,
              onTap: (_, p) => setState(() {
                _punto = p;
                _direccion = null;
                _resultados = [];
              }),
            ),
            children: [
              TileLayer(urlTemplate: mapaTiles, userAgentPackageName: mapaAgente),
              if (_punto != null)
                MarkerLayer(markers: [
                  Marker(
                    point: _punto!,
                    width: 48,
                    height: 48,
                    alignment: Alignment.topCenter,
                    child: const Icon(Icons.location_on, color: AppColors.danger, size: 48),
                  ),
                ]),
            ],
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Column(
              children: [
                Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(14),
                  color: AppColors.surface,
                  child: TextField(
                    controller: _busqueda,
                    onChanged: _escribir,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Buscar dirección o lugar',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _buscando
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          : null,
                    ),
                  ),
                ),
                if (_resultados.isNotEmpty)
                  Card(
                    margin: const EdgeInsets.only(top: 6),
                    child: Column(
                      children: [
                        for (final r in _resultados)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.place_outlined),
                            title: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(r.address, maxLines: 1, overflow: TextOverflow.ellipsis),
                            onTap: () => _elegir(r),
                          ),
                      ],
                    ),
                  )
                else if (_punto != null)
                  Card(
                    margin: const EdgeInsets.only(top: 6),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(
                        _direccion ?? '${_punto!.latitude.toStringAsFixed(5)}, ${_punto!.longitude.toStringAsFixed(5)}',
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Mini mapa de solo lectura con un marcador.
class MiniMapa extends StatelessWidget {
  const MiniMapa({super.key, required this.punto, this.alto = 160});
  final LatLng punto;
  final double alto;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: alto,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: punto,
            initialZoom: 15,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag),
          ),
          children: [
            TileLayer(urlTemplate: mapaTiles, userAgentPackageName: mapaAgente),
            MarkerLayer(markers: [
              Marker(
                point: punto,
                width: 40,
                height: 40,
                alignment: Alignment.topCenter,
                child: const Icon(Icons.location_on, color: AppColors.danger, size: 40),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
