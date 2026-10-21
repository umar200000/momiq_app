import 'dart:convert';
import '../../../core/widgets/momiq_scaffold.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'customer_widgets.dart';

/// Grid atlas keeps the generated artwork intact and crops only at paint time.
class CustomerAtlasArt extends StatelessWidget {
  const CustomerAtlasArt({
    super.key,
    required this.index,
    this.homes = false,
    this.fit = BoxFit.cover,
  });
  final int index;
  final bool homes;
  final BoxFit fit;
  @override
  Widget build(BuildContext context) => ClipRect(
    child: FittedBox(
      fit: fit,
      child: SizedBox(
        width: 512,
        height: homes ? 1024 : (index < 3 ? 460 : 544),
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment(
              (index % 3) - 1.0,
              homes ? 0 : (index ~/ 3) * 2.0 - 1,
            ),
            minWidth: 1536,
            maxWidth: 1536,
            minHeight: 1024,
            maxHeight: 1024,
            child: Image.asset(
              'assets/images/${homes ? 'customer_home_gallery' : 'customer_service_art'}.png',
              fit: BoxFit.fill,
              excludeFromSemantics: true,
            ),
          ),
        ),
      ),
    ),
  );
}

class CustomerBannerCarousel extends StatefulWidget {
  const CustomerBannerCarousel({super.key});
  @override
  State<CustomerBannerCarousel> createState() => _CustomerBannerCarouselState();
}

class _CustomerBannerCarouselState extends State<CustomerBannerCarousel>
    with WidgetsBindingObserver {
  final _pages = PageController();
  Timer? _timer;
  int _index = 0;
  bool _resumed = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (!_resumed || MediaQuery.disableAnimationsOf(context)) return;
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (_pages.hasClients &&
          !_pages.position.isScrollingNotifier.value &&
          (ModalRoute.of(context)?.isCurrent ?? true)) {
        _pages.animateToPage(
          (_index + 1) % 4,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pages.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final titles = [
      lt(
        'Mehrli enaga toping',
        'Find a caring sitter',
        'Найдите заботливую няню',
      ),
      lt(
        'Uydek qulay parvarish',
        'Care that feels like home',
        'Уютная забота как дома',
      ),
      lt(
        'Mehr uyingizga keladi',
        'Care comes to your home',
        'Забота придёт к вам домой',
      ),
      lt(
        'Har kuni xotirjam bo‘ling',
        'Peace of mind every day',
        'Спокойствие каждый день',
      ),
    ];
    final descriptions = [
      lt(
        'Sevimli do‘stingiz ishonchli qo‘llarda.',
        'Your pet is in caring hands.',
        'Ваш питомец в заботливых руках.',
      ),
      lt(
        'Do‘stingiz uchun mehrli va shinam joy.',
        'A warm, welcoming place for your pet.',
        'Уютное место для вашего друга.',
      ),
      lt(
        'Enaga do‘stingizni o‘z uyingizda parvarishlaydi.',
        'A sitter cares for your pet at your home.',
        'Няня позаботится о питомце у вас дома.',
      ),
      lt(
        'Parvarish va video hisobotlarni kuzating.',
        'Follow care and video updates.',
        'Следите за уходом и видеоотчётами.',
      ),
    ];
    return Column(
      children: [
        SizedBox(
          height:
              192 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6),
          child: PageView.builder(
            key: const ValueKey('customerBannerCarousel'),
            controller: _pages,
            itemCount: 4,
            onPageChanged: (value) => setState(() => _index = value),
            itemBuilder: (context, i) => Semantics(
              label: '${i + 1} / 4',
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  gradient: LinearGradient(
                    colors: [
                      [
                        const Color(0xFFF4D78C),
                        const Color(0xFFF0DEC0),
                        const Color(0xFFE2E2C8),
                        const Color(0xFFF2D498),
                      ][i],
                      const Color(0xFFFAF6F0),
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 6,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 16, 0, 16),
                        child: LayoutBuilder(
                          builder: (context, bounds) => FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: bounds.maxWidth,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    titles[i],
                                    style: const TextStyle(
                                      fontFamily: 'Quicksand',
                                      fontSize: 21,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF402411),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  cText(descriptions[i], size: 11),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 5,
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: ShaderMask(
                          blendMode: BlendMode.dstIn,
                          shaderCallback: (bounds) => const RadialGradient(
                            radius: .78,
                            colors: [
                              Colors.white,
                              Colors.white,
                              Colors.transparent,
                            ],
                            stops: [0, .65, 1],
                          ).createShader(bounds),
                          child: CustomerAtlasArt(index: [0, 1, 4, 2][i]),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            4,
            (i) => Semantics(
              label: '${i + 1} / 4',
              selected: i == _index,
              button: true,
              child: GestureDetector(
                onTap: () => _pages.animateToPage(
                  i,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                ),
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: i == _index ? 18 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: i == _index
                            ? listingGold
                            : const Color(0xFFD9C7AE),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}

class CustomerServiceTiles extends StatelessWidget {
  const CustomerServiceTiles({super.key, required this.onSelected});
  final ValueChanged<int> onSelected;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < 3; i++)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Material(
              color: listingSurface,
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: ValueKey('customerService-$i'),
                onTap: () => onSelected(i),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AspectRatio(
                      aspectRatio: 1.12,
                      child: CustomerAtlasArt(index: i + 3),
                    ),
                    SizedBox(
                      height:
                          58 *
                          MediaQuery.textScalerOf(
                            context,
                          ).scale(1).clamp(1.0, 2.0),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Center(
                          child: Text(
                            ct(customerServices[i]),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'Quicksand',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF402411),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class CustomerHomePhotos extends StatelessWidget {
  const CustomerHomePhotos({super.key, required this.sitter});
  final CJson sitter;
  @override
  Widget build(BuildContext context) {
    final photos = (sitter['homePhotos'] as List? ?? const [])
        .whereType<String>()
        .toList();
    if (photos.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: cText('Uy sharoiti', bold: true, size: 16)),
              cText(
                lt(
                  '${photos.length} ta rasm',
                  '${photos.length} photos',
                  '${photos.length} фото',
                ),
                size: 12,
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, bounds) => Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < photos.length; i++)
                  SizedBox(
                    width: (bounds.maxWidth - 12) / 3,
                    child: Semantics(
                      label: '${ct('Uy sharoiti')} ${i + 1}',
                      button: true,
                      child: GestureDetector(
                        key: ValueKey('sitterHomePhoto-${sitter['id']}-$i'),
                        onTap: () => cPush(
                          context,
                          CustomerHomeGallery(photos: photos, initialIndex: i),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: AspectRatio(
                            aspectRatio: 1.1,
                            child: Image.memory(
                              base64Decode(photos[i]),
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const Icon(Icons.broken_image_outlined),
                            ),
                          ),
                        ),
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

class CustomerHomeGallery extends StatefulWidget {
  const CustomerHomeGallery({
    super.key,
    required this.photos,
    required this.initialIndex,
  });
  final List<String> photos;
  final int initialIndex;
  @override
  State<CustomerHomeGallery> createState() => _CustomerHomeGalleryState();
}

class _CustomerHomeGalleryState extends State<CustomerHomeGallery> {
  late final PageController _pages = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;
  bool _zoomed = false;
  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MomiqScaffold(
    backgroundColor: listingBackground,
    appBar: AppBar(
      backgroundColor: listingBackground,
      title: Text(
        '${_index + 1} / ${widget.photos.length}',
        key: const ValueKey('homePhotoCount'),
      ),
    ),
    body: SafeArea(
      child: PageView.builder(
        key: const ValueKey('homePhotoGallery'),
        controller: _pages,
        itemCount: widget.photos.length,
        physics: _zoomed
            ? const NeverScrollableScrollPhysics()
            : const PageScrollPhysics(),
        onPageChanged: (i) => setState(() {
          _index = i;
          _zoomed = false;
        }),
        itemBuilder: (context, i) => _ZoomableHomePhoto(
          index: widget.photos[i],
          onZoomChanged: (zoomed) {
            if (_zoomed != zoomed) setState(() => _zoomed = zoomed);
          },
        ),
      ),
    ),
  );
}

class _ZoomableHomePhoto extends StatefulWidget {
  const _ZoomableHomePhoto({required this.index, required this.onZoomChanged});
  final String index;
  final ValueChanged<bool> onZoomChanged;
  @override
  State<_ZoomableHomePhoto> createState() => _ZoomableHomePhotoState();
}

class _ZoomableHomePhotoState extends State<_ZoomableHomePhoto> {
  final _transform = TransformationController();
  bool _zoomed = false;
  @override
  void initState() {
    super.initState();
    _transform.addListener(_changed);
  }

  void _changed() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed == _zoomed) return;
    setState(() => _zoomed = zoomed);
    widget.onZoomChanged(zoomed);
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => InteractiveViewer(
    transformationController: _transform,
    minScale: 1,
    maxScale: 4,
    panEnabled: _zoomed,
    child: Image.memory(
      base64Decode(widget.index),
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
    ),
  );
}
