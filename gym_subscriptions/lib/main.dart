import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/state/gym_store.dart';

void main() {
  runApp(AuraGymApp(store: GymStore()));
}
