
import 'package:flutter/material.dart';

import 'variables_data_info.dart';

class VariablesManager extends ChangeNotifier {
  factory VariablesManager() => _getInstance ??= VariablesManager._();

  VariablesManager._();

  static VariablesManager? _getInstance;

  String getString(String key) {
    dynamic val = VariablesDataInfo().getVariableValueByKey(key);
    return val.runtimeType == String ? val : (val.runtimeType == double || val.runtimeType == int) ? val.toString() : "";
  }

  Color getColor(String key) {
    dynamic val = VariablesDataInfo().getVariableValueByKey(key);
    return val.runtimeType == Color ? val : Color(0xFF000000);
  }

  double getFloat(String key) {
    dynamic val = VariablesDataInfo().getVariableValueByKey(key);
    return (val.runtimeType == double || val.runtimeType == int) ? val.toDouble() : 0.0;
  }

  bool getBoolean(String key) {
    dynamic val = VariablesDataInfo().getVariableValueByKey(key);
    return val.runtimeType == bool ? val : false;
  }

  void changeMode(String newMode) {
    if (VariablesDataInfo().setMode(newMode)) {
      notifyListeners();
    }
  }
}



