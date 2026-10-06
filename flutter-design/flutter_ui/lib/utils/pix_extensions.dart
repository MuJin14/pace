
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter_ui/utils/pix_flutter_interface.dart';

extension PixStringExtension on String {
  Uint8List decodeBase64Image() {
    final String pureBase64 = split(',').last;
    return base64Decode(pureBase64);
  }
}

extension PixBoxDecorationExtension on BoxDecoration {
  BoxDecoration copyWithInterface([PixFlutterInterface? flutterProp]) {
    BoxDecoration decoration = this;
    if (flutterProp == null) {
      return decoration;
    }
    if (flutterProp.gradient != null) {
      decoration = decoration.copyWith(gradient: flutterProp.gradient);
    }

    if (flutterProp.backgroundColor != null) {
      decoration = decoration.copyWith(color: flutterProp.backgroundColor);
    }

    if (flutterProp.backgroundImageName != null) {
      decoration = decoration.copyWith(
          image: DecorationImage(image: AssetImage(flutterProp.backgroundImageName!), fit: flutterProp.fit));
    }

    if (flutterProp.backgroundImageString != null) {
      decoration = decoration.copyWith(
          image: DecorationImage(
              image: MemoryImage(flutterProp.backgroundImageString!.decodeBase64Image()), fit: BoxFit.fill));
    }

    if (flutterProp.image != null) {
      decoration = decoration.copyWith(image: DecorationImage(image: flutterProp.image!, fit: BoxFit.fill));
    }

    if (flutterProp.border != null) {
      decoration = decoration.copyWith(border: flutterProp.border);
    }

    if (flutterProp.borderRadius != null) {
      decoration = decoration.copyWith(borderRadius: flutterProp.borderRadius);
    }

    if (flutterProp.boxShadow != null) {
      decoration = decoration.copyWith(boxShadow: flutterProp.boxShadow);
    }

    return decoration;
  }
}

