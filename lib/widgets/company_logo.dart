import 'package:flutter/material.dart';

class CompanyLogo extends StatelessWidget {
  static const String assetPath =
      'lib/images/ChatGPT Image Jul 23, 2026, 12_41_12 PM.png';

  final double width;
  final double height;
  final double borderRadius;

  const CompanyLogo({
    super.key,
    this.width = 58,
    this.height = 38,
    this.borderRadius = 9,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: ColoredBox(
        color: Colors.white,
        child: Image.asset(
          assetPath,
          width: width,
          height: height,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          semanticLabel: 'Company logo',
        ),
      ),
    );
  }
}
