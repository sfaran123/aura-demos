import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/integration/device_storage.dart';
import 'src/state/auth.dart';
import 'src/state/gym_store.dart';
import 'src/ui/splash.dart';

void main() {
  // The native launch screen stays until the app can take over from it seamlessly.
  SplashReveal.preserve(WidgetsFlutterBinding.ensureInitialized());
  // Data is kept on the device between runs (in the browser: localStorage).
  // With the AURA backend, pass a repository that talks to the API instead
  // (see HANDOFF.md).
  // Sign-in (domain + login, like the AURA POS app) is kept on the device too.
  runApp(SplashReveal(
    child: AuraGymApp(
      // No demo data here: after sign-in the app shows only what the server sent.
      store: GymStore(seed: false, repository: deviceGymRepository()),
      auth: AuthController(storage: deviceAuthStorage()),
    ),
  ));
}
