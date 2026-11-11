import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/integration/repository.dart';
import 'src/state/auth.dart';
import 'src/state/gym_store.dart';

void main() {
  // Data is kept on the device between runs. With the AURA backend, pass a
  // repository that talks to the API instead (see HANDOFF.md).
  // Sign-in (domain + login, like the AURA POS app) is kept on the device too.
  runApp(AuraGymApp(
    store: GymStore(repository: FileGymRepository.onDevice()),
    auth: AuthController(storage: FileAuthStorage.onDevice()),
  ));
}
