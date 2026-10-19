import 'package:flutter/material.dart';

/// Four columns and two rows; final cell is intentionally empty.
class AnimalArt extends StatelessWidget {
  const AnimalArt({super.key, required this.index, this.size = 110});
  final int index;
  final double size;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: size,
      height: size,
      child: ClipRect(
        clipper: _AnimalCellClipper(secondRow: index >= 4),
        child: OverflowBox(
          minWidth: size * 4,
          maxWidth: size * 4,
          minHeight: size * 2,
          maxHeight: size * 2,
          alignment: Alignment(-1 + (index % 4) * 2 / 3, index < 4 ? -1 : 1),
          child: Image.asset(
            'assets/images/animal_atlas.png',
            width: size * 4,
            height: size * 2,
            fit: BoxFit.fill,
          ),
        ),
      ),
    ),
  );
}

/// The upper sprites extend a few pixels across the atlas row boundary.
/// Trim only that empty gutter above the lower sprites, not the animals.
class _AnimalCellClipper extends CustomClipper<Rect> {
  const _AnimalCellClipper({required this.secondRow});
  final bool secondRow;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
    0,
    secondRow ? size.height * .065 : 0,
    size.width,
    size.height,
  );

  @override
  bool shouldReclip(_AnimalCellClipper oldClipper) =>
      oldClipper.secondRow != secondRow;
}
