import 'dart:convert';
import 'package:flutter/material.dart';

class CustomerPassportPhoto extends StatelessWidget {
  const CustomerPassportPhoto({super.key, required this.photo});
  final String photo;
  @override
  Widget build(BuildContext context) {
    final bytes = base64Decode(photo);
    return GestureDetector(
      onTap: () => showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Yopish',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Flexible(
                child: InteractiveViewer(
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
              ),
            ],
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.memory(
          bytes,
          height: 160,
          width: double.infinity,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
