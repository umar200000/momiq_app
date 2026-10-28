import 'package:momiq_app/core/widgets/momiq_scaffold.dart';
import '../data/current_position.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../data/care_map_runtime.dart';
import 'package:yandex_maps_mapkit/mapkit.dart' as ym;

import 'package:yandex_maps_mapkit/search.dart' as ys;
import 'package:yandex_maps_mapkit/yandex_map.dart';

import '../../../core/theme/app_colors.dart';
import '../../onboarding/presentation/widgets/onboarding_shell.dart';
import '../data/listing_store.dart';
import 'listing_style.dart';

typedef LocationPicker =
    Future<CareLocation?> Function(BuildContext context, CareLocation? current);

Future<CareLocation?> pickCareLocation(
  BuildContext context,
  CareLocation? current,
) => Navigator.of(context).push<CareLocation>(
  MaterialPageRoute(builder: (_) => CareLocationPage(initial: current)),
);

class CareLocationPage extends StatefulWidget {
  const CareLocationPage({super.key, this.initial});
  final CareLocation? initial;
  @override
  State<CareLocationPage> createState() => _CareLocationPageState();
}

class _CareLocationPageState extends State<CareLocationPage>
    with WidgetsBindingObserver
    implements ym.MapCameraListener, ym.MapLoadedListener {
  final _query = TextEditingController();
  bool _initializingMap = false;

  ym.MapWindow? _window;
  ym.Map? _map;
  ys.SearchManager? _search;
  ys.SearchSession? _querySession, _addressSession;
  // MapKit uses weak references, so retain listeners until requests finish.
  ys.SearchSessionSearchListener? _queryListener, _addressListener;
  Timer? _debounce;
  Timer? _tileTimeout;
  bool _tilesFailed = false;
  int _mapGeneration = 0;

  @override
  void onMapLoaded(ym.MapLoadStatistics statistics) {
    _tileTimeout?.cancel();
    if (mounted) setState(() => _tilesFailed = false);
  }

  void _retryTiles() {
    _tileTimeout?.cancel();
    if (_map?.isValid() == true) {
      _map!.removeCameraListener(this);
      _map!.setMapLoadedListener(null);
    }
    setState(() {
      _map = null;
      _window = null;
      _tilesFailed = false;
      _mapGeneration++;
    });
  }

  int _queryVersion = 0, _addressVersion = 0;
  bool _ready = false,
      _running = false,
      _locating = false,
      _searching = false,
      _resolving = false;
  String? _startupError, _searchError, _addressError;
  List<CareLocation> _results = [];
  CareLocation? _selected;
  ym.Point? _pendingPoint;
  static const _tashkent = ym.Point(latitude: 41.3111, longitude: 69.2797);

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    if (_initializingMap) return;
    _initializingMap = true;
    setState(() => _startupError = null);
    try {
      if (!Platform.isAndroid && !Platform.isIOS) {
        throw UnsupportedError('mobile');
      }
      await CareMapRuntime.initialize();
      if (!mounted) return;
      _search = ys.SearchFactory.instance.createSearchManager(
        ys.SearchManagerType.Online,
      );
      _start();
      setState(() => _ready = true);
    } catch (_) {
      if (mounted) {
        setState(
          () => _startupError = lt(
            'Xarita ochilmadi. Android yoki iOS qurilmada qayta urinib ko‘ring.',
            'Map unavailable. Retry on an Android or iOS device.',
            'Карта недоступна. Повторите на устройстве Android или iOS.',
          ),
        );
      }
    } finally {
      _initializingMap = false;
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

  void _mapCreated(ym.MapWindow window) {
    if (!mounted) return;
    _tileTimeout?.cancel();
    _tileTimeout = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _tilesFailed = true);
    });
    window.map.setMapLoadedListener(this);
    _window = window;
    _map = _window!.map;
    final initial = _selected;
    window.map.move(
      ym.CameraPosition(
        initial == null
            ? _tashkent
            : ym.Point(
                latitude: initial.latitude,
                longitude: initial.longitude,
              ),
        zoom: initial == null ? 12 : 17,
        azimuth: 0,
        tilt: 0,
      ),
    );
    window.map.addCameraListener(this);
    setState(() {});
  }

  @override
  void onCameraPositionChanged(
    ym.Map map,
    ym.CameraPosition position,
    ym.CameraUpdateReason reason,
    bool finished,
  ) {
    if (!mounted || reason != ym.CameraUpdateReason.Gestures) return;
    if (!finished) {
      _addressVersion++;
      _addressSession?.cancel();
      if (_selected != null || _addressError != null) {
        setState(() {
          _selected = null;
          _addressError = null;
        });
      }
    } else {
      _reverse(position.target);
    }
  }

  void _searchChanged(String value) {
    _debounce?.cancel();
    _querySession?.cancel();
    final version = ++_queryVersion;
    setState(() {
      _results = [];
      _searchError = null;
      _searching = value.trim().length >= 2;
    });
    if (value.trim().length < 2) return;
    _debounce = Timer(
      const Duration(milliseconds: 650),
      () => _searchPlaces(value.trim(), version),
    );
  }

  ys.SearchOptions _options({required bool reverse}) => ys.SearchOptions(
    searchTypes: reverse ? ys.SearchType.Geo : ys.SearchType.None,
    geometry: !reverse,
    resultPageSize: reverse ? null : 5,
  );

  void _searchPlaces(String text, int version) {
    if (!mounted || _search == null || text.length < 2) return;
    _querySession?.cancel();
    setState(() {
      _searching = true;
      _searchError = null;
    });
    _queryListener = ys.SearchSessionSearchListener(
      onSearchResponse: (response) {
        if (!mounted || version != _queryVersion) return;
        final places = <CareLocation>[];
        for (final item in response.collection.children) {
          final obj = item.asGeoObject();
          if (obj == null) continue;
          final points = obj.geometry
              .map((g) => g.asPoint())
              .whereType<ym.Point>();
          if (points.isEmpty) continue;
          places.add(
            CareLocation(
              latitude: points.first.latitude,
              longitude: points.first.longitude,
              address: [
                obj.name,
                obj.descriptionText,
              ].whereType<String>().where((s) => s.isNotEmpty).join(', '),
            ),
          );
        }
        setState(() {
          _results = places;
          _searching = false;
          _searchError = places.isEmpty
              ? lt('Manzil topilmadi.', 'No places found.', 'Адрес не найден.')
              : null;
        });
      },
      onSearchError: (_) {
        if (!mounted || version != _queryVersion) return;
        setState(() {
          _searching = false;
          _searchError = lt(
            'Qidiruv ishlamadi. Internetni tekshirib, qayta izlang.',
            'Search failed. Check your connection and retry.',
            'Ошибка поиска. Проверьте интернет и повторите.',
          );
        });
      },
    );
    _querySession = _search!.submit(
      ym.Geometry.fromPoint(_map?.cameraPosition.target ?? _tashkent),
      _options(reverse: false),
      _queryListener!,
      text: text,
    );
  }

  void _choose(CareLocation place) {
    FocusScope.of(context).unfocus();
    _debounce?.cancel();
    _querySession?.cancel();
    _queryVersion++;
    _addressVersion++;
    _addressSession?.cancel();
    _map?.move(
      ym.CameraPosition(
        ym.Point(latitude: place.latitude, longitude: place.longitude),
        zoom: 17,
        azimuth: 0,
        tilt: 0,
      ),
    );
    setState(() {
      _selected = place;
      _results = [];
      _searching = false;
      _resolving = false;
      _searchError = null;
      _addressError = null;
      _query.clear();
    });
  }

  void _reverse(ym.Point point) {
    _pendingPoint = point;
    final version = ++_addressVersion;
    _addressSession?.cancel();
    setState(() {
      _selected = null;
      _resolving = true;
      _addressError = null;
    });
    _addressListener = ys.SearchSessionSearchListener(
      onSearchResponse: (response) {
        if (!mounted || version != _addressVersion) return;
        final objects = response.collection.children
            .map((e) => e.asGeoObject())
            .whereType<ym.GeoObject>();
        final obj = objects.firstOrNull;
        final address = obj == null
            ? ''
            : [
                obj.name,
                obj.descriptionText,
              ].whereType<String>().where((s) => s.isNotEmpty).join(', ');
        setState(() {
          _resolving = false;
          // A valid map point remains usable even where no street address exists.
          _selected = CareLocation(
            latitude: point.latitude,
            longitude: point.longitude,
            address: address.isEmpty
                ? '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}'
                : address,
          );
        });
      },
      onSearchError: (_) {
        if (!mounted || version != _addressVersion) return;
        setState(() {
          _resolving = false;
          _addressError = lt(
            'Manzil aniqlanmadi. Internetni tekshirib, qayta urining.',
            'Could not resolve the address. Check your connection and retry.',
            'Не удалось определить адрес. Проверьте интернет и повторите.',
          );
        });
      },
    );
    _addressSession = _search!.submitPoint(
      point,
      _options(reverse: true),
      _addressListener!,
      zoom: 17,
    );
  }

  Future<void> _locate() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _notice(
          lt(
            'GPS o‘chiq. Uni yoqing yoki manzilni xaritadan qo‘lda tanlang.',
            'GPS is off. Enable it or choose the address manually on the map.',
            'GPS выключен. Включите его или выберите адрес на карте вручную.',
          ),
          locationSettings: true,
        );
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (!mounted) return;
      if (permission == LocationPermission.deniedForever) {
        _notice(
          lt(
            'Sozlamalarda joylashuvga ruxsat bering.',
            'Allow location in settings.',
            'Разрешите геолокацию в настройках.',
          ),
          settings: true,
        );
        return;
      }
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        _notice(
          lt(
            'Joylashuv ruxsati berilmadi. Manzilni xaritadan tanlashingiz mumkin.',
            'Permission denied. You can still choose a point on the map.',
            'Доступ не разрешён. Можно выбрать точку на карте.',
          ),
        );
        return;
      }

      final position = await resolveCurrentPosition();
      if (!mounted) return;
      if (_map?.isValid() != true) {
        throw StateError('Map is not ready');
      }
      FocusScope.of(context).unfocus();
      _searchChanged('');
      _query.clear();
      final point = ym.Point(
        latitude: position.latitude,
        longitude: position.longitude,
      );
      _map?.move(ym.CameraPosition(point, zoom: 17, azimuth: 0, tilt: 0));
      _reverse(point);
    } on PositionQualityException {
      if (mounted) {
        _notice(
          lt(
            'Joylashuv yetarlicha aniq emas. Xaritadagi manzilni qo‘lda tanlang yoki qayta urining.',
            'Location is not precise enough. Choose the address manually or retry.',
            'Местоположение недостаточно точное. Выберите адрес вручную или повторите.',
          ),
        );
      }
    } on TimeoutException {
      if (mounted) {
        _notice(
          lt(
            'Joylashuv aniqlanmadi. Ochiqroq joyda qayta urining va aniq joylashuv ruxsatini tekshiring.',
            'Location timed out. Try outdoors and check precise location permission.',
            'Не удалось определить местоположение. Попробуйте на открытом месте и проверьте доступ к точной геопозиции.',
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        _notice(
          lt(
            'Joylashuv olinmadi. Qayta urinib ko‘ring.',
            'Could not get location. Please retry.',
            'Не удалось определить местоположение. Повторите.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _notice(
    String message, {
    bool settings = false,
    bool locationSettings = false,
  }) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      action: settings || locationSettings
          ? SnackBarAction(
              label: lt('Sozlamalar', 'Settings', 'Настройки'),
              onPressed: locationSettings
                  ? Geolocator.openLocationSettings
                  : Geolocator.openAppSettings,
            )
          : null,
    ),
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _queryVersion++;
    _addressVersion++;
    _debounce?.cancel();
    _querySession?.cancel();
    _addressSession?.cancel();
    if (_map?.isValid() == true) _map!.removeCameraListener(this);
    _stop();
    _tileTimeout?.cancel();
    if (_map?.isValid() == true) _map!.setMapLoadedListener(null);
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MomiqScaffold(
    backgroundColor: listingBackground,
    appBar: AppBar(
      backgroundColor: listingBackground,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppColors.chocolate,
      centerTitle: true,
      title: Text(
        lt('Manzilni belgilang', 'Choose a location', 'Укажите адрес'),
        style: profileText(17, bold: true),
      ),
    ),
    body: !_ready
        ? Center(
            child: _startupError == null
                ? const CircularProgressIndicator()
                : Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_startupError!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _initialize,
                          child: Text(
                            lt('Qayta urinish', 'Retry', 'Повторить'),
                          ),
                        ),
                      ],
                    ),
                  ),
          )
        : SafeArea(
            top: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: _searchField(),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    lt(
                      'Manzilni qidiring yoki xaritani suring. GPS ruxsati shart emas.',
                      'Search an address or move the map. GPS permission is optional.',
                      'Найдите адрес или передвиньте карту. Разрешение GPS необязательно.',
                    ),
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: YandexMap(
                          key: ValueKey(_mapGeneration),
                          onMapCreated: _mapCreated,
                        ),
                      ),
                      const Center(
                        child: IgnorePointer(
                          child: FractionalTranslation(
                            translation: Offset(0, -.5),
                            child: Icon(
                              Icons.location_pin,
                              size: 46,
                              color: Color(0xFFD6493B),
                            ),
                          ),
                        ),
                      ),
                      if (_tilesFailed)
                        Positioned(
                          left: 12,
                          right: 12,
                          top: 8,
                          child: Material(
                            color: listingSurface,
                            borderRadius: BorderRadius.circular(10),
                            elevation: 2,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    lt(
                                      'Xarita yuklanmadi. Internetni yoqing yoki aloqani tekshiring.',
                                      'Map did not load. Turn on internet or check your connection.',
                                      'Карта не загрузилась. Включите интернет или проверьте соединение.',
                                    ),
                                    style: profileText(12),
                                  ),
                                  TextButton(
                                    onPressed: _retryTiles,
                                    child: Text(
                                      lt(
                                        'Qayta yuklash',
                                        'Reload map',
                                        'Загрузить снова',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        right: 14,
                        bottom: 28,
                        child: FloatingActionButton.small(
                          heroTag: 'locate',
                          tooltip: lt(
                            'Joriy joylashuv',
                            'Current location',
                            'Моё местоположение',
                          ),
                          backgroundColor: listingSurface,
                          onPressed: _locating || _map == null ? null : _locate,
                          child: _locating
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.my_location_rounded,
                                  color: AppColors.brown,
                                ),
                        ),
                      ),
                      if (_query.text.trim().length >= 2)
                        Positioned(
                          left: 12,
                          right: 12,
                          top: 0,
                          child: Material(
                            color: listingSurface,
                            elevation: 4,
                            borderRadius: BorderRadius.circular(9),
                            clipBehavior: Clip.antiAlias,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 240),
                              child: ListView(
                                shrinkWrap: true,
                                padding: EdgeInsets.zero,
                                children: [
                                  if (_searchError != null)
                                    Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Text(
                                        _searchError!,
                                        style: profileText(12),
                                      ),
                                    ),
                                  for (final result in _results)
                                    ListTile(
                                      dense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12,
                                          ),
                                      leading: const Icon(
                                        Icons.location_on,
                                        size: 20,
                                        color: listingGold,
                                      ),
                                      title: Text(
                                        result.address,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: profileText(12),
                                      ),
                                      onTap: () => _choose(result),
                                    ),
                                  const Divider(
                                    height: 1,
                                    color: listingBorder,
                                  ),
                                  ListTile(
                                    dense: true,
                                    leading: const Icon(
                                      Icons.my_location_rounded,
                                      size: 20,
                                      color: AppColors.brown,
                                    ),
                                    title: Text(
                                      lt(
                                        'Joriy joylashuvimdan foydalanish',
                                        'Use my current location',
                                        'Использовать моё местоположение',
                                      ),
                                      style: profileText(11),
                                    ),
                                    onTap: _locating || _map == null
                                        ? null
                                        : _locate,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                _selectionPanel(),
              ],
            ),
          ),
  );

  Widget _searchField() => TextField(
    controller: _query,
    onChanged: _searchChanged,
    onSubmitted: (value) {
      _debounce?.cancel();
      _searchPlaces(value.trim(), ++_queryVersion);
    },
    decoration: InputDecoration(
      filled: true,
      fillColor: listingSurface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      hintText: lt(
        'Manzil yoki joy nomini qidiring',
        'Search address or place',
        'Адрес или название места',
      ),
      hintStyle: profileText(12),
      prefixIcon: const Icon(Icons.search_rounded, size: 21),
      suffixIcon: _searching
          ? const Padding(
              padding: EdgeInsets.all(15),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : IconButton(
              tooltip: lt('Tozalash', 'Clear', 'Очистить'),
              onPressed: () {
                _query.clear();
                _searchChanged('');
              },
              icon: const Icon(Icons.close_rounded, size: 20),
            ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: BorderSide.none,
      ),
    ),
  );

  Widget _selectionPanel() => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
    decoration: const BoxDecoration(
      color: listingSurface,
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 32,
            height: 3,
            decoration: BoxDecoration(
              color: listingBorder,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          lt('Tanlangan manzil', 'Selected location', 'Выбранный адрес'),
          style: profileText(14, bold: true),
        ),
        const SizedBox(height: 4),
        Text(
          _resolving
              ? lt(
                  'Manzil aniqlanmoqda…',
                  'Finding address…',
                  'Определяем адрес…',
                )
              : _addressError ??
                    _selected?.address ??
                    lt(
                      'Avval xaritada manzilni belgilang',
                      'Choose a point on the map first',
                      'Сначала укажите точку на карте',
                    ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: profileText(11),
        ),
        const SizedBox(height: 4),
        Text(
          lt(
            'Xaritani surib, aniq joyni belgilang',
            'Move the map to choose the exact point',
            'Передвиньте карту к нужной точке',
          ),
          style: profileText(9),
        ),
        if (_addressError != null)
          TextButton(
            onPressed: () => _reverse(_pendingPoint!),
            child: Text(lt('Qayta urinish', 'Retry', 'Повторить')),
          ),
        const SizedBox(height: 12),
        FilledButton(
          style: serviceButtonStyle(),
          onPressed: _selected == null || _resolving
              ? null
              : () => Navigator.pop(context, _selected),
          child: Text(
            lt('Manzilni tasdiqlash', 'Confirm location', 'Подтвердить адрес'),
          ),
        ),
      ],
    ),
  );
}
