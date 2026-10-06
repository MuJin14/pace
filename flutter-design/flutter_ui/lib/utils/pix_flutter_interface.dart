
import 'package:flutter/cupertino.dart';

class PixFlutterInterface {
  String? name;

  Clip? clipBehavior;
  String? key;

  Color? backgroundColor;
  Gradient? gradient;
  String? backgroundImageName;
  BoxFit? fit;
  BoxBorder? border;
  BorderRadiusGeometry? borderRadius;
  List<BoxShadow>? boxShadow;

  double? width;
  double? height;
  double? left;
  double? top;
  double? angle;

  String? imageName;

  String? text;
  Color? textColor;
  String? fontFamily;
  FontWeight? fontWeight;
  double? fontSize;
  int? maxLines;
  TextAlign? textAlign;
  double? lineHeight;
  double? letterSpacing;
  TextDecoration? textDecoration;
  double? opacity;
  double? paragraphIndent;
  List<BoxShadow>? innerShadows;
  Gradient? textGradient;
  bool? visible;
  String? backgroundImageString;
  ImageProvider? image;

  Function()? onTap;
  Function()? onDoubleTap;
  Function(dynamic)? onTapDown;
  Function(dynamic)? onTapUp;
  Function(dynamic)? onPanStart;

  PixFlutterInterface? supInterface;

  String? componentNormName;

  MainAxisAlignment? mainAxisAlignment;

  PixFlutterInterface({
    this.name,
    this.clipBehavior,
    this.key,
    this.backgroundColor,
    this.gradient,
    this.backgroundImageName,
    this.fit,
    this.border,
    this.borderRadius,
    this.boxShadow,
    this.width,
    this.height,
    this.left,
    this.top,
    this.angle,
    this.imageName,
    this.text,
    this.textColor,
    this.fontFamily,
    this.fontWeight,
    this.fontSize,
    this.maxLines,
    this.textAlign,
    this.lineHeight,
    this.letterSpacing,
    this.textDecoration,
    this.opacity,
    this.paragraphIndent,
    this.innerShadows,
    this.textGradient,
    this.visible,
    this.backgroundImageString,
    this.image,
    this.onTap,
    this.onDoubleTap,
    this.onTapDown,
    this.onTapUp,
    this.onPanStart,
    this.supInterface,
    this.componentNormName,
    this.mainAxisAlignment,
  }) {
    if (supInterface != null) {
      merge(supInterface!);
    }
  }

  void merge(PixFlutterInterface supInterface) {
    if (supInterface.clipBehavior != null) {
      clipBehavior = supInterface.clipBehavior;
    }
    // if (supInterface.width != null) {
    //   width = supInterface.width;
    // }
    // if (supInterface.height != null) {
    //   height = supInterface.height;
    // }
    // if (supInterface.left != null) {
    //   left = supInterface.left;
    // }
    // if (supInterface.top != null) {
    //   top = supInterface.top;
    // }
    if (supInterface.angle != null) {
      angle = supInterface.angle;
    }
    if (supInterface.backgroundColor != null) {
      backgroundColor = supInterface.backgroundColor;
    }
    if (supInterface.gradient != null) {
      gradient = supInterface.gradient;
    }
    if (supInterface.backgroundImageName != null) {
      backgroundImageName = supInterface.backgroundImageName;
    }

    if (supInterface.fit != null) {
      fit = supInterface.fit;
    }
    if (supInterface.border != null) {
      border = supInterface.border;
    }
    if (supInterface.borderRadius != null) {
      borderRadius = supInterface.borderRadius;
    }
    if (supInterface.boxShadow != null) {
      boxShadow = supInterface.boxShadow;
    }
    if (supInterface.imageName != null) {
      imageName = supInterface.imageName;
    }
    if (supInterface.text != null) {
      text = supInterface.text;
    }
    if (supInterface.textColor != null) {
      textColor = supInterface.textColor;
    }
    if (supInterface.fontFamily != null) {
      fontFamily = supInterface.fontFamily;
    }
    if (supInterface.fontWeight != null) {
      fontWeight = supInterface.fontWeight;
    }
    if (supInterface.fontSize != null) {
      fontSize = supInterface.fontSize;
    }
    if (supInterface.maxLines != null) {
      maxLines = supInterface.maxLines;
    }
    if (supInterface.textAlign != null) {
      textAlign = supInterface.textAlign;
    }
    if (supInterface.lineHeight != null) {
      lineHeight = supInterface.lineHeight;
    }
    if (supInterface.letterSpacing != null) {
      letterSpacing = supInterface.letterSpacing;
    }
    if (supInterface.textDecoration != null) {
      textDecoration = supInterface.textDecoration;
    }
    if (supInterface.opacity != null) {
      opacity = supInterface.opacity;
    }
    if (supInterface.paragraphIndent != null) {
      paragraphIndent = supInterface.paragraphIndent;
    }
    if (supInterface.innerShadows != null) {
      innerShadows = supInterface.innerShadows;
    }
    if (supInterface.textGradient != null) {
      textGradient = supInterface.textGradient;
    }
    if (supInterface.visible != null) {
      visible = supInterface.visible;
    }

    if (supInterface.backgroundImageString != null) {
      backgroundImageString = supInterface.backgroundImageString;
    }

    if (supInterface.image != null) {
      image = supInterface.image;
    }

    if (supInterface.onTap != null) {
      onTap = supInterface.onTap;
    }
    if (supInterface.onDoubleTap != null) {
      onDoubleTap = supInterface.onDoubleTap;
    }
    if (supInterface.onTapDown != null) {
      onTapDown = supInterface.onTapDown;
    }
    if (supInterface.onTapUp != null) {
      onTapUp = supInterface.onTapUp;
    }
    if (supInterface.onPanStart != null) {
      onPanStart = supInterface.onPanStart;
    }
    if (supInterface.componentNormName != null) {
      componentNormName = supInterface.componentNormName;
    }
    if (supInterface.mainAxisAlignment != null) {
      mainAxisAlignment = supInterface.mainAxisAlignment;
    }
  }
}


