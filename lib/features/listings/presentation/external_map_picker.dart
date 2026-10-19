import 'package:flutter/material.dart';
import 'package:map_launcher/map_launcher.dart';
import '../../../core/widgets/momiq_shimmer.dart';
import '../../onboarding/presentation/widgets/onboarding_shell.dart';
import '../data/listing_store.dart';
import 'listing_style.dart';

typedef ExternalMapLoader =
    Future<List<SupportedMap>> Function(CareLocation location);

Future<List<SupportedMap>> installedNavigationMaps(
  CareLocation location,
) async {
  final request = MapLauncher.directions(
    Location.coords(
      location.latitude,
      location.longitude,
      title: location.address,
    ),
  );
  final maps = await request.getSupportedMaps(const [
    MapApp.yandexMaps,
    MapApp.yandexNavi,
    MapApp.google,
    MapApp.doubleGis,
    MapApp.apple,
    MapApp.waze,
  ]);
  return maps.where((map) => map.isInstalled).toList();
}

Future<void> showExternalMapPicker(
  BuildContext context,
  CareLocation location, {
  ExternalMapLoader loader = installedNavigationMaps,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: listingSurface,
  showDragHandle: true,
  builder: (_) => ExternalMapPicker(location: location, loader: loader),
);

class ExternalMapPicker extends StatefulWidget {
  const ExternalMapPicker({
    super.key,
    required this.location,
    this.loader = installedNavigationMaps,
  });
  final CareLocation location;
  final ExternalMapLoader loader;
  @override
  State<ExternalMapPicker> createState() => _ExternalMapPickerState();
}

class _ExternalMapPickerState extends State<ExternalMapPicker> {
  late Future<List<SupportedMap>> _maps = widget.loader(widget.location);
  bool _opening = false;
  String? _error;
  Future<void> _open(SupportedMap map) async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      await map.show();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = lt(
            'Navigator ochilmadi. Qayta urinib ko‘ring yoki boshqa ilovani tanlang.',
            'Could not open the navigator. Retry or choose another app.',
            'Не удалось открыть навигатор. Повторите или выберите другое приложение.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Widget _loading() => MomiqShimmer(
    child: Column(
      children: [
        for (var i = 0; i < 3; i++)
          Container(
            height: 48,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: listingBorder,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .7,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              lt(
                'Navigatorni tanlang',
                'Choose a navigator',
                'Выберите навигатор',
              ),
              style: profileText(20, bold: true),
            ),
            const SizedBox(height: 8),
            Text(widget.location.address, style: profileText(13)),
            const SizedBox(height: 16),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: profileText(13)),
              ),
            if (_opening) _loading(),
            FutureBuilder<List<SupportedMap>>(
              future: _maps,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return _loading();
                }
                if (snapshot.hasError) {
                  return Column(
                    children: [
                      Text(
                        lt(
                          'Navigatorlarni aniqlab bo‘lmadi.',
                          'Could not find navigation apps.',
                          'Не удалось найти навигаторы.',
                        ),
                        style: profileText(14),
                      ),
                      TextButton(
                        onPressed: () => setState(
                          () => _maps = widget.loader(widget.location),
                        ),
                        child: Text(lt('Qayta urinish', 'Retry', 'Повторить')),
                      ),
                    ],
                  );
                }
                final maps = (snapshot.data ?? [])
                    .where((map) => map.isInstalled)
                    .toList();
                if (maps.isEmpty) {
                  return Text(
                    lt(
                      'Navigator topilmadi. Google Maps, Yandex Maps yoki 2GIS ilovasini o‘rnating va qayta urinib ko‘ring.',
                      'No navigator found. Install Google Maps, Yandex Maps or 2GIS and try again.',
                      'Навигатор не найден. Установите Google Maps, Яндекс Карты или 2ГИС и повторите.',
                    ),
                    style: profileText(14),
                  );
                }
                return Column(
                  children: [
                    for (final map in maps)
                      ListTile(
                        key: ValueKey('externalMap-${map.map.id}'),
                        contentPadding: EdgeInsets.zero,
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(
                            map.iconBytes,
                            width: 40,
                            height: 40,
                          ),
                        ),
                        title: Text(
                          map.name,
                          style: profileText(16, bold: true),
                        ),
                        enabled: !_opening,
                        onTap: () => _open(map),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}
