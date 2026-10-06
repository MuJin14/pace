import 'package:flutter/cupertino.dart';

class VariablesDataInfo {
  factory VariablesDataInfo() => _getInstance ??= VariablesDataInfo._();

  VariablesDataInfo._();

  static VariablesDataInfo? _getInstance;

  Map? _currentModeIdData;

  Map variableSetMap = {};

  Map variableMap = {};

  _getVariableByKey(String key) {
    return variableMap[key];
  }

  String _getModeByKey(String key) {
    Map? variable = _getVariableByKey(key);
    if (variable != null) {
      String variableSetID = variable["variableSetID"] ?? "";
      if (_currentModeIdData != null && _currentModeIdData![variableSetID] != null) {
        return _currentModeIdData![variableSetID];
      } else {
        List? variableSet = variableSetMap[variableSetID];
        if (variableSet != null) {
          String currentModeId = variableSet[0]["id"] ?? '';
          if (_currentModeIdData != null) {
            _currentModeIdData![variableSetID] = currentModeId;
          } else {
            _currentModeIdData = {variableSetID: currentModeId};
          }
          return currentModeId;
        }
      }
    }
    return "";
  }

  getVariableValueByKey(String key) {
    Map? variable = _getVariableByKey(key);
    if (variable != null) {
      String mode = _getModeByKey(key);
      Map? modeValue = variable["modeValues"][mode];
      if (modeValue != null) {
        return _formatValue(modeValue);
      }
    }
    return null;
  }

  _formatValue(Map modeValue) {
    String dataType = modeValue["dataType"];
    Map? valueMap = modeValue["value"];
    if (valueMap == null) {
      return null;
    }
    switch (dataType) {
      case "STRING":
        return valueMap["textValue"];
      case "BOOLEAN":
        return valueMap["boolValue"];
      case "FLOAT":
        return valueMap["floatValue"];
      case "COLOR":
        Map colorValue = valueMap["colorValue"];
        final red = (colorValue["r"] as num).round().clamp(0, 255).toInt();
        final green = (colorValue["g"] as num).round().clamp(0, 255).toInt();
        final blue = (colorValue["b"] as num).round().clamp(0, 255).toInt();
        final alpha = (colorValue["a"] as num).toDouble();
        final opacity = (alpha > 1 ? alpha / 255 : alpha)
            .clamp(0.0, 1.0)
            .toDouble();
        return Color.fromRGBO(
          red,
          green,
          blue,
          opacity,
        );
      case "ALIAS":
        String? aliasKey = valueMap["alias"];
        if (aliasKey == null) {
          return null;
        }
        return getVariableValueByKey(aliasKey);
      default:
        return null;
    }
  }

  bool setMode(String newMode) {
    bool needNotify = false;
    variableSetMap.forEach((key, value) {
      List valueList = value;
      valueList.forEach((element) {
        if (element["id"] == newMode) {
          if (_currentModeIdData != null) {
            if (_currentModeIdData![key] != newMode) {
              _currentModeIdData![key] = newMode;
              needNotify = true;
            }
            return;
          } else {
            _currentModeIdData = {key: newMode};
            needNotify = true;
            return;
          }
        }
      });
    });
    return needNotify;
  }
}
