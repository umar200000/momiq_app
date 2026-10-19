import 'dart:io';
import 'package:flutter/material.dart';
import 'package:yandex_maps_mapkit/mapkit.dart' as ym;
import 'package:yandex_maps_mapkit/yandex_map.dart';
import '../../onboarding/presentation/widgets/onboarding_shell.dart';
import '../data/care_map_runtime.dart';
import '../data/listing_store.dart';
import 'listing_style.dart';

/// A real, non-interactive Yandex map. Editing opens the full location picker.
class CareLocationPreview extends StatefulWidget {
  const CareLocationPreview({super.key, this.location, required this.onTap});
  final CareLocation? location;
  final VoidCallback onTap;
  @override
  State<CareLocationPreview> createState() => _CareLocationPreviewState();
}

class _CareLocationPreviewState extends State<CareLocationPreview>
    with WidgetsBindingObserver {
  ym.MapWindow? _window;
  ym.Map? _map;
  bool _ready = false, _running = false, _failed = false;
  bool get _supported => Platform.isAndroid || Platform.isIOS;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_supported) _init();
  }

  Future<void> _init() async {
    try {
      await CareMapRuntime.initialize();
      if (!mounted) return;
      _start();
      setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _start() {
    if (!_running) {
      CareMapRuntime.startView();
      _running = true;
    }
  }

  void _stop() {
    if (_running) {
      CareMapRuntime.stopView();
      _running = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_ready) return;
    if (state == AppLifecycleState.resumed) {
      _start();
    } else {
      _stop();
    }
  }

  void _move() {
    final location = widget.location;
    _map?.move(
      ym.CameraPosition(
        ym.Point(
          latitude: location?.latitude ?? 41.3111,
          longitude: location?.longitude ?? 69.2797,
        ),
        zoom: location == null ? 12 : 16,
        azimuth: 0,
        tilt: 0,
      ),
    );
  }

  @override
  void didUpdateWidget(CareLocationPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) _move();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      border: Border.all(color: listingBorder),
      borderRadius: BorderRadius.circular(10),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        SizedBox(
          height: 140,
          child: Stack(
            children: [
              Positioned.fill(
                child: _ready
                    ? IgnorePointer(
                        child: YandexMap(
                          onMapCreated: (window) {
                            if (!mounted) return;
                            _window = window;
                            _map = _window!.map;
                            _move();
                          },
                        ),
                      )
                    : Container(
                        color: const Color(0xFFE8E5DD),
                        child: Center(
                          child: _supported && !_failed
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: listingGold,
                                  ),
                                )
                              : Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.map_outlined,
                                      size: 36,
                                      color: listingGold,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      lt(
                                        'Yandex xaritasi',
                                        'Yandex Maps',
                                        'Яндекс Карты',
                                      ),
                                      style: profileText(12),
                                    ),
                                  ],
                                ),
                        ),
                      ),
              ),
              if (_ready)
                const Center(
                  child: IgnorePointer(
                    child: FractionalTranslation(
                      translation: Offset(0, -.5),
                      child: Icon(
                        Icons.location_pin,
                        color: Color(0xFFD6493B),
                        size: 38,
                      ),
                    ),
                  ),
                ),
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: const ValueKey('chooseCareLocation'),
                    onTap: widget.onTap,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ],
          ),
        ),
        InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 19),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    widget.location?.address ??
                        lt(
                          'Manzil tanlanmagan',
                          'No location selected',
                          'Адрес не выбран',
                        ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: profileText(10),
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  lt('Xaritada belgilash', 'Choose on map', 'На карте'),
                  style: profileText(10).copyWith(
                    color: listingAccent,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
