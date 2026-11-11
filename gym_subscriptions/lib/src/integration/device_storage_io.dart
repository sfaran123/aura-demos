import '../state/auth.dart';
import 'repository.dart';

GymRepository? deviceGymRepository() => FileGymRepository.onDevice();

AuthStorage? deviceAuthStorage() => FileAuthStorage.onDevice();
