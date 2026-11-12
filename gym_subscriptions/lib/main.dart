import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/integration/device_storage.dart';
import 'src/state/auth.dart';
import 'src/state/gym_store.dart';

void main() {
  // Data is kept on the device between runs (in the browser: localStorage).
  // With the AURA backend, pass a repository that talks to the API instead
  // (see HANDOFF.md).
  // Sign-in (domain + login, like the AURA POS app) is kept on the device too.
  runApp(AuraGymApp(
    // No demo data here: after sign-in the app shows only what the server sent.
    store: GymStore(seed: false, repository: deviceGymRepository()),
    auth: AuthController(storage: deviceAuthStorage()),
  ));
}
